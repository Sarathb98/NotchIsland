import SwiftUI

struct ExpandedIsland: View {
    let widgets: WidgetStore
    @ObservedObject var settings: IslandSettings
    let topInset: CGFloat
    let notchWidth: CGFloat
    let collapse: () -> Void
    @Binding var selection: IslandWidget
    @EnvironmentObject private var coordinator: IslandCoordinator

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: max(32, topInset))
            Group {
                switch coordinator.page {
                case .dashboard:
                    IslandDashboard(widgets: widgets, settings: settings, openModule: openModule)
                        .accessibilityIdentifier("island.dashboard")
                case .tray:
                    FileShelfWidget(model: widgets.dropZone)
                        .accessibilityIdentifier("island.tray")
                case .module:
                    moduleContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .onChange(of: settings.enabledModules) { _, _ in selectEnabledModule() }
        .onAppear { selectEnabledModule() }
    }

    private var header: some View {
        GeometryReader { proxy in
            let wing = max(0, (proxy.size.width - notchWidth) / 2 - 24)
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Button { coordinator.showDashboard() } label: {
                        Label("Island", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .buttonStyle(IslandTabStyle(selected: coordinator.page == .dashboard))
                    .accessibilityIdentifier("island.tab.dashboard")
                    .accessibilityValue(coordinator.page == .dashboard ? String(localized: "Selected") : "")
                    if settings.orderedModules.contains(.files) {
                        Button { coordinator.showTray() } label: { Label("Tray", systemImage: "tray.fill") }
                            .buttonStyle(IslandTabStyle(selected: coordinator.page == .tray))
                            .accessibilityIdentifier("island.tab.tray")
                            .accessibilityValue(coordinator.page == .tray ? String(localized: "Selected") : "")
                    }
                }
                .frame(width: wing, alignment: .leading)
                Spacer(minLength: notchWidth)
                HStack(spacing: 12) {
                    if proxy.size.width > 850 { BatteryView(model: widgets.battery) }
                    Menu {
                        ForEach(settings.orderedModules) { widget in
                            Button { openModule(widget) } label: { Label(widget.title, systemImage: widget.symbol) }
                        }
                    } label: { Image(systemName: "square.grid.2x2").frame(width: 22, height: 26) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Modules").help("All modules")
                        .accessibilityIdentifier("module.picker")
                    Button {
                        NotificationCenter.default.post(name: Notification.Name("NotchIsland.showSettings"), object: nil)
                    } label: { Image(systemName: "gearshape.fill") }
                        .buttonStyle(IslandIconButtonStyle()).accessibilityLabel("Settings").help("Settings")
                    Button(action: collapse) { Image(systemName: "chevron.up") }
                        .buttonStyle(IslandIconButtonStyle()).accessibilityLabel("Collapse island").help("Collapse island")
                }
                .foregroundStyle(.secondary)
                .frame(width: wing, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: proxy.size.height)
        }
    }

    private var moduleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: selection.symbol).foregroundStyle(.blue)
                Text(selection.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date, style: .time).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Divider().overlay(.white.opacity(0.08))
            Group {
                if settings.orderedModules.isEmpty {
                    ContentUnavailableView("Choose Your Modules", systemImage: "square.grid.2x2", description: Text("Enable modules in Settings to personalize your island."))
                } else {
                    switch selection {
                    case .timer: ProductivityTimerWidget(model: widgets.timer)
                    case .calendar: CalendarPreviewWidget(model: widgets.calendar)
                    case .files: FileShelfWidget(model: widgets.dropZone)
                    case .clipboard: ClipboardWidget(model: widgets.clipboard)
                    case .notes: NotesWidget(model: widgets.notes)
                    case .actions: QuickActionsWidget(model: widgets.actions)
                    case .apps: AppLauncherWidget(model: widgets.launcher)
                    case .downloads: DownloadsWidget(model: widgets.downloads)
                    case .media: MediaWidget(model: widgets.media)
                    case .mirror: CameraMirrorWidget(model: widgets.mirror, height: 240)
                    case .tasks: TaskListWidget(model: widgets.tasks, height: 240)
                    case .system: SystemWidget(system: widgets.system, audio: widgets.audio, recorder: widgets.recorder)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 560, maxHeight: .infinity, alignment: .top)
    }

    private func openModule(_ module: IslandWidget) {
        if module == .files { coordinator.showTray() }
        else { coordinator.showModule(module) }
    }
    private func selectEnabledModule() {
        if coordinator.page == .tray && !settings.orderedModules.contains(.files) { coordinator.showDashboard() }
        if !settings.orderedModules.contains(selection), let first = settings.orderedModules.first { selection = first }
    }
}

struct BatteryView: View {
    @ObservedObject var model: BatteryMonitor
    var body: some View {
        HStack(spacing: 5) {
            Text(model.percentage.map { "\($0)%" } ?? "AC").monospacedDigit()
            Image(systemName: model.powerState == .charging ? "battery.100percent.bolt" : "battery.100percent")
                .foregroundStyle(model.powerState == .charging ? Color.green : Color.secondary)
        }.font(.system(size: 10, weight: .medium)).help(model.status)
            .accessibilityLabel("\(model.percentage.map { String(localized: "\($0) percent") } ?? String(localized: "No battery")), \(model.status)")
    }
}

extension IslandWidget {
    var symbol: String {
        switch self {
        case .timer: "timer"
        case .calendar: "calendar"
        case .files: "tray.fill"
        case .system: "gauge.with.dots.needle.50percent"
        case .clipboard: "doc.on.clipboard"
        case .notes: "note.text"
        case .actions: "bolt.fill"
        case .apps: "square.grid.2x2"
        case .downloads: "arrow.down.circle"
        case .media: "music.note"
        case .mirror: "web.camera"
        case .tasks: "checklist"
        }
    }
}
