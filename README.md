# Notch Island

A macOS menu bar app that puts a small dashboard below the notch or at the top of a screen without one. It brings together a timer, tasks, quick notes, a file shelf, calendar preview, system status, media controls and an optional live camera mirror. It runs on macOS 14 or later; screen recording requires macOS 15 or later.

## Install the app

When a signed and notarized beta is published:

1. Download `NotchIsland.zip` from this project's **GitHub Releases** page.
2. Open the ZIP and move **Notch Island.app** to your **Applications** folder.
3. Open the app from Applications. Look for its icon in the menu bar; the app has no Dock icon. Follow the welcome guide to choose any optional permissions.

There is no public, notarized download yet. The current Release build is signed only for local development, so it should not be distributed as an installer. The source and a future release ZIP can both live on GitHub; running this app does not require a separate hosting server.

## Build from source

Install Xcode 26 or later, open `NotchIsland.xcodeproj`, select the **NotchIsland** scheme, and click **Run**. You can also build from Terminal:

```sh
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
  -configuration Debug -derivedDataPath build build
```

The local app is at `build/Build/Products/Debug/Notch Island.app`. Use `-configuration Release` for an optimized build. Local builds use ad-hoc signing and are for development on your own Mac.

The source code is available under the [MIT License](LICENSE).

On first launch, the welcome guide explains interaction and optional permissions. No clipboard, Bluetooth, camera or recording access is enabled automatically. Launch at login is opt-in.

## Interaction

- Hover to preview; click to expand; Escape or click outside to collapse.
- Open from the menu bar or **Control–Option–Space**. Change or disable the shortcut in Settings.
- **Island** opens a horizontal dashboard with Media, Calendar, Notes, Timer, Tasks and Camera Mirror. **Tray** opens the file shelf. The grid menu opens every enabled module in a focused view. Dashboard columns scroll when they do not fit the screen.
- Tab, Shift-Tab, native controls and accessibility actions support keyboard and VoiceOver use.
- Right-click for the island context menu. Optional scroll gestures expand/collapse.
- Drag files onto the island to open its file shelf.
- The island has a black surface, curved shoulders, rounded bottom corners and blue accents. Settings retain their native appearance; island animations respect Reduce Motion, and its outline responds to Increase Contrast.

## Modules

| Module | Included behavior |
| --- | --- |
| Clock and battery | Current time, internal battery percentage and power status. |
| System | Network, CPU, memory and disk; public Core Audio volume control; opt-in Bluetooth/camera status; input-driver activity; app-owned screen recording on macOS 15+. |
| Timer | Presets, pause/reset, repeat, stopwatch and Pomodoro with sleep recovery. |
| Calendar | Permission flow, next 24 hours of events, countdowns, details and safe meeting links. |
| Files | Temporary copies, persistent pins, drag out, Quick Look, copy, reveal, remove and clear. Up to 50 regular files, 200 MB each. |
| Clipboard | Opt-in memory-only text/URL/image/file history, search, favorites, exclusions and clear. Starts paused on every launch. |
| Notes | Local quick notes with editing, copy, removal and debounced persistence. |
| Tasks | Add, complete, reopen and delete local tasks; clear completed tasks. Up to 100 tasks with 120-character titles, saved atomically under Application Support. |
| Camera Mirror | Start a live, horizontally mirrored circular camera preview on demand. Stop it from the same control; no frames are recorded or saved. Camera access follows macOS permission controls. |
| Actions | Configurable applications/folders/timers, focus timer, Screenshot, Downloads and lock-screen shortcut guidance. |
| Apps | Local application search, arrow-key selection and Return to launch. |
| Downloads | User-initiated HTTPS transfers, native save location, progress, cancel and Finder reveal. |
| Media | User-selected local audio/video playlist using AVPlayer, metadata/artwork, progress/seek and transport controls behind a public adapter protocol. |

Live activities use one primary slot, in this order: critical alert, meeting, user action, timer, file transfer, download, media, default. Temporary activities expire; interactions retain access to expanded controls.

Settings includes General, Appearance, Island, Modules, Shortcuts, Calendar, Files, Clipboard, Media, Advanced and About. Width, hover/collapse timing, animations, display behavior, module order/visibility and keyboard shortcuts persist locally.

The dashboard defaults to 1440 points wide and can be adjusted from 680 to 1440 points, bounded by the current screen. Its columns scroll horizontally on smaller displays. Existing compact-width preferences migrate once; custom module arrangements remain intact. See [UI reference](Documentation/UIReference.md).

An English string catalog under `NotchIsland/Resources` supports future translations. User-facing model text and native dialogs use localization APIs; stored identifiers stay stable across languages.

## Public API boundaries

Global other-app Now Playing and universal brightness observation are not claimed. Brightness has a capability fallback; media has a replaceable adapter. Bluetooth telemetry, input/camera activity and volume controls depend on what public APIs and drivers expose. Camera Mirror opens a separate AVFoundation preview only after you press Start Mirror. Lock screen provides the macOS shortcut instead of private system calls. Downloads and recordings show only operations started by this app.

See [Capabilities](Documentation/Capabilities.md) for integration and storage details. No third-party runtime dependency, private framework, analytics or telemetry service is included.

## Privacy and support

Notes, tasks, settings and pinned shelf files are stored on this Mac. Clipboard history starts off on every launch and stays in memory when enabled. Calendar, camera, Bluetooth status and screen recording require an explicit feature action or permission. The app has no account or analytics service. See [Privacy](PRIVACY.md) for what each feature reads or stores.

After the repository is public, use its GitHub Issues page to report bugs or suggest improvements. The [validation checklist](Documentation/Validation.md) records the hands-on testing still needed for the beta.

## Architecture

```text
NotchIsland/
├── App/          Lifecycle, onboarding, menu bar, privacy/signing metadata
├── Core/         NotchDetector, ScreenManager, IslandCoordinator,
│                 IslandWindowController, LiveActivityManager, shared store
├── Features/     Battery, System, Timer, Calendar, DropZone, Clipboard,
│                 Notes, Tasks, Mirror, Actions, Launcher, Downloads, Media
├── Views/        Island states, module host, reusable DesignSystem
└── Settings/     Persisted settings and native sidebar UI
Tests/            Isolated logic/storage/policy checks
UITests/          Native XCUITest interaction checks
Scripts/          Developer ID archive and notarization preparation
```

Notch size/position comes from `safeAreaInsets`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. Measurements remain in screen points; AppKit handles Retina backing pixels. Screens without a notch receive a small top-center island. A transparent borderless NSPanel uses status-bar level, all-Spaces and fullscreen-auxiliary behavior. Screen changes rebuild panels while shared feature state survives.

## Tests

```sh
sh Tests/run-all.sh
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland \
  -configuration Debug -derivedDataPath build -destination 'platform=macOS' test
```

Command-line checks cover geometry, states, pointer timing, settings, activity priority/expiry, timer modes, calendar link safety, shelf ownership/pins, clipboard limits/exclusions, notes, tasks, actions, download URL policy and media adapters. They use isolated fixtures and perform no remote downloads, media playback or permission grants.

XCUITest uses an isolated preferences suite and temporary notes/shelf storage with clipboard disabled and calendar monitoring off. It checks timer controls, module navigation and Escape/accessibility. Run it in an unlocked macOS desktop session with Xcode's UI testing permissions.

Build/test evidence and manual checks are recorded in [Development](Documentation/Development.md) and [Validation](Documentation/Validation.md). Logic checks and a universal Release build have passed; the current UI test rerun remains open. Hardware-dependent permissions, fullscreen Spaces, monitor hot-plugging, real recording/downloads and playback still need hands-on validation on release hardware.

## Distribution

See [Distribution](Documentation/Distribution.md). Signing entitlements, privacy declarations, universal archive and notarization scripts are included. Developer ID signing and notarization require your credentials and have not been performed.
