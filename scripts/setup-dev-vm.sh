#!/usr/bin/env bash
# setup-dev-vm.sh — Provision an Ubuntu 24.04 (arm64 or amd64) VM for BNG
# containerlab development and testing.
#
# Usage:
#   curl -sL <raw-url>/scripts/setup-dev-vm.sh | bash
#   ./scripts/setup-dev-vm.sh
#   ./scripts/setup-dev-vm.sh --github-runner
#
# What it does:
#   1. Install Docker (official apt repo)
#   2. Install containerlab
#   3. Pull test images (BNG Blaster, FRR)
#   4. Clone bng-edge-infra (with submodules)
#   5. Build BNG Docker image
#   6. Deploy bng01 lab and run smoke test
#   7. (Optional) Register as self-hosted GitHub Actions runner
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
CLAB_VERSION="0.69.3"
BNG_IMAGE="ghcr.io/codelaboratoryltd/bng:ci"
REPO_URL="https://github.com/codelaboratoryltd/bng-edge-infra.git"
REPO_DIR="$HOME/bng-edge-infra"
LAB_DIR="tests/containerlab-bng01"
GH_RUNNER=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --github-runner) GH_RUNNER=true ;;
    -h|--help)
      echo "Usage: $0 [--github-runner]"
      echo ""
      echo "Options:"
      echo "  --github-runner  Register as a self-hosted GitHub Actions runner"
      exit 0
      ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[1;34m==>\033[0m $*"; }
ok()    { echo -e "\033[1;32m==>\033[0m $*"; }
fail()  { echo -e "\033[1;31m==>\033[0m $*" >&2; exit 1; }

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this script as root — it uses sudo where needed."
  fi
}

# ---------------------------------------------------------------------------
# 1. Docker
# ---------------------------------------------------------------------------
install_docker() {
  if command -v docker &>/dev/null; then
    info "Docker already installed: $(docker --version)"
    return
  fi

  info "Installing Docker..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg

  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  ARCH=$(dpkg --print-architecture)
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin

  sudo usermod -aG docker "$USER"
  ok "Docker installed. You may need to log out/in for group membership."
}

# ---------------------------------------------------------------------------
# 2. Containerlab
# ---------------------------------------------------------------------------
install_containerlab() {
  if command -v clab &>/dev/null; then
    info "Containerlab already installed: $(clab version 2>&1 | head -1)"
    return
  fi

  info "Installing containerlab v${CLAB_VERSION}..."
  bash -c "$(curl -sL https://get.containerlab.dev)" -- -v "$CLAB_VERSION"
  ok "Containerlab installed: $(clab version 2>&1 | head -1)"
}

# ---------------------------------------------------------------------------
# 3. Pull images
# ---------------------------------------------------------------------------
pull_images() {
  info "Pulling test images..."
  docker pull rtbrick/bngblaster:latest
  docker pull frrouting/frr:v8.4.1
  ok "Images pulled."
}

# ---------------------------------------------------------------------------
# 4. Clone repo
# ---------------------------------------------------------------------------
clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    info "Repository exists at $REPO_DIR — pulling latest..."
    git -C "$REPO_DIR" pull --ff-only
    git -C "$REPO_DIR" submodule update --init --recursive
  else
    info "Cloning $REPO_URL..."
    git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
  fi
  ok "Repository ready at $REPO_DIR"
}

# ---------------------------------------------------------------------------
# 5. Build BNG image
# ---------------------------------------------------------------------------
build_bng() {
  info "Building BNG Docker image ($BNG_IMAGE)..."
  docker build -t "$BNG_IMAGE" "$REPO_DIR/src/bng"
  ok "BNG image built: $BNG_IMAGE"
}

# ---------------------------------------------------------------------------
# 6. Smoke test
# ---------------------------------------------------------------------------
smoke_test() {
  info "Running smoke test (deploy bng01 lab)..."
  cd "$REPO_DIR/$LAB_DIR"

  sudo clab deploy -t bng01.clab.yml --reconfigure

  # Wait for BNG health
  info "Waiting for BNG health check..."
  BNG_CONTAINER="clab-bng01-bng1"
  for i in $(seq 1 30); do
    if docker exec "$BNG_CONTAINER" wget -q -O- http://127.0.0.1:9090/health 2>/dev/null | grep -q "ok"; then
      ok "BNG is healthy (attempt $i)"
      break
    fi
    if [ "$i" -eq 30 ]; then
      fail "BNG did not become healthy in 60s"
    fi
    sleep 2
  done

  # Run BNG Blaster
  info "Running BNG Blaster (10 subscribers)..."
  SUBSCRIBER_CONTAINER="clab-bng01-subscribers"
  docker exec "$SUBSCRIBER_CONTAINER" \
    bngblaster -C /config/config.json -l info -T 60 2>&1 | tee /tmp/blaster-smoke.txt || true

  # Check results
  ESTABLISHED=$(grep -oP 'Sessions established:\s*\K\d+' /tmp/blaster-smoke.txt 2>/dev/null || echo "0")
  if [ "$ESTABLISHED" -ge 10 ]; then
    ok "Smoke test passed: $ESTABLISHED/10 sessions established"
  else
    info "Smoke test: $ESTABLISHED/10 sessions (check BNG logs for details)"
    docker logs "$BNG_CONTAINER" --tail=20
  fi

  # Cleanup
  info "Cleaning up lab..."
  sudo clab destroy -t bng01.clab.yml --cleanup || true
  ok "Smoke test complete."
}

# ---------------------------------------------------------------------------
# 7. GitHub Actions runner (optional)
# ---------------------------------------------------------------------------
setup_github_runner() {
  if [ "$GH_RUNNER" != "true" ]; then
    return
  fi

  info "Setting up GitHub Actions self-hosted runner..."
  echo ""
  echo "  You will need:"
  echo "    1. A GitHub personal access token (repo scope)"
  echo "    2. The repository owner/name (e.g. codelaboratoryltd/bng-edge-infra)"
  echo ""

  read -rp "GitHub repository (owner/repo): " GH_REPO
  read -rp "GitHub token: " GH_TOKEN

  RUNNER_DIR="$HOME/actions-runner"
  mkdir -p "$RUNNER_DIR"
  cd "$RUNNER_DIR"

  ARCH=$(dpkg --print-architecture)
  case "$ARCH" in
    amd64) RUNNER_ARCH="x64" ;;
    arm64) RUNNER_ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  # Get latest runner version
  RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | \
    grep -oP '"tag_name":\s*"v\K[^"]+')
  RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

  info "Downloading runner v${RUNNER_VERSION} (${RUNNER_ARCH})..."
  curl -sL "$RUNNER_URL" | tar xz

  # Get registration token
  REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: token $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$GH_REPO/actions/runners/registration-token" | \
    grep -oP '"token":\s*"\K[^"]+')

  if [ -z "$REG_TOKEN" ]; then
    fail "Failed to get registration token. Check your GitHub token and repo."
  fi

  info "Configuring runner..."
  ./config.sh --url "https://github.com/$GH_REPO" \
    --token "$REG_TOKEN" \
    --name "$(hostname)" \
    --labels "self-hosted,linux,$ARCH,containerlab" \
    --unattended

  info "Installing runner as service..."
  sudo ./svc.sh install
  sudo ./svc.sh start

  ok "GitHub Actions runner registered and started."
  echo "  Labels: self-hosted, linux, $ARCH, containerlab"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  require_root
  info "BNG dev VM setup starting..."
  echo ""

  install_docker
  install_containerlab
  pull_images
  clone_repo
  build_bng
  smoke_test
  setup_github_runner

  echo ""
  ok "Setup complete!"
  echo ""
  echo "  Next steps:"
  echo "    cd $REPO_DIR/$LAB_DIR"
  echo "    sudo clab deploy -t bng01.clab.yml"
  echo ""
}

main "$@"
