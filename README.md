# BNG Edge Infrastructure

GitOps repository for BNG (Broadband Network Gateway) edge deployment.

## Structure

```
bng-edge-infra/
├── clusters/
│   ├── local-dev/       # k3d for local development
│   ├── staging/         # Staging cluster (Flux)
│   └── production/      # Production cluster (Flux)
├── components/
│   ├── bng/             # BNG K8s manifests
│   ├── nexus/           # Nexus K8s manifests
│   ├── e2e-test/        # E2E integration test (DHCP → BNG → Nexus)
│   ├── blaster-test/    # L2 DHCP test with veth pairs
│   ├── bngblaster/      # BNG Blaster traffic generator
│   ├── walled-garden-test/  # Subscriber lifecycle demo
│   ├── ha-nexus-test/   # HA with shared Nexus
│   ├── ha-p2p-test/     # HA with P2P sync
│   ├── wifi-test/       # TTL-based lease expiration
│   ├── peer-pool-test/  # Distributed allocation (no Nexus)
│   ├── radius-time-test/# RADIUS-time allocation (KEY)
│   ├── pppoe-test/      # PPPoE session lifecycle
│   ├── ipv6-test/       # SLAAC + DHCPv6 + Prefix Delegation
│   ├── nat-test/        # NAT44/CGNAT
│   ├── qos-test/        # Per-subscriber rate limiting
│   ├── failure-test/    # Resilience and failover
│   └── bgp-test/        # BGP/FRR subscriber routes
├── charts/              # Generated Helm templates (committed for diff visibility)
├── src/
│   ├── bng/             # SUBMODULE: OLT-BNG source
│   └── nexus/           # SUBMODULE: Nexus source
├── scripts/
│   ├── helmfile.yaml    # Helm chart definitions
│   └── hydrate.sh       # Generate manifests from Helm
└── Tiltfile             # Local development orchestration
```

## Quick Start

### Prerequisites

**Required:**
- Docker Desktop (or Podman)
- **16GB+ RAM** for running all demos (8GB for individual demos)
- 20GB+ disk space

**Install tools (macOS):**
```bash
brew install k3d kubectl tilt-dev/tap/tilt helmfile helm
```

**Install tools (Linux):**
```bash
# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# tilt
curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash

# helmfile
brew install helmfile  # or download from GitHub releases

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Clone with Submodules

```bash
git clone --recurse-submodules git@github.com:codelaboratoryltd/bng-edge-infra.git
cd bng-edge-infra
```

If you already cloned without `--recurse-submodules`:
```bash
git submodule update --init --recursive
```

### Start Local Development

**Option 1: Using Tilt (recommended for development)**
```bash
tilt up
```

**Option 2: Create cluster first, then Tilt**
```bash
./scripts/init.sh   # Creates k3d cluster only
tilt up             # Installs everything else
```

Tilt will:
1. Create a k3d cluster (`bng-edge`) with Cilium CNI
2. Generate Helm templates via helmfile
3. Install Cilium, Prometheus, Grafana, Hubble
4. Build and deploy BNG and Nexus from submodules
5. Set up port forwarding

### Access Services

| Service | URL | Notes |
|---------|-----|-------|
| Tilt UI | http://localhost:10350 | Development dashboard |
| BNG API | http://localhost:8080 | BNG REST API (Demo A) |
| Nexus API | http://localhost:9000 | Nexus REST API |
| Hubble UI | http://localhost:12000 | Network observability |
| Prometheus | http://localhost:9090 | Metrics |
| Grafana | http://localhost:3000 | Dashboards (admin/admin) |

## Demo Scenarios

The Tiltfile includes 19 demo configurations covering all BNG features.

> **Note**: Some advanced demos (PPPoE, NAT, BGP) require features that are still being implemented in the BNG. These demos have placeholder configurations ready for when the features are complete.

### Core Demos (Fully Working)

| Demo | Flag | Description | Port |
|------|------|-------------|------|
| **A: Standalone** | `--demo=a` | Single BNG with local pool | 8080 |
| **B: Single Nexus** | `--demo=b` | BNG + single Nexus server | 8081/9001 |
| **C: P2P Cluster** | `--demo=c` | 3-node Nexus P2P cluster | 9002 |
| **D: Distributed** | `--demo=d` | Multi-BNG + Nexus integration | 8083/9003 |

### Integration Tests

| Demo | Flag | Description | Port |
|------|------|-------------|------|
| **E2E** | `--demo=e2e` | Real DHCP → BNG → Nexus flow | 9010 |
| **Blaster-Test** | `--demo=blaster-test` | L2 DHCP with veth pairs | 8090 |
| **Walled Garden** | `--demo=walled-garden` | Unknown → WalledGarden → Production | 9011 |

### High Availability

| Demo | Flag | Description | Port |
|------|------|-------------|------|
| **HA-Nexus** | `--demo=ha-nexus` | Two BNGs + shared Nexus | 9012 |
| **HA-P2P** | `--demo=ha-p2p` | Active/Standby with SSE sync | 8088/8089 |
| **Failure** | `--demo=failure` | Resilience and failover testing | - |

### Distributed Allocation

| Demo | Flag | Description | Port |
|------|------|-------------|------|
| **WiFi** | `--demo=wifi` | TTL-based lease expiration (EpochBitmap) | 8092 |
| **Peer-Pool** | `--demo=peer-pool` | Hashring coordination, no Nexus | 8093 |
| **RADIUS-Time** | `--demo=radius-time` | **KEY**: IP pre-allocated before DHCP | 8094 |

### Protocol Features

> These demos exercise BNG protocol features with test configurations.

| Demo | Flag | Description | Port | Status |
|------|------|-------------|------|--------|
| **PPPoE** | `--demo=pppoe` | Full PPPoE lifecycle (PADI→IPCP) | 8095 | Config Ready |
| **IPv6** | `--demo=ipv6` | SLAAC + DHCPv6 + Prefix Delegation | 8096 | Config Ready |
| **NAT** | `--demo=nat` | CGNAT with port blocks, hairpinning | 8097 | Config Ready |
| **QoS** | `--demo=qos` | Per-subscriber rate limiting | 8098 | Config Ready |
| **BGP** | `--demo=bgp` | FRR peering + subscriber routes | 8099 | **Working** |

### Running Demos

```bash
# Run a specific demo (recommended)
tilt up -- --demo=radius-time

# Run all demos (requires 16GB+ RAM)
tilt up

# Run multiple demos
tilt up -- --demo=e2e --demo=ha-p2p
```

> **Note**: Running all demos simultaneously (`tilt up` without flags) requires significant resources. For testing or development, select specific demos with `--demo=<name>`.

Each demo has test buttons in the Tilt UI (http://localhost:10350). Click to run tests interactively.

### Stop / Restart

```bash
# Stop Tilt (keeps cluster running)
tilt down

# Restart cluster
k3d cluster start bng-edge
tilt up

# Delete everything
k3d cluster delete bng-edge
```

### Update Submodules

```bash
git submodule update --remote
git add src/
git commit -m "chore: update submodules"
```

## Troubleshooting

### Port Conflicts

If you see port binding errors, check for conflicts:
```bash
lsof -i :8080 -i :9000 -i :10350 -i :12000 -i :9090 -i :3000
```

### Submodules Not Found

If Tilt warns about missing submodules:
```bash
git submodule update --init --recursive
```

### Cluster Won't Start

Check Docker is running and has enough resources:
```bash
docker info
```

Reset the cluster:
```bash
k3d cluster delete bng-edge
tilt up
```

## Application Repos

- [bng](https://github.com/codelaboratoryltd/bng) - eBPF-accelerated BNG (v0.2.0)
- [nexus](https://github.com/codelaboratoryltd/nexus) - Central coordination service

## License

BSL 1.1 - See [LICENSE](LICENSE)
