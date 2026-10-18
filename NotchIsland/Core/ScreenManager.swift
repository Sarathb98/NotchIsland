import AppKit
import Combine

@MainActor
final class ScreenManager {
    let widgets: WidgetStore
    let coordinator: IslandCoordinator
    private let singleDisplay: Bool
    private let settings: IslandSettings
    private var windows: [IslandWindowController] = []
    private var subscriptions = Set<AnyCancellable>()
    init(settings: IslandSettings, widgets: WidgetStore, singleDisplay: Bool = false) {
        self.singleDisplay = singleDisplay
        self.settings = settings
        self.widgets = widgets
        coordinator = IslandCoordinator(settings: settings)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.rebuild() }.store(in: &subscriptions)
        Publishers.CombineLatest(settings.$showOnExternalDisplays, settings.$showOnUnnotchedDisplays)
            .dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }.store(in: &subscriptions)
        Publishers.CombineLatest4(coordinator.$state, coordinator.$page,
                                  coordinator.$selectedWidget, settings.$enabledModules)
            .sink { [weak self] _, _, _, _ in self?.stopMirrorWhenHidden() }
            .store(in: &subscriptions)
        widgets.activities.$primary.sink { [weak self] in self?.coordinator.present($0) }.store(in: &subscriptions)
        rebuild()
    }
    private func rebuild() {
        // Display topology changes close the preview, even if the new island
        // remains expanded on another screen.
        widgets.mirror.stop()
        windows.forEach { $0.close() }
        windows = NSScreen.screens.prefix(singleDisplay ? 1 : NSScreen.screens.count).compactMap { screen in
            let geometry = NotchDetector.geometry(for: screen)
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard settings.showOnExternalDisplays || CGDisplayIsBuiltin(id) != 0 else { return nil }
            guard geometry.hasNotch || settings.showOnUnnotchedDisplays else { return nil }
            return IslandWindowController(geometry: geometry, widgets: widgets, coordinator: coordinator)
        }
    }
    private func stopMirrorWhenHidden() {
        guard widgets.mirror.isRunning || widgets.mirror.isStarting else { return }
        let visible = coordinator.state == .expanded && settings.orderedModules.contains(.mirror) &&
            (coordinator.page == .dashboard || coordinator.page == .module && coordinator.selectedWidget == .mirror)
        if !visible { widgets.mirror.stop() }
    }
    func expand() {
        coordinator.expand()
        windows.first(where: { $0.containsPointer })?.focus() ?? windows.first?.focus()
    }
    func shutdown() { widgets.mirror.stop(); windows.forEach { $0.close() }; windows.removeAll() }
}
