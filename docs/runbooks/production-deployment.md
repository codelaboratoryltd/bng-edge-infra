# Production Deployment Runbook

This runbook covers the deployment procedures for BNG Edge Infrastructure in production environments.

## Table of Contents

1. [Pre-Deployment Checklist](#pre-deployment-checklist)
2. [BNG Deployment (Bare Metal)](#bng-deployment-bare-metal)
3. [Nexus Deployment (Kubernetes)](#nexus-deployment-kubernetes)
4. [Health Check Verification](#health-check-verification)
5. [Rollback Procedures](#rollback-procedures)
6. [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)

---

## Pre-Deployment Checklist

### General Requirements

- [ ] Change request approved and scheduled
- [ ] Maintenance window communicated to stakeholders
- [ ] Rollback plan documented and tested
- [ ] Backup of current configuration completed
- [ ] Monitoring alerts silenced for maintenance window
- [ ] On-call team notified

### BNG Node Requirements

- [ ] Target OLT hardware meets minimum specifications:
  - Linux kernel 5.10+ (for XDP/eBPF support)
  - 10-40 Gbps network interfaces
  - 4+ CPU cores
  - 8+ GB RAM
  - 50+ GB disk space
- [ ] Network connectivity to Nexus cluster verified
- [ ] Network connectivity to RADIUS server verified
- [ ] BPF filesystem mounted (`/sys/fs/bpf`)
- [ ] Required kernel modules loaded (eBPF, XDP)
- [ ] FRR (Free Range Routing) installed for BGP

### Nexus Cluster Requirements

- [ ] Kubernetes cluster healthy (all nodes Ready)
- [ ] Sufficient cluster resources available
- [ ] Persistent volume storage available
- [ ] Network policies allow inter-node P2P communication (port 33123)
- [ ] Load balancer or ingress configured for API access

### Version Compatibility

- [ ] BNG version compatible with Nexus version
- [ ] Configuration schema compatible with new version
- [ ] eBPF programs compatible with kernel version

---

## BNG Deployment (Bare Metal)

### Overview

BNG runs as a systemd service on bare metal OLT hardware. Each site serves 1,000-2,000 subscribers with eBPF/XDP for kernel-level packet processing.

### Step 1: Prepare the Binary

```bash
# Download the release binary (replace VERSION)
VERSION="v0.2.0"
curl -LO "https://github.com/codelaboratoryltd/bng/releases/download/${VERSION}/bng-linux-amd64"
chmod +x bng-linux-amd64

# Verify checksum
curl -LO "https://github.com/codelaboratoryltd/bng/releases/download/${VERSION}/bng-linux-amd64.sha256"
sha256sum -c bng-linux-amd64.sha256

# Move to installation directory
sudo mv bng-linux-amd64 /usr/local/bin/olt-bng
```

### Step 2: Install Configuration

```bash
# Create configuration directory
sudo mkdir -p /etc/olt-bng

# Copy configuration file (customize for your site)
sudo cp config.yaml /etc/olt-bng/config.yaml
sudo chmod 600 /etc/olt-bng/config.yaml
```

Example configuration (`/etc/olt-bng/config.yaml`):

```yaml
# OLT-BNG Configuration
olt:
  id: "olt-east-01"
  name: "East Data Center OLT"
  region: "east"
  capacity: 2000

# Network interfaces
interfaces:
  subscriber: "eth1"      # Subscriber-facing interface (XDP attached)
  uplink: "eth0"          # Uplink to core network

# Nexus coordination
nexus:
  endpoints:
    - "nexus-1.example.com:9000"
    - "nexus-2.example.com:9000"
  heartbeat_interval: 30s
  timeout: 10s

# RADIUS configuration
radius:
  servers:
    - host: "radius.example.com"
      port: 1812
      secret: "${RADIUS_SECRET}"  # Use environment variable
  timeout: 5s
  retries: 3

# DHCP configuration
dhcp:
  pool_id: "residential-ipv4"
  lease_time: 3600
  renewal_time: 1800
  rebinding_time: 3150

# BGP configuration (FRR integration)
bgp:
  enabled: true
  local_as: 65001
  router_id: "10.1.1.10"
  neighbors:
    - address: "10.1.1.1"
      remote_as: 65000

# Metrics
metrics:
  enabled: true
  port: 9090
  path: "/metrics"
```

### Step 3: Install Systemd Service

```bash
# Create systemd service file
sudo tee /etc/systemd/system/olt-bng.service > /dev/null <<EOF
[Unit]
Description=OLT-BNG Service
Documentation=https://github.com/codelaboratoryltd/bng
After=network-online.target
Wants=network-online.target
Requires=frr.service
After=frr.service

[Service]
Type=simple
User=root
Group=root
Environment="RADIUS_SECRET=your-secret-here"
ExecStartPre=/usr/local/bin/olt-bng validate --config /etc/olt-bng/config.yaml
ExecStart=/usr/local/bin/olt-bng run --config /etc/olt-bng/config.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65536
LimitMEMLOCK=infinity

# Security hardening
NoNewPrivileges=no
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload
```

### Step 4: Deploy BNG

```bash
# Stop existing service (if upgrading)
sudo systemctl stop olt-bng

# Verify configuration
sudo /usr/local/bin/olt-bng validate --config /etc/olt-bng/config.yaml

# Start the service
sudo systemctl start olt-bng

# Enable on boot
sudo systemctl enable olt-bng

# Check status
sudo systemctl status olt-bng
```

### Step 5: Verify eBPF Programs Loaded

```bash
# Check XDP program attached to subscriber interface
sudo bpftool net show dev eth1

# List all loaded BPF programs
sudo bpftool prog show

# Verify eBPF maps created
sudo bpftool map show

# Check subscriber cache entries
sudo bpftool map dump name subscriber_pools | head -20
```

### Step 6: Register with Nexus

The BNG will automatically register with Nexus on startup. Verify registration:

```bash
# Check logs for successful registration
sudo journalctl -u olt-bng -f | grep -i "nexus"

# Verify via Nexus API
curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq '.[] | select(.id=="olt-east-01")'
```

---

## Nexus Deployment (Kubernetes)

### Overview

Nexus runs as a StatefulSet in Kubernetes, providing distributed coordination via CLSet CRDT.

### Step 1: Prepare Kubernetes Manifests

```bash
# Clone the infrastructure repository
git clone https://github.com/codelaboratoryltd/bng-edge-infra.git
cd bng-edge-infra

# Navigate to production manifests
cd clusters/production
```

### Step 2: Configure Nexus

Edit the Nexus configuration in `components/nexus/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nexus-config
  namespace: bng-system
data:
  nexus.yaml: |
    server:
      http_port: 9000
      grpc_port: 9001
      metrics_port: 9002

    node:
      role: "core"
      region: "production"

    p2p:
      listen_port: 33123

    storage:
      path: "/var/lib/nexus/data"

    clset:
      topic: "nexus-state"
      rebroadcast_interval: 5s
      num_workers: 50

    graceful_shutdown:
      timeout: 2m
      grace_period: 10s
```

### Step 3: Deploy Nexus Cluster

```bash
# Apply namespace and RBAC
kubectl apply -f components/nexus/namespace.yaml
kubectl apply -f components/nexus/rbac.yaml

# Apply ConfigMap and Secrets
kubectl apply -f components/nexus/configmap.yaml
kubectl apply -f components/nexus/secrets.yaml

# Deploy StatefulSet
kubectl apply -f components/nexus/statefulset.yaml

# Deploy Service
kubectl apply -f components/nexus/service.yaml
```

### Step 4: Wait for Rollout

```bash
# Watch rollout status
kubectl rollout status statefulset/nexus -n bng-system --timeout=5m

# Check pod status
kubectl get pods -n bng-system -l app=nexus -w

# Verify all replicas ready
kubectl get statefulset nexus -n bng-system
```

### Step 5: Verify Cluster Formation

```bash
# Check logs for P2P peer discovery
kubectl logs -n bng-system nexus-0 | grep -i "peer"

# Check CLSet synchronization
kubectl logs -n bng-system nexus-0 | grep -i "clset"

# Verify API health
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9000/health
```

### Step 6: Configure Load Balancer / Ingress

```bash
# Apply load balancer service
kubectl apply -f components/nexus/loadbalancer.yaml

# Or apply ingress
kubectl apply -f components/nexus/ingress.yaml

# Get external IP/hostname
kubectl get svc -n bng-system nexus-lb
```

---

## Health Check Verification

### BNG Health Checks

```bash
# Service status
sudo systemctl status olt-bng

# API health endpoint
curl -s http://localhost:8080/health | jq

# Metrics endpoint
curl -s http://localhost:9090/metrics | grep -E "^bng_|^dhcp_"

# Check DHCP fast path stats
curl -s http://localhost:8080/metrics | grep dhcp_requests_total

# Verify eBPF program health
sudo bpftool prog show name dhcp_fastpath

# Check subscriber count
sudo bpftool map dump name subscriber_pools | wc -l
```

### Nexus Health Checks

```bash
# Pod health
kubectl get pods -n bng-system -l app=nexus

# Health endpoint (per pod)
for i in 0 1 2; do
  kubectl exec -n bng-system nexus-$i -- curl -s localhost:9000/health
done

# Readiness endpoint
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9000/ready

# API accessibility
curl -s "http://nexus.example.com:9000/health"

# Check cluster membership
curl -s "http://nexus.example.com:9000/api/v1/nodes" | jq length

# Verify pool configuration
curl -s "http://nexus.example.com:9000/api/v1/pools" | jq

# Check allocation counts
curl -s "http://nexus.example.com:9000/api/v1/allocations?pool_id=residential-ipv4" | jq length
```

### End-to-End Verification

```bash
# Test DHCP flow (from a test subscriber)
sudo dhclient -v eth1

# Verify allocation in Nexus
curl -s "http://nexus.example.com:9000/api/v1/allocations/test-subscriber" | jq

# Check BNG logs for successful DHCP
sudo journalctl -u olt-bng --since "5 minutes ago" | grep -i dhcp
```

---

## Rollback Procedures

### BNG Rollback

#### Immediate Rollback (Within Maintenance Window)

```bash
# Stop current service
sudo systemctl stop olt-bng

# Restore previous binary
sudo mv /usr/local/bin/olt-bng /usr/local/bin/olt-bng.failed
sudo mv /usr/local/bin/olt-bng.backup /usr/local/bin/olt-bng

# Restore previous configuration (if changed)
sudo mv /etc/olt-bng/config.yaml /etc/olt-bng/config.yaml.failed
sudo mv /etc/olt-bng/config.yaml.backup /etc/olt-bng/config.yaml

# Restart service
sudo systemctl start olt-bng

# Verify health
sudo systemctl status olt-bng
curl -s http://localhost:8080/health
```

#### Rollback After Traffic Impact

```bash
# Check for active subscribers
curl -s http://localhost:8080/metrics | grep bng_active_sessions_total

# Graceful drain (if supported)
curl -X POST http://localhost:8080/admin/drain

# Wait for sessions to clear (or force if critical)
sleep 60

# Stop and rollback
sudo systemctl stop olt-bng
# ... restore steps as above ...
sudo systemctl start olt-bng
```

### Nexus Rollback

#### Rollback to Previous Version

```bash
# Check current deployment
kubectl describe statefulset nexus -n bng-system | grep Image

# Rollback to previous revision
kubectl rollout undo statefulset/nexus -n bng-system

# Watch rollout
kubectl rollout status statefulset/nexus -n bng-system

# Verify health
kubectl get pods -n bng-system -l app=nexus
```

#### Rollback to Specific Version

```bash
# List rollout history
kubectl rollout history statefulset/nexus -n bng-system

# Rollback to specific revision
kubectl rollout undo statefulset/nexus -n bng-system --to-revision=2
```

#### Emergency Pod Restart

```bash
# Delete pods to force restart with previous config
kubectl delete pod -n bng-system -l app=nexus

# Pods will be recreated by StatefulSet
kubectl get pods -n bng-system -l app=nexus -w
```

---

## Common Issues and Troubleshooting

### BNG Issues

#### eBPF Program Fails to Load

**Symptoms:** Service fails to start, logs show "failed to load BPF program"

**Resolution:**
```bash
# Check kernel version (needs 5.10+)
uname -r

# Verify BPF filesystem mounted
mount | grep bpf
# If not mounted:
sudo mount -t bpf bpf /sys/fs/bpf

# Check for conflicting XDP programs
sudo bpftool net show

# Increase locked memory limit
sudo sysctl -w kernel.unprivileged_bpf_disabled=0
ulimit -l unlimited
```

#### DHCP Requests Not Processed

**Symptoms:** Subscribers not receiving IP addresses

**Resolution:**
```bash
# Verify XDP attached to correct interface
sudo bpftool net show dev eth1

# Check for packet drops
sudo bpftool map dump name dhcp_stats

# Monitor DHCP traffic
sudo tcpdump -i eth1 port 67 or port 68 -vv

# Check slow path logs
sudo journalctl -u olt-bng -f | grep -i dhcp

# Verify Nexus connectivity
curl -s http://nexus.example.com:9000/health
```

#### Nexus Connection Failures

**Symptoms:** BNG logs show "failed to connect to nexus"

**Resolution:**
```bash
# Test network connectivity
nc -zv nexus.example.com 9000

# Verify DNS resolution
dig nexus.example.com

# Check firewall rules
sudo iptables -L -n | grep 9000

# Test API directly
curl -v http://nexus.example.com:9000/health

# Check BNG config for correct endpoints
cat /etc/olt-bng/config.yaml | grep -A5 nexus
```

#### High CPU Usage

**Symptoms:** CPU consistently above 80%

**Resolution:**
```bash
# Check DHCP request rate
curl -s http://localhost:8080/metrics | grep dhcp_requests_total

# Verify cache hit rate (should be >95%)
curl -s http://localhost:8080/metrics | grep dhcp_cache_hit_rate

# Check for slow path overflow
sudo journalctl -u olt-bng | grep -i "slow path"

# Increase eBPF map size if needed
# (requires config change and restart)
```

### Nexus Issues

#### Cluster Not Forming

**Symptoms:** Pods running but not discovering peers

**Resolution:**
```bash
# Check P2P port connectivity between pods
kubectl exec -n bng-system nexus-0 -- nc -zv nexus-1.nexus.bng-system.svc.cluster.local 33123

# Verify headless service DNS
kubectl exec -n bng-system nexus-0 -- nslookup nexus.bng-system.svc.cluster.local

# Check for network policy blocking
kubectl get networkpolicy -n bng-system

# Review P2P bootstrap configuration
kubectl get configmap nexus-config -n bng-system -o yaml | grep -A10 p2p
```

#### CLSet Sync Failures

**Symptoms:** Data inconsistency between nodes

**Resolution:**
```bash
# Check CLSet sync metrics
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9002/metrics | grep clset

# Review sync logs
kubectl logs -n bng-system nexus-0 | grep -i "sync\|clset"

# Force resync (if available)
kubectl exec -n bng-system nexus-0 -- curl -X POST localhost:9000/admin/resync

# Check for clock skew between nodes
for i in 0 1 2; do
  echo "nexus-$i: $(kubectl exec -n bng-system nexus-$i -- date)"
done
```

#### Persistent Volume Issues

**Symptoms:** Pod stuck in Pending, PVC not bound

**Resolution:**
```bash
# Check PVC status
kubectl get pvc -n bng-system

# Describe PVC for events
kubectl describe pvc nexus-data-nexus-0 -n bng-system

# Check storage class
kubectl get storageclass

# Verify available storage
kubectl get pv
```

#### API Timeouts

**Symptoms:** API requests timing out or slow

**Resolution:**
```bash
# Check pod resource usage
kubectl top pods -n bng-system

# Review request latency metrics
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9002/metrics | grep api_request_duration

# Check for connection limits
kubectl logs -n bng-system nexus-0 | grep -i "connection\|limit"

# Scale up if needed
kubectl scale statefulset nexus -n bng-system --replicas=5
```

### General Troubleshooting Commands

```bash
# BNG comprehensive status
sudo systemctl status olt-bng
sudo journalctl -u olt-bng --since "1 hour ago" | tail -100
sudo bpftool prog show
sudo bpftool map show
curl -s http://localhost:8080/health
curl -s http://localhost:9090/metrics | head -50

# Nexus comprehensive status
kubectl get all -n bng-system
kubectl describe statefulset nexus -n bng-system
kubectl logs -n bng-system nexus-0 --tail=100
kubectl exec -n bng-system nexus-0 -- curl -s localhost:9000/health

# Network diagnostics
tcpdump -i any port 67 or port 68 or port 9000 -c 20
netstat -tlnp | grep -E "8080|9000|9090"
```

---

## Appendix: Deployment Checklist Template

```
## Deployment: [VERSION] to [ENVIRONMENT]
Date: YYYY-MM-DD
Engineer: [NAME]
Change Request: [TICKET-ID]

### Pre-Deployment
- [ ] Change request approved
- [ ] Maintenance window scheduled
- [ ] Backup completed
- [ ] Rollback plan documented

### BNG Deployment
- [ ] Binary downloaded and verified
- [ ] Configuration deployed
- [ ] Service restarted
- [ ] eBPF programs loaded
- [ ] Health check passed
- [ ] Nexus registration confirmed

### Nexus Deployment
- [ ] Manifests applied
- [ ] Rollout completed
- [ ] Cluster formation verified
- [ ] Health checks passed
- [ ] API accessible

### Post-Deployment
- [ ] Monitoring alerts re-enabled
- [ ] Subscriber traffic verified
- [ ] Metrics baseline established
- [ ] Documentation updated

### Sign-off
Engineer: _____________ Date: _______
Reviewer: _____________ Date: _______
```
