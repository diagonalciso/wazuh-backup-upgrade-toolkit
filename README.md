# Wazuh Backup & Upgrade Toolkit

Small, dependency-free Bash toolkit to **back up, off-site, and upgrade a single-node
[Wazuh](https://wazuh.com/) stack** (indexer + manager + dashboard + filebeat) on
Debian/Ubuntu (apt). Config-driven, systemd-schedulable, safe-by-default: every destructive
step has an `EXIT` trap that brings services back, upgrades keep your configs and heap, and the
off-site copy is read-only against the server.

> ⚠️ **Read [`DISCLAIMER.md`](DISCLAIMER.md) first.** No warranty. Test in a lab. It stops
> services (downtime) and installs packages. You are responsible for your data.

## What's in it

| Script | Runs on | What it does |
|--------|---------|--------------|
| `scripts/wzbackup.sh` | Wazuh server (root) | Cold **Method A** backup: stop → `tar` state → sha256 → manifest → `RESTORE.md` → rotate. Trap restarts services. |
| `scripts/wzupgrade.sh` | Wazuh server (root) | In-place upgrade to `TARGET_VERSION`. Order indexer→manager→filebeat→dashboard; heap preserved; securityadmin re-pushed; shard allocation toggled; configs kept. |
| `scripts/wz-offsite-pull.sh` | A **separate** box | Pull newest tar to an off-box target (NAS/USB/remote FS) over ssh **key auth**, verify sha256, rotate. |
| `scripts/wz-common.sh` | — | Shared helpers (config load, logging, heap pin, rotation, admin-pw read). |
| `systemd/*` | both | `.service` + `.timer` units for weekly scheduling. |

## Quickstart

```bash
git clone https://github.com/diagonalciso/wazuh-backup-upgrade-toolkit.git
cd wazuh-backup-upgrade-toolkit

# 1. configure
sudo install -d -m 0750 /etc/wazuh-toolkit
sudo install -m 0640 wz.conf.example /etc/wazuh-toolkit/wz.conf
sudoedit /etc/wazuh-toolkit/wz.conf          # set paths, TARGET_VERSION, off-box target

# 2. install scripts (on the Wazuh server)
sudo install -m 0755 scripts/wz-common.sh scripts/wzbackup.sh scripts/wzupgrade.sh /usr/local/sbin/

# 3. back up NOW
sudo WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzbackup.sh

# 4. upgrade (after setting TARGET_VERSION in wz.conf)
sudo WZ_CONF=/etc/wazuh-toolkit/wz.conf /usr/local/sbin/wzupgrade.sh
```

Full setup, scheduling, rollback and gotchas: **[`docs/MANUAL.md`](docs/MANUAL.md)**.

## Design notes

- **Cold backup (Method A):** stops services and `tar`s state for a consistent snapshot. Simple,
  restorable, ~minutes of downtime. If you can't afford downtime, use a hot snapshot instead (see manual).
- **Off-box via pull, not push:** the server needs no credentials to your NAS; the puller box holds
  the ssh key and the mount. Read-only against the server.
- **No cleartext passwords.** The indexer admin password is read server-side from the install-files
  tar only when needed and never logged. Off-box copy uses ssh **key** auth.
- **Idempotent-ish upgrades:** apt version-pinned, `--force-confold` keeps your configs, heap re-pinned
  if a package reset `jvm.options`, repo left disabled between runs.

## Requirements

Debian/Ubuntu Wazuh install (apt packages `wazuh-indexer`, `wazuh-manager`, `wazuh-dashboard`,
`filebeat`), `bash`, `curl`, `rsync`, `tar`, `sha256sum`, systemd. Tested against Wazuh 4.14.x on
Ubuntu 24.04. Single-node only (multi-node clusters need a different allocation/upgrade dance).

## License

[MIT](LICENSE).
