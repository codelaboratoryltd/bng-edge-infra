# BNG Edge Infrastructure - Local Development
#
# Usage:
#   tilt up                    # All demos
#   tilt up -- --demo=a        # Just standalone BNG
#   tilt up -- --demo=b        # Just single integration
#   tilt up -- --demo=c        # Just Nexus P2P cluster
#   tilt up -- --demo=d        # Just full distributed
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

# Configuration
config.define_string('demo', usage='Demo to run: a, b, c, d, or all (default: all)')
cfg = config.parse()
selected_demo = cfg.get('demo', 'all')

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
# Docker Images
# -----------------------------------------------------------------------------

# Build BNG image (shared across demos)
if os.path.exists('src/bng/Dockerfile'):
    docker_build(
        'ghcr.io/codelaboratoryltd/bng',
        'src/bng',
        dockerfile='src/bng/Dockerfile',
        ssh='default',
    )
else:
    print("WARNING: src/bng submodule not found. Run: git submodule update --init")

# Build Nexus image (shared across demos)
if os.path.exists('src/nexus/Dockerfile'):
    docker_build(
        'ghcr.io/codelaboratoryltd/nexus',
        'src/nexus',
        dockerfile='src/nexus/Dockerfile',
        ssh='default',
    )
else:
    print("WARNING: src/nexus submodule not found. Run: git submodule update --init")

# -----------------------------------------------------------------------------
# Demo Configurations
# -----------------------------------------------------------------------------

# Demo port assignments
DEMO_PORTS = {
    'a': {'bng': 8080, 'nexus': None},
    'b': {'bng': 8081, 'nexus': 9001},
    'c': {'bng': None, 'nexus': 9002},
    'd': {'bng': 8083, 'nexus': 9003},
}

# Helper: Create namespace YAML
def namespace_yaml(name):
    return blob("""
apiVersion: v1
kind: Namespace
metadata:
  name: %s
""" % name)

# -----------------------------------------------------------------------------
# Demo A: Standalone BNG (no Nexus)
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'a':
    # Create namespace
    k8s_yaml(namespace_yaml('demo-standalone'))

    # BNG Deployment (standalone mode)
    k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bng-standalone
  namespace: demo-standalone
  labels:
    app: bng
    demo: standalone
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bng
      demo: standalone
  template:
    metadata:
      labels:
        app: bng
        demo: standalone
    spec:
      containers:
        - name: bng
          image: ghcr.io/codelaboratoryltd/bng:latest
          args:
            - demo
            - --subscribers=50
            - --duration=24h
            - --api-port=8080
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: bng
  namespace: demo-standalone
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
  selector:
    app: bng
    demo: standalone
"""))

    k8s_resource(
        'bng-standalone',
        port_forwards=['8080:8080'],
        resource_deps=['helmfile-hydrate'],
        labels=['demo-a'],
    )

    # Verification button
    local_resource(
        'verify-demo-a',
        cmd='curl -s http://localhost:8080/api/v1/sessions | jq ".count"',
        labels=['demo-a', 'verify'],
        auto_init=False,
        resource_deps=['bng-standalone'],
    )

# -----------------------------------------------------------------------------
# Demo B: Single Integration (1 Nexus + 1 BNG)
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'b':
    # Create namespace
    k8s_yaml(namespace_yaml('demo-single'))

    # Nexus Deployment (standalone mode, no P2P)
    k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nexus-standalone
  namespace: demo-single
  labels:
    app: nexus
    demo: single
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nexus
      demo: single
  template:
    metadata:
      labels:
        app: nexus
        demo: single
    spec:
      containers:
        - name: nexus
          image: ghcr.io/codelaboratoryltd/nexus:latest
          args:
            - serve
            - --http-port=9000
          ports:
            - containerPort: 9000
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: nexus
  namespace: demo-single
spec:
  ports:
    - name: http
      port: 9000
      targetPort: 9000
  selector:
    app: nexus
    demo: single
"""))

    # BNG Deployment (integrated with Nexus)
    k8s_yaml(blob("""
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bng-integrated
  namespace: demo-single
  labels:
    app: bng
    demo: single
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bng
      demo: single
  template:
    metadata:
      labels:
        app: bng
        demo: single
    spec:
      containers:
        - name: bng
          image: ghcr.io/codelaboratoryltd/bng:latest
          args:
            - demo
            - --subscribers=50
            - --duration=24h
            - --api-port=8080
            - --nexus-url=http://nexus.demo-single.svc:9000
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: bng
  namespace: demo-single
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
  selector:
    app: bng
    demo: single
"""))

    k8s_resource(
        'nexus-standalone',
        port_forwards=['9001:9000'],
        resource_deps=['helmfile-hydrate'],
        labels=['demo-b'],
    )

    k8s_resource(
        'bng-integrated',
        port_forwards=['8081:8080'],
        resource_deps=['nexus-standalone'],
        labels=['demo-b'],
    )

    # Verification button
    local_resource(
        'verify-demo-b',
        cmd='''
curl -s -X POST http://localhost:9001/api/v1/pools -H "Content-Type: application/json" \
  -d '{"id":"test-b","cidr":"10.50.0.0/24","prefix":32}' > /dev/null 2>&1 || true
curl -s -X POST http://localhost:9001/api/v1/allocations -H "Content-Type: application/json" \
  -d '{"pool_id":"test-b","subscriber_id":"sub-verify-b"}' | jq -r '.ip // "allocation failed"'
''',
        labels=['demo-b', 'verify'],
        auto_init=False,
        resource_deps=['bng-integrated'],
    )

# -----------------------------------------------------------------------------
# Demo C: Nexus P2P Cluster (3 Nexus with mDNS)
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'c':
    # Create namespace
    k8s_yaml(namespace_yaml('demo-p2p'))

    # Nexus StatefulSet with mDNS discovery (best for k3d local dev)
    k8s_yaml(blob("""
apiVersion: v1
kind: Service
metadata:
  name: nexus-p2p
  namespace: demo-p2p
  labels:
    app: nexus-p2p
spec:
  ports:
    - name: http
      port: 9000
      targetPort: 9000
    - name: p2p
      port: 33123
      targetPort: 33123
  clusterIP: None
  selector:
    app: nexus-p2p
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nexus-p2p
  namespace: demo-p2p
  labels:
    app: nexus-p2p
    demo: p2p
spec:
  serviceName: nexus-p2p
  replicas: 3
  selector:
    matchLabels:
      app: nexus-p2p
  template:
    metadata:
      labels:
        app: nexus-p2p
    spec:
      containers:
        - name: nexus
          image: ghcr.io/codelaboratoryltd/nexus:latest
          args:
            - serve
            - --http-port=9000
            - --p2p-port=33123
            - --p2p=true
            - --role=core
            - --data-path=/data
          ports:
            - name: http
              containerPort: 9000
            - name: p2p
              containerPort: 33123
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            # mDNS discovery for local k3d cluster
            - name: NEXUS_DISCOVERY
              value: "mdns"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 100Mi
"""))

    k8s_resource(
        'nexus-p2p',
        port_forwards=['9002:9000'],
        resource_deps=['helmfile-hydrate'],
        labels=['demo-c'],
    )

    # Verification button
    local_resource(
        'verify-demo-c',
        cmd='''
echo "Creating pool on nexus-p2p-0..."
kubectl exec -n demo-p2p nexus-p2p-0 -- curl -s -X POST localhost:9000/api/v1/pools \
  -H "Content-Type: application/json" \
  -d '{"id":"test-c","cidr":"10.60.0.0/24","prefix":32}' > /dev/null 2>&1 || true
echo "Waiting for CRDT sync..."
sleep 3
echo "Checking if pool appears on nexus-p2p-1:"
kubectl exec -n demo-p2p nexus-p2p-1 -- curl -s localhost:9000/api/v1/pools | jq -r '.pools[].id // "no pools found"'
''',
        labels=['demo-c', 'verify'],
        auto_init=False,
        resource_deps=['nexus-p2p'],
    )

# -----------------------------------------------------------------------------
# Demo D: Full Distributed (3 Nexus + 2 BNG)
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'd':
    # Create namespace
    k8s_yaml(namespace_yaml('demo-distributed'))

    # Nexus StatefulSet with mDNS discovery (best for k3d local dev)
    k8s_yaml(blob("""
apiVersion: v1
kind: Service
metadata:
  name: nexus-cluster
  namespace: demo-distributed
  labels:
    app: nexus-cluster
spec:
  ports:
    - name: http
      port: 9000
      targetPort: 9000
    - name: p2p
      port: 33123
      targetPort: 33123
  clusterIP: None
  selector:
    app: nexus-cluster
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: nexus-cluster
  namespace: demo-distributed
  labels:
    app: nexus-cluster
    demo: distributed
spec:
  serviceName: nexus-cluster
  replicas: 3
  selector:
    matchLabels:
      app: nexus-cluster
  template:
    metadata:
      labels:
        app: nexus-cluster
    spec:
      containers:
        - name: nexus
          image: ghcr.io/codelaboratoryltd/nexus:latest
          args:
            - serve
            - --http-port=9000
            - --p2p-port=33123
            - --p2p=true
            - --role=core
            - --data-path=/data
          ports:
            - name: http
              containerPort: 9000
            - name: p2p
              containerPort: 33123
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            # mDNS discovery for local k3d cluster
            - name: NEXUS_DISCOVERY
              value: "mdns"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
          volumeMounts:
            - name: data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 100Mi
"""))

    # BNG StatefulSet connected to Nexus
    k8s_yaml(blob("""
apiVersion: v1
kind: Service
metadata:
  name: bng-cluster
  namespace: demo-distributed
  labels:
    app: bng-cluster
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
  clusterIP: None
  selector:
    app: bng-cluster
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: bng-cluster
  namespace: demo-distributed
  labels:
    app: bng-cluster
    demo: distributed
spec:
  serviceName: bng-cluster
  replicas: 2
  selector:
    matchLabels:
      app: bng-cluster
  template:
    metadata:
      labels:
        app: bng-cluster
    spec:
      containers:
        - name: bng
          image: ghcr.io/codelaboratoryltd/bng:latest
          args:
            - demo
            - --subscribers=50
            - --duration=24h
            - --api-port=8080
            - --nexus-url=http://nexus-cluster.demo-distributed.svc:9000
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: BNG_NODE_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
"""))

    k8s_resource(
        'nexus-cluster',
        port_forwards=['9003:9000'],
        resource_deps=['helmfile-hydrate'],
        labels=['demo-d'],
    )

    k8s_resource(
        'bng-cluster',
        port_forwards=['8083:8080'],
        resource_deps=['nexus-cluster'],
        labels=['demo-d'],
    )

    # Verification button
    local_resource(
        'verify-demo-d',
        cmd='''
echo "Creating pool in distributed cluster..."
curl -s -X POST http://localhost:9003/api/v1/pools -H "Content-Type: application/json" \
  -d '{"id":"test-d","cidr":"10.70.0.0/24","prefix":32}' > /dev/null 2>&1 || true
echo "Allocating IP..."
curl -s -X POST http://localhost:9003/api/v1/allocations -H "Content-Type: application/json" \
  -d '{"pool_id":"test-d","subscriber_id":"sub-verify-d"}' | jq -r '.ip // "allocation failed"'
echo "Checking BNG sessions..."
curl -s http://localhost:8083/api/v1/sessions | jq '.count'
''',
        labels=['demo-d', 'verify'],
        auto_init=False,
        resource_deps=['bng-cluster'],
    )

# -----------------------------------------------------------------------------
# Infrastructure Components (Observability)
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

Demo Configurations:
  Demo A: Standalone BNG         - http://localhost:8080 (BNG only)
  Demo B: Single Integration     - http://localhost:9001 (Nexus), http://localhost:8081 (BNG)
  Demo C: Nexus P2P Cluster      - http://localhost:9002 (Nexus x3 with mDNS)
  Demo D: Full Distributed       - http://localhost:9003 (Nexus x3), http://localhost:8083 (BNG x2)

Run specific demo:
  tilt up -- --demo=a    # Standalone BNG only
  tilt up -- --demo=b    # Single integration only
  tilt up -- --demo=c    # P2P cluster only
  tilt up -- --demo=d    # Full distributed only
  tilt up                # All demos (default)

Verification:
  Click 'verify-demo-X' buttons in Tilt UI to test each demo

Observability:
  - Tilt UI:    http://localhost:10350
  - Hubble:     http://localhost:12000
  - Prometheus: http://localhost:9090
  - Grafana:    http://localhost:3000
""".strip())
