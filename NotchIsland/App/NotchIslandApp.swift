import SwiftUI

@main
struct NotchIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(settings: delegate.settings, widgets: delegate.widgets) }
    }
}
