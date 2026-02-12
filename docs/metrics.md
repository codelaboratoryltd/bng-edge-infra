# Prometheus Metrics Reference

All Prometheus metrics exposed by BNG and Nexus.

BNG serves metrics on its `--metrics-addr` (default `:9090/metrics`).
Nexus serves metrics on its `--metrics-port` (default `:9002/metrics`).

## BNG Metrics

### DHCP

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_dhcp_requests_total` | counter | `path`, `result` | Total DHCP requests. `path` is `fast` or `slow`; `result` is `success` or `error`. |
| `bng_dhcp_latency_seconds` | histogram | `path` | DHCP request latency by path. Buckets: 10us, 50us, 100us, 500us, 1ms, 5ms, 10ms, 50ms, 100ms. |
| `bng_dhcp_cache_hit_rate` | gauge | | Ratio of DHCP requests served by the eBPF fast path (0.0--1.0). |
| `bng_dhcp_active_leases` | gauge | | Number of active DHCP leases. |

### eBPF

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_ebpf_fastpath_hits_total` | counter | | Total DHCP requests served by eBPF fast path (XDP_TX). |
| `bng_ebpf_fastpath_misses_total` | counter | | Total DHCP requests passed to Go slow path (XDP_PASS). |
| `bng_ebpf_errors_total` | counter | | Total eBPF processing errors. |
| `bng_ebpf_cache_expired_total` | counter | | Total expired cache entries evicted from eBPF maps. |
| `bng_ebpf_map_entries` | gauge | `map_name` | Number of entries in each eBPF map. |

### Circuit-ID

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_circuit_id_hash_collisions_total` | counter | | Total FNV-1a hash collisions detected in the circuit-ID map. |
| `bng_circuit_id_collision_rate` | gauge | | Ratio of circuit-ID map insertions that resulted in hash collisions. |

### IP Pool

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_pool_utilization_ratio` | gauge | `pool_id`, `pool_name` | IP pool utilization ratio (0.0--1.0). |
| `bng_pool_available_ips` | gauge | `pool_id`, `pool_name` | Available IPs in pool. |
| `bng_pool_allocated_ips` | gauge | `pool_id`, `pool_name` | Allocated IPs in pool. |

### Session

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_session_active` | gauge | `type`, `state` | Number of active sessions by type and state. |
| `bng_session_total` | counter | `type`, `outcome` | Total sessions by outcome (`created`, `terminated`). |
| `bng_session_duration_seconds` | histogram | `type` | Session duration. Buckets: 1m, 5m, 10m, 30m, 1h, 2h, 4h, 8h, 12h, 24h. |
| `bng_session_bytes_in_total` | counter | `type`, `isp_id` | Total bytes received by session type and ISP. |
| `bng_session_bytes_out_total` | counter | `type`, `isp_id` | Total bytes sent by session type and ISP. |

### NAT

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_nat_bindings_active` | gauge | | Number of active NAT bindings. |
| `bng_nat_translations_total` | counter | `direction`, `protocol` | Total NAT translations. `direction` is `in` or `out`. |
| `bng_nat_ports_used` | gauge | `public_ip` | NAT ports in use per public IP address. |

### RADIUS

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_radius_requests_total` | counter | `type`, `result`, `server` | Total RADIUS requests by type (auth/acct), result, and server. |
| `bng_radius_latency_seconds` | histogram | `type`, `server` | RADIUS request latency. Buckets: 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s. |
| `bng_radius_timeouts_total` | counter | `server` | Total RADIUS timeouts per server. |

### QoS

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_qos_policies_active` | gauge | | Number of active QoS policies. |
| `bng_qos_packets_dropped_total` | counter | `policy_id`, `direction` | Total packets dropped by QoS. |
| `bng_qos_bytes_dropped_total` | counter | `policy_id`, `direction` | Total bytes dropped by QoS. |

### PPPoE

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_pppoe_sessions_active` | gauge | | Number of active PPPoE sessions. |
| `bng_pppoe_negotiations_total` | counter | `stage`, `result` | Total PPPoE negotiations by stage (PADI, PADO, PADR, PADS, LCP, AUTH, IPCP) and result. |

### Routing / BGP

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_routes_active` | gauge | `table` | Number of active routes by routing table. |
| `bng_bgp_peers_up` | gauge | | Number of BGP peers in established state. |
| `bng_bgp_prefixes_received` | gauge | `peer_ip`, `afi` | Number of prefixes received from a BGP peer, per address family. |

### Subscriber

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `bng_subscriber_total` | gauge | | Total number of subscribers. |
| `bng_subscriber_by_class` | gauge | `class` | Number of subscribers by class (e.g. `residential`, `business`). |
| `bng_subscriber_by_isp` | gauge | `isp_id` | Number of subscribers by ISP. |

---

## Nexus Metrics

### CRDT State

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `nexus_crdt_sync_lag_seconds` | gauge | | Maximum CRDT sync lag across all peers in seconds. |
| `nexus_crdt_peers_connected` | gauge | | Number of peers with CRDT sync data. |

### Failure Detector

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `nexus_failure_detector_nodes_failed_total` | counter | | Total number of node failures detected. |
| `nexus_failure_detector_detection_latency_seconds` | histogram | | Time from node `best_before` to failure detection. Buckets: 1s, 5s, 10s, 30s, 60s, 120s, 300s. |
| `nexus_failure_detector_nodes_monitored` | gauge | | Number of nodes currently being monitored. |
| `nexus_failure_detector_nodes_healthy` | gauge | | Number of nodes currently healthy (not expired). |
| `nexus_failure_detector_nodes_expired` | gauge | | Number of nodes currently expired but not yet failed. |
| `nexus_failure_detector_check_duration_seconds` | histogram | | Duration of each node health check cycle. Uses default Prometheus buckets. |

### Shard Reassignment

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `nexus_reassignment_total` | counter | | Total number of shard reassignment operations. |
| `nexus_reassignment_latency_seconds` | histogram | | Time taken to complete a reassignment operation. Uses default Prometheus buckets. |
| `nexus_reassignment_partitions_moved_total` | counter | | Total number of partitions moved during reassignments. |
| `nexus_reassignment_active_nodes` | gauge | | Number of active nodes in the hashring. |

---

## Useful PromQL Queries

### DHCP Fast Path Hit Rate (5-minute window)

```promql
bng_dhcp_cache_hit_rate
```

### DHCP Request Rate by Path

```promql
rate(bng_dhcp_requests_total[5m])
```

### DHCP P99 Latency (Fast Path)

```promql
histogram_quantile(0.99, rate(bng_dhcp_latency_seconds_bucket{path="fast"}[5m]))
```

### Pool Utilization Alert (> 80%)

```promql
bng_pool_utilization_ratio > 0.80
```

### RADIUS Error Rate

```promql
rate(bng_radius_requests_total{result="error"}[5m])
  / rate(bng_radius_requests_total[5m])
```

### NAT Port Exhaustion Warning

```promql
bng_nat_ports_used / 65535 > 0.80
```

### Nexus CRDT Sync Lag Alert

```promql
nexus_crdt_sync_lag_seconds > 30
```

### Node Failure Rate

```promql
rate(nexus_failure_detector_nodes_failed_total[1h])
```
