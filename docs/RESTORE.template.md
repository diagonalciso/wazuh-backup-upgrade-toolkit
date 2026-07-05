# Restore Wazuh from wazuh-full___TS__.tar

> Generated per-backup. Package versions must match `manifest___TS__.txt`.
> Restore onto a host with the SAME (or freshly installed matching) Wazuh package versions.

1. Stop all services:
   ```
   systemctl stop wazuh-dashboard filebeat wazuh-manager wazuh-indexer
   ```
2. Extract in place (preserves owners/perms; paths are relative to `/`):
   ```
   tar -C / -xpf wazuh-full___TS__.tar
   ```
3. Fix ownership:
   ```
   chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer /var/lib/wazuh-indexer
   chown -R wazuh:wazuh                 /var/ossec
   chown -R root:root                   /etc/filebeat /etc/wazuh-dashboard
   ```
4. Start the indexer FIRST, wait for `:9200`, confirm cluster green, then the rest:
   ```
   systemctl start wazuh-indexer
   # wait until: curl -sk -u admin:<pw> https://127.0.0.1:9200/_cluster/health  => "status":"green"
   systemctl start wazuh-manager filebeat wazuh-dashboard
   ```
5. If the security index did not load (401 / "OpenSearch Security not initialized"), re-push it:
   ```
   /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
     -cd /etc/wazuh-indexer/opensearch-security -icl -nhnv \
     -cacert /etc/wazuh-indexer/certs/root-ca.pem \
     -cert   /etc/wazuh-indexer/certs/admin.pem \
     -key    /etc/wazuh-indexer/certs/admin-key.pem -h 127.0.0.1
   ```
6. Verify: cluster green, 4 services active, dashboard reachable on :443, alerts flowing.
