import AppKit

@main
struct CoreChecks {
    @MainActor static func main() async {
        let suiteName = "NotchIsland.CoreChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = IslandSettings(defaults: defaults)
        checkNotchGeometry()
        checkSettings(settings, defaults: defaults)
        checkIslandLayout(settings: settings)
        checkIslandSilhouette()
        await checkPointerTransitions(settings: settings)
        await checkPresentationHolds(settings: settings)
        checkMenuActivityReplay(settings: settings)
        checkLiveActivities(settings: settings)
        checkRecordingOwnership()
        checkTimer()
        checkProductivityTimers()
        checkCalendarSnapshots()
        print("PASS: notch geometry, malformed display snapshots, Retina points, six island states, dashboard/tray/module layouts, shared silhouette hit testing, shared displays, settings persistence, pointer transitions, editing holds, menu activity replay, activity priorities/expiry, recording ownership, timer/stopwatch/Pomodoro lifecycle, calendar link safety")
    }

    private static func checkNotchGeometry() {
        let frame = CGRect(x: -1728, y: 900, width: 1728, height: 1117)
        let left = CGRect(x: -1728, y: 1980, width: 760, height: 37)
        let right = CGRect(x: -760, y: 1980, width: 760, height: 37)
        let geometry = NotchGeometry.resolve(
            frame: frame, safeTop: 37, left: left, right: right)
        expect(geometry.hasNotch, "Valid auxiliary areas identify the physical notch")
        expect(geometry.collapsedSize == CGSize(width: 208, height: 37), "Notch size uses auxiliary gap and safe inset")
        expect(geometry.centerX == -864, "A monitor above and left of the primary screen keeps its global origin")

        // Retina screens report these values in points. The physical pixel density
        // must not change the geometry given to NSPanel/SwiftUI.
        let retina = NotchGeometry.resolve(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                          safeTop: 32,
                                          left: CGRect(x: 0, y: 950, width: 664, height: 32),
                                          right: CGRect(x: 848, y: 950, width: 664, height: 32))
        expect(retina.collapsedSize == CGSize(width: 184, height: 32), "Retina dimensions remain points")
        let translated = NotchGeometry.resolve(frame: CGRect(x: 1512, y: -982, width: 1512, height: 982),
                                               safeTop: 32,
                                               left: CGRect(x: 1512, y: -32, width: 664, height: 32),
                                               right: CGRect(x: 2360, y: -32, width: 664, height: 32))
        expect(translated.collapsedSize == retina.collapsedSize, "Notch size is independent of monitor arrangement")
        expect(translated.centerX == retina.centerX + 1512, "Right-hand monitor notch uses global coordinates")
        let asymmetric = NotchGeometry.resolve(frame: frame, safeTop: 37, left: left,
                                              right: CGRect(x: -700, y: 1980, width: 700, height: 37))
        expect(asymmetric.centerX == -834, "Notch position comes from the actual auxiliary gap")

        let external = NotchGeometry.resolve(frame: frame, safeTop: 0, left: nil, right: nil)
        expect(!external.hasNotch && external.centerX == frame.midX, "Unnotched screens use a centered fallback")
        let invalid: [(String, CGFloat, CGRect?, CGRect?)] = [
            ("missing auxiliary areas", 37, nil, nil),
            ("missing right area", 37, left, nil),
            ("zero safe inset", 0, left, right),
            ("negative safe inset", -37, left, right),
            ("non-finite safe inset", .infinity, left, right),
            ("NaN safe inset", .nan, left, right),
            ("inset consumes entire screen", frame.height, left, right),
            ("empty auxiliary area", 37, .zero, right),
            ("negative auxiliary width", 37, CGRect(x: -968, y: 1980, width: -760, height: 37), right),
            ("non-finite auxiliary area", 37, CGRect(x: -.infinity, y: 1980, width: 760, height: 37), right),
            ("reversed areas", 37, right, left),
            ("overlapping areas", 37, CGRect(x: -1728, y: 1980, width: 1000, height: 37), right),
            ("areas touch without a notch", 37, CGRect(x: -1728, y: 1980, width: 968, height: 37), right),
            ("area outside screen", 37, CGRect(x: -1730, y: 1980, width: 760, height: 37), right),
            ("area below top safe band", 37, CGRect(x: -1728, y: 1900, width: 760, height: 37), right),
            ("area above screen", 37, CGRect(x: -1728, y: 1981, width: 760, height: 37), right)
        ]
        for (reason, safeTop, left, right) in invalid {
            let result = NotchGeometry.resolve(frame: frame, safeTop: safeTop, left: left, right: right)
            expect(!result.hasNotch && result == external, "Safe fallback for \(reason)")
        }
    }

    @MainActor private static func checkSettings(_ settings: IslandSettings, defaults: UserDefaults) {
        expect(settings.islandWidth == 1440 && settings.hoverDelay == 0.15, "Fresh settings use product defaults")
        settings.islandWidth = 960
        settings.showOnExternalDisplays = false
        settings.hoverDelay = 0.4
        settings.animationStyle = .subtle
        settings.appearance = .light
        let restored = IslandSettings(defaults: defaults)
        expect(restored.islandWidth == 960 && !restored.showOnExternalDisplays,
               "Size and display preferences survive a new settings instance")
        expect(restored.hoverDelay == 0.4 && restored.animationStyle == .subtle && restored.appearance == .light,
               "Interaction and appearance preferences persist")
        settings.islandWidth = 2000
        settings.hoverDelay = -5
        settings.autoCollapseDelay = .infinity
        settings.animationSpeed = .nan
        expect(settings.islandWidth == 1440 && settings.hoverDelay == 0, "Out-of-range preferences clamp to safe bounds")
        expect(settings.autoCollapseDelay == 1.5 && settings.animationSpeed == 1,
               "Non-finite preference values use safe defaults")
        expect(settings.animation(reduceMotion: true) == nil, "Reduce Motion suppresses island animations")
        settings.animationStyle = .none
        expect(settings.animation(reduceMotion: false) == nil, "Disabled animation stays disabled")
        defaults.set("invalid", forKey: "animationStyle")
        defaults.set("invalid", forKey: "appearance")
        defaults.set(-42, forKey: "islandWidth")
        let recovered = IslandSettings(defaults: defaults)
        expect(recovered.animationStyle == .spring && recovered.appearance == .system && recovered.islandWidth == 680,
               "Malformed stored preferences recover safely")
    }

    @MainActor private static func checkIslandLayout(settings: IslandSettings) {
        settings.islandWidth = 1120
        let geometry = NotchGeometry.resolve(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                             safeTop: 32,
                                             left: CGRect(x: 0, y: 950, width: 664, height: 32),
                                             right: CGRect(x: 848, y: 950, width: 664, height: 32))
        let model = IslandModel(geometry: geometry, coordinator: IslandCoordinator(settings: settings))
        expect(model.size == geometry.collapsedSize, "Collapsed island matches the physical notch")
        let heights: [(IslandModel.State, CGFloat)] = [
            (.collapsed, 0), (.hovered, 48), (.expanded, 220),
            (.liveActivity, 72), (.dragTarget, 160), (.alert, 72)
        ]
        for (state, contentHeight) in heights {
            model.state = state
            expect(model.size.height == geometry.collapsedSize.height + contentHeight,
                   "\(state.rawValue) content stays below the notch")
            expect(model.canvasSize.width >= model.size.width && model.canvasSize.height >= model.size.height,
                   "The panel canvas contains \(state.rawValue)")
        }
        model.coordinator.showDashboard()
        expect(model.coordinator.page == .dashboard && model.size.width == 1120 && model.contentHeight == 220,
               "Dashboard opens in the configured wide layout")
        model.coordinator.showTray()
        expect(model.coordinator.page == .tray && model.selectedWidget == .files && model.contentHeight == 160,
               "Tray navigation opens the shallower file shelf")
        expect(model.size.width == 1120, "Tray retains the dashboard width")
        for widget in IslandWidget.allCases {
            model.coordinator.showModule(widget)
            expect(model.state == .expanded && model.coordinator.page == .module && model.selectedWidget == widget,
                   "Every module remains directly navigable")
            expect(model.size.width == 640 && model.contentHeight == 280, "Module controls keep their compact working area")
        }
        model.coordinator.showDashboard()
        expect(model.contentHeight == 220 && model.size.width == 1120, "Returning home restores dashboard dimensions")
        expect(model.canvasSize == CGSize(width: 1440, height: 312), "The panel canvas accommodates every page and width")
        let external = IslandModel(geometry: .resolve(frame: CGRect(x: 1512, y: 0, width: 340, height: 480),
                                                      safeTop: 0, left: nil, right: nil),
                                   coordinator: model.coordinator)
        model.coordinator.expand()
        expect(external.state == .expanded, "All screens share presentation state")
        expect(external.size.width <= external.geometry.screenFrame.width, "Island width fits narrow displays")
        model.coordinator.beginDrag()
        expect(model.state == .dragTarget, "Dragging has a distinct target state")
        model.coordinator.endDrag(accepted: true)
        expect(model.state == .expanded && model.selectedWidget == .files && model.coordinator.page == .tray,
               "Accepted drops open the file tray")
        expect(external.selectedWidget == .files, "Widget selection is shared between screens")
        model.coordinator.beginDrag()
        model.coordinator.endDrag(accepted: false)
        expect(model.state == .collapsed, "Rejected drops collapse the island")
        model.coordinator.expand()
        model.coordinator.collapse()
        expect(model.state == .collapsed, "Explicit dismissal returns to collapsed state")

        let wideNotch = IslandModel(geometry: NotchGeometry(screenFrame: geometry.screenFrame,
                                                           collapsedSize: CGSize(width: 700, height: 32),
                                                           centerX: geometry.centerX, hasNotch: true),
                                   coordinator: model.coordinator)
        model.coordinator.showModule(.timer)
        expect(wideNotch.size.width == 700, "Compact module pages still encompass the physical notch")
        model.coordinator.collapse()
        expect(wideNotch.size == wideNotch.geometry.collapsedSize, "Page selection never changes the physical collapsed cap")
    }

    private static func checkIslandSilhouette() {
        let rect = CGRect(x: 0, y: 0, width: 1120, height: 252)
        let shape = IslandSilhouette(shoulderRadius: 12, bottomRadius: 28)
        let path = shape.path(in: rect)
        expect(path.contains(CGPoint(x: 560, y: 1)), "The expanded top edge remains attached to the display edge")
        expect(path.contains(CGPoint(x: 8, y: 1)), "Concave shoulders include their visible upper flare")
        expect(!path.contains(CGPoint(x: 1, y: 1)), "Transparent shoulder corners pass clicks through")
        expect(!path.contains(CGPoint(x: 6, y: 40)), "The transparent side gutter does not intercept clicks")
        expect(path.contains(CGPoint(x: 13, y: 40)), "The straight side begins at the shoulder inset")
        expect(!path.contains(CGPoint(x: 13, y: 251)), "Rounded bottom corners pass clicks through")
        expect(path.contains(CGPoint(x: 40, y: 251)), "The bottom edge remains interactive inside the corner")
        for point in [CGPoint(x: 8, y: 1), CGPoint(x: 6, y: 40), CGPoint(x: 13, y: 251)] {
            expect(path.contains(point) == path.contains(CGPoint(x: rect.width - point.x, y: point.y)),
                   "Left and right shoulder and corner hit regions are symmetric")
        }
        let collapsed = IslandSilhouette(shoulderRadius: 0, bottomRadius: 8)
            .path(in: CGRect(x: 0, y: 0, width: 184, height: 32))
        expect(collapsed.contains(CGPoint(x: 1, y: 1)), "Collapsed shape keeps its physical full-width top edge")
        expect(!collapsed.contains(CGPoint(x: 1, y: 31)), "Collapsed bottom corners retain their curve")
        let offset = shape.path(in: rect.offsetBy(dx: -100, dy: 200))
        expect(offset.contains(CGPoint(x: 460, y: 201)), "The shared path respects its supplied drawing origin")
        expect(shape.path(in: .zero).isEmpty, "Empty layout does not create an interactive shape")
    }

    @MainActor private static func checkPointerTransitions(settings: IslandSettings) async {
        settings.hoverDelay = 0.04
        settings.autoCollapseDelay = 0.25
        let coordinator = IslandCoordinator(settings: settings)
        let firstDisplay = UUID()
        let secondDisplay = UUID()
        coordinator.pointer(true, display: firstDisplay)
        expect(coordinator.state == .collapsed, "Hover respects its configured delay")
        await eventually("Hover expands after the delay") { coordinator.state == .hovered }
        coordinator.pointer(true, display: secondDisplay)
        coordinator.pointer(false, display: firstDisplay)
        try? await Task.sleep(for: .milliseconds(300))
        expect(coordinator.state == .hovered, "Leaving one display does not collapse while another is hovered")
        coordinator.removeDisplay(secondDisplay)
        await eventually("Removing the final hovered display permits collapse") { coordinator.state == .collapsed }
        coordinator.pointer(true, display: firstDisplay)
        coordinator.pointer(false, display: firstDisplay)
        try? await Task.sleep(for: .milliseconds(100))
        expect(coordinator.state == .collapsed, "Leaving before the hover delay cancels expansion")
        coordinator.pointer(true, display: secondDisplay)
        coordinator.removeDisplay(secondDisplay)
        try? await Task.sleep(for: .milliseconds(100))
        expect(coordinator.state == .collapsed, "Removing a display cancels its pending hover")
        coordinator.expand()
        coordinator.pointer(true, display: firstDisplay)
        coordinator.pointer(false, display: firstDisplay)
        await eventually("Expanded island collapses after pointer exit") { coordinator.state == .collapsed }
    }

    @MainActor private static func eventually(_ message: String, condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(condition(), message)
    }

    @MainActor private static func checkPresentationHolds(settings: IslandSettings) async {
        settings.autoCollapseDelay = 0.25
        let coordinator = IslandCoordinator(settings: settings)
        let display = UUID()
        coordinator.expand()
        coordinator.pointer(true, display: display)
        coordinator.setPresentationHeld(true, reason: "note-editor")
        coordinator.setPresentationHeld(true, reason: "search-editor")
        coordinator.pointer(false, display: display)
        coordinator.userDidInteract()
        try? await Task.sleep(for: .milliseconds(450))
        expect(coordinator.state == .expanded && coordinator.isPresentationHeld,
               "Pointer exit and keyboard activity cannot collapse a focused editor")
        coordinator.setPresentationHeld(false, reason: "note-editor")
        coordinator.setPresentationHeld(false, reason: "unknown-editor")
        try? await Task.sleep(for: .milliseconds(450))
        expect(coordinator.state == .expanded && coordinator.isPresentationHeld,
               "Releasing one editor or an unknown editor preserves another editor's hold")
        coordinator.setPresentationHeld(false, reason: "search-editor")
        expect(!coordinator.isPresentationHeld, "The final editor release clears the hold")
        await eventually("Final editor release resumes pointer-exit collapse") { coordinator.state == .collapsed }

        coordinator.expand()
        coordinator.pointer(true, display: display)
        coordinator.pointer(false, display: display)
        coordinator.setPresentationHeld(true, reason: "late-editor")
        try? await Task.sleep(for: .milliseconds(450))
        expect(coordinator.state == .expanded, "Acquiring an editor hold cancels a previously scheduled collapse")
        coordinator.collapse()
        expect(coordinator.state == .collapsed && !coordinator.isPresentationHeld,
               "Explicit dismissal overrides and clears editor holds")
        coordinator.setPresentationHeld(false, reason: "late-editor")
        expect(coordinator.state == .collapsed, "A late editor-end notification cannot reopen a dismissed island")
    }

    @MainActor private static func checkMenuActivityReplay(settings: IslandSettings) {
        let coordinator = IslandCoordinator(settings: settings)
        let menu = NSMenu()
        let submenu = NSMenu()
        let timer = IslandActivity(id: "menu.timer", title: "Time's up", detail: "", symbol: "timer",
                                   priority: .timer, expiresAt: .now.addingTimeInterval(60), progress: nil)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
        coordinator.present(timer)
        expect(coordinator.isInteractingWithMenu && coordinator.state == .collapsed,
               "A new activity waits while a native menu is tracking")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: submenu)
        expect(coordinator.isInteractingWithMenu && coordinator.state == .collapsed,
               "Closing a submenu does not interrupt the remaining menu")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        expect(!coordinator.isInteractingWithMenu && coordinator.state == .liveActivity && coordinator.activity?.id == timer.id,
               "Closing the final menu replays the pending unexpired activity")

        coordinator.collapse()
        var critical = timer
        critical.priority = .critical
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        coordinator.present(critical)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        expect(coordinator.state == .alert, "Deferred critical activities retain their alert presentation")

        coordinator.collapse()
        var expired = timer
        expired.expiresAt = .now.addingTimeInterval(-1)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        coordinator.present(expired)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        expect(coordinator.state == .collapsed, "An activity that expired during a menu is not replayed")

        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        coordinator.present(timer)
        coordinator.present(nil)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        expect(coordinator.state == .collapsed && coordinator.activity == nil,
               "An activity removed during a menu is not replayed")

        coordinator.expand()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        coordinator.present(timer)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        expect(coordinator.state == .expanded, "Menu replay preserves a user-expanded island")
        coordinator.collapse()
    }

    @MainActor private static func checkLiveActivities(settings: IslandSettings) {
        let manager = LiveActivityManager()
        let now = Date(timeIntervalSince1970: 10_000)
        let priorities: [IslandActivity.Priority] = [.standard, .media, .download, .fileTransfer, .timer, .userAction, .meeting, .critical]
        for priority in priorities {
            manager.post(id: "priority-\(priority.rawValue)", title: "Priority \(priority.rawValue)",
                         symbol: "bell", priority: priority, duration: 100, now: now)
            expect(manager.primary?.priority == priority, "Higher live activity priority takes ownership of the island")
        }
        manager.refresh(now: now.addingTimeInterval(100))
        expect(manager.primary == nil, "Activities expire exactly at their deadline")

        manager.post(id: "timer", title: "Focus", symbol: "timer", priority: .timer, duration: 60, now: now)
        manager.post(id: "battery", title: "Low battery", symbol: "battery.0percent", priority: .critical, duration: 5, now: now)
        expect(manager.primary?.id == "battery", "Critical activity temporarily interrupts a timer")
        manager.refresh(now: now.addingTimeInterval(5))
        expect(manager.primary?.id == "timer", "Expiring the primary activity reveals the next eligible activity")
        manager.post(id: "timer", title: "Focus updated", detail: "Almost there", symbol: "timer", priority: .timer,
                     duration: 10, progress: 0.75, now: now.addingTimeInterval(5))
        expect(manager.primary?.title == "Focus updated" && manager.primary?.progress == 0.75,
               "Repeated IDs update the existing activity")
        manager.refresh(now: now.addingTimeInterval(15))
        expect(manager.primary == nil, "Replacing an ID removes its previous longer expiry")

        manager.post(id: "zero", title: "Expired", symbol: "bell", duration: 0, now: now)
        expect(manager.primary == nil, "Zero-duration activities never become primary")
        manager.post(id: "later", title: "Later", symbol: "bell", duration: 20, now: now)
        manager.post(id: "sooner", title: "Sooner", symbol: "bell", duration: 10, now: now)
        expect(manager.primary?.id == "later", "Equal priority activities prefer the more recent expiry")
        manager.post(id: "alphabetical", title: "Stable tie", symbol: "bell", duration: 20, now: now)
        expect(manager.primary?.id == "alphabetical", "Equal priority and expiry resolve deterministically")
        manager.dismiss("alphabetical", now: now)
        expect(manager.primary?.id == "later", "Dismissing one activity preserves the remaining queue")
        manager.dismiss("unknown", now: now)
        expect(manager.primary?.id == "later", "Dismissing an unknown ID leaves the primary unchanged")

        let coordinator = IslandCoordinator(settings: settings)
        coordinator.present(manager.primary)
        expect(coordinator.state == .liveActivity, "An ordinary activity opens its temporary presentation")
        coordinator.present(nil)
        expect(coordinator.state == .collapsed, "Clearing an activity dismisses its presentation")
        manager.post(id: "critical", title: "Critical", symbol: "exclamationmark.triangle", priority: .critical, now: now)
        coordinator.present(manager.primary)
        expect(coordinator.state == .alert, "A critical activity uses the alert state")
        coordinator.expand()
        coordinator.present(nil)
        expect(coordinator.state == .expanded, "Activity expiry preserves a user-expanded island")
        coordinator.beginDrag()
        coordinator.present(manager.primary)
        expect(coordinator.state == .dragTarget, "New activities preserve an active file drop target")
    }

    @MainActor private static func checkRecordingOwnership() {
        let recording = AppRecordingState()
        let first = UUID()
        let second = UUID()
        expect(!recording.isRecording, "Recording indicator starts inactive")
        recording.didStopOwnedSession(first)
        expect(!recording.isRecording, "An unknown stop cannot activate recording")
        recording.didStartOwnedSession(first)
        expect(recording.isRecording, "An app-owned recording activates its indicator")
        recording.didStopOwnedSession(second)
        expect(recording.isRecording, "Another recording's stop does not clear the owned session")
        recording.didStartOwnedSession(second)
        recording.didStopOwnedSession(first)
        expect(recording.isRecording, "A stale stop does not clear a replacement session")
        recording.didStopOwnedSession(second)
        expect(!recording.isRecording, "The current session's stop clears its indicator")
    }

    @MainActor private static func checkTimer() {
        let timer = TimerModel(automaticallySchedulesTicks: false, playCompletionSound: false)
        let start = Date(timeIntervalSince1970: 1000)
        timer.reset(seconds: 60)
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(12))
        expect(timer.remaining == 48 && timer.isRunning, "Timer counts down from a wall-clock deadline")
        timer.start(at: start.addingTimeInterval(15))
        timer.tick(at: start.addingTimeInterval(16))
        expect(timer.remaining == 44, "Starting an active timer does not reset its deadline")
        timer.pause(at: start.addingTimeInterval(20))
        expect(timer.remaining == 40 && !timer.isRunning, "Pausing captures exact remaining time")
        timer.tick(at: start.addingTimeInterval(90))
        expect(timer.remaining == 40, "A paused timer ignores ticks")
        timer.start(at: start.addingTimeInterval(100))
        timer.tick(at: start.addingTimeInterval(110))
        expect(timer.remaining == 30, "Resuming preserves remaining duration")
        // Simulates waking after the deadline; no accumulated tick drift.
        timer.tick(at: start.addingTimeInterval(500))
        expect(timer.remaining == 0 && timer.finished && !timer.isRunning, "Waking after the deadline completes the timer")
        timer.tick(at: start.addingTimeInterval(600))
        expect(timer.remaining == 0 && timer.finished, "Completed timer ignores further ticks")
        timer.reset(seconds: 90)
        expect(timer.display == "01:30" && !timer.finished, "Reset clears completion")
        timer.reset(seconds: 0.2)
        expect(timer.display == "00:01", "Positive fractional seconds round up for display")
        timer.reset(seconds: -1)
        timer.start(at: start)
        expect(timer.remaining == 0 && !timer.isRunning, "Zero-length timer cannot start")
    }

    @MainActor private static func checkProductivityTimers() {
        let timer = TimerModel(automaticallySchedulesTicks: false, playCompletionSound: false)
        let start = Date(timeIntervalSince1970: 1_000)
        timer.setMode(.stopwatch)
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(12.5))
        expect(timer.elapsed == 12.5 && timer.display == "00:12", "Stopwatch derives elapsed time from its start date")
        timer.pause(at: start.addingTimeInterval(20))
        timer.tick(at: start.addingTimeInterval(90))
        expect(timer.elapsed == 20 && !timer.isRunning, "Paused stopwatch excludes idle time")
        timer.start(at: start.addingTimeInterval(100))
        timer.tick(at: start.addingTimeInterval(115))
        expect(timer.elapsed == 35, "Resumed stopwatch preserves accumulated time")
        timer.resetCurrent()
        expect(timer.mode == .stopwatch && timer.elapsed == 0 && !timer.isRunning, "Reset preserves stopwatch mode")

        timer.reset(seconds: 10)
        timer.repeatEnabled = true
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(10))
        expect(timer.remaining == 10 && timer.isRunning && timer.completionCount == 1,
               "A repeating countdown restarts exactly at its deadline")
        timer.tick(at: start.addingTimeInterval(35))
        expect(timer.remaining == 5 && timer.completionCount == 3, "Repeat catches up across missed intervals after sleep")
        timer.repeatEnabled = false
        timer.tick(at: start.addingTimeInterval(40))
        expect(timer.remaining == 0 && timer.finished && timer.completionCount == 4,
               "Disabling repeat completes the current interval")
        timer.reset(seconds: .infinity)
        expect(timer.remaining == 300, "A non-finite duration cannot create an invalid deadline")

        timer.configurePomodoro(focus: 10, shortBreak: 5)
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(10))
        expect(timer.pomodoroPhase == .shortBreak && timer.remaining == 5 && timer.isRunning && timer.completionCount == 1,
               "Pomodoro switches from focus to break at the deadline")
        timer.tick(at: start.addingTimeInterval(15))
        expect(timer.finished && !timer.isRunning && timer.completionCount == 2,
               "A non-repeating Pomodoro finishes after its break")
        timer.resetCurrent()
        expect(timer.pomodoroPhase == .focus && timer.remaining == 10, "Pomodoro reset returns to focus")
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(100))
        expect(timer.finished && timer.completionCount == 2, "Sleeping through focus and break completes both once")

        timer.resetCurrent()
        timer.repeatEnabled = true
        timer.start(at: start)
        timer.tick(at: start.addingTimeInterval(46))
        expect(timer.pomodoroPhase == .focus && timer.remaining == 9 && timer.completionCount == 6,
               "Repeated Pomodoro resolves skipped cycles without accumulated timing drift")
        timer.tick(at: start.addingTimeInterval(55))
        expect(timer.pomodoroPhase == .shortBreak && timer.remaining == 5 && timer.completionCount == 7,
               "Repeated Pomodoro reaches the next break")
        timer.pause(at: start.addingTimeInterval(58))
        timer.start(at: start.addingTimeInterval(1_000))
        timer.tick(at: start.addingTimeInterval(1_002))
        expect(timer.pomodoroPhase == .focus && timer.remaining == 10 && timer.completionCount == 8,
               "Pausing a break preserves the cycle when it resumes")
        timer.setMode(.timer)
        expect(!timer.isRunning && !timer.finished && timer.mode == .timer, "Switching modes stops the previous session")
    }

    private static func checkCalendarSnapshots() {
        let web = URL(string: "https://meet.example.com/room")!
        expect(CalendarEventSnapshot.webMeetingURL(eventURL: web, notes: nil) == web,
               "Explicit web meeting links are accepted")
        expect(CalendarEventSnapshot.webMeetingURL(eventURL: URL(string: "file:///tmp/meeting"), notes: nil) == nil,
               "Local file URLs are never offered as meeting links")
        expect(CalendarEventSnapshot.webMeetingURL(eventURL: URL(string: "zoommtg://zoom.us/join"), notes: nil) == nil,
               "Custom application schemes are not executed from calendar data")
        expect(CalendarEventSnapshot.webMeetingURL(eventURL: URL(string: "https://user:password@meet.example.com"), notes: nil) == nil,
               "Credential-bearing links are rejected")
        expect(CalendarEventSnapshot.webMeetingURL(eventURL: nil, notes: "Email person@example.com or join https://meet.example.com/room") == web,
               "Notes can supply a web meeting link while email links are skipped")
        let start = Date(timeIntervalSince1970: 10_000)
        let event = CalendarEventSnapshot(id: "example", title: "Meeting", startDate: start,
                                          endDate: start.addingTimeInterval(1_800), isAllDay: false,
                                          location: nil, notes: nil, calendarName: "Work", meetingURL: web)
        expect(event.countdown(at: start.addingTimeInterval(-60)) == String(localized: "Starts in \(1) min"),
               "Meeting countdown rounds to visible minutes")
        expect(event.countdown(at: start) == String(localized: "In progress"), "Meeting start switches to in-progress status")
        expect(event.countdown(at: start.addingTimeInterval(1_800)) == String(localized: "Ended"), "Meeting end uses the exact boundary")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                               file: StaticString = #file, line: UInt = #line) {
        precondition(condition(), message, file: file, line: line)
    }
}
