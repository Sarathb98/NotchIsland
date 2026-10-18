import AppKit
import SwiftUI
import Combine
import OSLog

/// The sole owner of presentation state. Display models only supply geometry.
@MainActor
final class IslandCoordinator: ObservableObject {
    enum State: String { case collapsed, hovered, expanded, liveActivity, dragTarget, alert }
    @Published private(set) var state: State = .collapsed
    @Published private(set) var isInteractingWithMenu = false
    @Published var page: IslandPage = .dashboard
    @Published var selectedWidget: IslandWidget = .timer
    let settings: IslandSettings
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var hoveredDisplays = Set<UUID>()
    private var dragging = false
    private var dragDisplay: UUID?
    private var trackingMenus = Set<ObjectIdentifier>()
    private var resumeHoverAfterMenu = false
    private var activityArrivedDuringMenu = false
    private var presentationHolds = Set<String>()
    var isPresentationHeld: Bool { !presentationHolds.isEmpty }
    private var subscriptions = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.notchisland.app", category: "Presentation")

    init(settings: IslandSettings) {
        self.settings = settings
        // Menu notifications arrive synchronously on AppKit's main thread. Deferring
        // them to the run loop can allow an outside-click dismissal to win the race.
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                self?.menuBeganTracking(menu)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                self?.menuEndedTracking(menu)
            }.store(in: &subscriptions)
    }
    func transition(to state: State) {
        hoverTask?.cancel()
        collapseTask?.cancel()
        hoverTask = nil
        collapseTask = nil
        resumeHoverAfterMenu = false
        self.state = state
        logger.debug("Island state: \(state.rawValue, privacy: .public)")
    }
    @Published private(set) var activity: IslandActivity?
    func present(_ activity: IslandActivity?) {
        self.activity = activity
        if isInteractingWithMenu { activityArrivedDuringMenu = activity != nil }
        if let activity {
            if state != .expanded && state != .dragTarget && !isInteractingWithMenu {
                transition(to: activity.priority == .critical ? .alert : .liveActivity)
            }
        } else if state == .liveActivity || state == .alert { collapse() }
    }
    func expand() { transition(to: .expanded) }
    func showDashboard() { page = .dashboard; expand() }
    func showTray() { selectedWidget = .files; page = .tray; expand() }
    func showModule(_ widget: IslandWidget) { selectedWidget = widget; page = .module; expand() }
    func collapse() { presentationHolds.removeAll(); dragging = false; dragDisplay = nil; transition(to: .collapsed) }
    func pointer(_ inside: Bool, display: UUID) {
        let wasInside = hoveredDisplays.contains(display)
        guard wasInside != inside else { return }
        if inside {
            hoveredDisplays.insert(display)
            collapseTask?.cancel()
            scheduleHover()
        } else {
            hoveredDisplays.remove(display)
            guard hoveredDisplays.isEmpty else { return }
            hoverTask?.cancel()
            scheduleCollapse()
        }
    }
    private func scheduleHover() {
        guard state == .collapsed, !hoveredDisplays.isEmpty else { return }
        guard !isInteractingWithMenu else { resumeHoverAfterMenu = true; return }
        hoverTask?.cancel()
        let delay = settings.hoverDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, state == .collapsed,
                  !isInteractingWithMenu, !hoveredDisplays.isEmpty else { return }
            transition(to: .hovered)
        }
    }
    func setPresentationHeld(_ held: Bool, reason: String) {
        if held { presentationHolds.insert(reason); collapseTask?.cancel() }
        else {
            let removed = presentationHolds.remove(reason) != nil
            if removed && !isPresentationHeld && hoveredDisplays.isEmpty { scheduleCollapse() }
        }
    }
    func userDidInteract() { collapseTask?.cancel(); if hoveredDisplays.isEmpty { scheduleCollapse() } }
    private func scheduleCollapse() {
        guard !dragging, !isInteractingWithMenu, !isPresentationHeld,
              state == .hovered || state == .expanded else { return }
        collapseTask?.cancel()
        let delay = settings.autoCollapseDelay
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !isInteractingWithMenu,
                  !dragging, !isPresentationHeld, hoveredDisplays.isEmpty else { return }
            collapse()
        }
    }
    private func menuBeganTracking(_ menu: NSMenu) {
        if trackingMenus.isEmpty { resumeHoverAfterMenu = hoverTask != nil && state == .collapsed }
        trackingMenus.insert(ObjectIdentifier(menu))
        isInteractingWithMenu = true
        hoverTask?.cancel()
        collapseTask?.cancel()
        hoverTask = nil
        collapseTask = nil
    }
    private func menuEndedTracking(_ menu: NSMenu) {
        trackingMenus.remove(ObjectIdentifier(menu))
        guard trackingMenus.isEmpty else { return }
        isInteractingWithMenu = false
        let resumeHover = resumeHoverAfterMenu
        resumeHoverAfterMenu = false
        if activityArrivedDuringMenu {
            activityArrivedDuringMenu = false
            if let activity, activity.expiresAt > .now { present(activity) }
        }
        if hoveredDisplays.isEmpty { scheduleCollapse() }
        else if resumeHover { scheduleHover() }
    }
    func beginDrag() {
        dragging = true
        dragDisplay = hoveredDisplays.first
        transition(to: .dragTarget)
    }
    func endDrag(accepted: Bool) {
        dragging = false
        dragDisplay = nil
        if accepted { showTray() } else { collapse() }
    }
    func removeDisplay(_ id: UUID) {
        hoveredDisplays.remove(id)
        if dragging, dragDisplay == nil || dragDisplay == id { collapse() }
        if hoveredDisplays.isEmpty { hoverTask?.cancel(); scheduleCollapse() }
    }
}
