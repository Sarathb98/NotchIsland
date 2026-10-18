import AppKit
import SwiftUI

struct LaunchableApplication: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let name: String
    let url: URL
}

@MainActor
final class AppLauncherModel: ObservableObject {
    @Published private(set) var applications: [LaunchableApplication] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published var query = "" { didSet { selectedID = filtered.first?.id } }
    @Published var selectedID: URL?
    var filtered: [LaunchableApplication] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? applications : applications.filter { $0.name.localizedStandardContains(query) }
    }
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        let found = await Task.detached(priority: .utility) {
            var found: [LaunchableApplication] = []
            var seen = Set<URL>()
            let manager = FileManager.default
            for root in roots {
                guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                while let url = enumerator.nextObject() as? URL {
                    if Task.isCancelled { break }
                    if enumerator.level > 5 { enumerator.skipDescendants(); continue }
                    guard url.pathExtension.lowercased() == "app", seen.insert(url.standardizedFileURL).inserted else { continue }
                    let bundle = Bundle(url: url)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? url.deletingPathExtension().lastPathComponent
                    found.append(.init(name: name, url: url))
                }
            }
            return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }.value
        applications = found
        selectedID = filtered.first?.id
        isLoading = false
    }
    func moveSelection(by offset: Int) {
        let list = filtered
        guard !list.isEmpty else { selectedID = nil; return }
        let index = selectedID.flatMap { id in list.firstIndex { $0.id == id } } ?? 0
        selectedID = list[min(list.count - 1, max(0, index + offset))].id
    }
    func launchSelected() {
        guard let app = filtered.first(where: { $0.id == selectedID }) ?? filtered.first else { return }
        launch(app)
    }
    func launch(_ app: LaunchableApplication) {
        error = nil
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init()) { [weak self] _, failure in
            guard let failure else { return }
            Task { @MainActor [weak self] in self?.error = failure.localizedDescription }
        }
    }
}

struct AppLauncherWidget: View {
    @ObservedObject var model: AppLauncherModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search applications", text: $model.query)
                    .textFieldStyle(.roundedBorder).focused($searchFocused)
                    .onSubmit { model.launchSelected() }
                    .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isLoading).help("Refresh applications").accessibilityLabel("Refresh applications")
            }
            if model.isLoading { ProgressView("Finding applications…").controlSize(.small) }
            ScrollViewReader { proxy in
                List(selection: $model.selectedID) {
                    ForEach(model.filtered) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                            Spacer()
                            Button("Open") { model.launch(app) }.controlSize(.small)
                        }.tag(app.id).id(app.id)
                            .contextMenu { Button("Open") { model.launch(app) }; Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } }
                    }
                }.listStyle(.plain)
                    .onChange(of: model.selectedID) { _, selected in if let selected { proxy.scrollTo(selected, anchor: .center) } }
                    .onKeyPress(.return) { model.launchSelected(); return .handled }
            }
            if !model.isLoading && model.filtered.isEmpty { Text("No matching applications").font(.caption).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.task {
            if model.applications.isEmpty { await model.refresh() }
            searchFocused = true
        }
    }
}
