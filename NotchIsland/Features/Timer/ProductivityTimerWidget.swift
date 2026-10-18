import SwiftUI

struct ProductivityTimerWidget: View {
    @ObservedObject var model: TimerModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Timer mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    ForEach(TimerModel.Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).controlSize(.small)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.display).font(.system(.largeTitle, design: .rounded).monospacedDigit())
                            .accessibilityLabel(model.mode == .stopwatch ? String(localized: "Elapsed time") : String(localized: "Time remaining"))
                            .accessibilityValue(model.display)
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.isRunning ? model.pause() : model.start() } label: {
                        Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    }.buttonStyle(.borderedProminent)
                        .disabled(model.mode != .stopwatch && model.remaining <= 0)
                        .accessibilityLabel(model.isRunning ? String(localized: "Pause") : String(localized: "Start"))
                        .help(model.isRunning ? String(localized: "Pause") : String(localized: "Start"))
                    Button { model.resetCurrent() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.bordered).accessibilityLabel("Reset").help("Reset")
                }
                if model.mode == .timer {
                    HStack {
                        Menu("Duration") {
                            ForEach(TimerModel.presetMinutes, id: \.self) { minutes in
                                Button("\(minutes) minutes") { model.reset(seconds: Double(minutes * 60)) }
                            }
                        }.fixedSize()
                        Spacer()
                        Toggle("Repeat", isOn: $model.repeatEnabled).toggleStyle(.checkbox)
                    }.controlSize(.small)
                } else if model.mode == .pomodoro {
                    HStack {
                        Text("25 min focus · 5 min break").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Repeat", isOn: $model.repeatEnabled).toggleStyle(.checkbox)
                    }.controlSize(.small)
                    Text("The short break starts when focus time ends.").font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
        }.frame(maxHeight: 200).accessibilityIdentifier("widget.timer")
    }
}
