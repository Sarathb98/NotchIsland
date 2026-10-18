import Combine
import Foundation

struct TaskListItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var completed: Bool
    let createdAt: Date

    init(id: UUID = UUID(), title: String, completed: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.completed = completed
        self.createdAt = createdAt
    }
}

@MainActor
final class TaskListModel: ObservableObject {
    static let maximumTaskCount = 100
    static let maximumTitleLength = 120

    @Published private(set) var tasks: [TaskListItem] = []
    @Published private(set) var error: String?

    var remainingCount: Int { tasks.reduce(0) { $0 + ($1.completed ? 0 : 1) } }
    var completedCount: Int { tasks.count - remainingCount }

    private let storageURL: URL
    private var canWrite = true

    init(storageURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.storageURL = storageURL ?? support.appendingPathComponent("NotchIsland/tasks.json")

        guard FileManager.default.fileExists(atPath: self.storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: self.storageURL)
            guard data.count <= 256_000 else { throw TaskListStorageError.invalidData }
            let restored = try JSONDecoder().decode([TaskListItem].self, from: data)
            guard restored.count <= Self.maximumTaskCount,
                  Set(restored.map(\.id)).count == restored.count,
                  restored.allSatisfy({
                      Self.normalizedTitle($0.title) == $0.title &&
                      $0.title.count <= Self.maximumTitleLength
                  }) else {
                throw TaskListStorageError.invalidData
            }
            tasks = restored
        } catch {
            // Keep the original file intact if its contents cannot be loaded.
            canWrite = false
            self.error = String(localized: "Could not read saved tasks: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func add(_ title: String) -> Bool {
        let normalized = Self.normalizedTitle(title)
        guard !normalized.isEmpty else { return false }
        guard tasks.count < Self.maximumTaskCount else {
            error = String(localized: "You can keep up to 100 tasks.")
            return false
        }
        let item = TaskListItem(title: String(normalized.prefix(Self.maximumTitleLength)))
        var updated = tasks
        updated.insert(item, at: 0)
        return persist(updated)
    }

    @discardableResult
    func toggle(_ id: UUID) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        var updated = tasks
        updated[index].completed.toggle()
        return persist(updated)
    }

    @discardableResult
    func remove(_ id: UUID) -> Bool {
        guard tasks.contains(where: { $0.id == id }) else { return false }
        return persist(tasks.filter { $0.id != id })
    }

    @discardableResult
    func clearCompleted() -> Bool {
        guard completedCount > 0 else { return false }
        return persist(tasks.filter { !$0.completed })
    }

    private static func normalizedTitle(_ input: String) -> String {
        input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func persist(_ updated: [TaskListItem]) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(updated).write(to: storageURL, options: .atomic)
            tasks = updated
            error = nil
            return true
        } catch {
            self.error = String(localized: "Could not save tasks: \(error.localizedDescription)")
            return false
        }
    }
}

private enum TaskListStorageError: LocalizedError {
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidData: String(localized: "The task file contains invalid data.")
        }
    }
}
