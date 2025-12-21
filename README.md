# BNG Edge Infrastructure

GitOps repository for BNG (Broadband Network Gateway) edge deployment.

## Structure

```
bng-edge-infra/
├── clusters/
│   ├── local-dev/       # k3d for local development
│   ├── staging/         # Staging cluster
│   └── production/      # Production cluster
├── components/
│   ├── cilium/          # CNI
│   ├── prometheus/      # Metrics
│   ├── grafana/         # Dashboards
│   ├── bng/             # BNG K8s manifests
│   └── nexus/           # Nexus K8s manifests
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

```bash
brew install k3d kubectl tilt-dev/tap/tilt helmfile
```

### Clone with submodules

```bash
git clone --recurse-submodules git@github.com:codelaboratoryltd/bng-edge-infra.git
cd bng-edge-infra
```

### Local Development

```bash
tilt up
```

Access:
- Tilt UI: http://localhost:10350
- BNG API: http://localhost:8080
- Nexus: http://localhost:9000
- Hubble UI: http://localhost:12000
- Prometheus: http://localhost:9090
- Grafana: http://localhost:3000

### Update Submodules

```bash
git submodule update --remote
git add src/
git commit -m "Update submodules"
```

## Flux GitOps

For staging/production, Flux watches this repo:

```bash
flux bootstrap github \
  --owner=codelaboratoryltd \
  --repository=bng-edge-infra \
  --path=clusters/staging \
  --personal
```

## Application Repos

- [bng](https://github.com/codelaboratoryltd/bng) - OLT-BNG (eBPF-accelerated)
- [nexus](https://github.com/codelaboratoryltd/nexus) - Central coordination service
