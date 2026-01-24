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
│   └── bngblaster/      # BNG Blaster traffic generator
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
- 8GB+ RAM available for Docker
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

The Tiltfile includes multiple demo configurations:

| Demo | Description | Nexus Port | BNG Port |
|------|-------------|------------|----------|
| **A: Standalone** | Single BNG with local pool | - | 8080 |
| **B: Single Nexus** | BNG + single Nexus server | 9001 | 8081 |
| **C: P2P Cluster** | 3-node Nexus P2P cluster | 9002 | - |
| **D: Distributed** | Multi-BNG + Nexus integration | 9003 | 8083 |

### Integration Tests

| Test | Description | Namespace |
|------|-------------|-----------|
| **E2E Test** | Real DHCP → BNG → Nexus flow | demo-e2e |
| **Blaster Test** | L2 DHCP with veth pairs | demo-blaster-test |

Run tests via Tilt UI buttons:
- `e2e-dhcp-test`: Full E2E DHCP verification
- `dhcp-single-test`: Single DHCP client test
- `dhcp-stress-test`: Multi-client stress test

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
