import SwiftUI
import Combine
import ServiceManagement

enum IslandAnimationStyle: String, CaseIterable, Identifiable {
    case spring, subtle, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spring: String(localized: "Spring")
        case .subtle: String(localized: "Subtle")
        case .none: String(localized: "None")
        }
    }
}

enum IslandAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum IslandShortcut: String, CaseIterable, Identifiable {
    case ctrlOptionSpace, cmdShiftSpace, ctrlOptionN
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ctrlOptionSpace: String(localized: "Control–Option–Space")
        case .cmdShiftSpace: String(localized: "Command–Shift–Space")
        case .ctrlOptionN: String(localized: "Control–Option–N")
        }
    }
}

@MainActor
final class IslandSettings: ObservableObject {
    static let widthRange = 680.0...1440.0
    static let defaultWidth = 1440.0
    static let defaultModuleOrder: [IslandWidget] = [.media, .mirror, .calendar, .notes, .timer, .tasks, .files,
                                                    .clipboard, .actions, .apps, .downloads, .system]
    private static let previousDashboardOrder = ["Media", "Calendar", "Notes", "Timer", "Files",
                                                  "Clipboard", "Actions", "Apps", "Downloads", "System"]
    private static let compactModuleOrder = ["Timer", "Calendar", "Files", "System", "Clipboard",
                                              "Notes", "Actions", "Apps", "Downloads", "Media"]
    private static let layoutVersion = 2
    static let hoverDelayRange = 0.0...1.0
    static let collapseDelayRange = 0.25...10.0
    static let animationSpeedRange = 0.5...2.0
    private let defaults: UserDefaults

    @Published var showOnExternalDisplays: Bool {
        didSet { defaults.set(showOnExternalDisplays, forKey: "showOnExternalDisplays") }
    }
    @Published var showOnUnnotchedDisplays: Bool {
        didSet { defaults.set(showOnUnnotchedDisplays, forKey: "showOnUnnotchedDisplays") }
    }
    @Published var islandWidth: Double {
        didSet {
            let value = Self.clamp(islandWidth, to: Self.widthRange, fallback: Self.defaultWidth)
            if islandWidth != value { islandWidth = value; return }
            defaults.set(islandWidth, forKey: "islandWidth")
        }
    }
    @Published var hoverDelay: Double {
        didSet {
            let value = Self.clamp(hoverDelay, to: Self.hoverDelayRange, fallback: 0.15)
            if hoverDelay != value { hoverDelay = value; return }
            defaults.set(hoverDelay, forKey: "hoverDelay")
        }
    }
    @Published var autoCollapseDelay: Double {
        didSet {
            let value = Self.clamp(autoCollapseDelay, to: Self.collapseDelayRange, fallback: 1.5)
            if autoCollapseDelay != value { autoCollapseDelay = value; return }
            defaults.set(autoCollapseDelay, forKey: "autoCollapseDelay")
        }
    }
    @Published var animationSpeed: Double {
        didSet {
            let value = Self.clamp(animationSpeed, to: Self.animationSpeedRange, fallback: 1)
            if animationSpeed != value { animationSpeed = value; return }
            defaults.set(animationSpeed, forKey: "animationSpeed")
        }
    }
    @Published var animationStyle: IslandAnimationStyle {
        didSet { defaults.set(animationStyle.rawValue, forKey: "animationStyle") }
    }
    @Published var appearance: IslandAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var scrollGesturesEnabled: Bool {
        didSet { defaults.set(scrollGesturesEnabled, forKey: "scrollGesturesEnabled") }
    }
    @Published var enabledModules: [String] {
        didSet {
            let normalized = Self.normalizeModules(enabledModules, includeMissing: false)
            if enabledModules != normalized { enabledModules = normalized; return }
            defaults.set(enabledModules, forKey: "enabledModules")
        }
    }
    @Published var moduleOrder: [String] {
        didSet {
            let normalized = Self.normalizeModules(moduleOrder, includeMissing: true)
            if moduleOrder != normalized { moduleOrder = normalized; return }
            defaults.set(moduleOrder, forKey: "moduleOrder")
        }
    }
    @Published var globalShortcutEnabled: Bool {
        didSet { defaults.set(globalShortcutEnabled, forKey: "globalShortcutEnabled") }
    }
    @Published var shortcutChoice: IslandShortcut {
        didSet { defaults.set(shortcutChoice.rawValue, forKey: "shortcutChoice") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    var allOrderedModules: [IslandWidget] { moduleOrder.compactMap(IslandWidget.init(rawValue:)) }
    var orderedModules: [IslandWidget] { allOrderedModules.filter { enabledModules.contains($0.rawValue) } }

    // The operating system owns this preference. A stored Boolean could falsely
    // claim the login item is enabled after permission is revoked in Settings.
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var isUpdatingLoginItem = false
    @Published private(set) var loginItemError: String?
    var launchAtLoginEnabled: Bool { launchAtLoginStatus == .enabled }
    var launchAtLoginNeedsApproval: Bool { launchAtLoginStatus == .requiresApproval }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Only untouched layouts adopt a new default. Explicit module choices
        // and nondefault widths retain their saved values across upgrades.
        let priorVersion = defaults.integer(forKey: "islandLayoutVersion")
        if priorVersion < 1 {
            if let width = defaults.object(forKey: "islandWidth") as? NSNumber,
               width.doubleValue <= 600 {
                defaults.set(Self.defaultWidth, forKey: "islandWidth")
            }
            if defaults.stringArray(forKey: "moduleOrder") == Self.compactModuleOrder {
                defaults.set(Self.defaultModuleOrder.map(\.rawValue), forKey: "moduleOrder")
            }
        }
        if priorVersion < Self.layoutVersion {
            if let width = defaults.object(forKey: "islandWidth") as? NSNumber,
               width.doubleValue == 1120 {
                defaults.set(Self.defaultWidth, forKey: "islandWidth")
            }
            if defaults.stringArray(forKey: "moduleOrder") == Self.previousDashboardOrder {
                defaults.set(Self.defaultModuleOrder.map(\.rawValue), forKey: "moduleOrder")
            }
            if defaults.stringArray(forKey: "enabledModules") == Self.compactModuleOrder ||
               defaults.stringArray(forKey: "enabledModules") == Self.previousDashboardOrder {
                defaults.set(IslandWidget.allCases.map(\.rawValue), forKey: "enabledModules")
            }
            defaults.set(Self.layoutVersion, forKey: "islandLayoutVersion")
        }
        defaults.register(defaults: [
            "showOnExternalDisplays": true, "showOnUnnotchedDisplays": true,
            "islandWidth": Self.defaultWidth, "hoverDelay": 0.15, "autoCollapseDelay": 1.5,
            "animationSpeed": 1.0, "animationStyle": IslandAnimationStyle.spring.rawValue,
            "appearance": IslandAppearance.system.rawValue, "scrollGesturesEnabled": false,
            "enabledModules": IslandWidget.allCases.map(\.rawValue), "moduleOrder": Self.defaultModuleOrder.map(\.rawValue),
            "globalShortcutEnabled": true, "shortcutChoice": IslandShortcut.ctrlOptionSpace.rawValue,
            "hasCompletedOnboarding": false
        ])
        showOnExternalDisplays = defaults.bool(forKey: "showOnExternalDisplays")
        showOnUnnotchedDisplays = defaults.bool(forKey: "showOnUnnotchedDisplays")
        islandWidth = Self.clamp(defaults.double(forKey: "islandWidth"), to: Self.widthRange, fallback: Self.defaultWidth)
        hoverDelay = Self.clamp(defaults.double(forKey: "hoverDelay"), to: Self.hoverDelayRange, fallback: 0.15)
        autoCollapseDelay = Self.clamp(defaults.double(forKey: "autoCollapseDelay"), to: Self.collapseDelayRange, fallback: 1.5)
        animationSpeed = Self.clamp(defaults.double(forKey: "animationSpeed"), to: Self.animationSpeedRange, fallback: 1)
        animationStyle = IslandAnimationStyle(rawValue: defaults.string(forKey: "animationStyle") ?? "") ?? .spring
        appearance = IslandAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        scrollGesturesEnabled = defaults.bool(forKey: "scrollGesturesEnabled")
        enabledModules = Self.normalizeModules(defaults.stringArray(forKey: "enabledModules") ?? IslandWidget.allCases.map(\.rawValue), includeMissing: false)
        moduleOrder = Self.normalizeModules(defaults.stringArray(forKey: "moduleOrder") ?? [], includeMissing: true)
        globalShortcutEnabled = defaults.bool(forKey: "globalShortcutEnabled")
        shortcutChoice = IslandShortcut(rawValue: defaults.string(forKey: "shortcutChoice") ?? "") ?? .ctrlOptionSpace
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        refreshLoginItemStatus()
    }

    func setModuleEnabled(_ module: IslandWidget, _ enabled: Bool) {
        if enabled {
            if !enabledModules.contains(module.rawValue) { enabledModules.append(module.rawValue) }
        } else { enabledModules.removeAll { $0 == module.rawValue } }
    }

    func moveModule(_ module: IslandWidget, by offset: Int) {
        guard let index = moduleOrder.firstIndex(of: module.rawValue) else { return }
        let boundedOffset = min(max(offset, -moduleOrder.count), moduleOrder.count)
        let destination = min(max(index + boundedOffset, 0), moduleOrder.count - 1)
        guard index != destination else { return }
        var updated = moduleOrder
        updated.insert(updated.remove(at: index), at: destination)
        moduleOrder = updated
    }

    func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch animationStyle {
        case .spring: return .spring(response: 0.36 / animationSpeed, dampingFraction: 0.86)
        case .subtle: return .easeInOut(duration: 0.2 / animationSpeed)
        case .none: return nil
        }
    }

    func refreshLoginItemStatus() {
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) async {
        guard !isUpdatingLoginItem else { return }
        isUpdatingLoginItem = true
        loginItemError = nil
        defer {
            refreshLoginItemStatus()
            isUpdatingLoginItem = false
        }
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status == .notRegistered || service.status == .notFound {
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try await service.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func normalizeModules(_ values: [String], includeMissing: Bool) -> [String] {
        let available = Self.defaultModuleOrder.map(\.rawValue)
        var seen = Set<String>()
        var result = values.filter { available.contains($0) && seen.insert($0).inserted }
        if includeMissing { result.append(contentsOf: available.filter { !seen.contains($0) }) }
        return result
    }
}
