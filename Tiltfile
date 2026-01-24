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
config.define_string('demo', usage='Demo to run: a, b, c, d, blaster, or all (default: all)')
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
    cmd='k3d cluster create -c clusters/local-dev/k3d-config.yaml 2>/dev/null || k3d cluster start bng-edge 2>/dev/null || true; k3d kubeconfig merge bng-edge -d 2>/dev/null || true',
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

# Build BNG Blaster image (traffic generator)
if os.path.exists('components/bngblaster/Dockerfile'):
    docker_build(
        'ghcr.io/codelaboratoryltd/bngblaster',
        'components/bngblaster',
        dockerfile='components/bngblaster/Dockerfile',
    )

# -----------------------------------------------------------------------------
# Demo Configurations
# -----------------------------------------------------------------------------

# Demo port assignments
DEMO_PORTS = {
    'a': {'bng': 8080, 'nexus': None},
    'b': {'bng': 8081, 'nexus': 9001},
    'c': {'bng': None, 'nexus': 9002},
    'd': {'bng': 8083, 'nexus': 9003},
    'blaster': {'bng': None, 'nexus': None, 'blaster': 8001},
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
# BNG Blaster - Traffic Generator for Testing
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'blaster':
    # Create namespace
    k8s_yaml(namespace_yaml('demo-blaster'))

    # BNG Blaster Deployment
    k8s_yaml(kustomize('components/bngblaster'))

    k8s_resource(
        'bngblaster',
        objects=['bngblaster-config:configmap'],
        resource_deps=['helmfile-hydrate'],
        labels=['blaster'],
    )

    # Interactive test buttons
    local_resource(
        'blaster-ipoe-test',
        cmd='''
kubectl exec -n demo-blaster deploy/bngblaster -- \
  bngblaster -C /etc/bngblaster/ipoe.json -T 2>&1 || \
  echo "Note: BNG Blaster requires actual network connectivity to BNG. Use for integration testing."
''',
        labels=['blaster', 'test'],
        auto_init=False,
        resource_deps=['bngblaster'],
    )

    local_resource(
        'blaster-pppoe-test',
        cmd='''
kubectl exec -n demo-blaster deploy/bngblaster -- \
  bngblaster -C /etc/bngblaster/pppoe.json -T 2>&1 || \
  echo "Note: BNG Blaster requires actual network connectivity to BNG. Use for integration testing."
''',
        labels=['blaster', 'test'],
        auto_init=False,
        resource_deps=['bngblaster'],
    )

    local_resource(
        'blaster-dhcp-stress',
        cmd='''
kubectl exec -n demo-blaster deploy/bngblaster -- \
  bngblaster -C /etc/bngblaster/dhcp-stress.json -T 2>&1 || \
  echo "Note: BNG Blaster requires actual network connectivity to BNG. Use for integration testing."
''',
        labels=['blaster', 'test'],
        auto_init=False,
        resource_deps=['bngblaster'],
    )

# -----------------------------------------------------------------------------
# Realistic DHCP Test (L2 connected BNG + client)
# -----------------------------------------------------------------------------

if selected_demo == 'all' or selected_demo == 'blaster-test':
    k8s_yaml(kustomize('components/blaster-test'))

    k8s_resource(
        'bng-dhcp-test',
        port_forwards='8090:8080',
        labels=['blaster-test'],
        resource_deps=['bng-image'],
    )

    # Single DHCP request test
    local_resource(
        'dhcp-single-test',
        cmd='''
echo "=== Single DHCP Request Test ==="
kubectl exec -n demo-blaster-test bng-dhcp-test -c client -- sh -c '
  apk add --no-cache busybox-extras iproute2 > /dev/null 2>&1 || true

  # Setup udhcpc script
  mkdir -p /etc/udhcpc
  cat > /etc/udhcpc/simple.script << "SCRIPT"
#!/bin/sh
case "$1" in
  bound|renew)
    ip addr add $ip/$mask dev $interface 2>/dev/null || true
    echo "Got IP: $ip/$mask via $interface"
    ;;
esac
SCRIPT
  chmod +x /etc/udhcpc/simple.script

  echo "Requesting DHCP lease on veth-client..."
  udhcpc -i veth-client -n -q -t 5 -T 3 -f -s /etc/udhcpc/simple.script 2>&1

  echo ""
  echo "Interface status:"
  ip addr show veth-client | grep inet
'
''',
        labels=['blaster-test', 'test'],
        auto_init=False,
        resource_deps=['bng-dhcp-test'],
    )

    # Multi-client stress test
    local_resource(
        'dhcp-stress-test',
        cmd='''
echo "=== Multi-Client DHCP Stress Test ==="
kubectl exec -n demo-blaster-test bng-dhcp-test -c client -- sh -c '
  apk add --no-cache busybox-extras iproute2 > /dev/null 2>&1 || true

  mkdir -p /etc/udhcpc
  cat > /etc/udhcpc/simple.script << "SCRIPT"
#!/bin/sh
case "$1" in
  bound|renew) ip addr add $ip/$mask dev $interface 2>/dev/null || true ;;
esac
SCRIPT
  chmod +x /etc/udhcpc/simple.script

  CLIENTS=10
  SUCCESS=0
  FAILED=0

  echo "Creating $CLIENTS virtual clients..."
  for i in $(seq 1 $CLIENTS); do
    VETH="veth-c$i"
    MAC=$(printf "02:00:00:00:%02x:%02x" $((i / 256)) $((i % 256)))

    ip link add $VETH type veth peer name ${VETH}-peer 2>/dev/null || continue
    ip link set $VETH address $MAC
    ip link set $VETH up
    ip link set ${VETH}-peer up
  done

  echo "Running DHCP requests..."
  START=$(date +%s)

  for i in $(seq 1 $CLIENTS); do
    VETH="veth-c$i"
    if timeout 5 udhcpc -i $VETH -n -q -t 3 -T 1 -f -s /etc/udhcpc/simple.script 2>/dev/null; then
      SUCCESS=$((SUCCESS + 1))
      IP=$(ip addr show $VETH 2>/dev/null | grep "inet " | cut -d" " -f6)
      echo "  Client $i: $IP"
    else
      FAILED=$((FAILED + 1))
    fi
  done

  END=$(date +%s)
  DURATION=$((END - START))
  [ $DURATION -eq 0 ] && DURATION=1

  echo ""
  echo "=== Results ==="
  echo "Successful: $SUCCESS / $CLIENTS"
  echo "Failed:     $FAILED"
  echo "Duration:   ${DURATION}s"
  echo "Rate:       $((SUCCESS / DURATION)) sessions/sec"
'
''',
        labels=['blaster-test', 'test'],
        auto_init=False,
        resource_deps=['bng-dhcp-test'],
    )

    # Check BNG sessions
    local_resource(
        'dhcp-check-sessions',
        cmd='''
echo "=== BNG DHCP Sessions ==="
curl -s http://localhost:8090/api/v1/sessions | jq '{
  count,
  sessions: [.sessions[]? | {subscriber_id, ipv4, state, mac}]
}'
''',
        labels=['blaster-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-dhcp-test'],
    )

# -----------------------------------------------------------------------------
# E2E Integration Test (Real DHCP → BNG → Nexus → Hashring)
# -----------------------------------------------------------------------------
# This demonstrates the FULL flow:
# 1. Real DHCP client sends DISCOVER
# 2. BNG receives packet (eBPF slow path)
# 3. BNG requests IP from Nexus via HTTP
# 4. Nexus allocates via hashring
# 5. BNG sends OFFER/ACK with Nexus-allocated IP
# 6. Client gets IP from Nexus pool (10.200.x.x)

if selected_demo == 'all' or selected_demo == 'e2e':
    k8s_yaml(kustomize('components/e2e-test'))

    k8s_resource(
        'nexus:deployment:demo-e2e',
        new_name='nexus-e2e',
        port_forwards='9010:9000',
        labels=['e2e-test'],
        resource_deps=['nexus-image'],
    )

    k8s_resource(
        'bng-e2e',
        labels=['e2e-test'],
        resource_deps=['bng-image', 'nexus-e2e'],
    )

    # Run the E2E DHCP test
    local_resource(
        'e2e-dhcp-test',
        cmd='''
echo "============================================"
echo "  E2E Integration Test: DHCP → BNG → Nexus"
echo "============================================"
echo ""

# Step 1: Verify Nexus pool exists
echo "Step 1: Checking Nexus pool..."
POOL=$(curl -s http://localhost:9010/api/v1/pools | jq -r '.pools[0].id // "none"')
if [ "$POOL" = "e2e-pool" ]; then
  echo "  ✓ Pool 'e2e-pool' exists in Nexus"
else
  echo "  ✗ Pool not found. Creating..."
  curl -s -X POST http://localhost:9010/api/v1/pools \
    -H "Content-Type: application/json" \
    -d '{"id":"e2e-pool","cidr":"10.200.0.0/16","prefix":32}' > /dev/null
fi
echo ""

# Step 2: Run DHCP request from client
echo "Step 2: Running DHCP request from client..."
kubectl exec -n demo-e2e bng-e2e -c client -- sh -c '
  mkdir -p /etc/udhcpc
  cat > /etc/udhcpc/simple.script << "EOF"
#!/bin/sh
case "$1" in
  bound|renew)
    ip addr flush dev $interface 2>/dev/null
    ip addr add $ip/$mask dev $interface
    echo "SUCCESS: Got IP $ip from DHCP"
    ;;
esac
EOF
  chmod +x /etc/udhcpc/simple.script

  # Clear any existing IP
  ip addr flush dev veth-client 2>/dev/null || true

  echo "  Sending DHCP DISCOVER..."
  udhcpc -i veth-client -n -q -t 5 -T 2 -f -s /etc/udhcpc/simple.script 2>&1
'
echo ""

# Step 3: Verify client got IP from Nexus pool
echo "Step 3: Verifying client IP..."
CLIENT_IP=$(kubectl exec -n demo-e2e bng-e2e -c client -- ip addr show veth-client 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "  Client IP: $CLIENT_IP"
echo ""

# Step 4: Check Nexus allocation
echo "Step 4: Checking Nexus allocations..."
curl -s http://localhost:9010/api/v1/allocations | jq '.allocations[] | {subscriber_id, ip, pool_id}' 2>/dev/null || echo "  No allocations found"
echo ""

# Step 5: Verify IP is from Nexus pool
echo "Step 5: Verification..."
case "$CLIENT_IP" in
  10.200.*)
    echo "  ✓ PASS: Client IP $CLIENT_IP is from Nexus pool (10.200.0.0/16)"
    echo ""
    echo "  Flow verified:"
    echo "    DHCP DISCOVER → BNG → Nexus allocation → DHCP OFFER/ACK"
    ;;
  "")
    echo "  ✗ FAIL: No IP assigned to client"
    ;;
  *)
    echo "  ✗ FAIL: Client IP $CLIENT_IP is NOT from Nexus pool"
    ;;
esac
echo ""
echo "============================================"
''',
        labels=['e2e-test', 'test'],
        auto_init=False,
        resource_deps=['bng-e2e'],
    )

    # View Nexus state
    local_resource(
        'e2e-nexus-state',
        cmd='''
echo "=== Nexus State ==="
echo ""
echo "Pools:"
curl -s http://localhost:9010/api/v1/pools | jq '.pools[] | {id, cidr, prefix}'
echo ""
echo "Allocations:"
curl -s http://localhost:9010/api/v1/allocations | jq '.allocations[] | {subscriber_id, ip, pool_id, allocated_at}'
echo ""
echo "Nodes:"
curl -s http://localhost:9010/api/v1/nodes | jq '.nodes[] | {id, status}'
''',
        labels=['e2e-test', 'verify'],
        auto_init=False,
        resource_deps=['nexus-e2e'],
    )

    # View BNG logs
    local_resource(
        'e2e-bng-logs',
        cmd='kubectl logs -n demo-e2e bng-e2e -c bng --tail=30',
        labels=['e2e-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-e2e'],
    )

# -----------------------------------------------------------------------------
# Walled Garden Test - Full subscriber lifecycle
# -----------------------------------------------------------------------------
# Demonstrates: Unknown subscriber → Walled Garden → Activation → Production IP
#
# Flow:
#   1. Unknown client gets walled garden IP (10.255.x.x)
#   2. Simulate activation (pre-allocate IP in Nexus)
#   3. Client renews and gets production IP (10.200.x.x)

if selected_demo == 'all' or selected_demo == 'walled-garden':
    k8s_yaml(kustomize('components/walled-garden-test'))

    k8s_resource(
        'nexus:deployment:demo-walled-garden',
        new_name='nexus-wgar',
        labels=['walled-garden-test'],
        resource_deps=['nexus-image'],
        port_forwards='9011:9000',
    )

    k8s_resource(
        'bng-wgar-test',
        labels=['walled-garden-test'],
        resource_deps=['bng-image', 'nexus-wgar'],
    )

    # Run full walled garden test
    local_resource(
        'wgar-full-test',
        cmd='''
echo "Running Walled Garden → Production IP test..."
echo ""
kubectl exec -n demo-walled-garden bng-wgar-test -c client -- sh /scripts/run-wgar-test.sh
''',
        labels=['walled-garden-test', 'test'],
        auto_init=False,
        resource_deps=['bng-wgar-test'],
    )

    # View BNG logs
    local_resource(
        'wgar-bng-logs',
        cmd='kubectl logs -n demo-walled-garden bng-wgar-test -c bng --tail=40',
        labels=['walled-garden-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-wgar-test'],
    )

    # View Nexus allocations
    local_resource(
        'wgar-nexus-state',
        cmd='''
echo "=== Nexus Pools ==="
curl -s http://localhost:9011/api/v1/pools | head -100
echo ""
echo "=== Nexus Allocations ==="
curl -s http://localhost:9011/api/v1/allocations | head -100
''',
        labels=['walled-garden-test', 'verify'],
        auto_init=False,
        resource_deps=['nexus-wgar'],
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
  Demo A: Standalone BNG         - http://localhost:8080 (BNG only, simulated)
  Demo B: Single Integration     - http://localhost:9001 (Nexus), http://localhost:8081 (BNG)
  Demo C: Nexus P2P Cluster      - http://localhost:9002 (Nexus x3 with mDNS)
  Demo D: Full Distributed       - http://localhost:9003 (Nexus x3), http://localhost:8083 (BNG x2)
  BNG Blaster:                   - Traffic generator placeholder
  Blaster Test:                  - Real L2 DHCP (local pool only)
  E2E Test:                      - Real DHCP → BNG → Nexus (FULL FLOW)
  Walled Garden Test:            - Walled Garden → Activation → Production IP

Run specific demo:
  tilt up -- --demo=a              # Standalone BNG only
  tilt up -- --demo=b              # Single integration only
  tilt up -- --demo=c              # P2P cluster only
  tilt up -- --demo=d              # Full distributed only
  tilt up -- --demo=blaster        # BNG Blaster placeholder
  tilt up -- --demo=blaster-test   # Real DHCP (local pool)
  tilt up -- --demo=e2e            # Real DHCP → Nexus (RECOMMENDED)
  tilt up -- --demo=walled-garden  # Walled Garden lifecycle
  tilt up                          # All demos (default)

E2E Integration Test (--demo=e2e):
  This is the FULL verification - real DHCP packets through BNG to Nexus:
  - e2e-dhcp-test:   Run real DHCP, verify IP from Nexus pool
  - e2e-nexus-state: View Nexus pools and allocations
  - e2e-bng-logs:    View BNG logs for DHCP/Nexus activity

Walled Garden Test (--demo=walled-garden):
  Full subscriber lifecycle: Unknown → Walled Garden → Activation → Production:
  - wgar-full-test:   Run complete walled garden → production test
  - wgar-bng-logs:    View BNG logs during test
  - wgar-nexus-state: View Nexus pools and allocations

Verification:
  Click 'verify-demo-X' buttons in Tilt UI to test each demo

Observability:
  - Tilt UI:    http://localhost:10350
  - Hubble:     http://localhost:12000
  - Prometheus: http://localhost:9090
  - Grafana:    http://localhost:3000
""".strip())
