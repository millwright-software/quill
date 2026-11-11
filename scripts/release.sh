#!/bin/bash
# Publish Quill as a GitHub release a Mac without Xcode can install: build, sign with the
# Developer ID, notarize with Apple, staple, zip, upload. Usage: scripts/release.sh 0.3.1 [--dry-run]
#
# One-time setup on the Mac that releases (Eric's): the repo on GitHub, and a notary login in the
# keychain, made with an app-specific password from appleid.apple.com:
#   xcrun notarytool store-credentials notary --apple-id <Apple ID> --team-id EP5JCD9CKW
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--dry-run]}"
DRY="${2:-}"
IDENTITY="Developer ID Application: Eric Richey (EP5JCD9CKW)"
PROFILE=notary
DIST=dist
ZIP="$DIST/Quill.zip"

security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || { echo "release needs the Developer ID on this Mac: $IDENTITY" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "commit first: the release is built from a clean tree" >&2; exit 1; }
if [[ -z "$DRY" ]]; then
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || { echo "no notary login in the keychain; see the setup line at the top of this script" >&2; exit 1; }
  gh repo view >/dev/null 2>&1 || { echo "no GitHub repo for this folder yet" >&2; exit 1; }
fi

# The version goes into the app's Info.plist for this build only.
PLIST=Resources/Info.plist
cp "$PLIST" "$PLIST.orig"
trap 'mv "$PLIST.orig" "$PLIST"' EXIT
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" "$PLIST"

QUILL_BUILD_ONLY=1 scripts/build.sh
rm -rf "$DIST"; mkdir -p "$DIST"
ditto -c -k --keepParent build/Quill.app "$ZIP"

if [[ -n "$DRY" ]]; then
  echo "dry run: $ZIP built and signed, not notarized or published"
  exit 0
fi

xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/Quill.app
rm "$ZIP"; ditto -c -k --keepParent build/Quill.app "$ZIP"   # re-zip with the ticket stapled in
spctl -a -vv build/Quill.app

git tag "v$VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Quill $VERSION" --generate-notes
echo "released v$VERSION"
