#!/usr/bin/env bash
# Unified health check script for BNG demos
# Usage: ./scripts/demo-health.sh [demo-name|all]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

pass() {
  echo -e "  ${GREEN}PASS${NC}: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "  ${RED}FAIL${NC}: $1"
  FAIL=$((FAIL + 1))
}

warn() {
  echo -e "  ${YELLOW}WARN${NC}: $1"
  WARN=$((WARN + 1))
}

check_pods() {
  local ns="$1"
  local label="${2:-}"
  local selector=""
  if [ -n "$label" ]; then
    selector="-l $label"
  fi

  # Check if namespace exists
  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    fail "Namespace $ns does not exist"
    return 1
  fi

  # Check pod status
  local not_ready
  not_ready=$(kubectl get pods -n "$ns" $selector --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l | tr -d ' ')
  local total
  total=$(kubectl get pods -n "$ns" $selector --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [ "$total" -eq 0 ]; then
    fail "No pods found in $ns"
    return 1
  fi

  if [ "$not_ready" -eq 0 ]; then
    pass "All $total pod(s) running in $ns"
  else
    fail "$not_ready of $total pod(s) not ready in $ns"
    kubectl get pods -n "$ns" $selector --no-headers 2>/dev/null | grep -v "Running\|Completed" | while read -r line; do
      echo "       $line"
    done
    return 1
  fi
  return 0
}

check_service() {
  local ns="$1"
  local svc="$2"
  if kubectl get service "$svc" -n "$ns" >/dev/null 2>&1; then
    pass "Service $svc exists in $ns"
  else
    fail "Service $svc not found in $ns"
  fi
}

check_health_endpoint() {
  local url="$1"
  local name="$2"
  if curl -sf --connect-timeout 3 "$url" >/dev/null 2>&1; then
    pass "$name health endpoint responding ($url)"
  else
    warn "$name health endpoint not reachable ($url)"
  fi
}

# ===========================================================================
# Demo health checks
# ===========================================================================

check_demo_a() {
  echo "=== Demo A: Standalone BNG ==="
  check_pods "demo-standalone"
  check_service "demo-standalone" "standalone-bng"
  check_health_endpoint "http://localhost:8080/health" "BNG"
  echo ""
}

check_demo_b() {
  echo "=== Demo B: Single Integration ==="
  check_pods "demo-single"
  check_service "demo-single" "single-bng"
  check_service "demo-single" "single-nexus"
  check_health_endpoint "http://localhost:8081/health" "BNG"
  check_health_endpoint "http://localhost:9001/health" "Nexus"
  echo ""
}

check_demo_c() {
  echo "=== Demo C: P2P Cluster ==="
  check_pods "demo-p2p"
  check_service "demo-p2p" "p2p-nexus"
  check_health_endpoint "http://localhost:9002/health" "Nexus"
  echo ""
}

check_demo_d() {
  echo "=== Demo D: Distributed ==="
  check_pods "demo-distributed"
  check_service "demo-distributed" "distributed-bng"
  check_service "demo-distributed" "distributed-nexus"
  check_health_endpoint "http://localhost:8083/health" "BNG"
  check_health_endpoint "http://localhost:9003/health" "Nexus"
  echo ""
}

check_demo_e() {
  echo "=== Demo E: RADIUS-less ==="
  check_pods "demo-radiusless"
  check_service "demo-radiusless" "radiusless-bng"
  check_service "demo-radiusless" "radiusless-nexus"
  check_health_endpoint "http://localhost:8084/health" "BNG"
  check_health_endpoint "http://localhost:9004/health" "Nexus"
  echo ""
}

check_demo_f() {
  echo "=== Demo F: WiFi + Nexus ==="
  check_pods "demo-wifi"
  check_service "demo-wifi" "wifi-bng"
  check_service "demo-wifi" "wifi-nexus"
  check_health_endpoint "http://localhost:8085/health" "BNG"
  check_health_endpoint "http://localhost:9005/health" "Nexus"
  echo ""
}

check_demo_g() {
  echo "=== Demo G: Pool Shards ==="
  check_pods "demo-pool-shards"
  check_service "demo-pool-shards" "shard-bng"
  check_health_endpoint "http://localhost:8086/health" "BNG"
  echo ""
}

check_demo_h() {
  echo "=== Demo H: HA Pair ==="
  check_pods "demo-ha-pair"
  check_service "demo-ha-pair" "ha-bng-active"
  check_service "demo-ha-pair" "ha-bng-standby"
  check_service "demo-ha-pair" "ha-nexus"
  check_health_endpoint "http://localhost:8087/health" "BNG Active"
  check_health_endpoint "http://localhost:8088/health" "BNG Standby"
  check_health_endpoint "http://localhost:9006/health" "Nexus"
  echo ""
}

check_e2e() {
  echo "=== E2E Integration Test ==="
  check_pods "demo-e2e"
  check_health_endpoint "http://localhost:9010/health" "Nexus"
  echo ""
}

# ===========================================================================
# Main
# ===========================================================================

usage() {
  echo "Usage: $0 [demo-name|all]"
  echo ""
  echo "Available demos:"
  echo "  demo-a    Standalone BNG"
  echo "  demo-b    Single Integration"
  echo "  demo-c    P2P Cluster"
  echo "  demo-d    Distributed"
  echo "  demo-e    RADIUS-less"
  echo "  demo-f    WiFi + Nexus"
  echo "  demo-g    Pool Shards"
  echo "  demo-h    HA Pair"
  echo "  e2e       E2E Integration Test"
  echo "  all       Check all demos"
}

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  usage
  exit 1
fi

echo "============================================"
echo "  BNG Demo Health Check"
echo "============================================"
echo ""

case "$TARGET" in
  demo-a)   check_demo_a ;;
  demo-b)   check_demo_b ;;
  demo-c)   check_demo_c ;;
  demo-d)   check_demo_d ;;
  demo-e)   check_demo_e ;;
  demo-f)   check_demo_f ;;
  demo-g)   check_demo_g ;;
  demo-h)   check_demo_h ;;
  e2e)      check_e2e ;;
  all)
    check_demo_a
    check_demo_b
    check_demo_c
    check_demo_d
    check_demo_e
    check_demo_f
    check_demo_g
    check_demo_h
    check_e2e
    ;;
  *)
    echo "Unknown demo: $TARGET"
    echo ""
    usage
    exit 1
    ;;
esac

echo "============================================"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
