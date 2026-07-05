# Operations Manual — Wazuh Backup & Upgrade Toolkit

Single-node Wazuh on Debian/Ubuntu (apt). Read [`../DISCLAIMER.md`](../DISCLAIMER.md) first.

---

## 1. Concepts

- **Method A — cold backup.** Stop services, `tar` the on-disk state, restart. Consistent and
  trivially restorable at the cost of a few minutes' downtime. This toolkit implements Method A.
- **State that matters:** `/var/ossec` (manager + agent keys + internal DBs), `/etc/wazuh-indexer`
  (+ certs + `opensearch-security`), `/var/lib/wazuh-indexer` (all indices + `.kibana` saved objects
  + the security index), `/etc/wazuh-dashboard`, `/etc/filebeat`, and your `wazuh-install-files.tar`
  (passwords/certs). Set these in `BACKUP_PATHS` / `INSTALL_FILES`.
- **Three roles:** the **server** (runs backup + upgrade), a **puller** box (runs the off-site copy,
  holds the ssh key + the mount), and an **off-box target** (NAS / USB / remote FS).

## 2. Configure

```bash
sudo install -d -m 0750 /etc/wazuh-toolkit
sudo install -m 0640 wz.conf.example /etc/wazuh-toolkit/wz.conf
sudoedit /etc/wazuh-toolkit/wz.conf
```

Key fields (see `wz.conf.example` for the full list): `BACKUP_DIR`, `BACKUP_PATHS`, `INSTALL_FILES`,
`JVM_OPTIONS`, `INDEXER_CERTS`, `WAZUH_REPO_LIST`, `KEEP`, `HEAP`, `TARGET_VERSION`, and the
`SRC_*` / `OFFSITE_*` block for the puller.

Scripts find the config via `$WZ_CONF`, else `/etc/wazuh-toolkit/wz.conf`, else `../wz.conf`.

## 3. Backup

```bash
sudo install -m 0755 scripts/wz-common.sh scripts/wzbackup.sh /usr/local/sbin/
sudo WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzbackup.sh
```

Produces in `BACKUP_DIR`: `wazuh-full_<ts>.tar`, `.sha256`, `manifest_<ts>.txt`, `RESTORE_<ts>.md`.
Keeps the newest `KEEP` sets. **Downtime** = the tar duration (minutes; longer on slow disks).
The `EXIT` trap restarts services even if the tar fails.

Run it **detached** so an ssh drop can't interrupt it:
```bash
sudo setsid bash -c 'nohup /usr/local/sbin/wzbackup.sh >>/var/log/wzbackup.log 2>&1 &'
```

## 4. Off-site copy (on the puller box)

Needs: ssh **key** to the server (`SSH_KEY`, no password), the target mounted at `OFFSITE_DEST`.

```bash
sudo install -m 0755 scripts/wz-common.sh scripts/wz-offsite-pull.sh /usr/local/sbin/
WZ_CONF=$HOME/.config/wazuh-toolkit/wz.conf /usr/local/sbin/wz-offsite-pull.sh
```

Pulls the newest tar, **skips the transfer if an identical-size copy already exists**, verifies
sha256, rotates to `OFFSITE_KEEP`. Read-only against the server.

> **Gotcha (important):** never use rsync `--inplace` *without* `--whole-file` to re-copy a large
> file that already exists over a slow/CIFS mount — rsync will delta-checksum the whole file on
> **both** sides (tens of minutes for a 15 GB tar). This toolkit uses `--whole-file` + a size-skip
> to avoid it. The sha256 verify still reads the whole file over the mount; that's inherent — it runs
> on the puller, not the server, so it doesn't affect Wazuh.

## 5. Upgrade

1. **Back up first** (section 3). Keep that tar as your rollback.
2. Set `TARGET_VERSION` in `wz.conf` to the exact apt version (e.g. `4.14.6-1`). Find it with:
   ```bash
   sudo sed -i 's/^#\s*deb /deb /' /etc/apt/sources.list.d/wazuh.list
   sudo apt-get update -qq && apt-cache madison wazuh-manager | head
   sudo sed -i 's/^deb /#deb /' /etc/apt/sources.list.d/wazuh.list   # re-disable
   ```
3. Run (detached recommended — network stack can blip):
   ```bash
   sudo install -m 0755 scripts/wzupgrade.sh /usr/local/sbin/
   sudo setsid bash -c 'nohup WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzupgrade.sh >>/var/log/wzupgrade.log 2>&1 &'
   ```
4. Watch: `tail -f /var/log/wzupgrade.log` until `=== UPGRADE DONE ===`.

What it does: enables the repo, disables shard allocation + flush, upgrades **indexer** (heap
re-pinned, restart, wait for green), **re-pushes securityadmin**, upgrades **manager**, restarts
**filebeat**, upgrades **dashboard**, re-enables allocation, prints versions + cluster health, and
(via the trap) re-disables the repo and guarantees services are up.

### Verify after
```bash
systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:443/        # dashboard: 200/302
curl -sk -u admin:<pw> https://127.0.0.1:9200/_cluster/health           # "status":"green", 0 unassigned
grep -E '^-Xm[sx]' /etc/wazuh-indexer/jvm.options                        # heap preserved
```

## 6. Rollback

Restore the pre-upgrade tar per its `RESTORE_<ts>.md` (or `docs/RESTORE.template.md`): stop all,
`tar -C / -xpf`, fix ownership, start indexer first, re-run securityadmin if the security index
didn't load. Match package versions to `manifest_<ts>.txt` (re-installing the old wazuh packages if
needed).

## 7. Schedule (systemd)

```bash
# server
sudo cp systemd/wazuh-backup.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now wazuh-backup.timer

# puller box (edit User= + WZ_CONF in the unit)
sudo cp systemd/wz-offsite-pull.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now wz-offsite-pull.timer
```

Defaults: server backup Sun 03:30, off-box pull Sun 05:30 (2 h later). `Persistent=true` catches up a
missed run if a box was off. Pick a real off-hours window if you have one; **each cold backup incurs
downtime**, so don't schedule it hourly.

## 8. Gotchas / field notes

- **Heap reset:** some indexer package upgrades rewrite `jvm.options`. The upgrade re-pins `-Xms/-Xmx`
  to `HEAP`; confirm after (step 5).
- **Security index not loading (401):** re-run the `securityadmin.sh` command (in `RESTORE.template.md`).
- **Slow boxes:** the dashboard/manager unpack can take 10–15 min each; the whole upgrade ~20–30 min.
  Poll the log; don't assume a hang.
- **Repo hygiene:** the Wazuh apt repo is kept **disabled** between runs so routine `apt upgrade` can't
  drift Wazuh. The upgrade script enables it only for its own run.
- **OS updates:** before an unrelated `apt upgrade`, `apt-mark hold wazuh-manager wazuh-indexer
  wazuh-dashboard filebeat`, then unhold after, so the OS update can't bump Wazuh unexpectedly.
- **Multi-node:** not supported here — clusters need per-node allocation handling and rolling restarts.
