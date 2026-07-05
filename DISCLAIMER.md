# Disclaimer

**Use at your own risk. No warranty of any kind.**

This toolkit performs **destructive and service-affecting operations** on a production security
system:

- `wzbackup.sh` and (during) `wzupgrade.sh` **stop the Wazuh indexer, manager, dashboard and
  filebeat services**, causing **downtime** and a gap in alert ingestion/collection.
- `wzupgrade.sh` **installs and upgrades system packages** via `apt`, modifies the Wazuh apt repo
  file and `jvm.options`, and pushes the OpenSearch security configuration.
- The rotation logic **deletes** older backup archives.

By running these scripts you accept full responsibility for the outcome. The authors and
contributors are **not liable** for data loss, extended downtime, failed upgrades, corrupted
indices, missed security events, or any other damage, direct or indirect.

Before using this in production you **must**:

1. **Read every script.** They are short on purpose. Understand what each step does.
2. **Test in a lab / staging** environment that mirrors your production versions first.
3. **Verify you have a known-good, restorable backup** *before* any upgrade — and actually test a
   restore at least once.
4. **Confirm the config** (`wz.conf`) paths, versions and retention match your environment.
5. **Schedule downtime** appropriately; the cold backup and the upgrade both interrupt service.

This project is **not affiliated with, endorsed by, or supported by Wazuh Inc.** "Wazuh" and
"OpenSearch" are trademarks of their respective owners. Consult the official Wazuh upgrade
documentation for your version before upgrading.

Security note: never commit a real `wz.conf`, backup archive, certificate, or `wazuh-install-files`
tar. Keep credentials in key/permission-restricted files, never inline in scripts or configs.

Provided **"AS IS"** under the MIT License (see `LICENSE`).
