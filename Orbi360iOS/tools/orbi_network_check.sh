#!/usr/bin/env bash
set -u

TARGET="${1:-192.168.2.1}"

echo "== Network =="
networksetup -getairportnetwork en0 2>/dev/null || true
route -n get "$TARGET" 2>/dev/null | sed -n '1,20p' || true
echo

echo "== Ping =="
ping -c 2 -W 1000 "$TARGET" || true
echo

echo "== TCP 8080 =="
if nc -vz -G 5 "$TARGET" 8080; then
  echo "Control port is reachable."
else
  echo "Control port is not reachable."
  echo "If Wi-Fi is connected, the glasses control service is probably not started yet."
fi
echo

echo "== ORBI protocol =="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if "$SCRIPT_DIR/orbi_probe.swift"; then
  echo "ORBI protocol is responding."
else
  echo "ORBI protocol did not respond."
fi
