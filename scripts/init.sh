#!/bin/sh
set -e # exit on error
set -u # treat usage of unset variables as an error and exit

# BNG Edge Infrastructure - Local Cluster Setup
# Creates k3d cluster, then use 'tilt up' for the rest.

CLUSTER_NAME="bng-edge"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../clusters/local-dev/k3d-config.yaml"

# Check if cluster already exists
if k3d cluster list 2>/dev/null | grep -q "^$CLUSTER_NAME"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    echo ""
    echo "Options:"
    echo "  Start it:  k3d cluster start $CLUSTER_NAME"
    echo "  Delete it: k3d cluster delete $CLUSTER_NAME"
    echo "  Then run:  tilt up"
    exit 1
fi

# Create the cluster
echo "Creating k3d cluster '$CLUSTER_NAME'..."
k3d cluster create --config "$CONFIG_FILE"

# Write kubeconfig
k3d kubeconfig write "$CLUSTER_NAME" --output "$HOME/.config/k3d/kubeconfig-$CLUSTER_NAME.yaml"

echo ""
echo "✅ K3d cluster '$CLUSTER_NAME' created successfully!"
echo "   Context: k3d-$CLUSTER_NAME"
echo "   Registry: localhost:5555"
echo ""
echo "Next: tilt up"
