import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", island = "Island", modules = "Modules"
    case shortcuts = "Shortcuts", calendar = "Calendar", files = "Files", clipboard = "Clipboard"
    case media = "Media", advanced = "Advanced", about = "About"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .island: String(localized: "Island")
        case .modules: String(localized: "Modules")
        case .shortcuts: String(localized: "Shortcuts")
        case .calendar: String(localized: "Calendar")
        case .files: String(localized: "Files")
        case .clipboard: String(localized: "Clipboard")
        case .media: String(localized: "Media")
        case .advanced: String(localized: "Advanced")
        case .about: String(localized: "About")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .island: "rectangle.topthird.inset.filled"
        case .modules: "square.grid.2x2"
        case .shortcuts: "keyboard"
        case .calendar: "calendar"
        case .files: "tray"
        case .clipboard: "doc.on.clipboard"
        case .media: "play.rectangle"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: IslandSettings
    let widgets: WidgetStore?
    @State private var selection: SettingsSection? = .general

    init(settings: IslandSettings, widgets: WidgetStore? = nil) {
        self.settings = settings
        self.widgets = widgets
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 200)
        } detail: {
            Form { selectedSection }
                .formStyle(.grouped)
                .navigationTitle((selection ?? .general).title)
        }
        .frame(minWidth: 700, minHeight: 520)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear { settings.refreshLoginItemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLoginItemStatus()
        }
    }

    @ViewBuilder private var selectedSection: some View {
        switch selection ?? .general {
        case .general: generalSettings
        case .appearance: appearanceSettings
        case .island: islandSettings
        case .modules: moduleSettings
        case .shortcuts: shortcutSettings
        case .calendar:
            if let widgets { CalendarSettingsPane(model: widgets.calendar) }
            else { Text("Calendar controls are available while Notch Island is running.") }
        case .files:
            if let widgets { FileSettingsPane(model: widgets.dropZone) }
            else { Text("The file shelf stores temporary copies. Pin a copy to keep it after relaunching.") }
        case .clipboard:
            if let widgets { ClipboardSettingsPane(model: widgets.clipboard) }
            else { Text("Clipboard history is optional and starts paused at every launch.") }
        case .media:
            Section("Media Integration") {
                Label("Local media", systemImage: "music.note")
                Text("Open an audio or video file in the Media module to see its title, artwork, progress, and available playback controls.")
                Text("Media adapters use supported public APIs. Playback in unrelated apps is only available through a separately supported integration.")
                    .foregroundStyle(.secondary)
            }
            Section("Camera Mirror") {
                Label("Live mirror", systemImage: "web.camera")
                Text("Choose Start Mirror in the island to request camera access. The preview is live and horizontally mirrored. It stops when you close the island or leave Mirror, and no video is saved.")
                    .foregroundStyle(.secondary)
            }
        case .advanced: advancedSettings
        case .about: aboutSettings
        }
    }

    private var generalSettings: some View {
        Group {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLoginEnabled || settings.launchAtLoginNeedsApproval },
                    set: { enabled in Task { await settings.setLaunchAtLogin(enabled) } }
                )).disabled(settings.isUpdatingLoginItem)
                if settings.launchAtLoginNeedsApproval {
                    Button("Open Login Items…") { settings.openLoginItemSettings() }
                    Text("Allow Notch Island in System Settings to finish enabling launch at login.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = settings.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            Section("Displays") {
                Toggle("Show on external displays", isOn: $settings.showOnExternalDisplays)
                Toggle("Show on displays without a notch", isOn: $settings.showOnUnnotchedDisplays)
                Text("On a display without a notch, the island sits at the top center of the screen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSettings: some View {
        Group {
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(IslandAppearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }
                Text("Settings follow this appearance. The island stays black to blend into the notch.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Animation") {
                Picker("Style", selection: $settings.animationStyle) {
                    ForEach(IslandAnimationStyle.allCases) { style in Text(style.title).tag(style) }
                }
                slider("Speed", value: $settings.animationSpeed, range: IslandSettings.animationSpeedRange,
                       step: 0.25, display: String(format: "%.2f×", settings.animationSpeed))
                    .disabled(settings.animationStyle == .none)
                Text("Animations follow macOS Reduce Motion. Surfaces follow Reduce Transparency and Increase Contrast.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var islandSettings: some View {
        Group {
            Section("Size and Timing") {
                slider("Expanded width", value: $settings.islandWidth, range: IslandSettings.widthRange,
                       step: 10, display: "\(Int(settings.islandWidth)) pt")
                slider("Hover delay", value: $settings.hoverDelay, range: IslandSettings.hoverDelayRange,
                       step: 0.05, display: String(format: "%.2f s", settings.hoverDelay))
                slider("Auto-collapse delay", value: $settings.autoCollapseDelay, range: IslandSettings.collapseDelayRange,
                       step: 0.25, display: String(format: "%.2f s", settings.autoCollapseDelay))
                Text("Collapsed dimensions follow the display’s safe area and physical notch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Interaction") {
                Toggle("Use scroll gestures to expand and collapse", isOn: $settings.scrollGesturesEnabled)
                Text("Hover to preview, click to expand, and press Escape or click outside to collapse. Right-click the island for its context menu.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var moduleSettings: some View {
        Section {
            ForEach(settings.allOrderedModules) { module in
                HStack {
                    Toggle(module.title, isOn: Binding(
                        get: { settings.enabledModules.contains(module.rawValue) },
                        set: { settings.setModuleEnabled(module, $0) }
                    ))
                    Spacer()
                    Button { settings.moveModule(module, by: -1) } label: { Image(systemName: "chevron.up") }
                        .disabled(settings.allOrderedModules.first == module)
                        .accessibilityLabel("Move \(module.title) up")
                    Button { settings.moveModule(module, by: 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(settings.allOrderedModules.last == module)
                        .accessibilityLabel("Move \(module.title) down")
                }.buttonStyle(.borderless)
            }
        } header: {
            Text("Enabled Modules and Order")
        } footer: {
            Text("Choose which modules appear in the island. Use the arrow buttons to arrange them. Clipboard collection and system permissions are controlled separately.")
        }
    }

    private var shortcutSettings: some View {
        Group {
            Section("Show Island") {
                Toggle("Enable global keyboard shortcut", isOn: $settings.globalShortcutEnabled)
                Picker("Shortcut", selection: $settings.shortcutChoice) {
                    ForEach(IslandShortcut.allCases) { shortcut in Text(shortcut.title).tag(shortcut) }
                }.disabled(!settings.globalShortcutEnabled)
            }
            Section("Keyboard Navigation") {
                LabeledContent("Collapse", value: "Escape")
                LabeledContent("Next control", value: "Tab")
                LabeledContent("Previous control", value: "Shift–Tab")
                Text("Enable Keyboard Navigation in macOS System Settings to move focus through all native controls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSettings: some View {
        Group {
            Section("Setup") {
                Button("Show Welcome on Next Launch") { settings.hasCompletedOnboarding = false }
                if !settings.hasCompletedOnboarding {
                    Text("The welcome guide will appear the next time you launch Notch Island.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Privacy and Performance") {
                Text("No analytics or telemetry is collected.")
                Text("System usage and device status are sampled while their panels are visible. Clipboard monitoring runs only when explicitly enabled.")
                Text("Camera Mirror starts only when you choose Start Mirror and never saves video. Calendar, Bluetooth, camera, screen recording, and file access follow macOS permission controls. You can revoke access in System Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSettings: some View {
        Section {
            Label("Notch Island", systemImage: "rectangle.topthird.inset.filled").font(.title2.weight(.semibold))
            Text("A native productivity surface for your Mac.").foregroundStyle(.secondary)
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
            Text("Built with SwiftUI and AppKit. Not affiliated with Apple.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: range, step: step).frame(maxWidth: 170).accessibilityLabel(Text(title))
            Text(display).monospacedDigit().frame(width: 55, alignment: .trailing)
        }
    }
}

private struct CalendarSettingsPane: View {
    @ObservedObject var model: CalendarModel
    var body: some View {
        Section("Calendar Access") {
            LabeledContent("Status", value: model.isAuthorized ? String(localized: "Allowed") : String(localized: "Not allowed"))
            Text("Preview upcoming events in the next 24 hours, meeting countdowns, and available meeting links.").foregroundStyle(.secondary)
            if model.canRequestAccess {
                Button("Connect Calendar…") { Task { await model.requestAccess() } }.disabled(model.requesting)
            } else if !model.isAuthorized {
                Button("Open System Settings…") { model.openSystemSettings() }
            } else {
                LabeledContent("Upcoming events", value: "\(model.upcoming.count)")
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
    }
}

private struct FileSettingsPane: View {
    @ObservedObject var model: DropZoneModel
    var body: some View {
        Section("File Shelf") {
            LabeledContent("Files on shelf", value: "\(model.items.count)")
            LabeledContent("Pinned copies", value: "\(model.items.filter(\.isPinned).count)")
            Text("Dropped files are copied into app-owned storage. Temporary copies are removed when you quit. Pinned copies survive relaunching; originals stay in place.")
                .foregroundStyle(.secondary)
            Text("Up to 50 regular files, 200 MB per file. Folders and symbolic links are not accepted.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear Unpinned Copies", role: .destructive) { model.clear() }
                .disabled(!model.items.contains { !$0.isPinned })
            if let error = model.error { Text(error).foregroundStyle(.red) }
        }
    }
}

private struct ClipboardSettingsPane: View {
    @ObservedObject var model: ClipboardModel
    var body: some View {
        Group {
            Section("Clipboard History") {
                Toggle("Collect new copies", isOn: Binding(get: { model.enabled }, set: model.setEnabled))
                Text("History starts paused at each launch. Text, URLs, images, and file references stay in memory and are cleared when you quit.")
                    .foregroundStyle(.secondary)
                LabeledContent("Saved items", value: "\(model.items.count)")
                Button("Clear History and Favorites", role: .destructive) { model.clear() }.disabled(model.items.isEmpty)
            }
            Section("Privacy Exclusions") {
                TextField("Excluded application bundle IDs", text: $model.excludedBundleIDs, axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.roundedBorder)
                Text("Separate bundle IDs with commas or newlines. Example: com.apple.Terminal")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Known password managers and items marked confidential or transient are skipped. Source detection follows the foreground app and cannot identify every sensitive copy.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Up to 100 items, 5 MB per item, and 32 MB total.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
