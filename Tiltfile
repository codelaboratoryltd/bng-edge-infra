# BNG Edge Infrastructure - Local Development
#
# Prerequisites:
#   ./scripts/init.sh    # Create k3d cluster and hydrate charts (REQUIRED)
#
# Usage:
#   tilt up                          # Nothing enabled (shows available groups)
#   tilt up demo-a                   # Standalone BNG only
#   tilt up demo-b                   # Single integration (BNG + Nexus)
#   tilt up demo-c                   # P2P cluster (3 Nexus)
#   tilt up demo-d                   # Distributed (3 Nexus + 2 BNG)
#   tilt up e2e                      # E2E integration test
#   tilt up demo-a demo-b            # Multiple groups
#   tilt up all                      # Everything
#
# Architecture:
#   - Single kustomization loads all manifests
#   - config.set_enabled_resources() controls what deploys
#   - Use Tilt UI labels to filter resources

print("""
-----------------------------------------------------------------
BNG Edge Infrastructure - Local Development
-----------------------------------------------------------------
""".strip())

# =============================================================================
# Configuration
# =============================================================================

config.define_string_list("with", args=True)
cfg = config.parse()

# =============================================================================
# Resource Groups
# =============================================================================

groups = {
    # Demos
    "demo-a": ["standalone-bng"],
    "demo-b": ["single-bng", "single-nexus"],
    "demo-c": ["p2p-nexus"],
    "demo-d": ["distributed-bng", "distributed-nexus"],

    # Tests
    "e2e": ["nexus", "bng-e2e"],
    "blaster": ["bngblaster"],
    "blaster-test": ["bng-dhcp-test"],
    "walled-garden": ["bng-wgar-test"],
    "ha-nexus": ["bng-ha-test"],
    "ha-p2p": ["bng-active", "bng-standby"],
    "wifi": ["bng-wifi"],
    "peer-pool": ["bng-peer-pool"],
    "radius-time": ["bng-radius-time"],
    "pppoe": ["pppoe-test"],
    "ipv6": ["bng-ipv6"],
    "nat": ["bng-nat"],
    "qos": ["qos-test"],
    "bgp": ["bng-bgp", "frr-upstream"],
    "failure": ["nexus-failure", "bng-failure-active", "bng-failure-standby", "test-controller"],

    # Infrastructure
    "infra": ["hubble-ui", "prometheus-server", "grafana"],

    # All demos
    "demos": ["standalone-bng", "single-bng", "single-nexus", "p2p-nexus", "distributed-bng", "distributed-nexus"],

    # All tests
    "tests": [
        "nexus", "bng-e2e", "bngblaster", "bng-dhcp-test", "bng-wgar-test",
        "bng-ha-test", "bng-active", "bng-standby", "bng-wifi", "bng-peer-pool",
        "bng-radius-time", "pppoe-test", "bng-ipv6", "bng-nat", "qos-test",
        "bng-bgp", "frr-upstream", "nexus-failure", "test-controller"
    ],

    # Everything
    "all": [],  # Populated below
}

# Build "all" group from all other groups
for name, resources in groups.items():
    if name != "all":
        for r in resources:
            if r not in groups["all"]:
                groups["all"].append(r)

# Group dependencies (when starting X, also start Y)
group_depends = {
    "demo-b": ["infra"],
    "demo-c": ["infra"],
    "demo-d": ["infra"],
    "e2e": ["infra"],
    "demos": ["infra"],
    "tests": ["infra"],
    "all": ["infra"],
}

# Resource dependencies (resource X depends on resource Y)
resource_depends = {
    "single-bng": ["single-nexus"],
    "distributed-bng": ["distributed-nexus"],
    "bng-e2e": ["nexus"],
}

# Port forwards
resource_port_forwards = {
    # Infrastructure
    "hubble-ui": "12000:80",
    "prometheus-server": "9090:9090",
    "grafana": "3000:3000",

    # Demo A
    "standalone-bng": "8080:8080",

    # Demo B
    "single-bng": "8081:8080",
    "single-nexus": "9001:9000",

    # Demo C
    "p2p-nexus": "9002:9000",

    # Demo D
    "distributed-bng": "8083:8080",
    "distributed-nexus": "9003:9000",

    # E2E
    "nexus": "9010:9000",

    # Tests
    "bng-dhcp-test": "8090:8080",
    "bng-wifi": "8092:8080",
    "bng-peer-pool": "8093:8080",
    "bng-radius-time": "8094:8080",
    "pppoe-test": "8095:8080",
    "bng-ipv6": "8096:8080",
    "bng-nat": "8097:8080",
    "qos-test": "8098:8080",
    "bng-bgp": "8099:8080",
}

# =============================================================================
# Safety Checks
# =============================================================================

allow_k8s_contexts('k3d-bng-edge')

def check_k3d_cluster():
    cluster_status = str(local('k3d cluster list 2>/dev/null | grep "^bng-edge" || echo "NOT_FOUND"', quiet=True)).strip()
    if "NOT_FOUND" in cluster_status:
        return False
    return cluster_status.endswith("true")

if not check_k3d_cluster():
    fail("""
k3d cluster 'bng-edge' is not running!

To fix this:
  1. Create the cluster: ./scripts/init.sh
  2. Then run: tilt up

If you already have a cluster, make sure it's started:
  k3d cluster start bng-edge
""")

print("k3d cluster 'bng-edge' is running")

# Add SSH keys for private repo access during Docker builds
local('ssh-add $HOME/.ssh/id_*[^pub] 2>/dev/null || true', quiet=True)

# Docker prune settings
docker_prune_settings(
    disable=False,
    max_age_mins=120,
    num_builds=5,
    keep_recent=2
)

# =============================================================================
# Docker Builds (unconditional - Tilt handles dependencies)
# =============================================================================

docker_build(
    'ghcr.io/codelaboratoryltd/bng',
    'src/bng',
    dockerfile='src/bng/Dockerfile',
    ssh='default',
)

docker_build(
    'ghcr.io/codelaboratoryltd/nexus',
    'src/nexus',
    dockerfile='src/nexus/Dockerfile',
    ssh='default',
)

docker_build(
    'ghcr.io/codelaboratoryltd/bngblaster',
    'components/bngblaster',
    dockerfile='components/bngblaster/Dockerfile',
)

# =============================================================================
# Kubernetes Resources (single kustomization - loads all manifests)
# =============================================================================

k8s_yaml(kustomize('clusters/local-dev'))

# =============================================================================
# Resource Configuration
# =============================================================================

enabled_resources = []

def enableResource(resource, labels):
    """Enable a resource and configure it with labels, deps, and port forwards.

    Labels come from the group name - this matches the borg pattern where
    the group name becomes the Tilt UI label for filtering.
    """
    if resource in enabled_resources:
        return
    enabled_resources.append(resource)

    deps = resource_depends.get(resource, [])
    forwards = resource_port_forwards.get(resource, [])

    # Handle prometheus-server rename
    if resource == "prometheus-server":
        k8s_resource(workload=resource, new_name="prometheus", labels=labels, resource_deps=deps, port_forwards=forwards)
    else:
        k8s_resource(workload=resource, labels=labels, resource_deps=deps, port_forwards=forwards)

# Process command line arguments
for arg in cfg.get('with', []):
    # First, enable any group dependencies
    if arg in group_depends:
        for dep_group in group_depends[arg]:
            if dep_group in groups:
                for resource in groups[dep_group]:
                    enableResource(resource, dep_group)

    # Then enable the requested group
    if arg in groups:
        for resource in groups[arg]:
            enableResource(resource, arg)
    else:
        # Assume it's a single resource name
        enableResource(arg, arg)

# =============================================================================
# Verification Resources (local_resource)
# =============================================================================

if "standalone-bng" in enabled_resources:
    local_resource(
        'verify-demo-a',
        cmd='curl -s http://localhost:8080/api/v1/sessions | jq ".count"',
        labels=['demo-a', 'verify'],
        auto_init=False,
        resource_deps=['standalone-bng'],
    )

if "single-bng" in enabled_resources:
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
        resource_deps=['single-bng'],
    )

if "p2p-nexus" in enabled_resources:
    local_resource(
        'verify-demo-c',
        cmd='''
echo "Creating pool on p2p-nexus-0..."
kubectl exec -n demo-p2p p2p-nexus-0 -- curl -s -X POST localhost:9000/api/v1/pools \
  -H "Content-Type: application/json" \
  -d '{"id":"test-c","cidr":"10.60.0.0/24","prefix":32}' > /dev/null 2>&1 || true
echo "Waiting for CRDT sync..."
sleep 3
echo "Checking if pool appears on p2p-nexus-1:"
kubectl exec -n demo-p2p p2p-nexus-1 -- curl -s localhost:9000/api/v1/pools | jq -r '.pools[].id // "no pools found"'
''',
        labels=['demo-c', 'verify'],
        auto_init=False,
        resource_deps=['p2p-nexus'],
    )

if "distributed-bng" in enabled_resources:
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
        resource_deps=['distributed-bng'],
    )

if "bng-e2e" in enabled_resources:
    local_resource(
        'e2e-dhcp-test',
        cmd='''
echo "============================================"
echo "  E2E Integration Test: DHCP -> BNG -> Nexus"
echo "============================================"
echo ""
echo "Step 1: Checking Nexus pool..."
POOL=$(curl -s http://localhost:9010/api/v1/pools | jq -r '.pools[0].id // "none"')
if [ "$POOL" = "e2e-pool" ]; then
  echo "  Pool 'e2e-pool' exists in Nexus"
else
  echo "  Pool not found. Creating..."
  curl -s -X POST http://localhost:9010/api/v1/pools \
    -H "Content-Type: application/json" \
    -d '{"id":"e2e-pool","cidr":"10.200.0.0/16","prefix":32}' > /dev/null
fi
echo ""
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
  ip addr flush dev veth-client 2>/dev/null || true
  echo "  Sending DHCP DISCOVER..."
  udhcpc -i veth-client -n -q -t 5 -T 2 -f -s /etc/udhcpc/simple.script 2>&1
'
echo ""
echo "Step 3: Verifying client IP..."
CLIENT_IP=$(kubectl exec -n demo-e2e bng-e2e -c client -- ip addr show veth-client 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo "  Client IP: $CLIENT_IP"
echo ""
echo "Step 4: Verification..."
case "$CLIENT_IP" in
  10.200.*) echo "  PASS: Client IP $CLIENT_IP is from Nexus pool" ;;
  "") echo "  FAIL: No IP assigned to client" ;;
  *) echo "  FAIL: Client IP $CLIENT_IP is NOT from Nexus pool" ;;
esac
echo "============================================"
''',
        labels=['e2e', 'test'],
        auto_init=False,
        resource_deps=['bng-e2e'],
    )

    local_resource(
        'e2e-nexus-state',
        cmd='''
echo "=== Nexus State ==="
echo "Pools:"
curl -s http://localhost:9010/api/v1/pools | jq '.pools[] | {id, cidr, prefix}'
echo "Allocations:"
curl -s http://localhost:9010/api/v1/allocations | jq '.allocations[] | {subscriber_id, ip, pool_id}'
''',
        labels=['e2e', 'verify'],
        auto_init=False,
        resource_deps=['nexus'],
    )

# =============================================================================
# Set Enabled Resources
# =============================================================================

config.clear_enabled_resources()

if len(enabled_resources) == 0:
    print("""
No resources specified. Available groups:

  Demos:
    demo-a          Standalone BNG (no Nexus)
    demo-b          Single integration (1 BNG + 1 Nexus)
    demo-c          P2P cluster (3 Nexus)
    demo-d          Distributed (3 Nexus + 2 BNG)
    demos           All demos

  Tests:
    e2e             E2E integration test (DHCP -> BNG -> Nexus)
    blaster         BNG Blaster traffic generator
    blaster-test    Blaster DHCP test
    walled-garden   Walled garden lifecycle test
    ha-nexus        HA with shared Nexus
    ha-p2p          HA P2P Active/Standby
    wifi            WiFi TTL lease mode
    peer-pool       Peer pool (no Nexus)
    radius-time     RADIUS-time allocation
    pppoe           PPPoE session lifecycle
    ipv6            IPv6 SLAAC/DHCPv6/PD
    nat             NAT/CGNAT
    qos             QoS rate limiting
    bgp             BGP/FRR integration
    failure         Failure injection
    tests           All tests

  Infrastructure:
    infra           Hubble, Prometheus, Grafana

  Meta:
    all             Everything

Usage:
  tilt up demo-a              # Single demo
  tilt up demo-a demo-b       # Multiple demos
  tilt up e2e                 # E2E test
  tilt up all                 # Everything
""")
else:
    config.set_enabled_resources(enabled_resources)
    print("\nEnabled resources: " + ", ".join(enabled_resources))

# =============================================================================
# Startup Message
# =============================================================================

print("""
Observability (when infra enabled):
  - Tilt UI:    http://localhost:10350
  - Hubble:     http://localhost:12000
  - Prometheus: http://localhost:9090
  - Grafana:    http://localhost:3000
""".strip())
