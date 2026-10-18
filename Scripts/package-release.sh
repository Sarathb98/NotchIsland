#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${NOTCH_TEAM_ID:?Set NOTCH_TEAM_ID to your Apple Developer team ID}"
: "${NOTCH_SIGN_IDENTITY:?Set NOTCH_SIGN_IDENTITY to your Developer ID Application identity}"
notch_app='build/Release/NotchIsland.xcarchive/Products/Applications/Notch Island.app'
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -configuration Release \
 -destination 'generic/platform=macOS' -archivePath build/Release/NotchIsland.xcarchive \
 DEVELOPMENT_TEAM="$NOTCH_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$NOTCH_SIGN_IDENTITY" \
 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
codesign --verify --deep --strict --verbose=2 "$notch_app"
notch_signed_team=$(codesign -dv --verbose=4 "$notch_app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
if [ "$notch_signed_team" != "$NOTCH_TEAM_ID" ]; then
  echo 'Archive is not signed by the requested Developer ID team.' >&2
  exit 1
fi
if ! codesign -dv --verbose=4 "$notch_app" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
  echo 'Archive does not have a Developer ID Application certificate.' >&2
  exit 1
fi
notch_entitlements=$(mktemp)
trap 'rm -f "$notch_entitlements"' 0
codesign -d --entitlements :- "$notch_app" > "$notch_entitlements" 2>/dev/null
if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$notch_entitlements" 2>/dev/null || true)" = true ]; then
  echo 'Archive allows debugging (get-task-allow); refusing to package it.' >&2
  exit 1
fi
ditto -c -k --keepParent "$notch_app" build/Release/NotchIsland.zip
