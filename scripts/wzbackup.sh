#!/bin/bash
# wzbackup.sh — COLD full backup (Method A) of a single-node Wazuh server.
# Stops all Wazuh services, tars state, sha256s it, writes manifest + RESTORE, rotates.
# An EXIT trap ALWAYS restarts services (indexer first). Expect a few minutes of downtime.
# Run as root:  sudo WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzbackup.sh
set -u
. "$(dirname "$0")/wz-common.sh"; wz_load_conf

TS="$(date +%Y%m%d_%H%M%S)"
TAR="$BACKUP_DIR/wazuh-full_${TS}.tar"

start_all() {
  log "restart: indexer"; systemctl start wazuh-indexer
  wz_wait_indexer && log "indexer up" || log "WARN indexer slow to answer"
  log "restart: manager filebeat dashboard"
  systemctl start wazuh-manager filebeat wazuh-dashboard
  log "services restarted"
}
trap start_all EXIT

[ "$(id -u)" = 0 ] || { log "must run as root"; exit 1; }
mkdir -p "$BACKUP_DIR"
log "=== Wazuh COLD backup $TS ==="

log "stop: dashboard filebeat manager indexer"
systemctl stop wazuh-dashboard filebeat wazuh-manager wazuh-indexer

log "tar -> $TAR"
( cd / && tar -cpf "$TAR" $BACKUP_PATHS ) || { log "TAR FAILED"; exit 1; }

log "sha256"
( cd "$BACKUP_DIR" && sha256sum "$(basename "$TAR")" > "$(basename "$TAR").sha256" )

log "manifest"
{
  echo "Wazuh full backup $TS  host=$(hostname)"
  echo "--- package versions ---"
  dpkg -l 2>/dev/null | awk '/wazuh-(manager|indexer|dashboard)|filebeat/ {print $2, $3}'
  echo "--- disk ---"; df -h / | tail -1
  echo "--- paths ---"; echo "$BACKUP_PATHS"
} > "$BACKUP_DIR/manifest_${TS}.txt"

log "RESTORE md"
sed -e "s/__TS__/${TS}/g" "$(dirname "$0")/../docs/RESTORE.template.md" \
  > "$BACKUP_DIR/RESTORE_${TS}.md" 2>/dev/null || \
  echo "See docs/RESTORE.md — restore wazuh-full_${TS}.tar with 'tar -C / -xpf', fix ownership, start indexer first." \
  > "$BACKUP_DIR/RESTORE_${TS}.md"

wz_rotate "$BACKUP_DIR" "$KEEP"
log "backup done: $TAR ($(du -h "$TAR" | cut -f1))"
# EXIT trap restarts services
