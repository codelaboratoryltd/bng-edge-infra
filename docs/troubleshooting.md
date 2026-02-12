# Troubleshooting Guide

Structured troubleshooting for common BNG and Nexus issues.

---

## eBPF

### Program won't load

**Symptoms**: BNG exits with `failed to load eBPF program` or verifier errors.

**Diagnostic commands**:
```bash
# Check kernel version (need 5.10+ for XDP)
uname -r

# Check BPF filesystem is mounted
mount | grep bpf

# Try loading manually to see verifier output
sudo bpftool prog load bpf/dhcp_fastpath.bpf.o /sys/fs/bpf/test

# Check available eBPF program types
sudo bpftool feature probe kernel

# Check BPF JIT is enabled
cat /proc/sys/net/core/bpf_jit_enable
```

**Common causes**:
- Kernel too old (need 5.10+). Upgrade the kernel.
- Missing `CAP_BPF` and `CAP_NET_ADMIN` capabilities. Run with sufficient privileges or add capabilities to the container security context.
- BPF filesystem not mounted. Mount with: `mount -t bpf bpf /sys/fs/bpf`.
- eBPF object file compiled for a different architecture. Rebuild with `make build-ebpf`.

### XDP attachment fails

**Symptoms**: `failed to attach XDP program to interface` or `device busy`.

**Diagnostic commands**:
```bash
# Check if another XDP program is already attached
sudo bpftool net show dev eth1

# List all XDP programs
sudo bpftool prog show | grep xdp

# Check interface exists and is up
ip link show eth1

# Check driver XDP support
ethtool -i eth1 | grep driver
```

**Common causes**:
- Another XDP program is already attached. Detach it first: `sudo bpftool net detach xdp dev eth1`.
- Driver does not support native XDP. The BNG will fall back to `XDP_SKB` mode (slower). Check `--bpf-path` points to the correct object file.
- Interface does not exist or is down.

### eBPF map errors

**Symptoms**: `failed to create map` or `map full` errors in logs.

**Diagnostic commands**:
```bash
# List all eBPF maps
sudo bpftool map show

# Check map sizes
sudo bpftool map show name subscriber_pools

# Dump map contents
sudo bpftool map dump name subscriber_pools | head -20

# Check system limits
ulimit -l          # locked memory limit
cat /proc/sys/kernel/bpf_map_max_entries
```

**Common causes**:
- Locked memory limit too low. Increase with `ulimit -l unlimited` or set `LimitMEMLOCK=infinity` in the systemd unit.
- Map capacity exceeded (too many subscribers for the configured map size).

### Verifier rejection

**Symptoms**: Long verifier error output mentioning instruction counts or stack depth.

**Diagnostic commands**:
```bash
# Load with verbose verifier output
sudo bpftool prog load bpf/dhcp_fastpath.bpf.o /sys/fs/bpf/test 2>&1 | tail -50

# Check program complexity
sudo bpftool prog show name dhcp_fastpath
```

**Common causes**:
- Program exceeds instruction limit (1M instructions on 5.2+). Simplify the eBPF program.
- Unbounded loops detected. Use `#pragma unroll` or bounded loop constructs.
- Stack depth exceeded (512 bytes). Reduce local variable usage.

---

## DHCP

### No DHCP responses

**Symptoms**: Clients send DISCOVER but never receive OFFER.

**Diagnostic commands**:
```bash
# Check DHCP packets arriving on the interface
sudo tcpdump -i eth1 port 67 or port 68 -vv

# Check XDP program is attached
sudo bpftool net show dev eth1

# Check eBPF fast path stats
curl -s localhost:9090/metrics | grep bng_ebpf_fastpath

# Check DHCP server is running
curl -s localhost:9090/health

# Check pool has available IPs
curl -s localhost:9090/metrics | grep bng_pool_available
```

**Common causes**:
- XDP program not attached. Check BNG startup logs.
- Wrong interface specified (`--interface`).
- IP pool exhausted. Check `bng_pool_available_ips` metric.
- Firewall blocking UDP ports 67/68.

### Slow path only (no fast path hits)

**Symptoms**: All requests go through slow path; `bng_ebpf_fastpath_hits_total` stays at zero.

**Diagnostic commands**:
```bash
# Check cache hit rate
curl -s localhost:9090/metrics | grep bng_dhcp_cache_hit_rate

# Check eBPF map entries
curl -s localhost:9090/metrics | grep bng_ebpf_map_entries

# Dump the subscriber map
sudo bpftool map dump name subscriber_pools
```

**Common causes**:
- eBPF program loaded in `XDP_SKB` mode (bypasses fast path for some drivers).
- Subscriber MAC addresses not populated in eBPF maps. Check RADIUS integration or that the slow path is inserting entries.
- eBPF map entries expiring too quickly.

### High DHCP latency

**Symptoms**: `bng_dhcp_latency_seconds` P99 exceeds targets (>100us for fast path, >10ms for slow path).

**Diagnostic commands**:
```bash
# Check latency distribution
curl -s localhost:9090/metrics | grep bng_dhcp_latency_seconds

# Check system CPU load
top -b -n1 | head -5

# Check for lock contention
go tool pprof http://localhost:9090/debug/pprof/mutex

# Check network latency to RADIUS (if slow path)
ping -c 10 <radius-server>
```

**Common causes**:
- Fast path: CPU contention or high interrupt rate on the interface. Consider CPU pinning.
- Slow path: RADIUS server latency. Check `bng_radius_latency_seconds`.
- Slow path: Nexus server latency (if using `--nexus-url`).
- Lock contention in the Go DHCP server under high load.

---

## Nexus

### Peer discovery not working

**Symptoms**: Nexus nodes start but don't find each other; `nexus_crdt_peers_connected` stays at 0.

**Diagnostic commands**:
```bash
# Check Nexus logs for discovery errors
kubectl logs <nexus-pod> | grep -i "discovery\|peer\|connect"

# Check DNS resolution (for DNS discovery)
nslookup <headless-service-name>
dig SRV _nexus._tcp.<namespace>.svc.cluster.local

# Check P2P port connectivity
nc -zv <peer-ip> 33123

# Check rendezvous server (for rendezvous discovery)
curl -s http://<rendezvous-host>:8765/
```

**Common causes**:
- DNS discovery: Headless service not configured correctly or pods not ready.
- Rendezvous discovery: Rendezvous server not running or unreachable.
- P2P port (`--p2p-port`, default 33123) blocked by network policy or firewall.
- Bootstrap addresses wrong or stale.
- `--p2p` flag not set (running in standalone mode).

### CRDT sync lag

**Symptoms**: `nexus_crdt_sync_lag_seconds` is high or growing.

**Diagnostic commands**:
```bash
# Check sync lag
curl -s localhost:9002/metrics | grep nexus_crdt_sync_lag

# Check connected peers
curl -s localhost:9002/metrics | grep nexus_crdt_peers_connected

# Check network between peers
ping -c 10 <peer-ip>

# Check Nexus logs for sync errors
kubectl logs <nexus-pod> | grep -i "sync\|crdt\|pubsub"
```

**Common causes**:
- Network partition between peers.
- One or more peers overloaded (high CPU/memory).
- Large number of concurrent writes causing pubsub backlog.
- Peer discovery issues (see above).

### API errors (HTTP 5xx)

**Symptoms**: API requests to Nexus return 500 errors.

**Diagnostic commands**:
```bash
# Check Nexus health
curl -s http://localhost:9000/health

# Check API endpoints
curl -s http://localhost:9000/api/v1/pools

# Check logs for errors
kubectl logs <nexus-pod> | grep -i "error\|panic"

# Check resource usage
kubectl top pod <nexus-pod>
```

**Common causes**:
- BadgerDB corruption (if using P2P mode). Try restarting with a fresh data directory.
- Out of memory. Increase pod memory limits.
- Rate limited. Check `--rate-limit` configuration.

---

## Kubernetes

### Pod startup failures

**Symptoms**: BNG or Nexus pods stuck in `CrashLoopBackOff` or `Error` state.

**Diagnostic commands**:
```bash
# Check pod status and events
kubectl describe pod <pod-name>

# Check pod logs
kubectl logs <pod-name> --previous

# Check resource limits
kubectl get pod <pod-name> -o yaml | grep -A5 resources

# Check image availability
kubectl get events --field-selector reason=Failed
```

**Common causes**:
- BNG pod: Missing `CAP_BPF`, `CAP_NET_ADMIN` capabilities or `hostNetwork: true`.
- BNG pod: `/sys/fs/bpf` not mounted as a volume.
- Image pull errors. Check registry credentials and image tags.
- Insufficient CPU or memory. Check resource requests/limits.

### Cilium issues

**Symptoms**: Pods can't communicate, network policies not enforced, Hubble not working.

**Diagnostic commands**:
```bash
# Check Cilium status
cilium status

# Check Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium

# Check Cilium endpoints
cilium endpoint list

# Check Hubble flows
hubble observe --last 20

# Verify kube-proxy replacement
cilium status | grep KubeProxy
```

**Common causes**:
- Flannel still running (k3d default). Ensure `--flannel-backend=none` in k3d config.
- Cilium agent not ready. Check for `Init:CrashLoopBackOff` in kube-system pods.
- Hubble not enabled. Reinstall Cilium with `--set hubble.enabled=true`.

### Resource limits

**Symptoms**: Pods evicted or OOMKilled.

**Diagnostic commands**:
```bash
# Check pod resource usage
kubectl top pod

# Check node resource usage
kubectl top node

# Check for OOMKilled pods
kubectl get events --field-selector reason=OOMKilling

# Check pod QoS class
kubectl get pod <pod-name> -o jsonpath='{.status.qosClass}'
```

**Recommended resource settings**:

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| BNG | 500m | 2000m | 256Mi | 1Gi |
| Nexus | 250m | 1000m | 128Mi | 512Mi |
| Cilium Agent | 100m | 500m | 128Mi | 512Mi |

---

## HA (High Availability)

### Failover not working

**Symptoms**: Standby BNG does not take over when active goes down.

**Diagnostic commands**:
```bash
# Check HA sync status
curl -s localhost:9090/metrics | grep ha

# Check HA role
kubectl logs <bng-pod> | grep -i "ha\|role\|active\|standby"

# Check connectivity between active and standby
nc -zv <peer-host> 9000

# Check TLS configuration (if using --ha-tls-*)
openssl s_client -connect <peer-host>:9000
```

**Common causes**:
- `--ha-peer` not set on standby node.
- `--ha-role` not configured (must be `active` or `standby`).
- Network connectivity between active and standby nodes.
- TLS certificate mismatch or expired certificates.
- Standby not monitoring active's health.

### Sync lag between HA peers

**Symptoms**: Standby has stale data compared to active.

**Diagnostic commands**:
```bash
# Check session counts on both nodes
curl -s http://<active>:9090/metrics | grep bng_dhcp_active_leases
curl -s http://<standby>:9090/metrics | grep bng_dhcp_active_leases

# Check HA sync logs
kubectl logs <bng-standby-pod> | grep -i "sync\|replicate"
```

**Common causes**:
- Network bandwidth between peers insufficient for sync volume.
- High write rate exceeding sync capacity.
- TLS handshake overhead slowing sync.

---

## General Diagnostics

### Checking overall health

```bash
# BNG health check
curl -s http://localhost:9090/health

# Nexus health check
curl -s http://localhost:9000/health

# All metrics
curl -s http://localhost:9090/metrics | head -50

# Kubernetes pod status
kubectl get pods -o wide

# Recent events
kubectl get events --sort-by=.lastTimestamp | tail -20
```

### Log level adjustment

BNG uses structured JSON logging. Set the level at startup:

```bash
bng run --log-level debug   # Most verbose
bng run --log-level info    # Default
bng run --log-level warn    # Warnings and errors only
bng run --log-level error   # Errors only
```

### Performance profiling

For Go-level profiling (slow path / userspace):

```bash
# CPU profile
go tool pprof http://localhost:9090/debug/pprof/profile?seconds=30

# Memory profile
go tool pprof http://localhost:9090/debug/pprof/heap

# Goroutine dump
curl http://localhost:9090/debug/pprof/goroutine?debug=2
```

For eBPF-level profiling (fast path):

```bash
# Check eBPF program run time
sudo bpftool prog show name dhcp_fastpath

# Trace eBPF events
sudo bpftool prog tracelog

# Performance events
sudo perf stat -e bpf:* -a sleep 10
```
