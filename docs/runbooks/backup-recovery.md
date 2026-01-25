# Backup and Recovery Procedures

This document covers backup strategies and recovery procedures for BNG Edge Infrastructure components.

## Table of Contents

1. [Overview](#overview)
2. [What Data Needs Backing Up](#what-data-needs-backing-up)
3. [Backup Procedures](#backup-procedures)
4. [Recovery Procedures](#recovery-procedures)
5. [Verification Procedures](#verification-procedures)
6. [Backup Schedules](#backup-schedules)

---

## Overview

The BNG Edge Infrastructure has a distributed architecture with state stored at multiple locations:

- **Nexus Cluster (Central)**: Master state for IP pools, allocations, and OLT registrations
- **BNG Nodes (Edge)**: Configuration, eBPF maps, and local subscriber cache
- **FRR (Edge)**: BGP routing state

The system is designed to be **offline-first**, meaning edge nodes can continue operating during network partitions. Recovery procedures must account for state reconciliation when connectivity is restored.

---

## What Data Needs Backing Up

### Critical Data (Must Backup)

| Component | Data | Location | Criticality |
|-----------|------|----------|-------------|
| Nexus | Pool definitions | `/var/lib/nexus/data/` | Critical |
| Nexus | IP allocations | `/var/lib/nexus/data/` | Critical |
| Nexus | OLT registrations | `/var/lib/nexus/data/` | Critical |
| Nexus | Configuration | ConfigMap/secrets | Critical |
| BNG | Configuration | `/etc/olt-bng/config.yaml` | Critical |
| BNG | Subscriber cache | eBPF maps (runtime) | Important |
| FRR | BGP config | `/etc/frr/frr.conf` | Important |

### Data That Can Be Regenerated

| Data | Source | Recovery Method |
|------|--------|-----------------|
| eBPF programs | Binary release | Re-deploy BNG |
| Prometheus metrics | Runtime collection | Historical data lost, regenerates |
| eBPF subscriber cache | Nexus allocations | Repopulates on DHCP requests |
| BGP routes | BNG subscriber state | Re-advertised on startup |

### Data Retention Requirements

| Data Type | Retention Period | Compliance |
|-----------|-----------------|------------|
| IP allocations | Active + 90 days | CGNAT logging (RFC 6888) |
| RADIUS accounting | 1 year minimum | Regulatory |
| Configuration changes | 1 year | Audit trail |
| System logs | 90 days | Troubleshooting |

---

## Backup Procedures

### Nexus Cluster Backup

#### Automated Backup (Recommended)

Create a Kubernetes CronJob for automated backups:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nexus-backup
  namespace: bng-system
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: ghcr.io/codelaboratoryltd/nexus-backup:latest
            command:
            - /bin/sh
            - -c
            - |
              # Create backup directory with timestamp
              BACKUP_DIR="/backups/nexus-$(date +%Y%m%d-%H%M%S)"
              mkdir -p $BACKUP_DIR

              # Export pools
              curl -s http://nexus.bng-system:9000/api/v1/pools > $BACKUP_DIR/pools.json

              # Export allocations (paginated)
              for pool in $(cat $BACKUP_DIR/pools.json | jq -r '.[].id'); do
                curl -s "http://nexus.bng-system:9000/api/v1/allocations?pool_id=$pool" > "$BACKUP_DIR/allocations-$pool.json"
              done

              # Export nodes
              curl -s http://nexus.bng-system:9000/api/v1/nodes > $BACKUP_DIR/nodes.json

              # Compress and upload to S3
              tar -czf /tmp/nexus-backup.tar.gz -C /backups .
              aws s3 cp /tmp/nexus-backup.tar.gz s3://backups-bucket/nexus/$(date +%Y/%m/%d)/

              # Cleanup old local backups (keep 7 days)
              find /backups -type d -mtime +7 -exec rm -rf {} +
            volumeMounts:
            - name: backup-storage
              mountPath: /backups
            env:
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: access-key
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: secret-key
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: nexus-backup-pvc
```

#### Manual Backup

```bash
# Export all data from Nexus API
BACKUP_DIR="/backup/nexus-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Export pools
curl -s "http://nexus.example.com:9000/api/v1/pools" > $BACKUP_DIR/pools.json

# Export allocations for each pool
for pool_id in $(jq -r '.[].id' $BACKUP_DIR/pools.json); do
  curl -s "http://nexus.example.com:9000/api/v1/allocations?pool_id=${pool_id}" \
    > "$BACKUP_DIR/allocations-${pool_id}.json"
done

# Export node registrations
curl -s "http://nexus.example.com:9000/api/v1/nodes" > $BACKUP_DIR/nodes.json

# Backup Kubernetes resources
kubectl get configmap nexus-config -n bng-system -o yaml > $BACKUP_DIR/configmap.yaml
kubectl get secret nexus-secrets -n bng-system -o yaml > $BACKUP_DIR/secrets.yaml
kubectl get statefulset nexus -n bng-system -o yaml > $BACKUP_DIR/statefulset.yaml

# Compress
tar -czf nexus-backup-$(date +%Y%m%d-%H%M%S).tar.gz $BACKUP_DIR

# Upload to remote storage
aws s3 cp nexus-backup-*.tar.gz s3://backup-bucket/nexus/
```

#### Badger Database Direct Backup

For direct database backup (requires pod access):

```bash
# Scale down to single replica to ensure consistency
kubectl scale statefulset nexus -n bng-system --replicas=1
kubectl rollout status statefulset/nexus -n bng-system

# Create backup from running pod
kubectl exec -n bng-system nexus-0 -- tar -czf /tmp/badger-backup.tar.gz -C /var/lib/nexus/data .

# Copy backup out of pod
kubectl cp bng-system/nexus-0:/tmp/badger-backup.tar.gz ./badger-backup-$(date +%Y%m%d).tar.gz

# Scale back up
kubectl scale statefulset nexus -n bng-system --replicas=3
```

### BNG Node Backup

#### Configuration Backup

```bash
#!/bin/bash
# /usr/local/bin/bng-backup.sh

BACKUP_DIR="/backup/bng-$(hostname)-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR

# Backup BNG configuration
cp /etc/olt-bng/config.yaml $BACKUP_DIR/

# Backup FRR configuration
cp /etc/frr/frr.conf $BACKUP_DIR/

# Backup systemd unit files
cp /etc/systemd/system/olt-bng.service $BACKUP_DIR/

# Export current eBPF map data (subscriber cache)
sudo bpftool map dump name subscriber_pools -j > $BACKUP_DIR/subscriber_pools.json 2>/dev/null || true
sudo bpftool map dump name dhcp_leases -j > $BACKUP_DIR/dhcp_leases.json 2>/dev/null || true

# Export metrics snapshot
curl -s http://localhost:9090/metrics > $BACKUP_DIR/metrics.txt 2>/dev/null || true

# Compress
tar -czf /backup/bng-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz $BACKUP_DIR

# Upload to central storage
scp /backup/bng-*.tar.gz backup-server:/backups/bng/

# Cleanup old backups (keep 7 days)
find /backup -name "bng-*.tar.gz" -mtime +7 -delete
```

Add to cron:
```bash
# Run daily at 2 AM
echo "0 2 * * * /usr/local/bin/bng-backup.sh" | sudo crontab -
```

#### eBPF Map Export (Runtime State)

```bash
# Export subscriber pool mappings
sudo bpftool map dump name subscriber_pools > /backup/ebpf-subscriber_pools.txt

# Export DHCP lease cache
sudo bpftool map dump name dhcp_leases > /backup/ebpf-dhcp_leases.txt

# Export NAT state (if applicable)
sudo bpftool map dump name nat_sessions > /backup/ebpf-nat_sessions.txt

# Export in JSON format for parsing
sudo bpftool map dump name subscriber_pools -j > /backup/ebpf-subscriber_pools.json
```

---

## Recovery Procedures

### Single BNG Node Failure

#### Scenario: Hardware failure, node unrecoverable

**Impact:** Subscribers on that OLT lose connectivity until recovery

**Recovery Steps:**

1. **Provision replacement hardware**
   ```bash
   # On new hardware, install OS and prerequisites
   # Ensure kernel 5.10+ with eBPF support
   uname -r
   ```

2. **Restore BNG configuration**
   ```bash
   # Download latest backup
   scp backup-server:/backups/bng/bng-olt-east-01-latest.tar.gz /tmp/
   tar -xzf /tmp/bng-olt-east-01-latest.tar.gz -C /tmp/

   # Restore configuration
   sudo mkdir -p /etc/olt-bng
   sudo cp /tmp/backup/config.yaml /etc/olt-bng/

   # Restore FRR config
   sudo cp /tmp/backup/frr.conf /etc/frr/
   ```

3. **Install BNG binary**
   ```bash
   # Download release binary
   VERSION="v0.2.0"
   curl -LO "https://github.com/codelaboratoryltd/bng/releases/download/${VERSION}/bng-linux-amd64"
   sudo mv bng-linux-amd64 /usr/local/bin/olt-bng
   sudo chmod +x /usr/local/bin/olt-bng
   ```

4. **Install systemd service**
   ```bash
   sudo cp /tmp/backup/olt-bng.service /etc/systemd/system/
   sudo systemctl daemon-reload
   ```

5. **Start services**
   ```bash
   sudo systemctl start frr
   sudo systemctl start olt-bng
   sudo systemctl enable olt-bng
   ```

6. **Verify registration with Nexus**
   ```bash
   # Check BNG logs
   sudo journalctl -u olt-bng -f | grep -i nexus

   # Verify in Nexus
   curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq '.[] | select(.id=="olt-east-01")'
   ```

7. **Verify subscriber connectivity**
   ```bash
   # Check active sessions rebuilding
   curl -s http://localhost:8080/metrics | grep bng_active_sessions_total

   # Monitor DHCP requests
   sudo journalctl -u olt-bng -f | grep -i dhcp
   ```

**Note:** Subscriber sessions will be re-established via DHCP. The eBPF cache will repopulate as subscribers reconnect. Nexus retains the IP allocations, so subscribers receive the same IPs.

---

### Nexus Cluster Failure

#### Scenario: All Nexus pods unavailable

**Impact:** New IP allocations fail; existing sessions continue (offline-first design)

**Immediate Response:**

1. **Verify cluster state**
   ```bash
   kubectl get pods -n bng-system -l app=nexus
   kubectl get events -n bng-system --sort-by='.lastTimestamp'
   ```

2. **Check persistent volumes**
   ```bash
   kubectl get pvc -n bng-system
   kubectl describe pvc -n bng-system
   ```

3. **Attempt pod recovery**
   ```bash
   # Delete pods to trigger restart
   kubectl delete pods -n bng-system -l app=nexus

   # Watch for recovery
   kubectl get pods -n bng-system -l app=nexus -w
   ```

**Full Recovery (Data Loss Scenario):**

1. **Restore from backup**
   ```bash
   # Download latest backup
   aws s3 cp s3://backup-bucket/nexus/latest/nexus-backup.tar.gz /tmp/
   tar -xzf /tmp/nexus-backup.tar.gz -C /tmp/
   ```

2. **Recreate Nexus deployment**
   ```bash
   # Delete existing resources
   kubectl delete statefulset nexus -n bng-system
   kubectl delete pvc -n bng-system -l app=nexus

   # Restore ConfigMap
   kubectl apply -f /tmp/backup/configmap.yaml

   # Redeploy StatefulSet
   kubectl apply -f /tmp/backup/statefulset.yaml

   # Wait for pods
   kubectl rollout status statefulset/nexus -n bng-system
   ```

3. **Restore data via API**
   ```bash
   # Restore pools
   for pool_file in /tmp/backup/pools/*.json; do
     curl -X POST "http://nexus.example.com:9000/api/v1/pools" \
       -H "Content-Type: application/json" \
       -d @$pool_file
   done

   # Restore allocations
   for alloc_file in /tmp/backup/allocations-*.json; do
     cat $alloc_file | jq -c '.[]' | while read alloc; do
       curl -X POST "http://nexus.example.com:9000/api/v1/allocations" \
         -H "Content-Type: application/json" \
         -d "$alloc"
     done
   done
   ```

4. **Verify cluster health**
   ```bash
   # Check API health
   curl -s "http://nexus.example.com:9000/health"

   # Verify pool data
   curl -s "http://nexus.example.com:9000/api/v1/pools" | jq length

   # Verify allocation counts match backup
   for pool in $(curl -s "http://nexus.example.com:9000/api/v1/pools" | jq -r '.[].id'); do
     echo "$pool: $(curl -s "http://nexus.example.com:9000/api/v1/allocations?pool_id=$pool" | jq length)"
   done
   ```

5. **Notify BNG nodes to re-sync**
   ```bash
   # BNG nodes should automatically reconnect
   # Verify registrations
   curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq
   ```

---

### Complete Site Failure

#### Scenario: Site-wide outage (data center failure)

**Impact:** All subscribers at site offline

**Recovery Steps:**

1. **Assess damage and timeline**
   - Determine if site is recoverable
   - Estimate time to restore
   - Consider failover to alternate site (if available)

2. **Communicate with stakeholders**
   - Notify NOC and management
   - Update status page
   - Prepare customer communications

3. **Restore infrastructure**
   ```bash
   # If restoring to same site:
   # 1. Restore network connectivity
   # 2. Restore Kubernetes cluster
   # 3. Restore Nexus (see Nexus Cluster Failure)
   # 4. Restore BNG nodes (see Single BNG Node Failure)
   ```

4. **Restore Nexus first**
   ```bash
   # Nexus must be available before BNG nodes
   # Follow Nexus Cluster Failure recovery
   ```

5. **Restore BNG nodes**
   ```bash
   # For each BNG node:
   # Follow Single BNG Node Failure recovery
   ```

6. **Verify subscriber connectivity**
   ```bash
   # Monitor DHCP requests across all BNG nodes
   for bng in olt-east-01 olt-east-02 olt-east-03; do
     echo "$bng: $(curl -s http://${bng}:9090/metrics | grep bng_active_sessions_total)"
   done
   ```

7. **Post-incident review**
   - Document timeline and actions
   - Identify improvements
   - Update runbooks if needed

---

### Data Restoration Steps

#### Restoring Nexus Data from Badger Backup

```bash
# Stop Nexus pods
kubectl scale statefulset nexus -n bng-system --replicas=0

# Access PVC (create debug pod)
kubectl run restore-pod --image=busybox -n bng-system \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"nexus-data-nexus-0"}}],"containers":[{"name":"restore","image":"busybox","command":["sleep","3600"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}'

# Wait for pod
kubectl wait --for=condition=Ready pod/restore-pod -n bng-system

# Copy backup into pod
kubectl cp badger-backup.tar.gz bng-system/restore-pod:/tmp/

# Restore data
kubectl exec -n bng-system restore-pod -- sh -c "
  rm -rf /data/*
  tar -xzf /tmp/badger-backup.tar.gz -C /data
"

# Cleanup
kubectl delete pod restore-pod -n bng-system

# Restart Nexus
kubectl scale statefulset nexus -n bng-system --replicas=3
kubectl rollout status statefulset/nexus -n bng-system
```

#### Restoring BNG eBPF Maps (Warm Start)

If you have a backup of eBPF map data and want to warm-start the cache:

```bash
# This is typically not necessary as cache repopulates automatically
# But can speed up recovery if you have recent map dumps

# Parse JSON backup and populate via BNG API (if supported)
cat subscriber_pools.json | jq -c '.[]' | while read entry; do
  mac=$(echo $entry | jq -r '.key.mac')
  ip=$(echo $entry | jq -r '.value.ip')
  curl -X POST "http://localhost:8080/api/v1/cache" \
    -H "Content-Type: application/json" \
    -d "{\"mac\": \"$mac\", \"ip\": \"$ip\"}"
done
```

---

## Verification Procedures

### Post-Recovery Verification Checklist

#### Nexus Verification

```bash
# 1. API health
curl -s "http://nexus.example.com:9000/health" | jq
# Expected: {"status": "healthy"}

# 2. Cluster membership
curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq length
# Expected: Number of registered OLT nodes

# 3. Pool integrity
EXPECTED_POOLS=5  # Adjust to your environment
ACTUAL_POOLS=$(curl -s "http://nexus.example.com:9000/api/v1/pools" | jq length)
[ "$ACTUAL_POOLS" -eq "$EXPECTED_POOLS" ] && echo "PASS: Pool count matches" || echo "FAIL: Pool count mismatch"

# 4. Allocation counts (compare with backup)
# Create a verification script
cat > /tmp/verify-allocations.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=$1
for pool_file in $BACKUP_DIR/allocations-*.json; do
  pool=$(basename $pool_file .json | sed 's/allocations-//')
  backup_count=$(jq length $pool_file)
  live_count=$(curl -s "http://nexus.example.com:9000/api/v1/allocations?pool_id=$pool" | jq length)
  if [ "$backup_count" -eq "$live_count" ]; then
    echo "PASS: $pool - $live_count allocations"
  else
    echo "FAIL: $pool - Backup: $backup_count, Live: $live_count"
  fi
done
EOF
chmod +x /tmp/verify-allocations.sh
/tmp/verify-allocations.sh /tmp/backup

# 5. CLSet synchronization
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9002/metrics | grep clset_sync
```

#### BNG Verification

```bash
# 1. Service status
sudo systemctl status olt-bng
# Expected: Active (running)

# 2. eBPF programs loaded
sudo bpftool prog show | grep -c "xdp"
# Expected: At least 1

# 3. Nexus connectivity
curl -s http://localhost:8080/health | jq '.nexus_connected'
# Expected: true

# 4. DHCP processing
curl -s http://localhost:9090/metrics | grep dhcp_requests_total
# Expected: Counter incrementing

# 5. Subscriber sessions
curl -s http://localhost:9090/metrics | grep bng_active_sessions_total
# Expected: Count rebuilding over time

# 6. BGP routes advertised
sudo vtysh -c "show bgp summary"
# Expected: Neighbors established
```

### Automated Verification Script

```bash
#!/bin/bash
# /usr/local/bin/verify-recovery.sh

echo "=== BNG Edge Infrastructure Recovery Verification ==="
echo "Date: $(date)"
echo ""

FAILURES=0

# Nexus checks
echo "--- Nexus Cluster ---"
if curl -sf "http://nexus.example.com:9000/health" > /dev/null; then
  echo "[PASS] Nexus API healthy"
else
  echo "[FAIL] Nexus API unreachable"
  FAILURES=$((FAILURES+1))
fi

NODES=$(curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq length)
if [ "$NODES" -gt 0 ]; then
  echo "[PASS] $NODES OLT nodes registered"
else
  echo "[FAIL] No OLT nodes registered"
  FAILURES=$((FAILURES+1))
fi

# BNG checks (run on each BNG node)
echo ""
echo "--- Local BNG Node ---"
if systemctl is-active --quiet olt-bng; then
  echo "[PASS] BNG service running"
else
  echo "[FAIL] BNG service not running"
  FAILURES=$((FAILURES+1))
fi

if sudo bpftool prog show | grep -q xdp; then
  echo "[PASS] eBPF XDP program loaded"
else
  echo "[FAIL] eBPF XDP program not loaded"
  FAILURES=$((FAILURES+1))
fi

# Summary
echo ""
echo "=== Summary ==="
if [ $FAILURES -eq 0 ]; then
  echo "All checks passed. Recovery successful."
  exit 0
else
  echo "$FAILURES check(s) failed. Review and remediate."
  exit 1
fi
```

---

## Backup Schedules

### Recommended Backup Frequency

| Component | Backup Type | Frequency | Retention |
|-----------|-------------|-----------|-----------|
| Nexus | API export (pools, allocations) | Every 6 hours | 30 days |
| Nexus | Badger database snapshot | Daily | 7 days |
| Nexus | Kubernetes manifests | On change | 1 year |
| BNG | Configuration files | Daily | 30 days |
| BNG | eBPF map dump | Every 6 hours | 7 days |
| FRR | Configuration | Daily | 30 days |
| All | Off-site replication | Daily | 90 days |

### Backup Monitoring

Set up alerts for backup failures:

```yaml
# Prometheus alerting rules
groups:
  - name: backup-alerts
    rules:
      - alert: NexusBackupFailed
        expr: time() - nexus_last_backup_timestamp > 86400
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Nexus backup is overdue"
          description: "Last successful backup was more than 24 hours ago"

      - alert: NexusBackupStorageLow
        expr: backup_storage_available_bytes < 10737418240  # 10GB
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Backup storage running low"
          description: "Less than 10GB available for backups"
```

### Backup Integrity Testing

Run monthly restore tests:

```bash
#!/bin/bash
# Monthly backup integrity test

# 1. Restore Nexus to test environment
kubectl config use-context test-cluster
kubectl apply -f /backup/latest/nexus/

# 2. Verify data integrity
/usr/local/bin/verify-recovery.sh

# 3. Run integration tests
./tests/integration/run-all.sh

# 4. Document results
echo "Backup test completed: $(date)" >> /var/log/backup-tests.log
```

---

## Appendix: Recovery Time Objectives

| Scenario | RTO Target | RPO Target | Notes |
|----------|------------|------------|-------|
| Single BNG node failure | 30 minutes | 0 (no data loss) | Subscribers reconnect automatically |
| Nexus pod restart | 5 minutes | 0 | StatefulSet handles restart |
| Nexus cluster failure | 2 hours | 6 hours | Restore from backup |
| Complete site failure | 4-8 hours | 6 hours | Depends on hardware availability |

**RTO** = Recovery Time Objective (maximum acceptable downtime)
**RPO** = Recovery Point Objective (maximum acceptable data loss)
