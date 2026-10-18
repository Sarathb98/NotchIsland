# Signing and distribution

Local Debug and Release builds use ad-hoc signing. They are suitable for development on this Mac; they are not a notarized release.

## Prepare a Developer ID release

1. Install a **Developer ID Application** certificate in your keychain and choose your Apple Developer team.
2. Set `NOTCH_TEAM_ID` and `NOTCH_SIGN_IDENTITY` in your shell. The identity is the certificate's full display name.
3. Run `sh Scripts/package-release.sh`. It archives a universal arm64/x86_64 app with the existing hardened runtime setting and entitlements, verifies the signature, confirms the requested Developer ID team and certificate, rejects a debugging entitlement, and produces `build/Release/NotchIsland.zip`.
4. Create a notarytool keychain profile using Apple's `xcrun notarytool store-credentials` flow. Keep credentials in Keychain, never in the repository.
5. Set `NOTCH_NOTARY_PROFILE` to that profile's name and run `sh Scripts/notarize-release.sh`. The script submits the ZIP, requires an Accepted result, staples the app, validates the ticket, and rebuilds the ZIP.
6. Test the resulting app from `/Applications` on a separate account or Mac. Launch at login and privacy permissions depend on stable installation and signing identity.

The project contains camera and calendar entitlements, purpose strings, and a privacy manifest. The manifest declares app-local preferences and on-device disk-space display; review it whenever APIs change. The current app targets direct Developer ID distribution and does not claim App Store sandbox compatibility.

Signing and notarization have **not** been executed: they require your Developer ID identity and notarytool credentials. These scripts are preparation, not proof of acceptance.

## Publish the source and download

The app does not need a hosting server. The MIT-licensed source is public at [Sarathb98/NotchIsland](https://github.com/Sarathb98/NotchIsland). GitHub can host the future downloadable ZIP on its Releases page. Keep `build/`, signing keys and notary credentials out of the repository; the ZIP belongs on a Release, not in source control.

1. After the signed ZIP passes a fresh-install check, create a version tag that matches the app version in `NotchIsland/App/Info.plist`.
2. Create a GitHub Release from that tag, attach `build/Release/NotchIsland.zip`, and include the macOS requirement, install steps and release notes.

There is no automatic updater in this app; users will download a new Release when you publish an update. The source is available now; the app download still requires Developer ID signing, notarization and installation testing.

References: [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [required-reason API declarations](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).
