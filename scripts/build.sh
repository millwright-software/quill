#!/bin/bash
# Build Quill.app, signed with the Developer ID so macOS keeps the Accessibility and
# Microphone grants across rebuilds, and install it as /Applications/Quill.app (the one copy,
# so the login item can't find a stale one). Usage: scripts/build.sh [--run]
# QUILL_BUILD_ONLY=1 leaves the signed app in build/ for scripts/release.sh instead.
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

# A release needs Apple's secure timestamp for notarization; local builds skip the round trip.
TIMESTAMP="--timestamp=none"
[[ -n "${QUILL_BUILD_ONLY:-}" && "$IDENTITY" != "-" ]] && TIMESTAMP="--timestamp"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Quill "$APP/Contents/MacOS/Quill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/quill-bubble.png Resources/menubar/*.png "$APP/Contents/Resources/"
codesign --force --options runtime $TIMESTAMP \
  --entitlements Resources/Quill.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
if [[ -n "${QUILL_BUILD_ONLY:-}" ]]; then echo "built $APP"; exit 0; fi
pkill -x Quill 2>/dev/null || true
INSTALLED=/Applications/Quill.app
rm -rf "$INSTALLED"
mv "$APP" "$INSTALLED"
echo "installed $INSTALLED"

if [[ "${1:-}" == "--run" ]]; then
  open -g "$INSTALLED"
fi
