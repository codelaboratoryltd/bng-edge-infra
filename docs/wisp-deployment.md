# WISP Deployment Guide

This guide covers deploying the BNG for Wireless Internet Service Provider (WISP) environments with centralized subscriber management, DHCP relay, BGP multi-homing, and integration with common ISP billing platforms.

## Deployment Model: Centralized BNG

WISPs typically have a hub-and-spoke topology: a central POP (Point of Presence) with fiber uplinks, and remote tower sites connected via backhaul links. The BNG runs at the central POP rather than on each tower.

```
                    Internet
                   /        \
            +-----+--+  +---+------+
            | ISP-A   |  | ISP-B    |
            | AS 65200|  | AS 65300 |
            +----+----+  +----+-----+
                 |             |
            BGP (primary) BGP (backup)
                 |             |
            +----+-------------+-----+
            |    Central POP (BNG)   |
            |    AS 65100            |
            |                        |
            |  +------------------+  |
            |  | BNG Process      |  |
            |  | - DHCP server    |  |
            |  | - RADIUS client  |  |
            |  | - BGP/FRR        |  |
            |  | - eBPF fast path |  |
            |  +------------------+  |
            |                        |
            |  +------------------+  |
            |  | Nexus            |  |
            |  | - IP allocation  |  |
            |  | - Session state  |  |
            |  +------------------+  |
            +-+------+-------+-----+-+
              |      |       |     |
         backhaul links (fiber/wireless)
              |      |       |     |
          +---+-+ +--+--+ +-+--+ +-+---+
          |Tower| |Tower| |Tower| |Tower|
          |  A  | |  B  | |  C  | |  D  |
          +--+--+ +--+--+ +--+--+ +--+--+
             |       |       |       |
         subscribers (CPE routers with DHCP relay)
```

### Why centralized (not per-tower)?

1. **Simpler management**: One BNG to configure, monitor, and update.
2. **Shared IP pools**: No per-tower pool fragmentation; one large pool for the whole network.
3. **Single BGP peering point**: Upstream ISPs peer with one AS, not many.
4. **Easier failover**: Active/standby BNG pair at the POP, rather than redundancy at every tower.
5. **Lower cost**: Tower hardware only needs basic routing (relay), not full BNG capability.

### When to use per-tower BNG

Per-tower BNG (the OLT model from the main architecture) is better when:
- Towers have direct fiber uplinks (not backhauled through a central POP)
- Subscriber counts per tower exceed 2,000
- Backhaul bandwidth is constrained (subscriber traffic should not traverse backhaul)
- Sites need to operate independently during POP outages

## DHCP Relay Architecture

Tower routers act as DHCP relay agents (RFC 3046), forwarding subscriber DHCP requests to the central BNG.

```
Subscriber CPE          Tower Router           Central BNG
     |                       |                      |
     |--- DHCP DISCOVER ---->|                      |
     |   (broadcast)         |                      |
     |                       |--- DHCP DISCOVER --->|
     |                       |   (unicast, giaddr   |
     |                       |    set, Option 82)   |
     |                       |                      |
     |                       |<-- DHCP OFFER -------|
     |                       |   (unicast to giaddr)|
     |<-- DHCP OFFER --------|                      |
     |   (unicast/broadcast) |                      |
     |                       |                      |
     |--- DHCP REQUEST ----->|                      |
     |                       |--- DHCP REQUEST ---->|
     |                       |<-- DHCP ACK ---------|
     |<-- DHCP ACK ----------|                      |
```

### Key fields in relayed DHCP

- **giaddr** (Gateway IP Address): Set by the relay agent to its own IP. The BNG uses this to identify which subnet/tower the request came from.
- **Option 82** (Relay Agent Information): Contains sub-options identifying the physical port and relay agent. See [DHCP Relay Technical Guide](dhcp-relay.md) for details.

### Tower router configuration

Example for MikroTik RouterOS (common in WISP deployments):

```
/ip dhcp-relay
add dhcp-server=10.0.0.1 interface=bridge-subscribers name=relay-to-bng \
    add-relay-info=yes relay-info-remote-id=tower-a
```

Example for Ubiquiti EdgeRouter:

```
set service dhcp-relay interface eth1
set service dhcp-relay server 10.0.0.1
set service dhcp-relay relay-options relay-agents-packets append
set service dhcp-relay relay-options circuit-id-format "%h:%p"
```

## BGP Configuration for Dual Upstream

### Topology

```
                ISP-A (AS 65200)         ISP-B (AS 65300)
                Primary upstream         Backup upstream
                     |                        |
                10.0.1.1/30              10.0.2.1/30
                     |                        |
                10.0.1.2/30              10.0.2.2/30
                     |                        |
              +------+------------------------+------+
              |             BNG (AS 65100)            |
              |          router-id: 10.0.0.1          |
              +---------------------------------------+
```

### BNG BGP configuration

The BNG reads BGP neighbor configuration from a JSON file (mounted via ConfigMap in Kubernetes, or placed in `/etc/bng/` on bare metal).

```json
{
  "local_as": 65100,
  "router_id": "10.0.0.1",
  "neighbors": [
    {
      "address": "10.0.1.1",
      "remote_as": 65200,
      "description": "ISP-A-Primary",
      "bfd_enabled": true,
      "next_hop_self": true,
      "route_map_in": "ISP-A-IN",
      "route_map_out": "ISP-A-OUT"
    },
    {
      "address": "10.0.2.1",
      "remote_as": 65300,
      "description": "ISP-B-Backup",
      "bfd_enabled": true,
      "next_hop_self": true,
      "route_map_in": "ISP-B-IN",
      "route_map_out": "ISP-B-OUT"
    }
  ]
}
```

### Route-maps for traffic engineering

Use BGP communities and local-preference to control traffic flow:

```
! Prefer ISP-A for inbound (higher local-pref)
route-map ISP-A-IN permit 10
 set local-preference 200
!
route-map ISP-B-IN permit 10
 set local-preference 100
!
! Tag outbound announcements with communities
route-map ISP-A-OUT permit 10
 set community 65200:100
!
route-map ISP-B-OUT permit 10
 set community 65300:100
 set as-path prepend 65100 65100
!
```

The AS-path prepend on ISP-B makes ISP-A the preferred inbound path. If ISP-A fails, BFD detects the failure and traffic shifts to ISP-B.

### Per-ISP routing tables

For advanced deployments, each ISP's routes can go to a separate routing table using the `SetNeighborRouteTable` API:

```go
// Route ISP-A default to table 100, ISP-B to table 200
bgpCtrl.SetNeighborRouteTable(net.ParseIP("10.0.1.1"), 100)
bgpCtrl.SetNeighborRouteTable(net.ParseIP("10.0.2.1"), 200)
```

This enables policy-based routing where different subscriber classes use different upstream paths.

## BFD Tuning for Sub-300ms Failover

BFD runs between the BNG and each upstream ISP router. The default configuration provides 300ms detection:

| Parameter | Default | Aggressive |
|-----------|---------|------------|
| Receive interval | 100ms | 50ms |
| Transmit interval | 100ms | 50ms |
| Detect multiplier | 3 | 3 |
| **Detection time** | **300ms** | **150ms** |

### BNG CLI flags

```bash
./bng run \
  --bgp-enabled \
  --bgp-local-as=65100 \
  --bgp-router-id=10.0.0.1 \
  --bfd-min-rx=100 \
  --bfd-min-tx=100 \
  --bfd-detect-multiplier=3
```

### Validating failover

1. Verify BFD sessions are Up:
   ```bash
   vtysh -c "show bfd peers"
   ```
2. Simulate ISP-A failure and time the failover:
   ```bash
   # On BNG
   sudo iptables -A INPUT -s 10.0.1.1 -j DROP
   # Observe BFD going Down within 300ms
   # BGP session tears down immediately after BFD Down
   # Traffic shifts to ISP-B
   ```
3. Check Prometheus metrics:
   ```promql
   bng_routing_bfd_state_changes_total
   bng_routing_bgp_session_state_changes_total
   ```

### Tuning recommendations

- **Do not** set detect-multiplier below 3 (too many false positives).
- **50ms timers** are suitable for directly connected links. For multi-hop paths, use 100ms+ to account for jitter.
- Enable echo mode (`--bfd-echo-mode`) for lower CPU usage on high-timer-frequency configurations.

## Hardware Recommendations

### Central POP Server (BNG)

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4 cores, x86_64 | 8+ cores, Xeon/EPYC |
| RAM | 8 GB | 16+ GB |
| NIC | 2x 1 GbE | 2x 10 GbE (Intel X520/X710) |
| Storage | 50 GB SSD | 100 GB NVMe |
| OS | Ubuntu 22.04+ / Debian 12+ | Ubuntu 24.04 LTS |
| Kernel | 5.15+ | 6.1+ (better eBPF support) |

The BNG process itself is lightweight. The NIC and CPU matter most for packet throughput. Two NICs are recommended: one for upstream (ISP-facing) and one for subscriber-facing (backhaul to towers).

### Tower Router

Any router supporting DHCP relay and basic routing. Common choices in WISP:

| Device | Subscribers | Notes |
|--------|-------------|-------|
| MikroTik hAP ac3 | < 50 | Small tower, budget |
| MikroTik RB5009 | < 200 | Mid-range, 10G SFP+ |
| Ubiquiti EdgeRouter X | < 100 | Simple, reliable |
| Ubiquiti EdgeRouter 4 | < 500 | Multi-tower aggregation |
| MikroTik CCR2004 | < 1,000 | Large tower or aggregation |

Tower routers only need to relay DHCP and route IP traffic -- they do not run the BNG software.

## Scale Expectations

| Deployment Size | Subscribers | Towers | BNG Instances | Notes |
|----------------|-------------|--------|---------------|-------|
| Small WISP | 500-2,000 | 5-10 | 1 (active only) | Single server, single ISP |
| Medium WISP | 2,000-5,000 | 10-30 | 2 (active/standby) | Dual upstream, BFD failover |
| Large WISP | 5,000-10,000 | 30-50 | 2 (active/standby) | Multi-ISP, route sharding |
| Very large | 10,000+ | 50+ | 2+ (active/active) | Consider per-region BNG |

### Bottlenecks at scale

- **DHCP relay**: At 10K subscribers, expect ~500 DHCP events/min (renewals). Well within BNG capacity (50K+ req/sec).
- **BGP routes**: 10K /32 routes is modest for FRR. See [BGP Scale Testing Guide](bgp-scale-test.md) for details.
- **Backhaul bandwidth**: The real constraint. Size backhaul links for peak subscriber traffic, not BNG throughput.

## RADIUS Integration

The BNG integrates with external RADIUS servers for subscriber authentication and accounting. Common WISP billing platforms:

### Splynx

```yaml
# BNG RADIUS configuration for Splynx
radius:
  server: 10.0.0.10
  port: 1812
  secret: "shared-secret"
  accounting_port: 1813
  interim_interval: 300  # 5-minute interim updates
  nas_identifier: "wisp-bng-01"
  nas_ip_address: "10.0.0.1"
```

Splynx uses standard RADIUS attributes. Configure the NAS in Splynx admin panel with the BNG's IP address.

### Sonar

```yaml
# BNG RADIUS configuration for Sonar
radius:
  server: radius.sonar.example.com
  port: 1812
  secret: "shared-secret"
  accounting_port: 1813
  interim_interval: 300
  nas_identifier: "wisp-bng-01"
```

Sonar supports CoA (Change of Authorization) for real-time plan changes. The BNG's RADIUS client handles CoA messages to update subscriber QoS policies without disconnection.

### Powercode

```yaml
# BNG RADIUS configuration for Powercode
radius:
  server: 10.0.0.20
  port: 1812
  secret: "shared-secret"
  accounting_port: 1813
  interim_interval: 600  # 10-minute interim updates
  nas_identifier: "wisp-bng-01"
```

### Common RADIUS attributes

| Attribute | Usage |
|-----------|-------|
| User-Name | Subscriber username or MAC |
| NAS-IP-Address | BNG IP address |
| NAS-Port-Id | Interface or Option 82 Circuit-ID |
| Framed-IP-Address | Assigned subscriber IP |
| Framed-IP-Netmask | Always 255.255.255.255 (/32) |
| Class | Session class for QoS mapping |
| Session-Timeout | Lease duration |
| Acct-Session-Id | Unique session identifier |
| Acct-Input-Octets | Upload bytes (accounting) |
| Acct-Output-Octets | Download bytes (accounting) |

## Example Topology: Medium WISP

```
                         Internet
                        /        \
                  ISP-A            ISP-B
                (primary)         (backup)
                   |                 |
               10.0.1.0/30      10.0.2.0/30
                   |                 |
    +--------------+--------+--------+--------------+
    |           Central POP (10.0.0.0/24)           |
    |                                                |
    |  BNG-Active (10.0.0.1)   BNG-Standby (10.0.0.2)|
    |  Nexus (10.0.0.10)       Prometheus (10.0.0.20)|
    |                                                |
    +------+---------+---------+---------+-----------+
           |         |         |         |
      172.16.1.0/24  |    172.16.3.0/24  |
           |         |         |         |
      +----+---+ +---+----+ +-+------+ +-+------+
      |Tower A | |Tower B | |Tower C | |Tower D |
      |relay:  | |relay:  | |relay:  | |relay:  |
      |.1.1    | |.2.1    | |.3.1    | |.4.1    |
      +---+----+ +---+----+ +---+----+ +---+----+
          |           |           |           |
     10.100.0.0/22  10.100.4.0/22           ...
     (1K subs)      (1K subs)
```

### IP addressing plan

| Purpose | Range | Notes |
|---------|-------|-------|
| POP management | 10.0.0.0/24 | Servers, switches |
| ISP-A transit | 10.0.1.0/30 | BGP peering |
| ISP-B transit | 10.0.2.0/30 | BGP peering |
| Tower backhaul | 172.16.0.0/16 | /24 per tower |
| Subscriber pools | 10.100.0.0/14 | ~260K addresses |

### Subscriber pool configuration in Nexus

```bash
# Create subscriber pool (covers all towers)
curl -X POST http://nexus:9000/api/v1/pools \
  -H "Content-Type: application/json" \
  -d '{
    "id": "wisp-subscribers",
    "cidr": "10.100.0.0/14",
    "prefix": 32
  }'
```

The Nexus hashring allocates /32 addresses from this pool. Each tower's giaddr determines which subnet range is preferred (configured via DHCP relay policy), but the BNG can allocate from any part of the pool.

## Bare Metal Installation

For production WISP deployments on bare metal:

```bash
# 1. Install FRR
curl -s https://deb.frrouting.org/frr/keys.gpg | sudo tee /usr/share/keyrings/frrouting.gpg > /dev/null
echo deb '[signed-by=/usr/share/keyrings/frrouting.gpg]' https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable | sudo tee /etc/apt/sources.list.d/frr.list
sudo apt update && sudo apt install -y frr frr-pythontools

# 2. Enable BGP and BFD daemons
sudo sed -i 's/bgpd=no/bgpd=yes/' /etc/frr/daemons
sudo sed -i 's/bfdd=no/bfdd=yes/' /etc/frr/daemons
sudo systemctl restart frr

# 3. Install BNG binary
sudo cp bng /usr/local/bin/bng

# 4. Create BNG configuration
sudo mkdir -p /etc/bng
sudo cp bgp-neighbors.json /etc/bng/

# 5. Create systemd service
sudo tee /etc/systemd/system/bng.service << 'EOF'
[Unit]
Description=BNG - Broadband Network Gateway
After=network.target frr.service
Requires=frr.service

[Service]
Type=simple
ExecStart=/usr/local/bin/bng run \
  --config=/etc/bng/config.yaml \
  --bgp-enabled \
  --bgp-local-as=65100 \
  --bgp-router-id=10.0.0.1 \
  --bgp-config=/etc/bng/bgp-neighbors.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now bng
```
