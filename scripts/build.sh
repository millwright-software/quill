#!/bin/bash
# Build Quill.app into build/, signed with the Developer ID so macOS keeps the
# Accessibility and Microphone grants across rebuilds. Usage: scripts/build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: Eric Richey (EP5JCD9CKW)"
APP=build/Quill.app

swift build -c release
pkill -x Quill 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Quill "$APP/Contents/MacOS/Quill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Quill.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "built $APP"

if [[ "${1:-}" == "--run" ]]; then
  open -g "$APP"
fi
