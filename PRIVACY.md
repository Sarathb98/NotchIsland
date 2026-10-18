# Privacy in Notch Island

Notch Island is a local macOS utility. Its current code has no account, sync service, analytics service or third-party SDK. The app does not upload notes, tasks, clipboard history, calendar events, camera video or screen recordings to an app-operated server. A user-started download connects to the HTTPS address the user enters; opening a meeting link hands that address to the default browser.

## What stays on your Mac

| Feature | Data and storage |
| --- | --- |
| Settings and quick actions | Display, module, shortcut and other preferences, including user-chosen clipboard exclusions and quick-action bookmarks, are stored in macOS preferences. Launch at login is optional. |
| Notes and tasks | Saved as local JSON files in `~/Library/Application Support/NotchIsland/`. There is no built-in sync. |
| File shelf | Files dropped onto the shelf are copied; originals are not moved. Pinned copies and their list are kept under `~/Library/Application Support/NotchIsland/FileShelf/`. Unpinned copies use the app's temporary directory and are removed on normal quit. After an interruption, the next launch cleans up copies it can safely identify as abandoned. Older temporary copies may remain until macOS clears them. |
| Clipboard history | Off at every launch. When you turn it on, new text, links, images and file references are kept in memory only; the history is not saved to disk. Copying an entry back places it on the macOS clipboard. Source-app exclusions and confidential-type checks are best effort and cannot recognize every secret. |
| Calendar | If you grant Calendar access, the app reads upcoming events through macOS EventKit for the preview and alerts. Event details are held in memory rather than saved by the app. |
| Camera Mirror | Starting the mirror asks for camera permission and displays a live preview. The app does not record or save camera frames. |
| Screen recording | On macOS 15 or later, a recording starts only after you choose **Record Main Display** and a save location. It captures the main display and cursor without audio, then saves an MP4 at the chosen location. |
| Downloads and media | A download starts only when you enter an HTTPS address and choose where to save it. The contacted server receives the ordinary network request. Media playback uses files you choose on your Mac. |

Bluetooth device status and camera awareness are optional. System status uses macOS device and connection information; the network indicator reports connection state, not the contents of network traffic.

## Your controls

You can pause or clear clipboard history in the app, remove notes and tasks, and remove files from the shelf. You can revoke Calendar, Camera, Bluetooth and Screen Recording permissions in macOS **System Settings → Privacy & Security**. Removing the app itself does not automatically remove notes, tasks, preferences, pinned files, downloads or recordings saved on your Mac.

For questions or bug reports, use this repository's GitHub Issues page. See [Capabilities](Documentation/Capabilities.md) for implementation details.
