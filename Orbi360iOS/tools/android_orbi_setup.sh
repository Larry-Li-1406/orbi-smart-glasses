#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APK="$ROOT_DIR/Orbi 360_1.5.1_APKPure.apk"

echo "== ADB =="
adb version
echo

echo "== Devices =="
adb devices -l
echo

if ! adb get-state >/dev/null 2>&1; then
  echo "No Android device is authorized yet."
  echo "Enable USB debugging, plug the phone in, and accept the RSA trust prompt."
  exit 1
fi

echo "== Install ORBI 360 APK =="
adb install -r "$APK"
echo

echo "Installed. On the Android phone:"
echo "1. Open ORBI 360."
echo "2. Connect the phone to the glasses Wi-Fi."
echo "3. Leave the app on the connection screen, then run:"
echo "   adb logcat | grep -iE 'orbi|192.168.2.1|8080|get_info|get-status'"
