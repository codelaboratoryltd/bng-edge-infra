# DHCP Relay Technical Guide

This document covers how the BNG handles relayed DHCP packets from tower routers in WISP deployments.

## Overview

In a WISP centralized deployment, subscriber CPE devices send DHCP broadcasts which are intercepted by the tower router's relay agent. The relay agent forwards these as unicast packets to the central BNG, adding metadata (giaddr, Option 82) that identifies the subscriber's location.

The BNG supports both direct L2 mode (subscribers on the same broadcast domain) and relay mode (subscribers behind relay agents). This guide focuses on relay mode.

## How DHCP Relay Works

### RFC 2131/3046 relay flow

1. Subscriber CPE broadcasts a DHCP DISCOVER.
2. Tower router (relay agent) receives the broadcast and:
   - Sets **giaddr** to its own IP address (the relay agent's address on the subscriber-facing interface).
   - Inserts **Option 82** (Relay Agent Information) with Circuit-ID and Remote-ID sub-options.
   - Forwards the packet as unicast to the BNG's IP.
3. BNG receives the relayed DISCOVER:
   - Inspects **giaddr** to determine which network segment the request came from.
   - Reads **Option 82** to identify the specific port/tower.
   - Allocates an IP from the appropriate pool (or retrieves pre-allocated IP from Nexus).
   - Sends DHCP OFFER back to the relay agent's giaddr.
4. Tower router relays the OFFER back to the subscriber (broadcast or unicast, depending on flags).

### Packet modifications by relay agent

| Field | Before Relay | After Relay |
|-------|-------------|-------------|
| Source IP | 0.0.0.0 | Tower router IP |
| Dest IP | 255.255.255.255 | BNG IP (unicast) |
| giaddr | 0.0.0.0 | Tower router subscriber-facing IP |
| hops | 0 | 1 (incremented) |
| Option 82 | absent | Circuit-ID + Remote-ID |

## giaddr Handling

The `giaddr` field is the primary mechanism for the BNG to identify the relay agent and, by extension, the subscriber's network segment.

### How BNG uses giaddr

When the BNG receives a DHCP packet with a non-zero giaddr:

1. **Pool selection**: The giaddr can be used to select a specific IP pool for that tower/segment. For example, tower A (giaddr 172.16.1.1) allocates from 10.100.0.0/22, tower B (giaddr 172.16.2.1) from 10.100.4.0/22.

2. **Response routing**: The DHCP response (OFFER, ACK) is sent as unicast to the giaddr, not broadcast. The relay agent then delivers it to the subscriber.

3. **Subnet validation**: The BNG verifies that the allocated IP is routable via the giaddr's subnet.

### Configuration

In the BNG configuration, giaddr-to-pool mappings can be defined:

```yaml
dhcp:
  relay_mode: true
  giaddr_pools:
    "172.16.1.1": "tower-a-pool"
    "172.16.2.1": "tower-b-pool"
    "172.16.3.1": "tower-c-pool"
  default_pool: "general-pool"
```

When no specific giaddr mapping exists, the BNG uses the default pool.

## Option 82 (Relay Agent Information)

Option 82 is defined in RFC 3046 and carries sub-options inserted by the relay agent.

### Sub-option 1: Circuit-ID

Identifies the physical interface or logical circuit on the relay agent where the subscriber is connected.

Common formats:
- Port-based: `eth1`, `ether5`, `bridge1/port3`
- VLAN-based: `vlan100`, `eth1.100`
- Custom string: `tower-a:port-5:vlan-100`

### Sub-option 2: Remote-ID

Identifies the relay agent itself. Usually the relay agent's hostname, MAC address, or a configured string.

Common formats:
- Hostname: `tower-a-router`
- MAC: `00:11:22:33:44:55`
- Custom: `site-001`

### BNG processing of Option 82

The BNG parses Option 82 in both the slow path (Go userspace) and the fast path (eBPF).

**Slow path** (`pkg/dhcp/server.go`):
- The `parseOption82()` function extracts Circuit-ID and Remote-ID from the TLV-encoded sub-options.
- Values are stored in the lease record for logging and RADIUS accounting.
- Circuit-ID is passed to RADIUS as `NAS-Port-Id` for subscriber identification.

**Fast path** (`bpf/dhcp_fastpath.c`):
- The eBPF program uses Circuit-ID as a lookup key in the `circuit_id_subscriber` map.
- A hash of the Circuit-ID maps directly to the subscriber's pre-allocated IP, enabling kernel-level DHCP reply without userspace involvement.
- See the `HashCircuitID()` function in `pkg/ebpf/` for the hashing algorithm.

### Option 82 and the eBPF fast path

For relayed packets, the eBPF fast path can reply entirely in kernel if the Circuit-ID-to-subscriber mapping exists:

```
Relayed DHCP Request (with Option 82)
    |
    v
eBPF/XDP Program
    |
    +-- Extract Circuit-ID from Option 82
    |
    +-- Hash Circuit-ID
    |
    +-- Lookup hash in circuit_id_subscriber map
    |
    +-- HIT: Build DHCP reply in kernel (~10us)
    |
    +-- MISS: Pass to userspace slow path
```

This means that after the first DHCP exchange (which populates the eBPF map via the slow path), subsequent renewals for relayed subscribers are handled entirely in kernel.

## Configuration for Relay Mode

### BNG CLI flags

```bash
./bng run \
  --dhcp-relay-mode \
  --dhcp-interface=eth0 \
  --dhcp-server-ip=10.0.0.1
```

### BNG configuration file

```yaml
dhcp:
  interface: eth0
  server_ip: 10.0.0.1
  relay_mode: true
  lease_duration: 3600      # 1 hour
  renewal_time: 1800        # 30 minutes
  rebind_time: 3150         # 52.5 minutes
```

### Kubernetes (demo-i)

In the WISP multi-homing demo, the BNG deployment includes relay mode configuration:

```yaml
args:
  - demo
  - --subscribers=100
  - --nexus-url=http://wisp-nexus.demo-wisp-multihoming.svc:9000
  - --bgp-enabled
  - --bgp-local-as=65100
```

## Differences from Direct L2 Mode

| Feature | Direct L2 Mode | Relay Mode |
|---------|----------------|------------|
| Subscriber connectivity | Same broadcast domain as BNG | Behind relay agent, different subnet |
| DHCP packet type | Broadcast | Unicast (relayed) |
| giaddr | 0.0.0.0 | Relay agent IP |
| Option 82 | Optional (if switch inserts) | Required (relay agent inserts) |
| Pool selection | Single pool or MAC-based | giaddr-based pool mapping |
| Response delivery | Broadcast or unicast to client | Unicast to relay agent giaddr |
| eBPF fast path key | MAC address | Circuit-ID hash (or MAC) |
| Typical use case | OLT with direct subscribers | WISP with tower routers |
| Latency | Lower (no relay hop) | Slightly higher (relay hop) |

### When to use which mode

- **Direct L2**: OLT deployments where the BNG is directly connected to subscriber access equipment (switches, OLTs). The BNG sees subscriber MAC addresses directly.

- **Relay mode**: WISP deployments where subscribers are behind tower routers. The BNG sees the relay agent's MAC, not the subscriber's. Option 82 Circuit-ID provides subscriber identification.

## Tower Router Configuration Examples

### MikroTik RouterOS

```
# Enable DHCP relay on subscriber bridge
/ip dhcp-relay
add name=relay-to-bng \
    interface=bridge-subscribers \
    dhcp-server=10.0.0.1 \
    local-address=172.16.1.1 \
    add-relay-info=yes \
    relay-info-remote-id=tower-a

# If using VLANs per subscriber
/ip dhcp-relay
add name=relay-vlan100 \
    interface=vlan100 \
    dhcp-server=10.0.0.1 \
    local-address=172.16.1.1 \
    add-relay-info=yes
```

### Ubiquiti EdgeRouter

```
configure
set service dhcp-relay interface eth1
set service dhcp-relay server 10.0.0.1
set service dhcp-relay relay-options relay-agents-packets append
set service dhcp-relay relay-options circuit-id-format "%h:%p"
set service dhcp-relay relay-options remote-id "tower-a"
commit
save
```

### Cisco IOS

```
interface GigabitEthernet0/1
 description Subscriber-facing
 ip address 172.16.1.1 255.255.255.0
 ip helper-address 10.0.0.1
 ip dhcp relay information option
 ip dhcp relay information option subscriber-id tower-a
```

### Linux (ISC DHCP Relay)

```bash
dhcrelay -a -i eth1 10.0.0.1
# -a: append agent info (Option 82)
# -i eth1: subscriber-facing interface
# 10.0.0.1: BNG IP
```

## Troubleshooting

### Relayed packets not reaching BNG

1. Check relay agent is configured and running on the tower router.
2. Verify unicast connectivity from tower to BNG IP: `ping 10.0.0.1`
3. Check firewall rules allow UDP 67/68 from tower to BNG.
4. Capture on BNG interface: `tcpdump -i eth0 port 67 -vv`

### BNG not responding to relayed requests

1. Verify relay mode is enabled: check BNG logs for "relay mode enabled".
2. Check giaddr is set: `tcpdump` should show non-zero giaddr in incoming packets.
3. Check pool mapping: ensure a pool exists for the giaddr or a default pool is configured.
4. Check BNG logs for Option 82 parsing: look for "DHCP request with Option 82" log entries.

### Option 82 not parsed correctly

1. Verify the relay agent is inserting Option 82 (check with `tcpdump -vv`).
2. Check sub-option format matches what BNG expects (TLV encoding per RFC 3046).
3. Some relay agents use non-standard Option 82 formats; check vendor documentation.

### Fast path not working for relayed subscribers

1. Verify the Circuit-ID subscriber mapping exists in eBPF map:
   ```bash
   bpftool map dump name circuit_id_sub
   ```
2. The first DHCP exchange always goes through the slow path (to populate the map). Only renewals use the fast path.
3. Check for Circuit-ID hash collisions (logged as warnings). See Issue #90 for collision rate monitoring.

### Subscriber gets wrong pool/subnet

1. Check giaddr-to-pool mapping in BNG configuration.
2. Verify the relay agent's giaddr matches the expected tower IP.
3. If using a single pool (no per-tower mapping), this is expected behavior -- all towers share one pool.
