import AppKit
import SwiftUI
import Combine
import OSLog

enum AppRuntime {
    static let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    static let defaults: UserDefaults = {
        guard isTesting else { return .standard }
        let suite = "com.notchisland.ui-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = IslandSettings(defaults: AppRuntime.defaults)
    lazy var widgets = WidgetStore(isTesting: AppRuntime.isTesting, defaults: AppRuntime.defaults)
    private var screenManager: ScreenManager?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var shortcut: ShortcutController?
    private var subscriptions = Set<AnyCancellable>()
    private var isTerminating = false
    private let logger = Logger(subsystem: "com.notchisland.app", category: "Lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if AppRuntime.isTesting {
            settings.animationStyle = .none
            settings.autoCollapseDelay = 10
            settings.showOnExternalDisplays = true
            settings.showOnUnnotchedDisplays = true
            settings.globalShortcutEnabled = false
            settings.hasCompletedOnboarding = true
        }
        screenManager = ScreenManager(settings: settings, widgets: widgets, singleDisplay: AppRuntime.isTesting)
        NotificationCenter.default.publisher(for: Notification.Name("NotchIsland.showSettings"))
            .sink { [weak self] _ in self?.showSettings() }.store(in: &subscriptions)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch Island")
        item.button?.setAccessibilityIdentifier("island.status")
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Show Island"), action: #selector(showIsland), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: String(localized: "Welcome & Permissions…"), action: #selector(showOnboarding), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Quit Notch Island"), action: #selector(quit), keyEquivalent: "q")
        for entry in menu.items { entry.target = self }
        item.menu = menu
        statusItem = item
        shortcut = ShortcutController { [weak self] in self?.showIsland() }
        Publishers.CombineLatest(settings.$globalShortcutEnabled, settings.$shortcutChoice)
            .receive(on: RunLoop.main).sink { [weak self] enabled, choice in
                self?.shortcut?.configure(enabled: enabled, choice: choice)
            }.store(in: &subscriptions)
        shortcut?.$error.compactMap { $0 }.sink { [weak self] message in
            self?.widgets.activities.post(id: "shortcut.error", title: String(localized: "Shortcut unavailable"), detail: message, symbol: "keyboard", priority: .userAction, duration: 8)
        }.store(in: &subscriptions)
        if ProcessInfo.processInfo.arguments.contains("--expanded") { showIsland() }
        if !settings.hasCompletedOnboarding && !ProcessInfo.processInfo.arguments.contains("--skip-onboarding") { showOnboarding() }
        logger.info("Notch Island started")
    }
    @objc private func showIsland() { screenManager?.expand() }
    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 560),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = String(localized: "Notch Island Settings")
            window.setAccessibilityIdentifier("settings.window")
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings, widgets: widgets))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)
        if onboardingWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 668, height: 578),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = String(localized: "Welcome to Notch Island")
            window.contentView = NSHostingView(rootView: OnboardingView(settings: settings, widgets: widgets) { [weak self] in
                self?.onboardingWindow?.close(); self?.showIsland()
            })
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateCancel }
        guard widgets.recorder.state != .idle || widgets.downloads.isBusy || widgets.dropZone.isImporting || !widgets.dropZone.busyItems.isEmpty else { return .terminateNow }
        isTerminating = true
        Task { [weak self] in
            guard let self else { NSApp.reply(toApplicationShouldTerminate: false); return }
            let canQuit = await widgets.prepareForTermination()
            isTerminating = false
            if !canQuit {
                let alert = NSAlert()
                alert.messageText = String(localized: "Finish the current operation before quitting")
                alert.informativeText = String(localized: "Close any open file dialog, or stop the recording and allow the file to finish saving, then try again.")
                alert.addButton(withTitle: String(localized: "OK"))
                alert.runModal()
            }
            NSApp.reply(toApplicationShouldTerminate: canQuit)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        shortcut?.stop()
        screenManager?.shutdown()
        widgets.shutdown()
        logger.info("Notch Island stopped")
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
