import Foundation
import Combine

@MainActor
final class WidgetStore {
    let activities = LiveActivityManager()
    let system = SystemMonitor()
    let audio = AudioMonitor()
    lazy var recorder = ScreenRecorder(recordingState: system.recording)
    private var subscriptions = Set<AnyCancellable>()
    private var lastLowBattery = false
    private var announcedMeetings = Set<String>()
    private let testStorage: URL?
    init(isTesting: Bool = false, defaults: UserDefaults = .standard) {
        testStorage = isTesting ? FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-UITests-\(UUID().uuidString)", isDirectory: true) : nil
        calendar = CalendarModel(monitoringEnabled: !isTesting)
        notes = NotesModel(storage: testStorage?.appendingPathComponent("notes.json"))
        tasks = TaskListModel(storageURL: testStorage?.appendingPathComponent("tasks.json"))
        dropZone = DropZoneModel(storageURL: testStorage?.appendingPathComponent("Pinned"), temporaryURL: testStorage?.appendingPathComponent("Shelf"))
        clipboard = ClipboardModel(defaults: defaults)
        actions = QuickActionsModel(defaults: defaults)

        actions.onStartTimer = { [weak self] seconds in self?.timer.reset(seconds: seconds); self?.timer.start() }
        actions.onStartFocus = { [weak self] in self?.timer.configurePomodoro(); self?.timer.start() }
        calendar.$upcoming.sink { [weak self] events in
            guard let self else { return }
            announcedMeetings.formIntersection(Set(events.map(\.id)))
            for event in events where !event.isAllDay && event.startDate.timeIntervalSinceNow > 0 && event.startDate.timeIntervalSinceNow <= 300 {
                if announcedMeetings.insert(event.id).inserted {
                    activities.post(id: "meeting.\(event.id)", title: event.title, detail: event.countdown(at: .now), symbol: "calendar", priority: .meeting, duration: 12)
                }
            }
        }.store(in: &subscriptions)
        Publishers.CombineLatest(downloads.$state, downloads.$progress)
            .throttle(for: .seconds(0.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] state, progress in
                guard let self else { return }
                switch state {
                case .downloading: activities.post(id: "download", title: String(localized: "Downloading"), symbol: "arrow.down.circle", priority: .download, duration: 60, progress: progress)
                case .completed: activities.post(id: "download", title: String(localized: "Download complete"), symbol: "checkmark.circle", priority: .download, duration: 5)
                case .failed: activities.post(id: "download", title: String(localized: "Download failed"), detail: downloads.error ?? String(localized: "Try again in Downloads."), symbol: "exclamationmark.circle", priority: .userAction, duration: 6)
                default: activities.dismiss("download")
                }
            }.store(in: &subscriptions)
        media.$snapshot.map { "\($0.title)|\($0.isPlaying)" }.removeDuplicates().dropFirst().receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, media.snapshot.canPlay else { return }
                activities.post(id: "media", title: media.snapshot.title, detail: media.snapshot.isPlaying ? media.snapshot.artist : String(localized: "Paused"), symbol: media.snapshot.isPlaying ? "music.note" : "pause", priority: .media, duration: 4)
            }.store(in: &subscriptions)
        audio.onVolumeChange = { [weak self] volume in
            self?.activities.post(id: "volume", title: String(localized: "Volume"), detail: String(localized: "\(Int(volume * 100))%"), symbol: "speaker.wave.2", priority: .userAction, duration: 2, progress: volume)
        }
        battery.$powerState.dropFirst().removeDuplicates().sink { [weak self] state in
            self?.activities.post(id: "charging", title: state.title, symbol: "battery.100percent.bolt", priority: .standard)
        }.store(in: &subscriptions)
        Publishers.CombineLatest(battery.$percentage, battery.$powerState).receive(on: RunLoop.main)
            .sink { [weak self] percentage, state in
            guard let self, let percentage else { return }
            let low = percentage <= 20 && state == .battery
            if low && !lastLowBattery { activities.post(id: "battery.low", title: String(localized: "Low battery"), detail: String(localized: "\(percentage)% remaining"), symbol: "battery.25percent", priority: .critical, duration: 8) }
            lastLowBattery = low
        }.store(in: &subscriptions)
        system.$network.dropFirst().removeDuplicates().sink { [weak self] network in
            self?.activities.post(id: "network", title: network, symbol: "network", duration: 3)
        }.store(in: &subscriptions)
        timer.$completionCount.dropFirst().filter { $0 > 0 }.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            activities.post(id: "timer", title: timer.mode == .pomodoro ? timer.status : String(localized: "Time’s up"), symbol: "timer", priority: .timer, duration: 8)
        }.store(in: &subscriptions)
        dropZone.$pendingImports.dropFirst().receive(on: RunLoop.main).sink { [weak self] count in
            guard let self else { return }
            if count > 0 { activities.post(id: "shelf.copy", title: String(localized: "Adding files"), detail: String(localized: "\(count) remaining"), symbol: "doc.on.doc", priority: .fileTransfer, duration: 120) }
            else { activities.dismiss("shelf.copy") }
        }.store(in: &subscriptions)
    }
    let battery = BatteryMonitor()
    let timer = TimerModel()
    let calendar: CalendarModel
    let dropZone: DropZoneModel
    let clipboard: ClipboardModel
    let notes: NotesModel
    let tasks: TaskListModel
    let mirror = CameraMirrorModel()
    let actions: QuickActionsModel
    let launcher = AppLauncherModel()
    let downloads = DownloadModel()
    let media = MediaModel()
    func prepareForTermination() async -> Bool {
        if recorder.state == .choosingDestination || recorder.state == .starting || downloads.state == .choosingDestination { return false }
        if recorder.state == .recording { await recorder.stop() }
        downloads.cancel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while (recorder.state != .idle || downloads.isBusy || dropZone.isImporting || !dropZone.busyItems.isEmpty), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return recorder.state == .idle && !downloads.isBusy && !dropZone.isImporting && dropZone.busyItems.isEmpty
    }
    func shutdown() {
        mirror.shutdown(); notes.save(); dropZone.shutdown(); clipboard.setEnabled(false); downloads.cancel(); audio.stop(); media.shutdown()
        if let testStorage { try? FileManager.default.removeItem(at: testStorage) }
    }
}
