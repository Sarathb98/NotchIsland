# Validation record

## Camera mirror, tasks and public beta preparation — 18 October 2026

The implementation adds a live AVFoundation camera mirror and a local task list. Startup also removes temporary shelf copies left by an interrupted session when an app-owned session lock proves that the session is no longer running. It preserves pinned files, active sessions and older unmarked directories.

After these changes, `sh Tests/run-all.sh` passed all seven logic/storage suites, including the new shelf recovery check. A fresh universal arm64/x86_64 Release build succeeded, and its local ad-hoc signature passed `codesign --verify --deep --strict`. This is a development build: it has no Developer ID team identity or notarization ticket.

An XCUITest result from earlier on 18 October records six passing tests for the camera/tasks revision. An attempted UI rerun after the shelf recovery change ended with `xcodebuild` exit 133 after test-runner signing output and before tests executed; it reported no test failure. UI tests on the exact current source still need a clean run in an unlocked desktop session.

Hands-on checks for this revision include camera grant, denial, revocation, no-camera and interruption paths; a visibly mirrored preview; camera release after Stop Mirror, collapse, navigation and quit; and task entry, completion, deletion, clear-completed behavior, relaunch persistence and VoiceOver labels. No camera permission or real video capture should be initiated by an automated launch.

## Video reference redesign — 17 October 2026

The existing app was updated to the black dashboard and tray layout described in [UI reference](UIReference.md). A Debug build and a universal arm64/x86_64 Release build succeeded. The Release app passed `codesign --verify --deep --strict` with its local ad-hoc signature.

`sh Tests/run-all.sh` passed all six suites. Geometry checks now cover dashboard/tray/module sizes, the shared visible/clickable outline, display bounds and legacy preference migration. Native XCUITest passed **four tests with zero failures**: dashboard/tray navigation, timer start/pause, module selection with clipboard off, and Escape collapse. The test result is `build/Logs/Test/Test-NotchIsland-2026.10.17_22-14-13-+0530.xcresult`.

I also inspected the expanded dashboard in the native app and the captured UI-test previews. They show the black continuous surface, pill tabs, four live dashboard columns and the dashed empty file tray. Test screenshots are in `build/Reference/UIPreviews/`. These images were captured from an isolated test launch, without selecting media, granting Calendar access or importing files.

The remaining hands-on checks below still apply, especially real file drag/drop, populated tray thumbnails, live media playback, external screens and fullscreen Spaces. Camera Mirror and Tasks were added in the subsequent 18 October revision; the video reference's AirDrop service remains outside scope.

Verified on 2 October 2026 with Xcode 26.6 (17F113), macOS 26.5.1 (25F80), on Apple silicon. The deployment target remains macOS 14. The older-system material fallback and Intel runtime behavior still require testing on those systems.

## Automated results

| Check | Result |
| --- | --- |
| Debug application build | Passed. |
| Release application build | Passed, universal arm64 and x86_64 executable. |
| Six logic/storage suites | All passed using `sh Tests/run-all.sh`. |
| Native XCUITest suite | Three tests passed, zero failures. |
| Release ad-hoc signature | `codesign --verify --deep --strict` passed. |
| Distribution scripts and metadata | Shell syntax checks and Info.plist, entitlements and privacy-manifest validation passed. |

No Swift compiler errors or warnings remained. Xcode logged nonblocking Simulator-service messages in the restricted build environment and an App Intents metadata-extraction notice because the app does not use App Intents. The macOS build and test commands completed successfully.

### Logic and storage coverage

- Notch geometry, malformed screen data, point/Retina handling and screens without a notch.
- Six presentation states, multiple display pointers, hover timing, editing holds, native-menu activity replay and preference persistence.
- Activity priorities, coalescing and expiry; app-owned recording session identity.
- Timer, stopwatch, Pomodoro, pause/repeat and sleep recovery; calendar meeting-link policy.
- Notes persistence and limits; shelf storage ownership, pins and cleanup; clipboard exclusions and limits.
- Quick-action persistence/order, download URL policy, launcher empty-state navigation, media adapter controls and settings migration/validation.

### UI coverage

- Expand the island, start a timer, then pause it.
- Select Notes and Clipboard from the native module menu; verify clipboard history remains off.
- Focus the panel and press Escape; verify expanded controls disappear, the visible surface shrinks and its top edge stays anchored.

The tests use a separate preferences suite, temporary notes/shelf storage, one display, no calendar monitoring and disabled clipboard collection. Timer clicks target verified visible control centers because XCUITest's automatic scrolling can fail on this SwiftUI panel. Collapse and clipboard checks assert observable geometry and text because XCUITest omits some SwiftUI accessibility values on this macOS version.

Local evidence is in `build/Validation/`: `debug-build.log`, `release-build.log`, `logic-checks.log` and `ui-tests.log`. The passing native test result is `build/Logs/Test/Test-NotchIsland-2026.10.02_17-34-22-+0530.xcresult`. Build output is ignored by Git.

## Reproduce

```sh
sh Tests/run-all.sh
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' test
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
  -configuration Release -derivedDataPath build \
  -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
codesign --verify --deep --strict 'build/Build/Products/Release/Notch Island.app'
```

UI tests need an unlocked desktop session and permission for Xcode's testing services.

## Hands-on release checklist

These checks remain open; build/test success does not establish hardware or permission behavior.

- [ ] Notched and unnotched Macs; external-monitor attach/detach, scaling, display rearrangement, clamshell and wake.
- [ ] Desktop/fullscreen Spaces, Stage Manager, menu-bar auto-hide and pointer pass-through around rounded edges.
- [ ] VoiceOver, complete keyboard navigation, Reduce Motion, Increase Contrast, Reduce Transparency and macOS 14 appearance.
- [ ] Calendar permission grant, denial and revocation; meeting updates from a real calendar.
- [ ] Bluetooth/camera-status opt-in, device reconnects, volume-driver support and microphone driver activity changes.
- [ ] Camera Mirror permission grant, denial and revocation; default and external cameras; interruption and recovery; visible horizontal mirroring; release after Stop Mirror, collapse, navigation and quit.
- [ ] Task add, complete, reopen, delete and clear-completed actions; persistence after relaunch, limits, error display and VoiceOver labels.
- [ ] Start/stop/save a real screen recording on macOS 15+; test cancellation, permission denial and quit while saving.
- [ ] Real local-media playback and metadata, user-managed HTTPS download/cancellation, file drag-out and Quick Look.
- [ ] Measure idle CPU/memory and prolonged use with Instruments. Resource sampling is limited to the visible System pane; this is an implementation choice, not a measured performance guarantee.
- [ ] Developer ID signing, notarization, Gatekeeper verification, stable installation and launch at login on a separate account/Mac.

No camera, Bluetooth, calendar or screen-capture permission was granted during automated validation. Tests perform no real playback or remote transfers. Developer ID signing and notarization require credentials and have not been executed; see [Distribution](Distribution.md).

## Supported scope

Media playback currently uses explicitly selected local files. Global other-app Now Playing, universal brightness observation and device battery telemetry have documented capability fallbacks. The English string catalog is ready for translation; additional languages are not included. See [Capabilities](Capabilities.md) for public API boundaries.
