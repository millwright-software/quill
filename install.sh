#!/bin/bash
# Installs the latest Quill release into /Applications and opens it. Needs no Xcode.
#   Private repo (needs the GitHub CLI, logged in):
#     gh api repos/millwright-software/quill/contents/install.sh --jq .content | base64 -d | bash
#   Public repo:
#     curl -fsSL https://raw.githubusercontent.com/millwright-software/quill/master/install.sh | bash
set -euo pipefail
REPO=millwright-software/quill
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh release download --repo "$REPO" --pattern Quill.zip --dir "$TMP"
else
  curl -fsSL -o "$TMP/Quill.zip" "https://github.com/$REPO/releases/latest/download/Quill.zip" \
    || { echo "download failed: a private repo needs the GitHub CLI (brew install gh; gh auth login)" >&2; exit 1; }
fi

ditto -x -k "$TMP/Quill.zip" "$TMP"
pkill -x Quill 2>/dev/null || true
rm -rf /Applications/Quill.app
mv "$TMP/Quill.app" /Applications/Quill.app
open -g /Applications/Quill.app
echo "Quill installed. Allow Microphone and Accessibility when macOS asks; the speech model downloads on first launch (~0.5 GB)."
