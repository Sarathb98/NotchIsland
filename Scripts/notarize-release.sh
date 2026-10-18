#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
: "${NOTCH_NOTARY_PROFILE:?Set NOTCH_NOTARY_PROFILE to an existing notarytool keychain profile}"
xcrun notarytool submit build/Release/NotchIsland.zip --keychain-profile "$NOTCH_NOTARY_PROFILE" --wait --output-format json > build/Release/notarization.json
notch_status=$(/usr/bin/plutil -extract status raw -o - build/Release/notarization.json)
if [ "$notch_status" != Accepted ]; then
  echo 'Notarization did not succeed. Inspect build/Release/notarization.json and the notarytool log.' >&2
  exit 1
fi
xcrun stapler staple 'build/Release/NotchIsland.xcarchive/Products/Applications/Notch Island.app'
xcrun stapler validate 'build/Release/NotchIsland.xcarchive/Products/Applications/Notch Island.app'
ditto -c -k --keepParent 'build/Release/NotchIsland.xcarchive/Products/Applications/Notch Island.app' build/Release/NotchIsland.zip
