# BNG Edge Infrastructure - Local Development
#
# Usage:
#   tilt up
#
# This will:
#   1. Create k3d cluster with Cilium CNI
#   2. Install infrastructure components
#   3. Build and deploy BNG and Nexus from submodules
#   4. Enable live reload for development

print("""
-----------------------------------------------------------------
BNG Edge Infrastructure - Local Development
-----------------------------------------------------------------
""".strip())

# Add SSH keys for private repo access during Docker builds
local('ssh-add $HOME/.ssh/id_*[^pub] 2>/dev/null || true')

# Only allow k3d-bng-edge context
allow_k8s_contexts('k3d-bng-edge')

# Docker prune settings (prune after 5 builds, keep images < 2hrs old)
docker_prune_settings(
    disable=False,
    max_age_mins=120,
    num_builds=5,
    keep_recent=2
)

# -----------------------------------------------------------------------------
# k3d Cluster Creation
# -----------------------------------------------------------------------------

local_resource(
    'k3d-cluster',
    cmd='k3d cluster create -c clusters/local-dev/k3d-config.yaml 2>/dev/null || k3d cluster start bng-edge 2>/dev/null || true',
    deps=['clusters/local-dev/k3d-config.yaml'],
    labels=['infrastructure'],
)

local_resource(
    'k3d-wait',
    # Wait for API server only - nodes won't be ready until CNI is installed
    cmd='kubectl cluster-info && kubectl get nodes',
    resource_deps=['k3d-cluster'],
    labels=['infrastructure'],
)

# -----------------------------------------------------------------------------
# Helmfile - Install Infrastructure
# -----------------------------------------------------------------------------

local_resource(
    'helmfile-hydrate',
    cmd='cd scripts && ./hydrate.sh',
    deps=['scripts/helmfile.yaml', 'scripts/hydrate.sh'],
    resource_deps=['k3d-wait'],
    labels=['infrastructure'],
)

# -----------------------------------------------------------------------------
# BNG Application (from submodule)
# -----------------------------------------------------------------------------

# Check if submodule exists
if os.path.exists('src/bng/Dockerfile'):
    docker_build(
        'ghcr.io/codelaboratoryltd/bng',
        'src/bng',
        dockerfile='src/bng/Dockerfile',
        ssh='default',
    )

    k8s_yaml(kustomize('components/bng'))

    k8s_resource(
        'bng',
        port_forwards=['8080:8080', '9090:9090'],
        resource_deps=['helmfile-hydrate'],
        labels=['apps'],
    )
else:
    print("WARNING: src/bng submodule not found. Run: git submodule update --init")

# -----------------------------------------------------------------------------
# Nexus Application (from submodule)
# -----------------------------------------------------------------------------

if os.path.exists('src/nexus/Dockerfile'):
    docker_build(
        'ghcr.io/codelaboratoryltd/nexus',
        'src/nexus',
        dockerfile='src/nexus/Dockerfile',
        ssh='default',
    )

    k8s_yaml(kustomize('components/nexus'))

    k8s_resource(
        'nexus',
        port_forwards=['9000:9000'],
        resource_deps=['helmfile-hydrate'],
        labels=['apps'],
    )
else:
    print("WARNING: src/nexus submodule not found. Run: git submodule update --init")

# -----------------------------------------------------------------------------
# Infrastructure Components
# -----------------------------------------------------------------------------

k8s_yaml(kustomize('clusters/local-dev'))

k8s_resource(
    'hubble-ui',
    port_forwards='12000:80',
    labels=['observability'],
)

k8s_resource(
    'prometheus-server',
    new_name='prometheus',
    port_forwards='9090:9090',
    labels=['observability'],
)

k8s_resource(
    'grafana',
    port_forwards='3000:3000',
    labels=['observability'],
)

# -----------------------------------------------------------------------------
# Helper
# -----------------------------------------------------------------------------

print("""
Tiltfile loaded.

Next steps:
  1. Add submodules if not done:
     git submodule add git@github.com:codelaboratoryltd/bng.git src/bng
     git submodule add git@github.com:codelaboratoryltd/nexus.git src/nexus

  2. Run: tilt up

  3. Access:
     - Tilt UI:    http://localhost:10350
     - BNG:        http://localhost:8080
     - Nexus:      http://localhost:9000
     - Hubble:     http://localhost:12000
     - Prometheus: http://localhost:9090
     - Grafana:    http://localhost:3000
""".strip())
