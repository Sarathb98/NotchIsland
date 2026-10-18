import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickAction: Codable, Identifiable {
    enum Kind: String, Codable { case application, folder, screenshot, timer, focus, downloads, lockGuidance }
    let id: UUID
    var title: String
    let kind: Kind
    var bookmark: Data?
    var seconds: TimeInterval?
    init(title: String, kind: Kind, bookmark: Data? = nil, seconds: TimeInterval? = nil) {
        id = UUID(); self.title = title; self.kind = kind; self.bookmark = bookmark; self.seconds = seconds
    }
}

@MainActor
final class QuickActionsModel: ObservableObject {
    @Published private(set) var actions: [QuickAction]
    @Published private(set) var message: String?
    var onStartTimer: ((TimeInterval) -> Void)?
    var onStartFocus: (() -> Void)?
    private let defaults: UserDefaults
    private let storageKey = "quickActions.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode([QuickAction].self, from: data) {
            actions = saved
        } else {
            actions = Self.defaultActions
        }
    }
    private static var defaultActions: [QuickAction] {
        [.init(title: String(localized: "Screenshot"), kind: .screenshot), .init(title: String(localized: "5-minute timer"), kind: .timer, seconds: 300),
         .init(title: String(localized: "Focus session"), kind: .focus), .init(title: String(localized: "Downloads"), kind: .downloads),
         .init(title: String(localized: "Lock screen shortcut"), kind: .lockGuidance)]
    }
    func restoreDefaults() { actions = Self.defaultActions; save() }
    func addTimer(minutes: Int) {
        let minutes = min(180, max(1, minutes))
        actions.append(.init(title: String(localized: "\(minutes)-minute timer"), kind: .timer, seconds: Double(minutes * 60)))
        save()
    }
    func addLocation(application: Bool) {
        let panel = NSOpenPanel()
        panel.title = application ? String(localized: "Choose an Application") : String(localized: "Choose a Folder")
        panel.canChooseDirectories = !application
        panel.canChooseFiles = application
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = !application
        if application { panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    actions.append(.init(title: application ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent,
                                         kind: application ? .application : .folder, bookmark: bookmark))
                    message = nil
                    save()
                } catch { message = error.localizedDescription }
            }
        }
    }
    func remove(_ action: QuickAction) { actions.removeAll { $0.id == action.id }; save() }
    func rename(_ action: QuickAction, to title: String) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        actions[index].title = String(title.prefix(80)); save()
    }
    func move(_ action: QuickAction, by offset: Int) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        let target = min(actions.count - 1, max(0, index + offset))
        actions.swapAt(index, target); save()
    }
    func run(_ action: QuickAction) {
        message = nil
        switch action.kind {
        case .application, .folder:
            guard let bookmark = action.bookmark else { message = String(localized: "Choose this location again."); return }
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if stale, let index = actions.firstIndex(where: { $0.id == action.id }) {
                    actions[index].bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    save()
                }
                if !NSWorkspace.shared.open(url) { message = String(localized: "This location could not be opened. Choose it again.") }
            } catch { message = error.localizedDescription }
        case .screenshot:
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screencaptureui"), NSWorkspace.shared.open(url) else {
                message = String(localized: "Press Shift–Command–5 to open the macOS Screenshot controls."); return
            }
        case .timer:
            if let onStartTimer { onStartTimer(action.seconds ?? 300) }
            else { message = String(localized: "Timer is unavailable.") }
        case .focus:
            if let onStartFocus { onStartFocus() }
            else { message = String(localized: "Focus timer is unavailable.") }
        case .downloads:
            guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                  NSWorkspace.shared.open(url) else { message = String(localized: "The Downloads folder could not be opened."); return }
        case .lockGuidance:
            message = String(localized: "Press Control–Command–Q to lock your Mac.")
        }
    }
    private func save() {
        do { defaults.set(try JSONEncoder().encode(actions), forKey: storageKey) }
        catch { message = String(localized: "Could not save quick actions: \(error.localizedDescription)") }
    }
}

struct QuickActionsWidget: View {
    @EnvironmentObject private var coordinator: IslandCoordinator
    @ObservedObject var model: QuickActionsModel
    @State private var timerMinutes = 10
    @State private var renaming: QuickAction?
    @State private var newTitle = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Actions").font(.headline)
                Spacer()
                Menu("Add") {
                    Button("Application…") { model.addLocation(application: true) }
                    Button("Folder…") { model.addLocation(application: false) }
                    Divider()
                    Stepper("Timer: \(timerMinutes) minutes", value: $timerMinutes, in: 1...180)
                    Button("Add Timer") { model.addTimer(minutes: timerMinutes) }
                    Divider()
                    Button("Restore Defaults") { model.restoreDefaults() }
                }.fixedSize()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(model.actions) { action in
                        Button { model.run(action) } label: {
                            Label(action.title, systemImage: symbol(action.kind)).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                            .contextMenu {
                                Button("Rename…") { newTitle = action.title; renaming = action }
                                Button("Move Up") { model.move(action, by: -1) }
                                Button("Move Down") { model.move(action, by: 1) }
                                Divider()
                                Button("Remove", role: .destructive) { model.remove(action) }
                            }
                    }
                }
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.onChange(of: renaming?.id) { _, id in coordinator.setPresentationHeld(id != nil, reason: "actions.rename") }
        .onDisappear { coordinator.setPresentationHeld(false, reason: "actions.rename") }
        .alert("Rename Action", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let renaming { model.rename(renaming, to: newTitle) }; renaming = nil }
        }
    }
    private func symbol(_ kind: QuickAction.Kind) -> String {
        switch kind {
        case .application: return "app"
        case .folder: return "folder"
        case .screenshot: return "camera.viewfinder"
        case .timer: return "timer"
        case .focus: return "moon"
        case .downloads: return "arrow.down.circle"
        case .lockGuidance: return "lock"
        }
    }
}
