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
│   └── nexus/           # Nexus K8s manifests
├── charts/              # Generated Helm templates (gitignored)
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

```bash
tilt up
```

This will:
1. Create a k3d cluster (`bng-edge`) with Cilium CNI
2. Generate Helm templates via helmfile
3. Install Cilium, Prometheus, Grafana, Hubble
4. Build and deploy BNG and Nexus from submodules
5. Set up port forwarding

### Access Services

| Service | URL | Notes |
|---------|-----|-------|
| Tilt UI | http://localhost:10350 | Development dashboard |
| BNG API | http://localhost:8080 | BNG REST API |
| Nexus API | http://localhost:9000 | Nexus REST API |
| Hubble UI | http://localhost:12000 | Network observability |
| Prometheus | http://localhost:9090 | Metrics |
| Grafana | http://localhost:3000 | Dashboards (admin/admin) |

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

### Helmfile Errors

If helmfile fails, ensure helm repos are added:
```bash
helm repo add cilium https://helm.cilium.io/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

## Flux GitOps (Staging/Production)

For staging/production, use Flux to watch this repo:

```bash
flux bootstrap github \
  --owner=codelaboratoryltd \
  --repository=bng-edge-infra \
  --path=clusters/staging \
  --personal
```

## Application Repos

- [bng](https://github.com/codelaboratoryltd/bng) - eBPF-accelerated BNG (v0.2.0)
- [nexus](https://github.com/codelaboratoryltd/nexus) - Central coordination service

## License

BSL 1.1 - See [LICENSE](LICENSE)
