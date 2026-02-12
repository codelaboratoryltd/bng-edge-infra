# BGP Scale Testing Guide

This document describes how to scale-test the BNG's BGP/FRR integration with 1,000 to 10,000+ concurrent subscriber routes.

## Overview

Each subscriber session results in a /32 host route injected into FRR via the `SubscriberRouteManager`. These routes are advertised to upstream BGP neighbors. Scale testing validates that the BNG can handle route injection, convergence, and failover at WISP-level subscriber counts.

## Architecture

```
                         +-----------------+
                         |   FRR (bgpd)    |
                         |  AS 65100       |
                         +--------+--------+
                                  |
                    vtysh commands (route inject/withdraw)
                                  |
                         +--------+--------+
                         |  BNG Process    |
                         |  subscriber     |
                         |  route manager  |
                         +--------+--------+
                                  |
                     session events (up/down)
                                  |
                         +--------+--------+
                         |  DHCP / RADIUS  |
                         |  session mgmt   |
                         +-----------------+
```

The `SubscriberRouteManager` injects routes in batches (default: 100 routes per batch, 100ms delay between batches) to avoid overwhelming FRR's vtysh interface.

## Prerequisites

- BNG binary built with BGP support (`make build`)
- FRR installed and running (`bgpd`, `bfdd`, `zebra`)
- At least one BGP neighbor configured and Established
- Prometheus and Grafana for metrics collection (optional but recommended)

## Test Plan

### Test 1: 1,000 Concurrent Routes

**Goal**: Baseline performance at small WISP scale (single tower site).

```bash
# Start BNG with BGP enabled
./bng run \
  --bgp-enabled \
  --bgp-local-as=65100 \
  --bgp-router-id=10.0.0.1 \
  --api-port=8080

# Inject 1,000 subscriber routes via the API
for i in $(seq 1 1000); do
  IP="10.100.$((i / 256)).$((i % 256))"
  curl -s -X POST http://localhost:8080/api/v1/sessions \
    -H "Content-Type: application/json" \
    -d "{\"subscriber_id\":\"sub-$i\",\"ip\":\"$IP\"}" &
  # Batch in groups of 50 to avoid overwhelming the API
  if [ $((i % 50)) -eq 0 ]; then
    wait
    sleep 0.1
  fi
done
wait
```

**Expected Results**:

| Metric | Target |
|--------|--------|
| Total injection time | < 30s |
| Route injection rate | > 50 routes/sec |
| FRR memory increase | < 50 MB |
| BNG CPU during injection | < 30% |
| BGP convergence to neighbor | < 5s after last route |

### Test 2: 5,000 Concurrent Routes

**Goal**: Medium WISP scale (multiple tower sites, single BNG).

```bash
# Same setup as Test 1, but 5,000 routes
for i in $(seq 1 5000); do
  IP="10.$((100 + i / 65536)).$((i / 256 % 256)).$((i % 256))"
  curl -s -X POST http://localhost:8080/api/v1/sessions \
    -H "Content-Type: application/json" \
    -d "{\"subscriber_id\":\"sub-$i\",\"ip\":\"$IP\"}" &
  if [ $((i % 100)) -eq 0 ]; then
    wait
    sleep 0.1
  fi
done
wait
```

**Expected Results**:

| Metric | Target |
|--------|--------|
| Total injection time | < 120s |
| Route injection rate | > 50 routes/sec |
| FRR memory increase | < 200 MB |
| BNG CPU during injection | < 40% |
| BGP convergence to neighbor | < 10s after last route |
| vtysh command latency P99 | < 100ms |

### Test 3: 10,000 Concurrent Routes

**Goal**: Large WISP scale (full deployment, stress test).

```bash
# Same pattern scaled to 10,000
# Consider using the bulk injection API instead:
curl -s -X POST http://localhost:8080/api/v1/routes/bulk \
  -H "Content-Type: application/json" \
  -d @routes-10k.json
```

Generate the test data file:

```bash
python3 -c "
import json
routes = []
for i in range(1, 10001):
    ip = f'10.{100 + i // 65536}.{(i // 256) % 256}.{i % 256}'
    routes.append({'subscriber_id': f'sub-{i}', 'ip': ip, 'session_id': f'sess-{i}'})
json.dump({'routes': routes}, open('routes-10k.json', 'w'))
print(f'Generated {len(routes)} routes')
"
```

**Expected Results**:

| Metric | Target |
|--------|--------|
| Total injection time | < 300s |
| Route injection rate | > 40 routes/sec |
| FRR memory (total) | < 1 GB |
| BNG memory (total) | < 512 MB |
| BNG CPU during injection | < 50% |
| BGP convergence to neighbor | < 30s after last route |
| vtysh command latency P99 | < 200ms |
| Route table size in FRR | ~10,000 entries |

## Measuring Convergence Time

BGP convergence time is measured from when the last route is injected until all routes appear in the neighbor's RIB.

### On the BNG (FRR local)

```bash
# Check announced routes count
vtysh -c "show bgp ipv4 unicast summary" | grep -E "^[0-9]"

# Count total routes in BGP RIB
vtysh -c "show bgp ipv4 unicast" | grep -c "Network"

# Watch convergence in real-time
watch -n 1 'vtysh -c "show bgp summary json" | jq ".ipv4Unicast.peers | to_entries[] | {peer: .key, pfxSnt: .value.pfxSnt}"'
```

### On the upstream neighbor

```bash
# Check received routes from BNG
vtysh -c "show bgp ipv4 unicast neighbors 10.0.0.1 received-routes" | wc -l

# Compare sent vs received
BNG_SENT=$(vtysh -c "show bgp summary json" | jq '.ipv4Unicast.peers["10.0.1.1"].pfxSnt')
UPSTREAM_RECV=$(ssh upstream vtysh -c "show bgp summary json" | jq '.ipv4Unicast.peers["10.0.0.1"].pfxRcd')
echo "BNG sent: $BNG_SENT, Upstream received: $UPSTREAM_RECV"
```

### Using Prometheus metrics

```promql
# Active subscriber routes
bng_routing_subscriber_routes_active

# Route injection rate (routes/sec over 5m)
rate(bng_routing_subscriber_routes_injected_total[5m])

# Injection latency P99
histogram_quantile(0.99, rate(bng_routing_route_injection_latency_seconds_bucket[5m]))

# BGP neighbors established
bng_routing_bgp_neighbors_established

# Prefixes announced
bng_routing_bgp_prefixes_announced

# FRR command latency P99
histogram_quantile(0.99, rate(bng_routing_frr_command_latency_seconds_bucket[5m]))
```

## BFD Failover Timing Validation

BFD (Bidirectional Forwarding Detection) provides sub-second failure detection.

### Default configuration

```
BFD timers: rx=100ms, tx=100ms, detect-multiplier=3
Detection time: 100ms * 3 = 300ms
```

### Aggressive configuration

```
BFD timers: rx=50ms, tx=50ms, detect-multiplier=3
Detection time: 50ms * 3 = 150ms
```

### Testing failover

1. Establish BGP session with BFD enabled between BNG and upstream.
2. Verify BFD session is Up:
   ```bash
   vtysh -c "show bfd peers"
   ```
3. Simulate link failure (drop interface or add iptables rule):
   ```bash
   # Simulate failure on upstream interface
   sudo iptables -A INPUT -s 10.0.1.1 -j DROP
   ```
4. Measure time from failure to BGP session teardown:
   ```bash
   # Watch BFD state (polls every second, BFD detects faster)
   watch -n 0.1 'vtysh -c "show bfd peers json" | jq ".[0].status"'
   ```
5. Verify failover to backup path:
   ```bash
   # Check routing table switched to backup next-hop
   ip route show table main | grep default
   ```
6. Remove failure and verify recovery:
   ```bash
   sudo iptables -D INPUT -s 10.0.1.1 -j DROP
   ```

### Expected BFD failover results

| Scenario | Detection Time | BGP Teardown | Total Failover |
|----------|---------------|--------------|----------------|
| Default (100ms/3x) | ~300ms | < 50ms | < 350ms |
| Aggressive (50ms/3x) | ~150ms | < 50ms | < 200ms |
| Without BFD (hold-timer) | 90s (default) | immediate | ~90s |

### Prometheus metrics for BFD

```promql
# BFD peers up/down
bng_routing_bfd_peers_up
bng_routing_bfd_peers_down

# BFD state changes (failover events)
rate(bng_routing_bfd_state_changes_total[5m])
```

## CPU/Memory Usage Expectations

### FRR (bgpd) resource usage

| Route Count | Memory (RSS) | CPU (steady state) | CPU (convergence) |
|-------------|-------------|-------------------|-------------------|
| 1,000 | ~80 MB | < 1% | < 5% |
| 5,000 | ~150 MB | < 2% | < 10% |
| 10,000 | ~300 MB | < 3% | < 15% |
| 20,000 | ~500 MB | < 5% | < 25% |

### BNG process resource usage

| Route Count | Memory (RSS) | CPU (injection) | CPU (steady state) |
|-------------|-------------|----------------|-------------------|
| 1,000 | ~50 MB overhead | < 10% | < 1% |
| 5,000 | ~100 MB overhead | < 20% | < 2% |
| 10,000 | ~200 MB overhead | < 30% | < 3% |

*Overhead = additional memory beyond base BNG process for route state tracking.*

### Monitoring commands

```bash
# FRR memory usage
vtysh -c "show memory bgpd"

# BNG process memory
ps -o rss,vsz -p $(pgrep bng) | awk 'NR==2{printf "RSS: %d MB, VSZ: %d MB\n", $1/1024, $2/1024}'

# System-wide CPU during test
mpstat 1

# Per-process CPU
pidstat -p $(pgrep bng),$(pgrep bgpd) 1
```

## Running Scale Tests in k3d

Use the `demo-i` (WISP multi-homing) demo as a base:

```bash
# Start the WISP demo with monitoring
tilt up demo-i infra

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l demo=wisp-multihoming -n demo-wisp-multihoming --timeout=120s

# Port-forward to BNG API
# (Tilt does this automatically: localhost:8089)

# Run scale test
./scripts/bgp-scale-test.sh 1000   # 1K routes
./scripts/bgp-scale-test.sh 5000   # 5K routes
./scripts/bgp-scale-test.sh 10000  # 10K routes

# Check results in Grafana (localhost:3000)
# Dashboard: "BNG Routing" -> BGP panel
```

## Bulk Route Withdrawal Test

After injection, test bulk withdrawal (simulates BNG graceful shutdown):

```bash
# Withdraw all routes
curl -s -X DELETE http://localhost:8080/api/v1/routes/bulk

# Measure withdrawal time and verify upstream neighbor
# receives all withdrawals
watch -n 1 'vtysh -c "show bgp summary json" | \
  jq ".ipv4Unicast.peers | to_entries[] | {peer: .key, pfxSnt: .value.pfxSnt}"'
```

**Expected**: All routes withdrawn within 60s for 10K routes (batch withdrawal with 100ms inter-batch delay).

## Route Churn Test

Simulate realistic subscriber connect/disconnect patterns:

```bash
# Inject 5,000 routes, then continuously churn 10% per minute
# (500 disconnects + 500 new connects per minute)
for round in $(seq 1 10); do
  echo "Round $round: churning 500 routes..."
  # Withdraw random 500
  for i in $(shuf -i 1-5000 -n 500); do
    curl -s -X DELETE "http://localhost:8080/api/v1/sessions/sub-$i" &
  done
  wait
  # Inject 500 new
  BASE=$((5000 + (round - 1) * 500))
  for i in $(seq 1 500); do
    N=$((BASE + i))
    IP="10.$((100 + N / 65536)).$((N / 256 % 256)).$((N % 256))"
    curl -s -X POST http://localhost:8080/api/v1/sessions \
      -H "Content-Type: application/json" \
      -d "{\"subscriber_id\":\"sub-$N\",\"ip\":\"$IP\"}" &
  done
  wait
  sleep 6  # ~10 rounds/minute
done
```

**Expected**: Route count stays stable at ~5,000. FRR command latency stays under 200ms P99 throughout churn.

## Troubleshooting

### Routes not appearing on upstream neighbor

1. Check BGP session is Established: `vtysh -c "show bgp summary"`
2. Check routes are in local RIB: `vtysh -c "show bgp ipv4 unicast"`
3. Check route-map isn't filtering: `vtysh -c "show route-map"`
4. Check FRR logs: `journalctl -u frr -f`

### High vtysh command latency

1. Check FRR CPU: `vtysh -c "show memory bgpd"`
2. Reduce batch size in BNG config (default 100)
3. Increase inter-batch delay (default 100ms)
4. Check for zebra/bgpd lock contention in FRR logs

### BFD not detecting failure

1. Verify BFD session exists: `vtysh -c "show bfd peers"`
2. Check BFD timers match on both sides
3. Verify BFD packets aren't being firewalled (UDP 3784/3785)
4. Check for asymmetric timers (negotiation issue)
