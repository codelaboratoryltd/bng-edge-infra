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
│   ├── base/            # Reusable base components
│   │   ├── bng/         # BNG deployment template
│   │   ├── nexus/       # Nexus StatefulSet template
│   │   ├── nexus-p2p/   # Nexus P2P cluster template
│   │   └── rendezvous-server/  # P2P discovery server
│   ├── demos/           # Demo overlays (compose base components)
│   │   ├── standalone/  # Demo A: Standalone BNG
│   │   ├── single/      # Demo B: BNG + Nexus
│   │   ├── p2p-cluster/ # Demo C: 3-node Nexus P2P
│   │   └── distributed/ # Demo D: Multi-BNG + Nexus
│   ├── e2e-test/        # E2E integration test
│   ├── bngblaster/      # BNG Blaster traffic generator
│   └── ...              # Other test components
├── charts/              # Generated Helm templates (Cilium, Prometheus, Grafana)
├── src/
│   ├── bng/             # SUBMODULE: OLT-BNG source
│   └── nexus/           # SUBMODULE: Nexus source
├── scripts/
│   └── init.sh          # Create k3d cluster
└── Tiltfile             # Local development orchestration
```

## Quick Start

### Prerequisites

**Required:**
- Docker Desktop (or Podman)
- **8GB+ RAM** for E2E demo (16GB+ for running all demos simultaneously)
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

**Option 1: Using Tilt (recommended)**
```bash
./scripts/init.sh   # Create k3d cluster (first time only)
tilt up demo-a      # Run standalone BNG demo
```

**Option 2: Run specific demo or test**
```bash
./scripts/init.sh   # Create k3d cluster (first time only)
tilt up demo-b      # BNG + Nexus integration
tilt up e2e         # E2E integration test
tilt up demo-a demo-b infra  # Multiple groups
```

Tilt will:
1. Install Cilium CNI (always required)
2. Build and deploy only the selected components
3. Set up port forwarding
4. Enable live reload for development

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

| Demo | Command | Description | Port |
|------|---------|-------------|------|
| **A: Standalone** | `tilt up demo-a` | Single BNG with local pool | 8080 |
| **B: Single Nexus** | `tilt up demo-b` | BNG + single Nexus server | 8081/9001 |
| **C: P2P Cluster** | `tilt up demo-c` | 3-node Nexus P2P cluster | 9002 |
| **D: Distributed** | `tilt up demo-d` | Multi-BNG + Nexus integration | 8083/9003 |

### Integration Tests

| Test | Command | Description | Port |
|------|---------|-------------|------|
| **E2E** | `tilt up e2e` | Real DHCP → BNG → Nexus flow | 9010 |
| **Blaster** | `tilt up blaster` | BNG Blaster traffic generator | - |
| **Blaster-Test** | `tilt up blaster-test` | L2 DHCP with veth pairs | 8090 |
| **Walled Garden** | `tilt up walled-garden` | Unknown → WalledGarden → Production | 9011 |

### High Availability

| Test | Command | Description | Port |
|------|---------|-------------|------|
| **HA-Nexus** | `tilt up ha-nexus` | Two BNGs + shared Nexus | 9012 |
| **HA-P2P** | `tilt up ha-p2p` | Active/Standby with SSE sync | 8088/8089 |
| **Failure** | `tilt up failure` | Resilience and failover testing | - |

### Distributed Allocation

| Test | Command | Description | Port |
|------|---------|-------------|------|
| **WiFi** | `tilt up wifi` | TTL-based lease expiration (EpochBitmap) | 8092 |
| **Peer-Pool** | `tilt up peer-pool` | Hashring coordination, no Nexus | 8093 |
| **RADIUS-Time** | `tilt up radius-time` | **KEY**: IP pre-allocated before DHCP | 8094 |

### Protocol Features

| Test | Command | Description | Port |
|------|---------|-------------|------|
| **PPPoE** | `tilt up pppoe` | Full PPPoE lifecycle (PADI→IPCP) | 8095 |
| **IPv6** | `tilt up ipv6` | SLAAC + DHCPv6 + Prefix Delegation | 8096 |
| **NAT** | `tilt up nat` | CGNAT with port blocks, hairpinning | 8097 |
| **QoS** | `tilt up qos` | Per-subscriber rate limiting | 8098 |
| **BGP** | `tilt up bgp` | FRR peering + subscriber routes | 8099 |

### Running Demos

```bash
# Show available groups
tilt up

# Run a specific demo
tilt up demo-a

# Run multiple groups
tilt up demo-a demo-b infra

# Run all demos (requires significant resources)
tilt up all
```

> **Note**: Running `tilt up` without arguments shows available groups. Running all demos simultaneously requires significant resources (~50+ pods).

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
