import AppKit
import EventKit
import Combine

/// Views and activity scheduling receive values, never live EventKit objects.
struct CalendarEventSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let notes: String?
    let calendarName: String
    let meetingURL: URL?

    func countdown(at date: Date) -> String {
        if isAllDay { return String(localized: "All day") }
        if endDate <= date { return String(localized: "Ended") }
        if startDate <= date { return String(localized: "In progress") }
        let minutes = max(1, Int(ceil(startDate.timeIntervalSince(date) / 60)))
        if minutes < 60 { return String(localized: "Starts in \(minutes) min") }
        return startDate.formatted(date: .abbreviated, time: .shortened)
    }

    /// Custom application schemes and local file URLs from event data are never opened.
    static func webMeetingURL(eventURL: URL?, notes: String?) -> URL? {
        if let eventURL, isWebURL(eventURL) { return eventURL }
        guard let notes, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        return detector.matches(in: notes, range: NSRange(notes.startIndex..., in: notes))
            .compactMap(\.url).first(where: isWebURL)
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }
}

@MainActor
final class CalendarModel: ObservableObject {
    @Published private(set) var title = String(localized: "Connect your calendar")
    @Published private(set) var detail = String(localized: "Preview your next event")
    @Published private(set) var canRequestAccess = true
    @Published private(set) var requesting = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var upcoming: [CalendarEventSnapshot] = []
    @Published private(set) var error: String?
    private let store = EKEventStore()
    private var subscriptions = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private let monitoringEnabled: Bool
    init(monitoringEnabled: Bool = true) {
        self.monitoringEnabled = monitoringEnabled
        guard monitoringEnabled else { return }

        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }
    func requestAccess() async {
        guard !requesting else { return }
        requesting = true
        error = nil
        defer { requesting = false }
        do {
            _ = try await store.requestFullAccessToEvents()
            refresh()
        } catch {
            title = String(localized: "Calendar unavailable")
            detail = error.localizedDescription
            self.error = error.localizedDescription
        }
    }
    func refresh(at now: Date = .now) {
        guard monitoringEnabled else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        canRequestAccess = status == .notDetermined || status == .writeOnly
        isAuthorized = status == .fullAccess
        guard isAuthorized else {
            upcoming = []
            refreshTimer = nil
            title = canRequestAccess ? String(localized: "Connect your calendar") : String(localized: "Calendar access is off")
            detail = canRequestAccess ? String(localized: "Preview your next event") : String(localized: "Enable in System Settings → Privacy → Calendars")
            return
        }
        error = nil
        if refreshTimer == nil {
            // Meeting alerts remain current while authorized; no polling before permission.
            refreshTimer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        }
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        upcoming = store.events(matching: predicate).filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }.prefix(30).map { event in
                let notes = event.notes.map { String($0.prefix(16_000)) }
                return CalendarEventSnapshot(
                    id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                    title: event.title?.isEmpty == false ? event.title : String(localized: "Untitled event"),
                    startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
                    location: event.location, notes: notes, calendarName: event.calendar.title,
                    meetingURL: CalendarEventSnapshot.webMeetingURL(eventURL: event.url, notes: notes))
            }
        title = upcoming.first?.title ?? String(localized: "Nothing coming up")
        if let event = upcoming.first {
            detail = event.isAllDay ? String(localized: "All day") : event.startDate.formatted(date: .abbreviated, time: .shortened)
        } else { detail = String(localized: "Your next 24 hours are clear") }
    }

    func openMeeting(_ event: CalendarEventSnapshot) {
        guard let url = event.meetingURL, CalendarEventSnapshot.isWebURL(url) else { return }
        if !NSWorkspace.shared.open(url) { error = String(localized: "The event link could not be opened.") }
    }

    func openSystemSettings() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
