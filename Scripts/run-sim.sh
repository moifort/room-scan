#!/usr/bin/env bash
# Génère le projet, compile pour le simulateur, lance l'app et capture l'écran.
# Usage: Scripts/run-sim.sh [chemin/capture.png]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIM="iPhone 17"
BUNDLE_ID="com.thibautmottet.RoomScan"
SHOT="${1:-$ROOT/.build/screenshot.png}"
APP="$ROOT/.build/dd/Build/Products/Debug-iphonesimulator/RoomScan.app"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project RoomScan.xcodeproj -scheme RoomScan \
  -destination "platform=iOS Simulator,name=$SIM" \
  -derivedDataPath "$ROOT/.build/dd" -quiet build

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$BUNDLE_ID" >/dev/null

mkdir -p "$(dirname "$SHOT")"
# Le tout premier rendu RealityKit compile ses shaders Metal : capturer trop
# tôt donne un écran blanc qui fait croire à un bug de rendu.
sleep 6
xcrun simctl io "$SIM" screenshot --type=png "$SHOT" >/dev/null 2>&1
echo "Capture : $SHOT"
