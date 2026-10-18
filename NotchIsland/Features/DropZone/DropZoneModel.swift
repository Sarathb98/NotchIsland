import AppKit
import Darwin
import UniformTypeIdentifiers

struct ShelfFile: Identifiable, Codable, Equatable {
    let id: UUID
    var url: URL
    var isPinned: Bool
    let addedAt: Date
}

@MainActor
final class DropZoneModel: ObservableObject {
    @Published private(set) var files: [URL] = []
    @Published private(set) var items: [ShelfFile] = []
    @Published private(set) var error: String?
    @Published private(set) var pendingImports = 0
    @Published private(set) var busyItems: Set<UUID> = []
    var isImporting: Bool { pendingImports > 0 }
    private let storageURL: URL
    private let temporaryURL: URL
    private var sessionLockFD: Int32?
    private static let sessionMarker = "NotchIslandShelfSession-v1\n"
    private var generation = 0
    private var shuttingDown = false
    private let maximumFiles = 50
    private let maximumBytes = 200 * 1_024 * 1_024

    init(storageURL: URL? = nil, temporaryURL: URL? = nil) {
        self.storageURL = (storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland/FileShelf", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        self.temporaryURL = (temporaryURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchIsland/Shelf/\(UUID().uuidString)", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        if let root = Self.managedShelfRoot(for: self.temporaryURL) {
            sessionLockFD = Self.lockNewSession(at: self.temporaryURL, in: root)
            if sessionLockFD != nil { Self.removeStaleSessions(in: root, excluding: self.temporaryURL) }
        }
        let manifest = self.storageURL.appendingPathComponent("PinnedFiles.json")
        if let data = try? Data(contentsOf: manifest), let saved = try? JSONDecoder().decode([ShelfFile].self, from: data) {
            var restoredIDs = Set<UUID>()
            items = Array(saved.filter { item in
                let expected = self.storageURL.appendingPathComponent("Pinned", isDirectory: true)
                    .appendingPathComponent(item.id.uuidString, isDirectory: true).appendingPathComponent(item.url.lastPathComponent)
                let validPath = item.url.isFileURL && item.url.standardizedFileURL == expected.standardizedFileURL &&
                    item.url.resolvingSymlinksInPath().standardizedFileURL == expected.standardizedFileURL
                let values = try? item.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return item.isPinned && validPath && values?.isRegularFile == true && values?.isSymbolicLink != true && restoredIDs.insert(item.id).inserted
            }.prefix(maximumFiles))
            files = items.map(\.url)
        }
    }

    deinit {
        if let sessionLockFD { _ = Darwin.close(sessionLockFD) }
    }

    private static func managedShelfRoot(for session: URL) -> URL? {
        guard let id = UUID(uuidString: session.lastPathComponent), id.uuidString == session.lastPathComponent else { return nil }
        let root = session.deletingLastPathComponent()
        guard root.lastPathComponent == "Shelf", root.deletingLastPathComponent().lastPathComponent == "NotchIsland" else { return nil }
        return root
    }

    private static func lockNewSession(at session: URL, in root: URL) -> Int32? {
        let manager = FileManager.default
        do { try manager.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { return nil }
        guard Darwin.mkdir(session.path, 0o700) == 0 else { return nil }
        let marker = session.appendingPathComponent(".session.lock")
        let descriptor = Darwin.open(marker.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK, 0o600)
        guard descriptor >= 0 else { try? manager.removeItem(at: session); return nil }
        let bytes = Array(sessionMarker.utf8)
        let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard written == bytes.count else {
            _ = Darwin.close(descriptor)
            try? manager.removeItem(at: session)
            return nil
        }
        return descriptor
    }

    private static func removeStaleSessions(in root: URL, excluding current: URL) {
        let manager = FileManager.default
        guard let candidates = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for candidate in candidates where candidate.standardizedFileURL != current.standardizedFileURL {
            guard managedShelfRoot(for: candidate)?.standardizedFileURL == root.standardizedFileURL else { continue }
            var directoryInfo = Darwin.stat()
            guard Darwin.lstat(candidate.path, &directoryInfo) == 0,
                  directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { continue }
            let marker = candidate.appendingPathComponent(".session.lock")
            let descriptor = Darwin.open(marker.path, O_RDONLY | O_NOFOLLOW | O_EXLOCK | O_NONBLOCK)
            guard descriptor >= 0 else { continue }
            defer { _ = Darwin.close(descriptor) }
            var markerInfo = Darwin.stat()
            guard Darwin.fstat(descriptor, &markerInfo) == 0,
                  markerInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  markerInfo.st_size == sessionMarker.utf8.count else { continue }
            var bytes = [UInt8](repeating: 0, count: sessionMarker.utf8.count)
            let readCount = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            guard readCount == bytes.count, String(bytes: bytes, encoding: .utf8) == sessionMarker else { continue }
            try? manager.removeItem(at: candidate)
        }
    }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        guard !shuttingDown else { return false }
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        let available = max(0, maximumFiles - items.count - pendingImports)
        if supported.count > available { error = String(localized: "The shelf holds up to 50 files.") }
        for provider in supported.prefix(available) {
            pendingImports += 1
            let requestGeneration = generation
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard let url, url.isFileURL else {
                        self.pendingImports -= 1
                        self.cleanupTemporaryFilesIfIdle()
                        self.error = String(localized: "Could not read the dropped file.")
                        return
                    }
                    await self.importFile(url, generation: requestGeneration)
                }
            }
        }
        return !supported.isEmpty && available > 0
    }

    func importFiles(_ urls: [URL]) {
        guard !shuttingDown else { return }
        let available = max(0, maximumFiles - items.count - pendingImports)
        if urls.count > available { error = String(localized: "The shelf holds up to 50 files.") }
        for url in urls.prefix(available) {
            pendingImports += 1
            let requestGeneration = generation
            Task { await importFile(url, generation: requestGeneration) }
        }
    }

    private func importFile(_ source: URL, generation requestGeneration: Int) async {
        defer { pendingImports -= 1; cleanupTemporaryFilesIfIdle() }
        guard requestGeneration == generation else { return }
        let id = UUID()
        let destination = temporaryURL.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(source.lastPathComponent)
        let byteLimit = maximumBytes
        do {
            try await Task.detached(priority: .utility) {
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw ShelfError.unsupportedFile
                }
                guard let size = values.fileSize, size <= byteLimit else { throw ShelfError.fileTooLarge }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
                let copiedValues = try destination.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
                guard copiedValues.isRegularFile == true, copiedValues.isSymbolicLink != true else { throw ShelfError.unsupportedFile }
                guard let copiedSize = copiedValues.fileSize, copiedSize <= byteLimit else { throw ShelfError.fileTooLarge }
            }.value
            guard requestGeneration == generation else {
                try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                return
            }
            items.append(ShelfFile(id: id, url: destination, isPinned: false, addedAt: .now))
            files = items.map(\.url)
            error = nil
        } catch {
            self.error = error.localizedDescription
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
        }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func copyToPasteboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
    func remove(_ url: URL) {
        guard let item = items.first(where: { $0.url == url }), !busyItems.contains(item.id) else { return }
        do {
            let updated = items.filter { $0.id != item.id }
            if item.isPinned { try savePins(updated) }
            try FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
            items = updated
            files = items.map(\.url)
            error = nil
        } catch {
            if item.isPinned { try? savePins(items) }
            self.error = error.localizedDescription
        }
    }

    /// Pinned copies survive clearing and relaunching; remove them individually.
    func clear() {
        generation += 1
        for item in items.filter({ !$0.isPinned }) { remove(item.url) }
    }

    func togglePin(_ url: URL) {
        guard !shuttingDown else { return }
        guard let item = items.first(where: { $0.url == url }), !busyItems.contains(item.id) else { return }
        busyItems.insert(item.id)
        let root = item.isPinned ? temporaryURL : storageURL.appendingPathComponent("Pinned", isDirectory: true)
        let destination = root.appendingPathComponent(item.id.uuidString, isDirectory: true).appendingPathComponent(url.lastPathComponent)
        Task {
            defer { busyItems.remove(item.id); cleanupTemporaryFilesIfIdle() }
            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: url, to: destination)
                }.value
                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                var updated = items
                updated[index].url = destination
                updated[index].isPinned.toggle()
                do { try savePins(updated) }
                catch {
                    try? await Task.detached(priority: .utility) {
                        try FileManager.default.moveItem(at: destination, to: url)
                        try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                    }.value
                    throw error
                }
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                items = updated
                files = items.map(\.url)
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }

    func shutdown() {
        shuttingDown = true
        generation += 1
        cleanupTemporaryFilesIfIdle()
    }

    private func cleanupTemporaryFilesIfIdle() {
        guard shuttingDown, pendingImports == 0, busyItems.isEmpty else { return }
        try? FileManager.default.removeItem(at: temporaryURL)
        if let sessionLockFD {
            _ = Darwin.close(sessionLockFD)
            self.sessionLockFD = nil
        }
    }

    private func savePins(_ snapshot: [ShelfFile]) throws {
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot.filter(\.isPinned))
        try data.write(to: storageURL.appendingPathComponent("PinnedFiles.json"), options: .atomic)
    }
}

private enum ShelfError: LocalizedError {
    case unsupportedFile, fileTooLarge
    var errorDescription: String? {
        switch self {
        case .unsupportedFile: String(localized: "Add regular files to the shelf. Folders and symbolic links are not supported.")
        case .fileTooLarge: String(localized: "Each shelf file must be smaller than 200 MB.")
        }
    }
}
