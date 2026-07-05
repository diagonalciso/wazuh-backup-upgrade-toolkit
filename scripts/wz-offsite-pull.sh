#!/bin/bash
# wz-offsite-pull.sh — pull the newest Wazuh backup tar from the server to an off-box target.
# Runs on a SEPARATE machine that has both ssh access to the server and the off-box target mounted.
# Key auth only (no cleartext password). Verifies sha256, rotates. Safe: read-only on the server.
#   WZ_CONF=$HOME/.config/wazuh-toolkit/wz.conf /usr/local/sbin/wz-offsite-pull.sh
set -u
. "$(dirname "$0")/wz-common.sh"; wz_load_conf

SSH="ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"
RHOST="$SRC_USER@$SRC_HOST"

mountpoint -q "$(dirname "$OFFSITE_DEST")" 2>/dev/null || \
  [ -d "$OFFSITE_DEST" ] || { log "off-box target $OFFSITE_DEST not present — ABORT"; exit 1; }
mkdir -p "$OFFSITE_DEST"

TAR="$($SSH "$RHOST" "ls -1t $SRC_BACKUP_DIR/wazuh-full_*.tar 2>/dev/null | head -1 | xargs -r basename")"
[ -n "$TAR" ] || { log "no tar found on server — ABORT"; exit 1; }
STAMP="${TAR#wazuh-full_}"; STAMP="${STAMP%.tar}"
log "newest on server: $TAR"

log "rsync sidecars (.sha256 + RESTORE) -> off-box"
rsync -e "$SSH" --whole-file \
  "$RHOST:$SRC_BACKUP_DIR/$TAR.sha256" \
  "$RHOST:$SRC_BACKUP_DIR/RESTORE_${STAMP}.md" \
  "$OFFSITE_DEST/" 2>&1
log "sidecar rsync exit=$?"

# Skip the big tar if an identical-size copy already exists (delta-checksum over a slow mount is pathological).
RSIZE="$($SSH "$RHOST" "stat -c %s '$SRC_BACKUP_DIR/$TAR' 2>/dev/null")"
LSIZE="$(stat -c %s "$OFFSITE_DEST/$TAR" 2>/dev/null || echo 0)"
if [ -n "$RSIZE" ] && [ "$RSIZE" = "$LSIZE" ]; then
  log "tar already off-box, same size ($LSIZE) — SKIP transfer, verify only"
else
  log "rsync tar (whole-file) -> off-box  remote=$RSIZE local=$LSIZE"
  rsync -e "$SSH" --partial --whole-file --inplace "$RHOST:$SRC_BACKUP_DIR/$TAR" "$OFFSITE_DEST/" 2>&1
  log "tar rsync exit=$?"
fi

log "verify sha256 on off-box copy"
cd "$OFFSITE_DEST" || exit 1
EXPECT="$(awk '{print $1}' "$TAR.sha256")"
GOT="$(sha256sum "$TAR" | awk '{print $1}')"
if [ "$EXPECT" = "$GOT" ]; then log "SHA256 MATCH — $TAR verified"; else log "SHA256 MISMATCH — FAIL"; exit 2; fi

log "rotate off-box: keep last $OFFSITE_KEEP"
ls -1t "$OFFSITE_DEST"/wazuh-full_*.tar 2>/dev/null | tail -n +$((OFFSITE_KEEP+1)) | while read -r old; do
  b="$(basename "$old")"; s="${b#wazuh-full_}"; s="${s%.tar}"
  log "prune off-box $s"
  rm -f "$OFFSITE_DEST/wazuh-full_${s}.tar" "$OFFSITE_DEST/wazuh-full_${s}.tar.sha256" "$OFFSITE_DEST/RESTORE_${s}.md"
done
log "offsite pull done"
