# Configuration Reference

Complete reference for all BNG and Nexus configuration options.

Both services use CLI flags. Nexus additionally supports environment variables for select options (noted below).

## BNG Configuration

The BNG binary uses the `bng run` subcommand with the following flags.

### General

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--interface`, `-i` | string | `eth1` | Network interface for subscriber traffic |
| `--config`, `-c` | string | `/etc/bng/config.yaml` | Configuration file path |
| `--log-level`, `-l` | string | `info` | Log level: `debug`, `info`, `warn`, `error` |
| `--bpf-path` | string | `bpf/dhcp_fastpath.bpf.o` | Path to compiled eBPF program |
| `--server-ip` | string | *(auto-detect)* | DHCP server IP address (defaults to interface IP) |
| `--metrics-addr` | string | `:9090` | Prometheus metrics listen address |

### DHCP Pool

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--pool-network` | string | `10.0.1.0/24` | Default IP pool network (CIDR) |
| `--pool-gateway` | string | `10.0.1.1` | Default pool gateway |
| `--pool-dns` | string | `8.8.8.8,8.8.4.4` | DNS servers (comma-separated) |
| `--lease-time` | duration | `24h` | Default DHCP lease time |
| `--pool-mode` | string | `static` | Allocation mode: `static` or `lease` |
| `--epoch-period` | duration | `5m` | Duration of each epoch for lease mode |
| `--epoch-grace` | int | `1` | Number of grace epochs before reclaiming IPs |

### RADIUS

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--radius-enabled` | bool | `false` | Enable RADIUS authentication |
| `--radius-servers` | string | | RADIUS server addresses (comma-separated, e.g. `radius1:1812,radius2:1812`) |
| `--radius-secret` | string | | RADIUS shared secret (**deprecated** -- visible in `ps` output, use `--radius-secret-file`) |
| `--radius-secret-file` | string | | Path to file containing RADIUS shared secret |
| `--radius-nas-id` | string | `bng` | RADIUS NAS-Identifier |
| `--radius-timeout` | duration | `3s` | RADIUS request timeout |

### QoS

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--qos-enabled` | bool | `false` | Enable QoS rate limiting via eBPF TC |
| `--qos-bpf-path` | string | `bpf/qos_ratelimit.bpf.o` | Path to compiled QoS eBPF program |

### NAT44/CGNAT

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--nat-enabled` | bool | `false` | Enable NAT44/CGNAT via eBPF TC |
| `--nat-bpf-path` | string | `bpf/nat44.bpf.o` | Path to compiled NAT44 eBPF program |
| `--nat-public-ips` | string | | Public IP addresses for NAT pool (comma-separated) |
| `--nat-ports-per-sub` | int | `1024` | Number of ports allocated per subscriber |
| `--nat-log-enabled` | bool | `false` | Enable NAT translation logging (required for legal compliance) |
| `--nat-log-path` | string | *(stdout)* | Path to NAT log file (empty for stdout) |
| `--nat-inside-interface` | string | *(main interface)* | Inside interface for NAT (subscriber-facing) |
| `--nat-outside-interface` | string | *(main interface)* | Outside interface for NAT (public-facing) |
| `--nat-eim` | bool | `true` | Enable Endpoint-Independent Mapping per RFC 4787 |
| `--nat-eif` | bool | `true` | Enable Endpoint-Independent Filtering per RFC 4787 |
| `--nat-hairpin` | bool | `true` | Enable hairpinning for internal-to-internal NAT traffic |
| `--nat-alg-ftp` | bool | `true` | Enable FTP Application Layer Gateway |
| `--nat-alg-sip` | bool | `false` | Enable SIP Application Layer Gateway |
| `--nat-bulk-logging` | bool | `false` | Enable RFC 6908 bulk port allocation logging format |

### Device Authentication

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--auth-mode` | string | `none` | Device authentication mode: `none`, `psk`, `mtls` |
| `--auth-psk` | string | | Pre-shared key for device authentication (use `--auth-psk-file` for production) |
| `--auth-psk-file` | string | | Path to file containing pre-shared key |
| `--auth-mtls-cert` | string | | Path to device certificate (PEM) for mTLS |
| `--auth-mtls-key` | string | | Path to device private key (PEM) for mTLS |
| `--auth-mtls-ca` | string | | Path to CA certificate bundle (PEM) for mTLS server verification |
| `--auth-mtls-server-name` | string | | Expected server hostname for mTLS verification |
| `--auth-mtls-insecure` | bool | `false` | Skip TLS server verification (**insecure** -- testing only) |

### DHCPv6

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--dhcpv6-enabled` | bool | `false` | Enable DHCPv6 server for IPv6 address assignment |
| `--dhcpv6-address-pool` | string | | DHCPv6 address pool (CIDR, e.g. `2001:db8:1::/64`) |
| `--dhcpv6-prefix-pool` | string | | DHCPv6 prefix delegation pool (CIDR, e.g. `2001:db8:2::/48`) |
| `--dhcpv6-delegation-length` | uint8 | `60` | Prefix length to delegate to customers (e.g. 56, 60, 64) |
| `--dhcpv6-dns` | string | | DHCPv6 DNS servers (comma-separated IPv6 addresses) |
| `--dhcpv6-domain-search` | string | | DHCPv6 domain search list (comma-separated) |
| `--dhcpv6-preferred-lifetime` | uint32 | `3600` | DHCPv6 preferred lifetime in seconds |
| `--dhcpv6-valid-lifetime` | uint32 | `7200` | DHCPv6 valid lifetime in seconds |

### SLAAC / Router Advertisements

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--slaac-enabled` | bool | `false` | Enable SLAAC Router Advertisement daemon |
| `--slaac-prefixes` | string | | Prefixes to advertise via SLAAC (comma-separated CIDR) |
| `--slaac-managed` | bool | `false` | Set M flag -- use DHCPv6 for addresses (disables SLAAC address generation) |
| `--slaac-other` | bool | `false` | Set O flag -- use DHCPv6 for other config (DNS, etc.) |
| `--slaac-mtu` | uint32 | `0` | MTU to advertise (0 = don't advertise) |
| `--slaac-dns` | string | | DNS servers to advertise via RDNSS (comma-separated IPv6 addresses) |
| `--slaac-dns-domains` | string | | DNS search domains to advertise via DNSSL (comma-separated) |
| `--slaac-min-interval` | duration | `200s` | Minimum RA interval |
| `--slaac-max-interval` | duration | `600s` | Maximum RA interval |
| `--slaac-lifetime` | uint16 | `1800` | Router lifetime in seconds (0 = not a default router) |

### Nexus Integration

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--nexus-url` | string | | Nexus server URL for distributed IP allocation (e.g. `http://nexus:9000`) |
| `--nexus-pool` | string | `default` | Nexus pool ID to use for IP allocation |

### Peer Pool (Distributed Allocation Without Nexus)

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--peers` | []string | | Peer BNG addresses (comma-separated, e.g. `bng-0:8080,bng-1:8080`) |
| `--peer-discovery` | string | `static` | Peer discovery method: `static` (use `--peers`), `dns` (use `--peer-service`) |
| `--peer-service` | string | | DNS service name for peer discovery (e.g. `bng-peers.demo.svc`) |
| `--node-id` | string | *(hostname)* | This node's ID for hashring |
| `--peer-listen` | string | `:8081` | Listen address for peer pool API |

### HA (Active/Standby)

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--ha-peer` | string | | HA peer URL for P2P state sync (e.g. `bng-standby:9000`) |
| `--ha-role` | string | *(empty = no HA)* | HA role: `active` or `standby` |
| `--ha-listen` | string | `:9000` | HA sync listen address (active node only) |
| `--ha-tls-cert` | string | | Path to TLS certificate for HA peer sync (PEM) |
| `--ha-tls-key` | string | | Path to TLS private key for HA peer sync (PEM) |
| `--ha-tls-ca` | string | | Path to CA certificate for HA peer verification (PEM) |
| `--ha-tls-skip-verify` | bool | `false` | Skip TLS verification for HA peer sync (**insecure** -- testing only) |

### Resilience

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--health-check-interval` | duration | `5s` | Interval for checking Nexus/peer health |
| `--health-check-retries` | int | `3` | Number of failed health checks before declaring partition |
| `--radius-partition-mode` | string | `cached` | Behavior during RADIUS unavailability: `reject`, `cached`, `allow` |
| `--short-lease-enabled` | bool | `false` | Enable short leases when pool utilization is high |
| `--short-lease-threshold` | float64 | `0.90` | Pool utilization threshold to trigger short leases (0.0-1.0) |
| `--short-lease-duration` | duration | `5m` | Duration of short leases when threshold is exceeded |

### PPPoE

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--pppoe-enabled` | bool | `false` | Enable PPPoE server |
| `--pppoe-interface` | string | *(main interface)* | Interface for PPPoE |
| `--pppoe-ac-name` | string | `BNG-AC` | Access Concentrator name |
| `--pppoe-service-name` | string | `internet` | Service name to advertise |
| `--pppoe-auth-type` | string | `pap` | Authentication type: `pap`, `chap`, or `both` |
| `--pppoe-session-timeout` | duration | `30m` | Session idle timeout |
| `--pppoe-mru` | uint16 | `1492` | Maximum Receive Unit |

### Other Subcommands

| Subcommand | Description |
|------------|-------------|
| `bng version` | Print version and build commit |
| `bng stats` | Show eBPF statistics (reads from `/metrics` endpoint) |

---

## Nexus Configuration

The Nexus binary uses the `nexus serve` subcommand with the following flags.

### General

| Flag | Type | Default | Env Override | Description |
|------|------|---------|--------------|-------------|
| `--node-id` | string | *(auto-generated)* | | Node identifier |
| `--role` | string | `core` | | Node role: `core`, `write`, `read` |
| `--http-port` | int | `9000` | | HTTP API port |
| `--metrics-port` | int | `9002` | | Prometheus metrics port |
| `--p2p-port` | int | `33123` | | P2P listen port |
| `--data-path` | string | `data` | | Data directory path |
| `--bootstrap` | []string | | | Bootstrap peer addresses (comma-separated) |
| `--p2p` | bool | `false` | | Enable P2P mode with CLSet CRDT |

### Peer Discovery

| Flag | Type | Default | Env Override | Description |
|------|------|---------|--------------|-------------|
| `--discovery` | string | *(auto-detect)* | `NEXUS_DISCOVERY` | Peer discovery mode: `none`, `rendezvous`, `dns` |
| `--rendezvous-server` | string | | `NEXUS_RENDEZVOUS_SERVER` | Rendezvous server multiaddr for P2P discovery |
| `--rendezvous-namespace` | string | `nexus` | `NEXUS_RENDEZVOUS_NAMESPACE` | Rendezvous namespace for peer discovery |
| `--dns-service-name` | string | | `NEXUS_DNS_SERVICE_NAME` | Headless service DNS name for peer discovery |
| `--dns-poll-interval` | duration | `10s` | | How often to poll DNS for peer discovery |
| `--dns-ready-timeout` | duration | `30s` | | Timeout before marking ready without peers (for first node) |

### Rate Limiting

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--rate-limit` | int | `100` | Maximum requests per minute per client (0 to disable) |
| `--rate-limit-burst` | int | `200` | Rate limit burst size (max tokens per client) |

### ZTP (Zero Touch Provisioning)

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--ztp` | bool | `false` | Enable ZTP DHCP server for OLT-BNG provisioning |
| `--ztp-interface` | string | `eth0` | Interface for ZTP DHCP server |
| `--ztp-network` | string | `192.168.100.0/24` | Management network CIDR for OLT-BNG devices |
| `--ztp-gateway` | string | *(first IP in network)* | Gateway IP for management network |
| `--ztp-dns` | string | `8.8.8.8,8.8.4.4` | DNS servers (comma-separated) |

### Other Subcommands

| Subcommand | Description |
|------------|-------------|
| `nexus version` | Print version and build commit |
| `nexus rendezvous` | Run a libp2p rendezvous server for peer discovery |
| `nexus peer-id` | Print the peer ID for a given data directory |

#### Rendezvous Subcommand Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--port` | int | `8765` | Rendezvous server listen port |
| `--data-path` | string | `rendezvous-data` | Data directory for rendezvous server |
| `--db-backend` | string | `memory` | Database backend: `memory` or `badger` |

#### Peer ID Subcommand Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--data-path` | string | `data` | Data directory containing `node.key` |
