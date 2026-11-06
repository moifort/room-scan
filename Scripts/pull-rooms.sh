#!/usr/bin/env bash
# Copies the saved rooms (scan, realistic mesh, photos) off the connected iPhone.
# Usage: Scripts/pull-rooms.sh <destination folder>
set -euo pipefail

DEVICE="${DEVICE:-00008130-000A2068029A001C}"
DEST="${1:?destination folder}"
mkdir -p "$DEST"
xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier com.thibautmottet.RoomScan \
  --source Documents/Rooms --destination "$DEST"
