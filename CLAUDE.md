# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps repository for BNG (Broadband Network Gateway) edge deployment infrastructure. It contains:

1. **Kubernetes manifests** for staging/production clusters
2. **Local development environment** (k3d + Tilt + Cilium)
3. **Git submodules** containing application source code:
   - `src/bng` - eBPF-accelerated BNG implementation
   - `src/nexus` - Central coordination service (CLSet CRDT)

The BNG runs directly on OLT hardware at ISP edge locations using eBPF/XDP for kernel-level packet processing. Nexus provides distributed resource management (IP allocation, VLAN allocation) via hashring-based coordination.

## Project Structure

```
bng-edge-infra/
├── clusters/
│   ├── local-dev/           # k3d development cluster config
│   │   └── kustomization.yaml  # Master kustomization (composes all demos/tests)
│   ├── staging/             # Staging Flux manifests
│   └── production/          # Production Flux manifests
├── components/
│   ├── base/                # Reusable base components
│   │   ├── bng/             # BNG Deployment + Service
│   │   ├── nexus/           # Nexus StatefulSet + Service
│   │   └── nexus-p2p/       # Nexus P2P cluster variant
│   ├── demos/               # Demo overlays (use base components)
│   │   ├── standalone/      # Demo A: BNG only
│   │   ├── single/          # Demo B: BNG + Nexus
│   │   ├── p2p-cluster/     # Demo C: 3 Nexus P2P
│   │   └── distributed/     # Demo D: 3 Nexus + 2 BNG
│   ├── *-test/              # Test components (e2e, wifi, pppoe, etc.)
│   └── monitoring/          # Grafana dashboards, Prometheus rules
├── charts/                  # Helm charts (Cilium, Prometheus, Grafana)
├── scripts/
│   └── helmfile.yaml        # Helm chart definitions
├── src/
│   ├── bng/                 # SUBMODULE: OLT-BNG source (see src/bng/CLAUDE.md)
│   └── nexus/               # SUBMODULE: Nexus source
└── Tiltfile                 # Local development orchestration
```

## Common Commands

### Local Development

```bash
# Initialize cluster (first time only)
./scripts/init.sh

# Start specific demo/test (run without args to see available groups)
tilt up demo-a              # Standalone BNG
tilt up demo-b              # Single integration (BNG + Nexus)
tilt up demo-c              # P2P cluster (3 Nexus)
tilt up demo-d              # Distributed (3 Nexus + 2 BNG)
tilt up e2e                 # E2E integration test
tilt up all                 # Everything

# Multiple groups
tilt up demo-a demo-b

# Stop development environment (preserves cluster)
tilt down

# Delete cluster completely
k3d cluster delete bng-edge

# Update submodules to latest
git submodule update --remote
```

### Building BNG (in src/bng/)

```bash
cd src/bng

# Build BNG binary (includes eBPF compilation)
make build

# Build eBPF programs only
make build-ebpf

# Run tests
make test

# Run linter
make lint

# Run demo
make demo
```

### Building Nexus (in src/nexus/)

```bash
cd src/nexus

# Build Nexus binary
go build -o nexus ./cmd/nexus

# Run tests
go test ./...
```

### Kubernetes Operations

```bash
# Apply manifests (local development)
kubectl apply -k clusters/local-dev

# Check Cilium status
cilium status

# Watch network flows
hubble observe

# Watch DHCP traffic specifically
hubble observe --protocol dhcp
```

## Architecture

### Deployment Model

```
Central (Kubernetes at NOC/POP):
├── Nexus Server - CLSet CRDT, hashring IP allocation, bootstrap API
├── Prometheus/Grafana - Monitoring
└── Image Registry - OLT-BNG updates

Edge (Bare Metal OLTs):
├── OLT-BNG - systemd service with eBPF/XDP
├── Each site serves 1,000-2,000 subscribers
└── Subscriber traffic stays LOCAL (no central BNG)
```

### Key Design Decisions

1. **eBPF/XDP over VPP**: Simpler deployment for 10-40 Gbps edge scale. VPP requires DPDK, hugepages, dedicated NICs - overkill for edge.

2. **IP allocation at RADIUS time**: DHCP is read-only. IPs are pre-allocated via Nexus hashring during RADIUS authentication, enabling eBPF fast path to reply entirely in kernel.

3. **Two-tier DHCP**: Fast path (eBPF, ~10μs latency, 95%+ traffic) + slow path (Go userspace, cache misses).

4. **Offline-first**: Edge sites continue operating during network partitions using cached state.

## Submodule Details

### BNG (src/bng/)

The BNG submodule has its own comprehensive CLAUDE.md. Key packages:
- `pkg/ebpf/` - eBPF loader and map management
- `pkg/dhcp/` - DHCP slow path server
- `pkg/nexus/` - Nexus client for IP allocation
- `pkg/radius/` - RADIUS client with CoA support
- `pkg/qos/`, `pkg/nat/` - TC eBPF rate limiting and NAT
- `pkg/pppoe/` - PPPoE server
- `bpf/` - eBPF/XDP C programs

### Nexus (src/nexus/)

Central coordination service:
- `internal/api/` - HTTP handlers for pools, allocations, nodes
- `internal/audit/` - Security audit logging
- `internal/validation/` - Input validation
- `internal/hashring/` - Consistent hashing for resource distribution
- `internal/state/` - State management
- `internal/store/` - Persistence layer
- `internal/ztp/` - Zero Touch Provisioning

## Local Development Environment

The k3d cluster (`bng-edge`, context: `k3d-bng-edge`) is configured with:
- Cilium CNI (Flannel disabled)
- Hubble network observability
- kube-proxy replacement via eBPF
- Prometheus and Grafana

Access after `tilt up <group>`:
- Tilt UI: http://localhost:10350
- Hubble UI: http://localhost:12000 (with infra)
- Prometheus: http://localhost:9090 (with infra)
- Grafana: http://localhost:3000 (with infra)

Demo-specific ports (when enabled):
- Demo A (Standalone BNG): http://localhost:8080
- Demo B (Single BNG): http://localhost:8081
- Demo B (Single Nexus): http://localhost:9001
- Demo C (P2P Nexus): http://localhost:9002
- Demo D (Distributed BNG): http://localhost:8083
- Demo D (Distributed Nexus): http://localhost:9003
- E2E Nexus: http://localhost:9010

## Performance Targets

| Metric | Target |
|--------|--------|
| DHCP fast path latency | <100μs P99 |
| DHCP slow path latency | <10ms P99 |
| Total throughput | 50,000+ req/sec |
| Cache hit rate | >95% |
| Subscribers per OLT | 1,000-2,000 |
