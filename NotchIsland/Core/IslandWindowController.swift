import AppKit
import SwiftUI
import Combine

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Keep the panel at the physical screen edge, including the menu-bar area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class IslandWindowController {
    let model: IslandModel
    private let panel: IslandPanel
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let displayID = UUID()
    private var subscriptions = Set<AnyCancellable>()

    init(geometry: NotchGeometry, widgets: WidgetStore, coordinator: IslandCoordinator) {
        model = IslandModel(geometry: geometry, coordinator: coordinator)
        let size = model.canvasSize
        panel = IslandPanel(contentRect: CGRect(x: geometry.centerX - size.width / 2,
                                               y: geometry.screenFrame.maxY - size.height,
                                               width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Notch Island"
        panel.setAccessibilityIdentifier("island.panel")
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: IslandView(model: model, widgets: widgets))
        panel.orderFrontRegardless()
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: events.union(.keyDown)) { [weak self] event in
            let consumed: Bool = MainActor.assumeIsolated {
                if event.type == .keyDown, event.keyCode == 53, event.window === self?.panel,
                   self?.model.state != .collapsed, self?.model.coordinator.isInteractingWithMenu == false {
                    self?.model.coordinator.collapse()
                    return true
                }
                if event.type == .keyDown, event.window === self?.panel { self?.model.coordinator.userDidInteract() }
                self?.handle(event)
                return false
            }
            return consumed ? nil : event
        }
        let center = NotificationCenter.default
        center.publisher(for: NSControl.textDidBeginEditingNotification)
            .merge(with: center.publisher(for: NSText.didBeginEditingNotification))
            .sink { [weak self] note in
                guard let self, (note.object as? NSView)?.window === panel else { return }
                coordinator.setPresentationHeld(true, reason: "editor.\(displayID)")
            }.store(in: &subscriptions)
        center.publisher(for: NSControl.textDidEndEditingNotification)
            .merge(with: center.publisher(for: NSText.didEndEditingNotification))
            .sink { [weak self] note in
                guard let self, (note.object as? NSView)?.window === panel else { return }
                coordinator.setPresentationHeld(false, reason: "editor.\(displayID)")
            }.store(in: &subscriptions)
        center.publisher(for: NSWindow.didResignKeyNotification, object: panel).sink { [weak self] _ in
            guard let self else { return }
            coordinator.setPresentationHeld(false, reason: "editor.\(displayID)")
        }.store(in: &subscriptions)
        coordinator.$state.receive(on: RunLoop.main).sink { [weak self] state in
            // A nonactivating panel must release keyboard ownership when dismissed;
            // AppKit returns it to the active app without activating another app.
            if state == .collapsed, self?.panel.isKeyWindow == true { self?.panel.resignKey() }
            self?.updatePointer()
        }.store(in: &subscriptions)
        updatePointer()
    }

    private func handle(_ event: NSEvent) {
        if let window = event.window, window is IslandPanel, window !== panel {
            updatePointer()
            return
        }
        // Native menus may extend beyond the panel. Let their own event tracking
        // handle selection, dismissal, scrolling, and Escape first.
        if model.coordinator.isInteractingWithMenu { updatePointer(); return }
        let inside = containsIslandPoint(NSEvent.mouseLocation)
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !inside {
                // Native popovers/alerts dismiss themselves on outside clicks.
                if !model.coordinator.isPresentationHeld || event.window == nil { model.coordinator.collapse() }
            }
            else if event.type == .leftMouseDown { panel.makeKey() }
        }
        let inHeader = NSEvent.mouseLocation.y >= model.geometry.screenFrame.maxY - model.geometry.collapsedSize.height - 8
        if event.type == .scrollWheel, inside, inHeader, model.coordinator.settings.scrollGesturesEnabled {
            if event.scrollingDeltaY < -4 { model.coordinator.expand() }
            if event.scrollingDeltaY > 4 { model.coordinator.collapse() }
        }
        updatePointer()
    }
    var containsPointer: Bool { model.geometry.screenFrame.contains(NSEvent.mouseLocation) }
    private var islandRect: CGRect {
        let size = model.size
        return CGRect(x: model.geometry.centerX - size.width / 2,
                      y: model.geometry.screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
    private func updatePointer() {
        let inside = containsIslandPoint(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        model.coordinator.pointer(inside, display: displayID)
    }
    private func containsIslandPoint(_ point: CGPoint) -> Bool {
        let rect = islandRect
        guard rect.contains(point) else { return false }
        // Use the same silhouette as IslandView. Convert
        // AppKit's upward Y axis to the downward local coordinates of the shape.
        let localPoint = CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y)
        return model.silhouette.path(in: CGRect(origin: .zero, size: rect.size)).contains(localPoint)
    }
    func focus() { panel.makeKeyAndOrderFront(nil) }
    func expand() { model.coordinator.expand(); focus() }
    func close() {
        model.coordinator.setPresentationHeld(false, reason: "editor.\(displayID)")
        model.coordinator.removeDisplay(displayID)
        subscriptions.removeAll()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        panel.close()
    }
}
