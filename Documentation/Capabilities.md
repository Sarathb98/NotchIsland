# Public integrations and data storage

| Feature | Integration and scope |
| --- | --- |
| Display placement | NSScreen safe/auxiliary areas in points; AppKit panel on eligible displays. |
| Battery | IOKit Power Sources; internal battery only. |
| Output volume | Core Audio scalar control/listener when the current output driver exposes it. External devices may have hardware-only controls. |
| Brightness | Capability protocol and explicit fallback. Use macOS brightness controls; no private display frameworks. |
| Network | NWPathMonitor connection/interface state; no traffic interception. |
| Bluetooth | Explicitly enabled public CoreBluetooth authorization and paired-device IOBluetooth status. Device battery telemetry is unavailable without a supported device integration. |
| Headphones | Current Core Audio output name; no undocumented AirPods protocol. |
| Camera status | Opt-in AVFoundation device availability flags. Driver support varies; no camera session is opened solely to inspect use. |
| Camera Mirror | Explicit Start Mirror action requests camera permission if needed, then opens a live AVFoundation preview using the default camera. The circular preview is mirrored horizontally. Stop Mirror releases the session; no frames are recorded or saved. |
| Microphone | Public default-input driver running flag, updated by device/property listeners after System is first opened. It may include driver activity and does not identify apps. |
| Screen recording | Only sessions started with this app's Record Main Display action; ScreenCaptureKit recording output on macOS 15+. No audio. macOS 14 displays an unavailable explanation. |
| Resource usage | Mach host statistics; Foundation disk capacity. CPU/memory/disk polling occurs while the System pane is visible. |
| Calendar | EventKit full access after Enable; event content stays on the Mac. Meeting links must be HTTP(S). |
| File shelf | App-owned copies; pinning keeps a copy under Application Support. Original files are not moved or deleted. |
| Clipboard | Off at launch; memory-only history; explicit collection switch, exclusions, confidential/transient type checks, and bounded storage. Best-effort source-app exclusions cannot classify every sensitive value. |
| Quick notes | Local atomic JSON under Application Support/NotchIsland. |
| Tasks | Local atomic JSON under Application Support/NotchIsland/tasks.json. Up to 100 entries with normalized titles of at most 120 characters. No account or sync service. |
| Quick actions | Native file/application bookmarks; macOS Screenshot app; timer/focus timer. Lock screen uses the documented keyboard-shortcut guidance. |
| Launcher | Local application bundles; NSWorkspace launch. |
| Downloads | Transfers initiated in Notch Island only. No inspection of other apps' downloads. |
| Media | Explicitly selected local audio/video files through AVPlayer and a replaceable adapter. No global other-app Now Playing access. |

No analytics, telemetry service, account, or third-party SDK is included. System permission prompts are initiated from explicit feature controls. Permission-dependent integrations must be validated on the target signed app and hardware.
