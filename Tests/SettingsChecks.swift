import Foundation

@main
struct SettingsChecks {
    @MainActor
    static func main() {
        let suiteName = "NotchIslandSettingsChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = IslandSettings(defaults: defaults)
        let allModules = IslandWidget.allCases
        let dashboardOrder: [IslandWidget] = [.media, .mirror, .calendar, .notes, .timer, .tasks, .files,
                                              .clipboard, .actions, .apps, .downloads, .system]
        precondition(settings.orderedModules == dashboardOrder, "Fresh installs enable all modules in dashboard order")
        precondition(settings.islandWidth == 1440, "Fresh installs show all six dashboard tools on a wide display")
        precondition(!settings.hasCompletedOnboarding, "Fresh installs must show onboarding")
        precondition(settings.globalShortcutEnabled && settings.shortcutChoice == .ctrlOptionSpace)

        settings.setModuleEnabled(.calendar, false)
        precondition(!settings.orderedModules.contains(.calendar))
        precondition(settings.allOrderedModules.contains(.calendar), "Disabling must preserve module ordering")
        settings.moveModule(.media, by: -100)
        precondition(settings.allOrderedModules.first == .media, "Moving clamps at the start")
        settings.moveModule(.media, by: Int.max)
        precondition(settings.allOrderedModules.last == .media, "Moving clamps at the end without integer overflow")
        settings.moveModule(.timer, by: 1)
        precondition(settings.allOrderedModules[4] == .timer, "Move must retain all modules")
        settings.setModuleEnabled(.calendar, true)
        settings.setModuleEnabled(.calendar, true)
        precondition(settings.enabledModules.filter { $0 == IslandWidget.calendar.rawValue }.count == 1)

        settings.moduleOrder = [IslandWidget.media.rawValue, "Removed module", IslandWidget.media.rawValue]
        precondition(settings.allOrderedModules.first == .media)
        precondition(Set(settings.moduleOrder) == Set(allModules.map(\.rawValue)))
        precondition(settings.moduleOrder.count == allModules.count, "Unknown keys and duplicates must be removed")
        settings.enabledModules = [IslandWidget.files.rawValue, "Removed module", IslandWidget.files.rawValue]
        precondition(settings.orderedModules == [.files])
        settings.setModuleEnabled(.files, false)
        precondition(settings.orderedModules.isEmpty, "Disabling all modules must be a valid persisted choice")
        settings.shortcutChoice = .ctrlOptionN
        settings.globalShortcutEnabled = false
        settings.hasCompletedOnboarding = true
        settings.islandWidth = .nan
        settings.hoverDelay = .infinity
        settings.animationSpeed = -100
        precondition(settings.islandWidth == 1440 && settings.hoverDelay == 0.15 && settings.animationSpeed == 0.5)
        let restored = IslandSettings(defaults: defaults)
        precondition(restored.orderedModules.isEmpty && restored.moduleOrder == settings.moduleOrder)
        precondition(restored.hasCompletedOnboarding && !restored.globalShortcutEnabled && restored.shortcutChoice == .ctrlOptionN)
        precondition(restored.islandWidth == 1440 && restored.hoverDelay == 0.15 && restored.animationSpeed == 0.5)

        defaults.set("Invalid shortcut", forKey: "shortcutChoice")
        defaults.set(["Removed module", IslandWidget.media.rawValue, IslandWidget.media.rawValue], forKey: "moduleOrder")
        let repaired = IslandSettings(defaults: defaults)
        precondition(repaired.shortcutChoice == .ctrlOptionSpace, "Unknown shortcut choices must fall back")
        precondition(repaired.allOrderedModules.first == .media && repaired.moduleOrder.count == allModules.count)
        defaults.removeObject(forKey: "islandLayoutVersion")
        defaults.set(420.0, forKey: "islandWidth")
        defaults.set(["Timer", "Calendar", "Files", "System", "Clipboard", "Notes",
                      "Actions", "Apps", "Downloads", "Media"], forKey: "moduleOrder")
        let migrated = IslandSettings(defaults: defaults)
        precondition(migrated.islandWidth == 1440, "Existing compact widths migrate to the dashboard default")
        precondition(defaults.integer(forKey: "islandLayoutVersion") == 2, "Migration is recorded")
        precondition(migrated.orderedModules.isEmpty && migrated.hasCompletedOnboarding,
                     "Layout migration preserves module and onboarding preferences")
        precondition(migrated.allOrderedModules == dashboardOrder,
                     "The legacy untouched module order adopts the dashboard arrangement")
        migrated.islandWidth = 680
        let secondLaunch = IslandSettings(defaults: defaults)
        precondition(secondLaunch.islandWidth == 680, "Subsequent launches retain a chosen dashboard width")
        defaults.set(500.0, forKey: "islandWidth")
        let repairedWidth = IslandSettings(defaults: defaults)
        precondition(repairedWidth.islandWidth == 680, "After migration, invalid widths clamp instead of resetting")
        defaults.removeObject(forKey: "islandLayoutVersion")
        defaults.set(1260.0, forKey: "islandWidth")
        let customOrder = Array(allModules.reversed())
        defaults.set(customOrder.map(\.rawValue), forKey: "moduleOrder")
        let alreadyWide = IslandSettings(defaults: defaults)
        precondition(alreadyWide.islandWidth == 1260, "Migration preserves an already valid wide preference")
        precondition(alreadyWide.allOrderedModules == customOrder, "Migration preserves custom module arrangements")

        let legacySuite = "NotchIslandSettingsLegacyChecks.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        legacyDefaults.set(1, forKey: "islandLayoutVersion")
        legacyDefaults.set(1120.0, forKey: "islandWidth")
        legacyDefaults.set(["Media", "Calendar", "Notes", "Timer", "Files", "Clipboard",
                            "Actions", "Apps", "Downloads", "System"], forKey: "moduleOrder")
        legacyDefaults.set(["Timer", "Calendar", "Files", "System", "Clipboard", "Notes",
                            "Actions", "Apps", "Downloads", "Media"], forKey: "enabledModules")
        let upgraded = IslandSettings(defaults: legacyDefaults)
        precondition(upgraded.islandWidth == 1440 && upgraded.orderedModules == dashboardOrder,
                     "An untouched dashboard adopts visible Mirror and Tasks")
        precondition(legacyDefaults.integer(forKey: "islandLayoutVersion") == 2)

        legacyDefaults.set(1, forKey: "islandLayoutVersion")
        legacyDefaults.set(1260.0, forKey: "islandWidth")
        legacyDefaults.set(["Notes", "Timer"], forKey: "enabledModules")
        legacyDefaults.set(["Notes", "Timer", "Media"], forKey: "moduleOrder")
        let customized = IslandSettings(defaults: legacyDefaults)
        precondition(customized.islandWidth == 1260 && customized.orderedModules == [.notes, .timer],
                     "Upgrade preserves explicit width and enabled-module choices")
        precondition(Array(customized.allOrderedModules.prefix(3)) == [.notes, .timer, .media],
                     "Upgrade preserves a custom ordering")
        print("Settings checks passed: persistence, module order, normalization, dashboard migrations")
    }
}
