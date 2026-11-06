#!/usr/bin/env bash
# Generates the project, builds for the connected iPhone, installs and launches the app.
# Usage: Scripts/run-device.sh [launch arguments…]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${DEVICE:-00008130-000A2068029A001C}"
BUNDLE_ID="com.thibautmottet.RoomScan"
APP="$ROOT/build/dd/Build/Products/Debug-iphoneos/RoomScan.app"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project RoomScan.xcodeproj -scheme RoomScan -configuration Debug \
  -destination "id=$DEVICE" -derivedDataPath "$ROOT/build/dd" \
  -allowProvisioningUpdates -quiet build

xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
  "$BUNDLE_ID" "$@" >/dev/null || echo "Installed; unlock the iPhone to launch it."
