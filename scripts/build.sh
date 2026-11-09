#!/bin/bash
# Build Quill.app, signed with the Developer ID so macOS keeps the Accessibility and
# Microphone grants across rebuilds, and install it as /Applications/Quill.app (the one copy,
# so the login item can't find a stale one). Usage: scripts/build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

# Eric's Developer ID when this Mac has it (grants survive rebuilds); otherwise ad-hoc signing,
# which runs fine but makes macOS ask for Microphone and Accessibility again after each rebuild.
IDENTITY="${QUILL_SIGN_IDENTITY:-Developer ID Application: Eric Richey (EP5JCD9CKW)}"
if ! security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
  echo "signing identity not found; signing ad-hoc"
  IDENTITY="-"
fi
APP=build/Quill.app

swift build -c release
pkill -x Quill 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Quill "$APP/Contents/MacOS/Quill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/quill-bubble.png Resources/menubar/*.png "$APP/Contents/Resources/"
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Quill.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
INSTALLED=/Applications/Quill.app
rm -rf "$INSTALLED"
mv "$APP" "$INSTALLED"
echo "installed $INSTALLED"

if [[ "${1:-}" == "--run" ]]; then
  open -g "$INSTALLED"
fi
