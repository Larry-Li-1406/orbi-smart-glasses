#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Orbi360iOS.xcodeproj"

echo "== System =="
sw_vers
uname -m
echo

echo "== Disk =="
df -h / /Applications /Users 2>/dev/null || df -h /
echo

echo "== Xcode =="
if [ -d /Applications/Xcode.app ]; then
  echo "Xcode.app: installed"
else
  echo "Xcode.app: missing"
fi
xcode-select -p 2>/dev/null || true
xcodebuild -version 2>&1 || true
echo

echo "== Project =="
plutil -lint "$PROJECT/project.pbxproj" "$ROOT/Orbi360iOS/Info.plist"
if command -v swiftc >/dev/null 2>&1; then
  echo "swiftc: $(swiftc -version | head -1)"
fi
echo

echo "== Devices =="
xcrun xctrace list devices 2>/dev/null | sed -n '1,80p' || true
echo

echo "== Next =="
echo "Open project: open \"$PROJECT\""
echo "If Xcode was just installed, run it once, accept the license, and install components."
