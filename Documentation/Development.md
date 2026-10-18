# Development record

The original Xcode project, bundle identifier, app lifecycle and feature folders are retained. Changes are applied in sequence, with a build and checks at each phase boundary.

## Phase 1 — Core and native UI

- Central `IslandCoordinator` owns the six presentation states and delayed hover/collapse transitions.
- Screen-derived geometry is validated and kept in points; each eligible screen gets an AppKit panel with Spaces/fullscreen auxiliary behavior.
- Pointer, drag, click-outside, Escape, context menu and accessibility actions route through the coordinator.
- Native material/glass surfaces, system type, semantic colors and accessibility contrast/motion preferences support the notch's black physical cap.
- Persistent appearance/display/interaction settings and opt-in ServiceManagement launch at login.

Build/check results are appended when each phase gate completes. Hardware-sensitive behaviors remain separately listed in the manual validation checklist.

Phase 1 gate: Debug build succeeded; geometry/state/settings/pointer/timer checks passed. Runtime checks found and fixed recursion in validated `@Published` settings setters. Native menu tracking suspends dismissal; collapse releases panel keyboard focus; rounded corners pass pointer events through.

## Phase 2 — System island

- `LiveActivityManager` keeps one primary activity and expires queued entries using a cancellable task. Battery, power-source, network, volume and timer completion publish activities.
- CPU and memory use Mach host statistics; disk uses Foundation volume capacity. Sampling starts only while the System pane is visible. Network uses `NWPathMonitor`; audio uses public Core Audio properties/listeners.
- Unsupported brightness observation is represented by `BrightnessProviding` with an explicit unavailable capability, rather than a private framework.
- App recording state accepts only the current owned session ID. It does not claim knowledge of other apps' recordings.

Phase 2 gate: Debug build succeeded; all earlier checks plus priority, expiry, queue replacement, activity presentation and recording ownership checks passed. Public IOBluetooth and AVFoundation device status are opt-in. ScreenCaptureKit recording requires an explicit save/start action; no capture was initiated during verification.

## Phase 3 — Productivity

Local models and native views extend the original Timer, Calendar and DropZone feature folders. Notes use atomic local JSON storage and debounced writes. New productivity features are integrated into the existing island and shared store rather than separate app replacements.

Phase 3 gate: Debug build succeeded and all four core/notes/shelf-clipboard/action-download test suites passed. Live UI checks verified native module selection, the timer layout and clipboard's default-off state. Tests used isolated storage and did not enable personal-data permissions or download remote files.

## Phase 4 — Media, customization and production preparation

- `NowPlayingAdapter` isolates supported integrations. `LocalAVPlayerAdapter` implements user-selected local audio/video playback, metadata/artwork, seeking and transport controls; no private MediaRemote APIs.
- All eleven settings sections, module visibility/order, configurable registered hot key, appearance and animation controls.
- Onboarding and explicit permission controls; launch at login remains opt-in.
- Isolated UI-test launch mode, a native XCUITest target, additional settings/media checks, clean media/recording shutdown, OSLog lifecycle messages and localization extraction.
- Developer ID archive/notarization scripts, entitlements and privacy manifest. No credentials or telemetry are included.

Phase 4 gate (2 October 2026): Debug and universal arm64/x86_64 Release builds succeeded. All six logic/storage suites and all three native UI tests passed. The Release ad-hoc signature and distribution metadata validated. Final review fixed stale microphone-driver state with public CoreAudio listeners and removed battery behavior's dependency on English labels. An English string catalog now includes extractable UI, model and native-dialog text.

The final interaction checks cover timer start/pause, module navigation, clipboard's default-off state and Escape collapse. Editing holds and native-menu activity replay have regression checks. Hardware, permission, performance and signed-distribution validation remain explicitly listed in [Validation](Validation.md).

## Video reference UI revision — 17 October 2026

The existing panel now presents a wide black dashboard with pill Island/Tray navigation, four live columns and a dashed horizontal file tray. A shared `IslandSilhouette` path drives both SwiftUI clipping and AppKit hit testing. The physical notch geometry remains screen-derived. Untouched compact-width and default module-order preferences migrate once; custom module order stays intact. The native module menu retains all ten modules, with a focused view for each.

Gate: Debug and universal Release builds succeeded. All six logic/storage suites and all four native UI tests passed. The Release ad-hoc signature verified. See [UI reference](UIReference.md) and the latest [Validation](Validation.md) entry for previews and remaining hands-on checks.

## Camera mirror and tasks — 18 October 2026

The redesigned island adds an on-demand AVFoundation camera preview and a local task list. The camera view shows a circular, horizontally mirrored live image; Start Mirror is the only action that asks macOS for camera access. The preview does not record or save frames. Tasks support add, complete, reopen, delete and clear-completed actions. Their bounded JSON store is written atomically under Application Support; unreadable or invalid stored data is left intact and reported to the user. Both features use the existing dashboard and focused-module surfaces.

Build, automated test and hardware-check results for this revision belong in [Validation](Validation.md) after they are run.
