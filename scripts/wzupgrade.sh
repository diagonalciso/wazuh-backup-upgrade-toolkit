#!/bin/bash
# wzupgrade.sh — in-place patch/minor upgrade of a single-node Wazuh server.
# Order: indexer -> manager -> filebeat -> dashboard. Preserves heap, re-pushes securityadmin,
# toggles shard allocation, keeps configs (--force-confold). EXIT trap brings services back + re-disables repo.
# TAKE A BACKUP FIRST (wzbackup.sh). Run as root. Set TARGET_VERSION in wz.conf.
#   sudo WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzupgrade.sh
set -u
. "$(dirname "$0")/wz-common.sh"; wz_load_conf
[ "$(id -u)" = 0 ] || { log "must run as root"; exit 1; }

IPW="$(wz_admin_pw)"
[ -n "$IPW" ] || log "WARN: admin pw not extracted — cluster/allocation curls will be skipped"

curl_idx() { curl -sk -u "admin:$IPW" "$@"; }

start_all() {
  log "EXIT: ensure services up"
  systemctl start wazuh-indexer 2>/dev/null
  wz_wait_indexer
  systemctl start wazuh-manager filebeat wazuh-dashboard 2>/dev/null
  [ -n "$IPW" ] && curl_idx -X PUT "$INDEXER_URL/_cluster/settings" -H 'Content-Type: application/json' \
    -d '{"persistent":{"cluster.routing.allocation.enable":null}}' >/dev/null 2>&1
  sed -i 's/^deb /#deb /' "$WAZUH_REPO_LIST" 2>/dev/null   # re-disable repo
  log "EXIT done"
}
trap start_all EXIT

log "=== Wazuh upgrade -> $TARGET_VERSION ==="
log "enable repo"; sed -i 's/^#\s*deb /deb /' "$WAZUH_REPO_LIST"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
APT="apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef install"

if [ -n "$IPW" ]; then
  log "disable shard allocation + flush"
  curl_idx -X PUT "$INDEXER_URL/_cluster/settings" -H 'Content-Type: application/json' \
    -d '{"persistent":{"cluster.routing.allocation.enable":"primaries"}}' >/dev/null 2>&1
  curl_idx -X POST "$INDEXER_URL/_flush" >/dev/null 2>&1
fi

log "--- indexer ---"; wz_ensure_heap
$APT "wazuh-indexer=$TARGET_VERSION" || { log "indexer apt FAIL"; exit 1; }
wz_ensure_heap
systemctl daemon-reload; systemctl restart wazuh-indexer; wz_wait_indexer && log "indexer up"

log "--- securityadmin re-push ---"
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /etc/wazuh-indexer/opensearch-security -icl -nhnv \
  -cacert "$INDEXER_CERTS/root-ca.pem" -cert "$INDEXER_CERTS/admin.pem" -key "$INDEXER_CERTS/admin-key.pem" \
  -h 127.0.0.1 2>&1 | tail -3

log "--- manager ---"
$APT "wazuh-manager=$TARGET_VERSION" || { log "manager apt FAIL"; exit 1; }
systemctl daemon-reload; systemctl restart wazuh-manager

log "--- filebeat (restart; oss module unchanged within a minor) ---"
systemctl restart filebeat

log "--- dashboard ---"
$APT "wazuh-dashboard=$TARGET_VERSION" || { log "dashboard apt FAIL"; exit 1; }
systemctl daemon-reload; systemctl restart wazuh-dashboard

[ -n "$IPW" ] && { log "re-enable shard allocation"; curl_idx -X PUT "$INDEXER_URL/_cluster/settings" \
  -H 'Content-Type: application/json' -d '{"persistent":{"cluster.routing.allocation.enable":null}}' >/dev/null 2>&1; }

log "versions after:"; dpkg -l | awk '/wazuh-(manager|indexer|dashboard)/{print $2,$3}'
[ -n "$IPW" ] && { log "cluster:"; curl_idx "$INDEXER_URL/_cluster/health" 2>/dev/null \
  | grep -oE '"status":"[^"]*"|"unassigned_shards":[0-9]+'; }
log "=== UPGRADE DONE ==="
# EXIT trap re-disables repo + ensures services
