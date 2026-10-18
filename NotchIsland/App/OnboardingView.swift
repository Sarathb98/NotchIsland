import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: IslandSettings
    let widgets: WidgetStore
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Welcome to Notch Island", systemImage: "rectangle.topthird.inset.filled").font(.largeTitle.weight(.semibold))
            Text("Your mirror, tasks, timer, files, and notes, just below the notch.")
                .font(.title3).foregroundStyle(.secondary)
            Form {
                Section("Get around") {
                    Label("Hover to preview. Click to open.", systemImage: "cursorarrow")
                    Label("Press Escape or click outside to close.", systemImage: "escape")
                    Label("Use the menu-bar icon or your configured shortcut to open the island from the keyboard.", systemImage: "keyboard")
                }
                Section("Choose what to connect") {
                    OnboardingCalendar(model: widgets.calendar)
                    Text("Clipboard history starts off at each launch. Enable it in the Clipboard module when you want to collect new copies.")
                    Text("Camera Mirror requests access only when you choose Start Mirror. Its live preview is not recorded. Bluetooth and screen recording use their own controls. No access is requested during setup.")
                }
                Section("Start with your Mac") {
                    Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLoginEnabled || settings.launchAtLoginNeedsApproval }, set: { enabled in Task { await settings.setLaunchAtLogin(enabled) } }))
                        .disabled(settings.isUpdatingLoginItem)
                    if let error = settings.loginItemError { Text(error).foregroundStyle(.secondary) }
                    if settings.launchAtLoginNeedsApproval { Button("Approve in Login Items…") { settings.openLoginItemSettings() } }
                }
            }.formStyle(.grouped)
            HStack {
                Text("Stored locally. No analytics or telemetry.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Get Started") { settings.hasCompletedOnboarding = true; finish() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620, height: 530)
            .preferredColorScheme(settings.appearance.colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refreshLoginItemStatus() }
    }
}

private struct OnboardingCalendar: View {
    @ObservedObject var model: CalendarModel
    var body: some View {
        HStack {
            Label("Calendar preview", systemImage: "calendar")
            Spacer()
            if model.isAuthorized { Text("Connected").foregroundStyle(.secondary) }
            else if model.canRequestAccess { Button("Connect…") { Task { await model.requestAccess() } }.disabled(model.requesting) }
            else { Button("Open Privacy Settings…", action: model.openSystemSettings) }
        }
    }
}
