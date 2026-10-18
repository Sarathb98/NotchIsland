import Foundation
import Combine

struct IslandActivity: Identifiable, Equatable {
    enum Priority: Int, Comparable {
        case standard = 0, media, download, fileTransfer, timer, userAction, meeting, critical
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    let id: String
    var title: String
    var detail: String
    var symbol: String
    var priority: Priority
    var expiresAt: Date
    var progress: Double?
}

@MainActor
final class LiveActivityManager: ObservableObject {
    @Published private(set) var primary: IslandActivity?
    private var activities: [String: IslandActivity] = [:]
    private var expiryTask: Task<Void, Never>?
    func post(id: String, title: String, detail: String = "", symbol: String,
              priority: IslandActivity.Priority = .standard, duration: TimeInterval = 4, progress: Double? = nil,
              now: Date = .now) {
        guard duration.isFinite, duration > 0 else { dismiss(id, now: now); return }
        activities[id] = IslandActivity(id: id, title: title, detail: detail, symbol: symbol,
                                       priority: priority, expiresAt: now.addingTimeInterval(duration), progress: progress)
        refresh(now: now)
    }
    func dismiss(_ id: String, now: Date = .now) { activities.removeValue(forKey: id); refresh(now: now) }
    func refresh(now: Date = .now) {
        activities = activities.filter { $0.value.expiresAt > now }
        primary = activities.values.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.expiresAt != $1.expiresAt { return $0.expiresAt > $1.expiresAt }
            return $0.id < $1.id
        }.first
        expiryTask?.cancel()
        guard let next = activities.values.map(\.expiresAt).min() else { return }
        let delay = max(0.01, next.timeIntervalSince(now))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
