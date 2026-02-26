#!/bin/sh
# Wait for containerlab to create the veth interfaces before starting BNG.
# Containerlab creates containers first, then wires links — so the BNG
# entrypoint must wait for eth1 (subscriber-facing) to appear.
set -e

echo "Waiting for eth1 interface..."
for i in $(seq 1 30); do
  if ip link show eth1 >/dev/null 2>&1; then
    echo "eth1 is up (attempt $i)"
    # Add the pool gateway IP so the BNG responds to subscriber ARP requests
    ip addr add 10.0.1.1/24 dev eth1 2>/dev/null || true
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: eth1 did not appear after 30s"
    exit 1
  fi
  sleep 1
done

# Configure upstream interface (eth2 → core router)
echo "Waiting for eth2 interface..."
for i in $(seq 1 30); do
  if ip link show eth2 >/dev/null 2>&1; then
    echo "eth2 is up (attempt $i)"
    ip addr add 10.0.0.1/24 dev eth2 2>/dev/null || true
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "WARN: eth2 did not appear, starting without upstream"
    break
  fi
  sleep 1
done

echo "Starting BNG..."
exec /app/bng run --config /etc/bng/config.yaml
