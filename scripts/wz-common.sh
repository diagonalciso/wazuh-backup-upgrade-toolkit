#!/bin/bash
# Shared helpers for the Wazuh toolkit. Sourced by the other scripts. Not run directly.

# Locate + load config: $WZ_CONF, else /etc/wazuh-toolkit/wz.conf, else ./wz.conf
wz_load_conf() {
  local c="${WZ_CONF:-/etc/wazuh-toolkit/wz.conf}"
  [ -f "$c" ] || c="$(dirname "${BASH_SOURCE[0]}")/../wz.conf"
  [ -f "$c" ] || { echo "FATAL: no wz.conf found (set WZ_CONF)"; exit 1; }
  # shellcheck disable=SC1090
  . "$c"
}

log() { echo "[$(date '+%F %H:%M:%S')] $*"; }

# Extract the indexer 'admin' password from the install-files tar, server-side.
# Prints to stdout; caller captures into a var. Never log the value.
wz_admin_pw() {
  tar -O -xf "$INSTALL_FILES" wazuh-install-files/wazuh-passwords.txt 2>/dev/null \
    | grep -A1 "indexer_username: 'admin'" | grep indexer_password | head -1 \
    | grep -oP "(?<=indexer_password: ').*(?=')"
}

# Wait until the local indexer answers on :9200 (any HTTP code = up). Arg: max tries (default 60).
wz_wait_indexer() {
  local tries="${1:-60}" i
  for i in $(seq 1 "$tries"); do
    curl -sk -o /dev/null "$INDEXER_URL" && return 0
    sleep 5
  done
  return 1
}

# Re-pin heap in jvm.options if an upgrade reset it.
wz_ensure_heap() {
  grep -q "^-Xmx${HEAP}\$" "$JVM_OPTIONS" 2>/dev/null && return 0
  sed -i "s/^-Xmx.*/-Xmx${HEAP}/;s/^-Xms.*/-Xms${HEAP}/" "$JVM_OPTIONS"
  log "heap re-pinned to ${HEAP}"
}

# Rotate a backup dir: keep newest $2 sets of wazuh-full_<ts>.tar (+ sidecars).
# Args: dir keep
wz_rotate() {
  local dir="$1" keep="$2" old b s
  ls -1t "$dir"/wazuh-full_*.tar 2>/dev/null | tail -n +$((keep+1)) | while read -r old; do
    b="$(basename "$old")"; s="${b#wazuh-full_}"; s="${s%.tar}"
    log "prune $s"
    rm -f "$dir/wazuh-full_${s}.tar" "$dir/wazuh-full_${s}.tar.sha256" \
          "$dir/manifest_${s}.txt" "$dir/RESTORE_${s}.md"
  done
}
