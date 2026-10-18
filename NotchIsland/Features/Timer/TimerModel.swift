import AppKit
import Combine

@MainActor
final class TimerModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case timer, stopwatch, pomodoro
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timer: String(localized: "Timer")
            case .stopwatch: String(localized: "Stopwatch")
            case .pomodoro: String(localized: "Pomodoro")
            }
        }
    }
    enum PomodoroPhase { case focus, shortBreak }
    static let presetMinutes = [1, 5, 15, 25, 45, 60]

    @Published private(set) var mode: Mode = .timer
    @Published private(set) var remaining: TimeInterval = 300
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    @Published private(set) var finished = false
    @Published private(set) var pomodoroPhase: PomodoroPhase = .focus
    @Published private(set) var completionCount = 0
    @Published var repeatEnabled = false
    private(set) var duration: TimeInterval = 300
    private(set) var focusDuration: TimeInterval = 25 * 60
    private(set) var breakDuration: TimeInterval = 5 * 60
    private var deadline: Date?
    private var stopwatchStartedAt: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var ticker: AnyCancellable?
    private var wakeObserver: AnyCancellable?
    private let automaticallySchedulesTicks: Bool
    private let playCompletionSound: Bool

    init(automaticallySchedulesTicks: Bool = true, playCompletionSound: Bool = true) {
        self.automaticallySchedulesTicks = automaticallySchedulesTicks
        self.playCompletionSound = playCompletionSound
        if automaticallySchedulesTicks {
            wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.tick(at: .now) }
        }
    }

    var display: String { Self.format(mode == .stopwatch ? floor(elapsed) : ceil(remaining)) }
    var status: String {
        if finished { return String(localized: "Time’s up") }
        switch mode {
        case .timer: return isRunning ? String(localized: "Counting down") : String(localized: "Ready when you are")
        case .stopwatch: return isRunning ? String(localized: "Elapsed time") : String(localized: "Stopwatch paused")
        case .pomodoro: return pomodoroPhase == .focus ? String(localized: "Focus session") : String(localized: "Short break")
        }
    }

    func setMode(_ mode: Mode) {
        guard self.mode != mode else { return }
        self.mode = mode
        resetCurrent()
    }

    func start(at date: Date = .now) {
        guard !isRunning, mode == .stopwatch || remaining > 0 else { return }
        finished = false
        if mode == .stopwatch { stopwatchStartedAt = date }
        else { deadline = date.addingTimeInterval(remaining) }
        isRunning = true
        startTicker()
    }

    func pause(at date: Date = .now) {
        guard isRunning else { return }
        tick(at: date)
        accumulatedElapsed = elapsed
        deadline = nil
        stopwatchStartedAt = nil
        isRunning = false
        ticker = nil
    }

    /// The existing countdown API remains available to presets and quick actions.
    func reset(seconds: TimeInterval = 300) {
        mode = .timer
        duration = Self.validDuration(seconds, allowingZero: true)
        resetCurrent()
    }

    func resetCurrent() {
        deadline = nil
        stopwatchStartedAt = nil
        ticker = nil
        isRunning = false
        finished = false
        elapsed = 0
        accumulatedElapsed = 0
        completionCount = 0
        pomodoroPhase = .focus
        remaining = mode == .pomodoro ? focusDuration : mode == .timer ? duration : 0
    }

    func configurePomodoro(focus: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60) {
        focusDuration = Self.validDuration(focus, allowingZero: false)
        breakDuration = Self.validDuration(shortBreak, allowingZero: false)
        mode = .pomodoro
        resetCurrent()
    }

    func tick(at date: Date) {
        guard isRunning else { return }
        if mode == .stopwatch, let stopwatchStartedAt {
            elapsed = accumulatedElapsed + max(0, date.timeIntervalSince(stopwatchStartedAt))
            return
        }
        guard let deadline else { return }
        guard date >= deadline else {
            remaining = deadline.timeIntervalSince(date)
            return
        }
        let countBefore = completionCount
        if mode == .pomodoro {
            advancePomodoro(at: date, deadline: deadline)
        } else if repeatEnabled, duration > 0 {
            let intervals = floor(date.timeIntervalSince(deadline) / duration) + 1
            completionCount += Int(min(intervals, Double(Int.max / 2)))
            self.deadline = deadline.addingTimeInterval(intervals * duration)
            remaining = self.deadline!.timeIntervalSince(date)
        } else {
            completionCount += 1
            finish()
        }
        if playCompletionSound, completionCount > countBefore { NSSound(named: "Glass")?.play() }
    }

    private func advancePomodoro(at date: Date, deadline: Date) {
        if repeatEnabled {
            let cycle = focusDuration + breakDuration
            let cycleStart = deadline.addingTimeInterval(pomodoroPhase == .focus ? -focusDuration : -cycle)
            let cycleElapsed = max(0, date.timeIntervalSince(cycleStart))
            let cycles = floor(cycleElapsed / cycle)
            let position = cycleElapsed.truncatingRemainder(dividingBy: cycle)
            let previousPhaseOffset = pomodoroPhase == .focus ? 0.0 : 1.0
            let completions = cycles * 2 + (position >= focusDuration ? 1 : 0) - previousPhaseOffset
            completionCount += Int(min(max(0, completions), Double(Int.max / 2)))
            pomodoroPhase = position < focusDuration ? .focus : .shortBreak
            self.deadline = cycleStart.addingTimeInterval(cycles * cycle + (pomodoroPhase == .focus ? focusDuration : cycle))
            remaining = max(0, self.deadline!.timeIntervalSince(date))
        } else if pomodoroPhase == .focus {
            completionCount += 1
            pomodoroPhase = .shortBreak
            let breakEnd = deadline.addingTimeInterval(breakDuration)
            if date < breakEnd {
                self.deadline = breakEnd
                remaining = breakEnd.timeIntervalSince(date)
            } else {
                completionCount += 1
                finish()
            }
        } else {
            completionCount += 1
            finish()
        }
    }

    private func finish() {
        deadline = nil
        remaining = 0
        isRunning = false
        ticker = nil
        finished = true
    }

    private func startTicker() {
        guard automaticallySchedulesTicks, ticker == nil else { return }
        ticker = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] date in self?.tick(at: date) }
    }

    private static func validDuration(_ value: TimeInterval, allowingZero: Bool) -> TimeInterval {
        guard value.isFinite else { return 300 }
        return min(7 * 24 * 60 * 60, max(allowingZero ? 0 : 1, value))
    }

    private static func format(_ interval: TimeInterval) -> String {
        let seconds = Int(min(Double(Int.max / 2), max(0, interval)))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
