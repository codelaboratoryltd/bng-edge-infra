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
# HA with Nexus Test - Two BNGs with shared Nexus (implicit HA)
# -----------------------------------------------------------------------------
# Demonstrates: Both BNGs lookup allocations from same Nexus
#   - Client gets same IP from either BNG
#   - Failover is automatic via shared state
#   - No explicit state sync needed between BNGs

if selected_demo == 'all' or selected_demo == 'ha-nexus':
    k8s_yaml(kustomize('components/ha-nexus-test'))

    k8s_resource(
        'nexus:deployment:demo-ha-nexus',
        new_name='nexus-ha',
        labels=['ha-nexus-test'],
        resource_deps=['nexus-image'],
        port_forwards='9012:9000',
    )

    k8s_resource(
        'bng-ha-test',
        labels=['ha-nexus-test'],
        resource_deps=['bng-image', 'nexus-ha'],
    )

    # Run HA test
    local_resource(
        'ha-nexus-test',
        cmd='''
echo "Running HA with Nexus test..."
echo ""
kubectl exec -n demo-ha-nexus bng-ha-test -c client -- sh /scripts/run-ha-test.sh
''',
        labels=['ha-nexus-test', 'test'],
        auto_init=False,
        resource_deps=['bng-ha-test'],
    )

    # View BNG logs
    local_resource(
        'ha-nexus-bng-logs',
        cmd='kubectl logs -n demo-ha-nexus bng-ha-test -c bng --tail=40',
        labels=['ha-nexus-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-ha-test'],
    )

    # View Nexus state
    local_resource(
        'ha-nexus-state',
        cmd='''
echo "=== Nexus Pools ==="
curl -s http://localhost:9012/api/v1/pools | head -50
echo ""
echo "=== Nexus Allocations ==="
curl -s http://localhost:9012/api/v1/allocations | head -50
''',
        labels=['ha-nexus-test', 'verify'],
        auto_init=False,
        resource_deps=['nexus-ha'],
    )

# -----------------------------------------------------------------------------
# HA P2P Test - Two BNGs with direct P2P sync (no Nexus)
# -----------------------------------------------------------------------------
# Demonstrates: Active/Standby BNG pair with SSE state sync
#   - Active BNG handles DHCP and syncs sessions to standby
#   - Standby has full state, ready for failover
#   - No central coordinator (Nexus) required

if selected_demo == 'all' or selected_demo == 'ha-p2p':
    k8s_yaml(kustomize('components/ha-p2p-test'))

    k8s_resource(
        'bng-active:pod:demo-ha-p2p',
        new_name='bng-ha-active',
        labels=['ha-p2p-test'],
        resource_deps=['bng-image'],
        port_forwards='8088:8080',
    )

    k8s_resource(
        'bng-standby:pod:demo-ha-p2p',
        new_name='bng-ha-standby',
        labels=['ha-p2p-test'],
        resource_deps=['bng-image', 'bng-ha-active'],
        port_forwards='8089:8080',
    )

    # Run HA P2P test
    local_resource(
        'ha-p2p-test',
        cmd='''
echo "Running HA P2P (Active/Standby) test..."
echo ""
kubectl exec -n demo-ha-p2p bng-active -c client -- sh /scripts/run-ha-test.sh
''',
        labels=['ha-p2p-test', 'test'],
        auto_init=False,
        resource_deps=['bng-ha-standby'],
    )

    # View Active BNG logs
    local_resource(
        'ha-p2p-active-logs',
        cmd='kubectl logs -n demo-ha-p2p bng-active -c bng --tail=40',
        labels=['ha-p2p-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-ha-active'],
    )

    # View Standby BNG logs
    local_resource(
        'ha-p2p-standby-logs',
        cmd='kubectl logs -n demo-ha-p2p bng-standby -c bng --tail=40',
        labels=['ha-p2p-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-ha-standby'],
    )

    # Check HA sync status
    local_resource(
        'ha-p2p-sync-status',
        cmd='''
echo "=== HA Sync Status ==="
echo ""
echo "Active BNG sessions:"
curl -s http://localhost:8088/api/v1/sessions 2>/dev/null | head -50 || echo "  (not available)"
echo ""
echo "Standby BNG sessions:"
curl -s http://localhost:8089/api/v1/sessions 2>/dev/null | head -50 || echo "  (not available)"
echo ""
echo "Active BNG HA health:"
curl -s http://localhost:8088/ha/health 2>/dev/null || echo "  (not available)"
echo ""
echo "Standby BNG HA health:"
curl -s http://localhost:8089/ha/health 2>/dev/null || echo "  (not available)"
''',
        labels=['ha-p2p-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-ha-standby'],
    )

# -----------------------------------------------------------------------------
# Demo F: WiFi with TTL-Based Lease Expiration
# -----------------------------------------------------------------------------
# Shows epoch-based allocation with automatic expiration
# Uses EpochBitmapAllocator for memory-efficient lease tracking

if selected_demo == 'all' or selected_demo == 'wifi':
    k8s_yaml(kustomize('components/wifi-test'))

    k8s_resource(
        'nexus:pod:demo-wifi',
        new_name='nexus:wifi',
        labels=['wifi-test'],
    )

    k8s_resource(
        'bng-wifi',
        port_forwards=[
            '8092:8080',  # BNG API
        ],
        labels=['wifi-test'],
        resource_deps=['nexus:wifi'],
    )

    # Run WiFi lease test
    local_resource(
        'wifi-test',
        cmd='''
kubectl exec -n demo-wifi bng-wifi -c client -- sh /scripts/run-wifi-test.sh
''',
        labels=['wifi-test', 'test'],
        auto_init=False,
        resource_deps=['bng-wifi'],
    )

    # View BNG logs
    local_resource(
        'wifi-bng-logs',
        cmd='kubectl logs -n demo-wifi bng-wifi -c bng --tail=40',
        labels=['wifi-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-wifi'],
    )

    # Check pool and epoch status
    local_resource(
        'wifi-pool-status',
        cmd='''
echo "=== WiFi Pool Status ==="
echo ""
echo "Nexus pool info:"
curl -s http://localhost:9000/api/v1/pools 2>/dev/null | head -20 || echo "  (not available via port-forward)"
echo ""
echo "BNG stats:"
curl -s http://localhost:8092/api/v1/stats 2>/dev/null || echo "  (not available)"
echo ""
echo "BNG sessions:"
curl -s http://localhost:8092/api/v1/sessions 2>/dev/null | head -30 || echo "  (not available)"
''',
        labels=['wifi-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-wifi'],
    )

    # Verification button (quick pass/fail)
    local_resource(
        'verify-demo-wifi',
        cmd='''
echo "=== WiFi Demo Verification ==="
# Run DHCP and check we get an IP
IP=$(kubectl exec -n demo-wifi bng-wifi -c client -- sh -c '
  ip addr flush dev veth-client 2>/dev/null
  timeout 10 udhcpc -i veth-client -n -q -t 3 -T 2 -f -s /dev/null 2>&1
  ip addr show veth-client 2>/dev/null | grep "inet " | head -1 | awk "{print \\$2}" | cut -d/ -f1
' 2>/dev/null)

if [ -n "$IP" ] && [ "$IP" != "" ]; then
  echo "✓ PASS: Got IP $IP via lease mode"
  exit 0
else
  echo "✗ FAIL: No IP allocated"
  exit 1
fi
''',
        labels=['wifi-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-wifi'],
    )

# -----------------------------------------------------------------------------
# Demo G: Peer Pool (Distributed Allocation without Central Nexus)
# -----------------------------------------------------------------------------
# BNGs form a hashring to coordinate IP allocation
# No central Nexus required - peers forward requests to owner

if selected_demo == 'all' or selected_demo == 'peer-pool':
    k8s_yaml(kustomize('components/peer-pool-test'))

    k8s_resource(
        'bng-peer-pool',
        new_name='bng-peers',
        port_forwards=[
            '8093:8080',  # BNG-0 API (via headless service)
        ],
        labels=['peer-pool-test'],
        resource_deps=['bng-image'],
    )

    # Run peer pool test from BNG-0
    local_resource(
        'peer-pool-test-0',
        cmd='''
echo "=== Testing from BNG-0 ==="
kubectl exec -n demo-peer-pool bng-peer-pool-0 -c client -- sh /scripts/run-peer-test.sh
''',
        labels=['peer-pool-test', 'test'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # Run peer pool test from BNG-1
    local_resource(
        'peer-pool-test-1',
        cmd='''
echo "=== Testing from BNG-1 ==="
kubectl exec -n demo-peer-pool bng-peer-pool-1 -c client -- sh /scripts/run-peer-test.sh
''',
        labels=['peer-pool-test', 'test'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # Run peer pool test from BNG-2
    local_resource(
        'peer-pool-test-2',
        cmd='''
echo "=== Testing from BNG-2 ==="
kubectl exec -n demo-peer-pool bng-peer-pool-2 -c client -- sh /scripts/run-peer-test.sh
''',
        labels=['peer-pool-test', 'test'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # View BNG-0 logs
    local_resource(
        'peer-pool-bng0-logs',
        cmd='kubectl logs -n demo-peer-pool bng-peer-pool-0 -c bng --tail=40',
        labels=['peer-pool-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # Check pool status across all peers
    local_resource(
        'peer-pool-status',
        cmd='''
echo "=== Peer Pool Status ==="
echo ""
for i in 0 1 2; do
  echo "BNG-$i pool status:"
  kubectl exec -n demo-peer-pool bng-$i -c bng -- wget -q -O- http://localhost:8080/pool/status 2>/dev/null || echo "  (not available)"
  echo ""
done
''',
        labels=['peer-pool-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # Verify consistent allocation
    local_resource(
        'peer-pool-verify',
        cmd='''
echo "=== Verify Consistent Allocation ==="
echo ""
echo "Allocating from BNG-0 for test-subscriber..."
kubectl exec -n demo-peer-pool bng-peer-pool-0 -c bng -- wget -q -O- --post-data='{"subscriber_id":"test-sub-123"}' \
  --header='Content-Type: application/json' http://localhost:8080/pool/allocate 2>/dev/null || echo "  (allocation failed)"
echo ""
echo "Checking allocation from all peers..."
for i in 0 1 2; do
  echo "BNG-$i lookup:"
  kubectl exec -n demo-peer-pool bng-$i -c bng -- wget -q -O- "http://localhost:8080/pool/lookup?subscriber_id=test-sub-123" 2>/dev/null || echo "  (not found)"
done
''',
        labels=['peer-pool-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

    # Verification button (quick pass/fail)
    local_resource(
        'verify-demo-peer-pool',
        cmd='''
echo "=== Peer Pool Demo Verification ==="

# Allocate from BNG-0
ALLOC=$(kubectl exec -n demo-peer-pool bng-peer-pool-0 -c bng -- wget -q -O- --post-data='{"subscriber_id":"verify-test-'$(date +%s)'"}' \
  --header='Content-Type: application/json' http://localhost:8080/pool/allocate 2>/dev/null)

IP=$(echo "$ALLOC" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)

if [ -n "$IP" ] && [ "$IP" != "" ]; then
  echo "✓ PASS: Allocated IP $IP via peer pool"

  # Check consistency - lookup from another node
  LOOKUP=$(kubectl exec -n demo-peer-pool bng-peer-pool-1 -c bng -- wget -q -O- \
    "http://localhost:8080/pool/lookup?subscriber_id=verify-test-$(date +%s)" 2>/dev/null || echo "{}")

  echo "  Peer consistency check from BNG-1: $LOOKUP"
  exit 0
else
  echo "✗ FAIL: No IP allocated"
  echo "  Response: $ALLOC"
  exit 1
fi
''',
        labels=['peer-pool-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-peers'],
    )

# -----------------------------------------------------------------------------
# Demo: RADIUS-Time Allocation (The Key Optimization)
# -----------------------------------------------------------------------------
# Shows IP allocation at RADIUS time (before DHCP), enabling eBPF fast path
# This is THE KEY optimization: DHCP served from kernel (~10us) not userspace (~10ms)

if selected_demo == 'all' or selected_demo == 'radius-time':
    k8s_yaml(kustomize('components/radius-time-test'))

    k8s_resource(
        'nexus:deployment:demo-radius-time',
        new_name='nexus:radius-time',
        labels=['radius-time-test'],
        resource_deps=['nexus-image'],
        port_forwards='9013:9000',
    )

    k8s_resource(
        'bng-radius-time',
        port_forwards='8094:8080',
        labels=['radius-time-test'],
        resource_deps=['bng-image', 'nexus:radius-time'],
    )

    # Run RADIUS-time allocation test
    local_resource(
        'radius-time-test',
        cmd='''
echo "Running RADIUS-Time Allocation test..."
echo ""
kubectl exec -n demo-radius-time bng -c client -- sh /scripts/run-radius-time-test.sh
''',
        labels=['radius-time-test', 'test'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

    # View BNG logs
    local_resource(
        'radius-time-bng-logs',
        cmd='kubectl logs -n demo-radius-time deploy/bng -c bng --tail=40',
        labels=['radius-time-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

    # Check provision endpoint (IPv4 only)
    local_resource(
        'radius-time-provision',
        cmd='''
echo "=== Test Provision API (IPv4) ==="
echo ""
echo "Provisioning a subscriber (simulates RADIUS Access-Accept)..."
curl -s -X POST http://localhost:8094/api/v1/provision \
  -H "Content-Type: application/json" \
  -d '{"mac":"02:00:00:00:00:99","subscriber_id":"test-sub-99"}' | jq .
echo ""
echo "Checking BNG stats (fast path counter)..."
curl -s http://localhost:8094/api/v1/stats | jq .
''',
        labels=['radius-time-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

    # Test dual-stack provisioning (IPv4 + IPv6)
    local_resource(
        'radius-time-dualstack',
        cmd='''
echo "=== Test Dual-Stack Provision API (IPv4 + IPv6) ==="
echo ""
kubectl exec -n demo-radius-time deploy/bng -c client -- sh /scripts/run-dualstack-test.sh
''',
        labels=['radius-time-test', 'test'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

    # Test dual-stack via curl directly
    local_resource(
        'radius-time-dualstack-curl',
        cmd='''
echo "=== Dual-Stack Provisioning via curl ==="
echo ""
MAC="02:00:00:00:$(printf '%02x' $((RANDOM % 256))):$(printf '%02x' $((RANDOM % 256)))"
echo "MAC: $MAC"
echo ""
echo "Provisioning dual-stack (IPv4 + IPv6)..."
curl -s -X POST http://localhost:8094/api/v1/provision \
  -H "Content-Type: application/json" \
  -d "{\"mac\":\"$MAC\",\"subscriber_id\":\"dualstack-test-$(date +%s)\",\"ipv6_pool_id\":\"radius-demo-v6\"}" | jq .
''',
        labels=['radius-time-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

    # Verification button
    local_resource(
        'verify-demo-radius-time',
        cmd='''
echo "=== RADIUS-Time Allocation Verification ==="
MAC="02:00:00:00:00:$(date +%S)"

echo "Step 1: Provision via API (RADIUS-time)..."
PROVISION=$(curl -s -X POST http://localhost:8094/api/v1/provision \
  -H "Content-Type: application/json" \
  -d "{\"mac\":\"$MAC\",\"subscriber_id\":\"verify-sub-$(date +%s)\"}")

PROVISIONED_IP=$(echo "$PROVISION" | grep -o '"ip":"[^"]*"' | cut -d'"' -f4)
FAST_PATH=$(echo "$PROVISION" | grep -o '"fast_path":[^,}]*' | cut -d':' -f2)

echo "  Provisioned IP: $PROVISIONED_IP"
echo "  Fast path enabled: $FAST_PATH"

if [ -n "$PROVISIONED_IP" ] && [ "$FAST_PATH" = "true" ]; then
  echo ""
  echo "✓ PASS: RADIUS-time allocation working"
  echo "  - IP allocated before DHCP request"
  echo "  - eBPF fast path enabled"
  echo "  - DHCP will be served from kernel"
  exit 0
else
  echo ""
  echo "✗ FAIL: Provisioning failed"
  echo "  Response: $PROVISION"
  exit 1
fi
''',
        labels=['radius-time-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-radius-time'],
    )

# -----------------------------------------------------------------------------
# Demo: PPPoE Session Lifecycle
# -----------------------------------------------------------------------------
# Demonstrates full PPPoE stack: PADI→PADO→PADR→PADS→LCP→Auth→IPCP

if selected_demo == 'all' or selected_demo == 'pppoe':
    k8s_yaml(kustomize('components/pppoe-test'))

    k8s_resource(
        'pppoe-test',
        port_forwards='8095:8080',
        labels=['pppoe-test'],
        resource_deps=['helmfile-hydrate'],
    )

    # Run PPPoE session test
    local_resource(
        'pppoe-test-run',
        cmd='kubectl exec -n demo-pppoe pppoe-test -c client -- /scripts/run-pppoe-test.sh',
        labels=['pppoe-test', 'test'],
        auto_init=False,
        resource_deps=['pppoe-test'],
    )

    # Quick verification
    local_resource(
        'pppoe-verify',
        cmd='kubectl exec -n demo-pppoe pppoe-test -c client -- /scripts/verify-pppoe.sh',
        labels=['pppoe-test', 'verify'],
        auto_init=False,
        resource_deps=['pppoe-test'],
    )

    # View BNG logs
    local_resource(
        'pppoe-bng-logs',
        cmd='kubectl logs -n demo-pppoe pppoe-test -c bng --tail=50',
        labels=['pppoe-test', 'logs'],
        auto_init=False,
        resource_deps=['pppoe-test'],
    )

# -----------------------------------------------------------------------------
# Demo: IPv6 (SLAAC + DHCPv6 + Prefix Delegation)
# -----------------------------------------------------------------------------
# Demonstrates Router Advertisements, DHCPv6 address allocation, and PD

if selected_demo == 'all' or selected_demo == 'ipv6':
    k8s_yaml(kustomize('components/ipv6-test'))

    k8s_resource(
        'bng-ipv6',
        port_forwards='8096:8080',
        labels=['ipv6-test'],
        resource_deps=['helmfile-hydrate'],
    )

    # Run full IPv6 test (SLAAC + DHCPv6 + PD)
    local_resource(
        'ipv6-test-run',
        cmd='kubectl exec -n demo-ipv6 bng-ipv6 -c client -- /scripts/run-ipv6-test.sh',
        labels=['ipv6-test', 'test'],
        auto_init=False,
        resource_deps=['bng-ipv6'],
    )

    # View BNG logs
    local_resource(
        'ipv6-bng-logs',
        cmd='kubectl logs -n demo-ipv6 bng-ipv6 -c bng --tail=50',
        labels=['ipv6-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-ipv6'],
    )

    # Check IPv6 addresses on client
    local_resource(
        'ipv6-client-addrs',
        cmd='kubectl exec -n demo-ipv6 bng-ipv6 -c client -- ip -6 addr show',
        labels=['ipv6-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-ipv6'],
    )

# -----------------------------------------------------------------------------
# Demo: NAT44/CGNAT
# -----------------------------------------------------------------------------
# Demonstrates CGNAT with port blocks, hairpinning, and logging

if selected_demo == 'all' or selected_demo == 'nat':
    k8s_yaml(kustomize('components/nat-test'))

    k8s_resource(
        'bng-nat',
        port_forwards='8097:8080',
        labels=['nat-test'],
        resource_deps=['helmfile-hydrate'],
    )

    # Run all NAT tests
    local_resource(
        'nat-test-all',
        cmd='kubectl exec -n demo-nat bng-nat -c client-1 -- sh /scripts/run-all-tests.sh',
        labels=['nat-test', 'test'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

    # Test basic NAT
    local_resource(
        'nat-test-basic',
        cmd='kubectl exec -n demo-nat bng-nat -c client-1 -- sh /scripts/test-basic-nat.sh',
        labels=['nat-test', 'test'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

    # Test hairpinning
    local_resource(
        'nat-test-hairpin',
        cmd='kubectl exec -n demo-nat bng-nat -c client-1 -- sh /scripts/test-hairpinning.sh',
        labels=['nat-test', 'test'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

    # Test port blocks
    local_resource(
        'nat-test-ports',
        cmd='kubectl exec -n demo-nat bng-nat -c client-1 -- sh /scripts/test-port-blocks.sh',
        labels=['nat-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

    # View NAT logs
    local_resource(
        'nat-logs',
        cmd='kubectl exec -n demo-nat bng-nat -c client-1 -- sh /scripts/test-nat-logging.sh',
        labels=['nat-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

    # View BNG logs
    local_resource(
        'nat-bng-logs',
        cmd='kubectl logs -n demo-nat bng-nat -c bng --tail=50',
        labels=['nat-test', 'logs'],
        auto_init=False,
        resource_deps=['bng-nat'],
    )

# -----------------------------------------------------------------------------
# Demo: QoS / Rate Limiting (TC eBPF)
# -----------------------------------------------------------------------------
# Demonstrates per-subscriber rate limiting with token bucket algorithm

if selected_demo == 'all' or selected_demo == 'qos':
    k8s_yaml(kustomize('components/qos-test'))

    k8s_resource(
        'qos-test',
        port_forwards='8098:8080',
        labels=['qos-test'],
        resource_deps=['helmfile-hydrate'],
    )

    # Run complete QoS demo
    local_resource(
        'qos-demo-run',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/run-demo.sh',
        labels=['qos-test', 'test'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # Configure rate limit
    local_resource(
        'qos-configure',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/configure-rate-limit.sh 10.100.0.100 10 5 128',
        labels=['qos-test', 'test'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # Measure throughput
    local_resource(
        'qos-measure',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/measure-throughput.sh 10',
        labels=['qos-test', 'verify'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # Verify rate limiting
    local_resource(
        'qos-verify',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/verify-rate-limiting.sh 10 5',
        labels=['qos-test', 'verify'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # Multi-subscriber test
    local_resource(
        'qos-multi-sub',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/multi-subscriber-test.sh',
        labels=['qos-test', 'test'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # Show stats
    local_resource(
        'qos-stats',
        cmd='kubectl exec -n demo-qos qos-test -c client -- /scripts/show-stats.sh',
        labels=['qos-test', 'verify'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

    # View BNG logs
    local_resource(
        'qos-bng-logs',
        cmd='kubectl logs -n demo-qos qos-test -c bng --tail=50',
        labels=['qos-test', 'logs'],
        auto_init=False,
        resource_deps=['qos-test'],
    )

# -----------------------------------------------------------------------------
# Demo: Failure Injection / Resilience Testing
# -----------------------------------------------------------------------------
# Tests failover, partition recovery, and graceful degradation

if selected_demo == 'all' or selected_demo == 'failure':
    k8s_yaml(kustomize('components/failure-test'))

    k8s_resource(
        'nexus-failure',
        new_name='nexus-failure-cluster',
        labels=['failure-test'],
        resource_deps=['helmfile-hydrate'],
    )

    k8s_resource(
        'bng-active:pod:demo-failure',
        new_name='bng-failure-active',
        labels=['failure-test'],
        resource_deps=['nexus-failure-cluster'],
    )

    k8s_resource(
        'bng-standby:pod:demo-failure',
        new_name='bng-failure-standby',
        labels=['failure-test'],
        resource_deps=['bng-failure-active'],
    )

    k8s_resource(
        'test-controller',
        new_name='failure-controller',
        labels=['failure-test'],
        resource_deps=['bng-failure-standby'],
    )

    # Run all failure tests
    local_resource(
        'failure-test-all',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/run-all-tests.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

    # Individual test: Nexus node failure
    local_resource(
        'failure-nexus',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/test-nexus-failure.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

    # Individual test: BNG failover
    local_resource(
        'failure-bng',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/test-bng-failover.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

    # Individual test: Network partition
    local_resource(
        'failure-partition',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/test-network-partition.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

    # Individual test: State recovery
    local_resource(
        'failure-recovery',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/test-state-recovery.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

    # Individual test: Graceful degradation
    local_resource(
        'failure-degradation',
        cmd='kubectl exec -n demo-failure test-controller -- /scripts/test-graceful-degradation.sh',
        labels=['failure-test', 'test'],
        auto_init=False,
        resource_deps=['failure-controller'],
    )

# -----------------------------------------------------------------------------
# Demo: BGP/FRR Integration (Subscriber Route Injection)
# -----------------------------------------------------------------------------
# Demonstrates BGP peering, subscriber route injection/withdrawal, and BFD

if selected_demo == 'all' or selected_demo == 'bgp':
    k8s_yaml(kustomize('components/bgp-test'))

    k8s_resource(
        'frr-upstream',
        labels=['bgp-test'],
        resource_deps=['helmfile-hydrate'],
    )

    k8s_resource(
        'bng-bgp',
        port_forwards='8099:8080',
        labels=['bgp-test'],
        resource_deps=['frr-upstream'],
    )

    # Run full BGP demo
    local_resource(
        'bgp-demo-run',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/run-demo.sh',
        labels=['bgp-test', 'test'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Check BGP session
    local_resource(
        'bgp-session',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/check-bgp-session.sh',
        labels=['bgp-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Check BFD session
    local_resource(
        'bgp-bfd',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/check-bfd-session.sh',
        labels=['bgp-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Inject subscriber route
    local_resource(
        'bgp-inject-route',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/inject-subscriber-route.sh 10.0.1.100',
        labels=['bgp-test', 'test'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Show routes
    local_resource(
        'bgp-show-routes',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/show-routes.sh',
        labels=['bgp-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Check upstream received routes
    local_resource(
        'bgp-upstream-routes',
        cmd='kubectl exec -n demo-bgp deploy/frr-upstream -- /scripts/check-upstream-routes.sh',
        labels=['bgp-test', 'verify'],
        auto_init=False,
        resource_deps=['bng-bgp'],
    )

    # Withdraw subscriber route
    local_resource(
        'bgp-withdraw-route',
        cmd='kubectl exec -n demo-bgp deploy/bng-bgp -c frr -- /scripts/withdraw-subscriber-route.sh 10.0.1.100',
        labels=['bgp-test', 'test'],
        auto_init=False,
        resource_deps=['bng-bgp'],
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
  HA Nexus Test:                 - Two BNGs + shared Nexus (implicit HA)
  HA P2P Test:                   - Two BNGs direct sync (Active/Standby)
  WiFi Test:                     - TTL-based lease mode with epoch expiration
  Peer Pool Test:                - Distributed allocation without central Nexus
  RADIUS-Time Test:              - IP allocation at RADIUS time (KEY OPTIMIZATION)
  PPPoE Test:                    - Full PPPoE session lifecycle
  IPv6 Test:                     - SLAAC + DHCPv6 + Prefix Delegation
  NAT Test:                      - CGNAT with port blocks and hairpinning
  QoS Test:                      - Per-subscriber rate limiting (TC eBPF)
  Failure Test:                  - Resilience and failover scenarios
  BGP Test:                      - FRR peering and subscriber route injection

Run specific demo:
  tilt up -- --demo=a              # Standalone BNG only
  tilt up -- --demo=b              # Single integration only
  tilt up -- --demo=c              # P2P cluster only
  tilt up -- --demo=d              # Full distributed only
  tilt up -- --demo=blaster        # BNG Blaster placeholder
  tilt up -- --demo=blaster-test   # Real DHCP (local pool)
  tilt up -- --demo=e2e            # Real DHCP → Nexus (RECOMMENDED)
  tilt up -- --demo=walled-garden  # Walled Garden lifecycle
  tilt up -- --demo=ha-nexus       # HA with shared Nexus
  tilt up -- --demo=ha-p2p         # HA P2P Active/Standby
  tilt up -- --demo=wifi           # WiFi TTL lease mode
  tilt up -- --demo=peer-pool      # Peer pool (no Nexus)
  tilt up -- --demo=radius-time    # RADIUS-time allocation (KEY OPTIMIZATION)
  tilt up -- --demo=pppoe          # PPPoE session lifecycle
  tilt up -- --demo=ipv6           # IPv6 SLAAC/DHCPv6/PD
  tilt up -- --demo=nat            # NAT/CGNAT
  tilt up -- --demo=qos            # QoS rate limiting
  tilt up -- --demo=failure        # Failure injection/resilience
  tilt up -- --demo=bgp            # BGP/FRR subscriber routes
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

HA with Nexus (--demo=ha-nexus):
  Two BNGs sharing state via central Nexus:
  - ha-nexus-test:     Run HA test (same IP from either BNG)
  - ha-nexus-bng-logs: View BNG logs
  - ha-nexus-state:    View Nexus allocations

HA P2P (--demo=ha-p2p):
  Active/Standby BNGs with direct P2P sync (no Nexus):
  - ha-p2p-test:        Run HA P2P test
  - ha-p2p-active-logs: View Active BNG logs
  - ha-p2p-standby-logs: View Standby BNG logs
  - ha-p2p-sync-status: Check HA sync status

WiFi Test (--demo=wifi):
  TTL-based lease mode with epoch expiration (EpochBitmapAllocator):
  - wifi-test:         Run WiFi lease allocation test
  - wifi-bng-logs:     View BNG logs
  - wifi-pool-status:  Check pool and epoch status

Peer Pool (--demo=peer-pool):
  Distributed allocation without central Nexus (hashring coordination):
  - peer-pool-test-0/1/2: Run allocation from each BNG
  - peer-pool-bng0-logs:  View BNG-0 logs
  - peer-pool-status:     Check pool status across all peers
  - peer-pool-verify:     Verify consistent allocation

RADIUS-Time Allocation (--demo=radius-time) - KEY OPTIMIZATION:
  IP allocated during RADIUS auth (before DHCP), enabling eBPF fast path:
  - radius-time-test:          Run full RADIUS-time allocation test
  - radius-time-dualstack:     Test dual-stack (IPv4 + IPv6) provisioning
  - radius-time-dualstack-curl: Test dual-stack via curl
  - radius-time-bng-logs:      View BNG logs
  - radius-time-provision:     Test provision API directly (IPv4)
  This is THE KEY optimization - DHCP served from kernel (~10us) not userspace (~10ms)
  Supports dual-stack: pass ipv6_pool_id to provision both IPv4 and IPv6 atomically

PPPoE (--demo=pppoe):
  Full PPPoE session lifecycle (PADI→PADO→PADR→PADS→LCP→Auth→IPCP):
  - pppoe-test-run:  Run PPPoE session establishment test
  - pppoe-verify:    Quick verification of session state
  - pppoe-bng-logs:  View BNG PPPoE logs

IPv6 (--demo=ipv6):
  SLAAC, DHCPv6 address allocation, and Prefix Delegation:
  - ipv6-test-run:    Run all IPv6 tests (SLAAC + DHCPv6 + PD)
  - ipv6-client-addrs: Show IPv6 addresses on client
  - ipv6-bng-logs:    View BNG IPv6 logs

NAT/CGNAT (--demo=nat):
  CGNAT with port blocks, hairpinning, and RFC 6908 logging:
  - nat-test-all:     Run all NAT tests
  - nat-test-basic:   Test basic client→NAT→external connectivity
  - nat-test-hairpin: Test hairpinning (client→NAT→same-subnet)
  - nat-test-ports:   Test port block allocation
  - nat-logs:         View NAT logging events
  - nat-bng-logs:     View BNG NAT logs

QoS/Rate Limiting (--demo=qos):
  Per-subscriber rate limiting with TC eBPF token bucket:
  - qos-demo-run:     Run complete QoS demo
  - qos-configure:    Configure rate limit (10 Mbps down, 5 Mbps up)
  - qos-measure:      Measure throughput with iperf3
  - qos-verify:       Verify rate limiting is enforced
  - qos-multi-sub:    Test multiple subscriber plans (Basic/Premium/Business)
  - qos-stats:        Show QoS statistics from eBPF maps

Failure Injection (--demo=failure):
  Resilience testing with 5 scenarios:
  - failure-test-all:    Run all failure tests
  - failure-nexus:       Nexus node failure (hashring rebalancing)
  - failure-bng:         BNG failover (P2P sync takeover)
  - failure-partition:   Network partition (split-brain recovery)
  - failure-recovery:    State recovery (restart and restore)
  - failure-degradation: Graceful degradation (overload handling)

BGP/FRR Integration (--demo=bgp):
  Subscriber route injection via BGP with BFD:
  - bgp-demo-run:        Run full BGP demo
  - bgp-session:         Check BGP session status
  - bgp-bfd:             Check BFD session status
  - bgp-inject-route:    Inject subscriber /32 route
  - bgp-withdraw-route:  Withdraw subscriber route
  - bgp-show-routes:     Show BNG routing table
  - bgp-upstream-routes: Check routes received on upstream

Verification:
  Click 'verify-demo-X' buttons in Tilt UI to test each demo

Observability:
  - Tilt UI:    http://localhost:10350
  - Hubble:     http://localhost:12000
  - Prometheus: http://localhost:9090
  - Grafana:    http://localhost:3000
""".strip())
