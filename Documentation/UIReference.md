# Video reference redesign

The 17 October 2026 revision follows the supplied `hero-v11.mp4` reference within the existing Notch Island application.

## Visual changes

- A continuous black surface grows from the physical notch, with concave shoulders and rounded bottom corners.
- Pill tabs switch between **Island** and **Tray**. The grid menu retains access to every enabled module; a gear opens Settings.
- The dashboard places Media, Calendar, Notes, Timer, Tasks and Camera Mirror in a horizontal row with thin separators. Columns grow to use available width and scroll horizontally when space is limited.
- The file tray uses native thumbnails, two-line names, pin badges and a rounded dashed drop area. Dropping files expands the tray; dragging them out still uses the stored copies.
- Hover shows current media or timer information, with a compact battery indicator. Alerts retain the same black treatment.
- State/page size changes use the existing configurable animation and respect Reduce Motion.

The camera housing is still measured from NSScreen. Header controls sit in the wings on either side of it. SwiftUI clipping and AppKit hit testing now share one outline, so the transparent shoulder and corner areas pass clicks through.

## Functional scope

Media uses selected local files, Calendar keeps its explicit permission flow, notes remain local, and timer controls operate the existing timer. Tasks are stored locally and provide add, complete, reopen, delete and clear-completed actions. Camera Mirror stays off until Start Mirror is pressed; it shows a live circular mirrored preview and saves no video. The reference's AirDrop service is outside this implementation. No permission is enabled automatically and no demonstration data is stored in the user's modules.

The earlier modules remain available beside Tasks and Camera Mirror. Dashboard order follows the user's module order. The wide dashboard defaults to 1440 points with a 680–1440 point preference range; full module views remain at most 640 points wide.

## Verification

The geometry/state checks cover the three page layouts, screen-width limits, shared outline and one-time preference migration. Native UI coverage includes dashboard/tray navigation, timer controls, module navigation, clipboard's default-off state and Escape. Final build and test results are recorded in [Validation](Validation.md).
