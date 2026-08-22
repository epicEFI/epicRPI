#!/bin/bash
# Bring up SocketCAN can0 for EpicEFI / RealDash (listen-only)
set -euo pipefail

IFACE=can0
BITRATE=500000

# Wait for MCP2515 device node (overlay may appear slightly after boot)
for i in $(seq 1 50); do
  if ip link show "$IFACE" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "can0-up: $IFACE not present (no MCP2515?) — skipping"
  exit 0
fi

ip link set "$IFACE" down 2>/dev/null || true
ip link set "$IFACE" type can bitrate "$BITRATE" restart-ms 100
ip link set "$IFACE" up
ip link set "$IFACE" txqueuelen 1000
echo "can0-up: $IFACE up @ ${BITRATE}"
