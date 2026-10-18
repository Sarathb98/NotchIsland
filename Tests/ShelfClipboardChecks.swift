import AppKit
import Foundation

@main
struct ShelfClipboardChecks {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIslandShelfChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await checkShelf(root: root)
        try await checkStaleShelfCleanup(root: root)
        try checkClipboard()
        print("Shelf and clipboard checks passed")
    }

    @MainActor
    private static func checkShelf(root: URL) async throws {
        let source = root.appendingPathComponent("Original.txt")
        try Data("Original contents".utf8).write(to: source)
        let storage = root.appendingPathComponent("Storage", isDirectory: true)
        let temporary = root.appendingPathComponent("Temporary", isDirectory: true)
        let model = DropZoneModel(storageURL: storage, temporaryURL: temporary)
        model.importFiles([source])
        try await waitUntil { model.pendingImports == 0 }
        precondition(model.items.count == 1, "Shelf must import a file")
        let copied = model.files[0]
        precondition(copied != source, "Shelf must own a copy")
        try Data("Changed original".utf8).write(to: source)
        let copiedContents = try Data(contentsOf: copied)
        precondition(copiedContents == Data("Original contents".utf8), "Copies must not change with their originals")
        model.togglePin(copied)
        try await waitUntil { model.busyItems.isEmpty }
        precondition(model.items[0].isPinned && model.error == nil, "Pin must persist the copied file")
        model.clear()
        precondition(model.items.count == 1, "Clearing temporary files must preserve pins")
        let restored = DropZoneModel(storageURL: storage, temporaryURL: root.appendingPathComponent("RestoredTemporary"))
        precondition(restored.items == model.items, "Pins must restore from the manifest")
        model.shutdown()
        precondition(!FileManager.default.fileExists(atPath: temporary.path), "Shutdown must clean temporary copies")
        precondition(FileManager.default.fileExists(atPath: restored.files[0].path), "Shutdown must preserve pins")
        restored.remove(restored.files[0])
        precondition(restored.items.isEmpty, "Removing a pin must remove its owned copy")
        precondition(FileManager.default.fileExists(atPath: source.path), "Shelf actions must preserve originals")
        restored.shutdown()

        // A malformed local manifest must never authorize removal of an
        // arbitrary file's parent directory.
        let forged = ShelfFile(id: UUID(), url: source, isPinned: true, addedAt: .now)
        try JSONEncoder().encode([forged]).write(to: storage.appendingPathComponent("PinnedFiles.json"))
        let guarded = DropZoneModel(storageURL: storage, temporaryURL: root.appendingPathComponent("GuardedTemporary"))
        precondition(guarded.items.isEmpty, "Reject manifest paths outside the exact pinned storage location")
        guarded.remove(source)
        precondition(FileManager.default.fileExists(atPath: source.path), "Reject removing an unowned URL")
        guarded.shutdown()

        let rejecting = DropZoneModel(storageURL: root.appendingPathComponent("RejectStorage"), temporaryURL: root.appendingPathComponent("RejectTemporary"))
        rejecting.importFiles([root])
        try await waitUntil { rejecting.pendingImports == 0 }
        precondition(rejecting.items.isEmpty && rejecting.error != nil, "Reject folders instead of recursively copying unbounded data")
        rejecting.shutdown()
    }

    @MainActor
    private static func checkStaleShelfCleanup(root: URL) async throws {
        let manager = FileManager.default
        let shelfRoot = root.appendingPathComponent("Managed/NotchIsland/Shelf", isDirectory: true)
        let storage = root.appendingPathComponent("ManagedStorage", isDirectory: true)
        let source = root.appendingPathComponent("StaleSource.txt")
        let pinSource = root.appendingPathComponent("PinnedSource.txt")
        try Data("Temporary copy".utf8).write(to: source)
        try Data("Pinned copy".utf8).write(to: pinSource)

        let abandonedDirectory = shelfRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var abandoned: DropZoneModel? = DropZoneModel(storageURL: storage, temporaryURL: abandonedDirectory)
        abandoned!.importFiles([source, pinSource])
        try await waitUntil { abandoned!.pendingImports == 0 }
        precondition(abandoned!.items.count == 2, "Both shelf copies must import before cleanup")
        let staleCopy = abandoned!.items.first(where: { $0.url.lastPathComponent == source.lastPathComponent })!.url
        let pinCopy = abandoned!.items.first(where: { $0.url.lastPathComponent == pinSource.lastPathComponent })!.url
        abandoned!.togglePin(pinCopy)
        try await waitUntil { abandoned!.busyItems.isEmpty }
        let pinnedCopy = abandoned!.items.first(where: \.isPinned)!.url

        let liveDirectory = shelfRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let live = DropZoneModel(storageURL: storage, temporaryURL: liveDirectory)
        precondition(manager.fileExists(atPath: staleCopy.path), "A second launch must preserve a live session's files")
        precondition(live.items.contains(where: { $0.url == pinnedCopy }), "A second launch must restore pins")

        // Older, unmarked folders and unrelated names have no proof of being
        // abandoned. Leave them untouched even inside the shelf root.
        let unmarked = shelfRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let unrelated = shelfRoot.appendingPathComponent("Unrelated", isDirectory: true)
        try manager.createDirectory(at: unmarked, withIntermediateDirectories: true)
        try manager.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("Unmarked".utf8).write(to: unmarked.appendingPathComponent("Keep.txt"))
        try Data("Unrelated".utf8).write(to: unrelated.appendingPathComponent("Keep.txt"))

        weak let released = abandoned
        abandoned = nil // Simulates a crash: the lock closes without shutdown cleanup.
        precondition(released == nil, "The abandoned model must release its session lock")
        let next = DropZoneModel(storageURL: storage, temporaryURL: shelfRoot.appendingPathComponent(UUID().uuidString, isDirectory: true))
        precondition(!manager.fileExists(atPath: abandonedDirectory.path), "Startup must remove an unlocked app-owned session")
        precondition(manager.fileExists(atPath: liveDirectory.path), "Startup must preserve another live session")
        precondition(manager.fileExists(atPath: pinnedCopy.path) && next.items.contains(where: { $0.url == pinnedCopy }), "Startup cleanup must preserve pins")
        precondition(manager.fileExists(atPath: unmarked.path) && manager.fileExists(atPath: unrelated.path), "Startup must preserve unmarked and unrelated directories")
        live.shutdown()
        next.shutdown()
    }

    @MainActor
    private static func checkClipboard() throws {
        let suiteName = "NotchIslandClipboardChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // A named pasteboard isolates the test; the user's general pasteboard is
        // never read or modified. Collection remains disabled throughout.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(suiteName))
        let model = ClipboardModel(defaults: defaults, pasteboard: pasteboard)
        precondition(!model.enabled && model.items.isEmpty, "Clipboard collection must require opt-in")
        precondition(ClipboardModel.shouldExclude(sourceBundleID: "com.1password.1password", userExclusions: ""))
        precondition(ClipboardModel.shouldExclude(sourceBundleID: "com.apple.Passwords", userExclusions: ""))
        precondition(ClipboardModel.shouldExclude(sourceBundleID: nil, userExclusions: ""))
        precondition(ClipboardModel.shouldExclude(sourceBundleID: "com.apple.Terminal", userExclusions: "com.example.Other, COM.APPLE.TERMINAL"))
        precondition(!ClipboardModel.shouldExclude(sourceBundleID: "com.example.Editor", userExclusions: ""))
        precondition(ClipboardModel.shouldIgnorePasteboardTypes(["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        precondition(ClipboardModel.shouldIgnorePasteboardTypes(["org.nspasteboard.TransientType"]))
        precondition(!ClipboardModel.shouldIgnorePasteboardTypes(["public.png"]))
        model.add(.text("Keep this favorite"), sourceBundleID: "com.example.Editor")
        let favorite = model.items[0].id
        model.toggleFavorite(favorite)
        for index in 0..<120 { model.add(.text("Entry \(index)"), sourceBundleID: "com.example.Editor") }
        precondition(model.items.count == 100, "History must be bounded")
        precondition(model.items.contains { $0.id == favorite && $0.isFavorite }, "Eviction must preserve favorites")
        model.searchQuery = "keep THIS"
        precondition(model.filteredItems.count == 1, "Search must ignore case")
        model.clear()
        precondition(model.items.isEmpty, "Clear must also remove favorites")
        model.add(.image(Data(repeating: 1, count: 5 * 1_024 * 1_024 + 1)), sourceBundleID: "com.example.Editor")
        precondition(model.items.isEmpty, "Oversized entries must be skipped")
        for index in 0..<9 { model.add(.image(Data(repeating: UInt8(index), count: 4 * 1_024 * 1_024)), sourceBundleID: "com.example.Editor") }
        precondition(model.items.count == 8, "Total clipboard storage must stay at or below 32 MB")
        model.clear()
        model.excludedBundleIDs = "com.example.Editor"
        let reloaded = ClipboardModel(defaults: defaults, pasteboard: pasteboard)
        precondition(reloaded.excludedBundleIDs == "com.example.Editor" && reloaded.items.isEmpty && !reloaded.enabled)
    }

    @MainActor
    private static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            precondition(Date() < deadline, "Asynchronous shelf operation timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
