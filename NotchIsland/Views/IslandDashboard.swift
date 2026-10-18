import AppKit
import SwiftUI

/// A single horizontal surface keeps the everyday tools close to the notch.
/// Each column observes its own model so playback and timer updates stay local.
struct IslandDashboard: View {
    let widgets: WidgetStore
    @ObservedObject var settings: IslandSettings
    let openModule: (IslandWidget) -> Void

    private var modules: [IslandWidget] {
        settings.orderedModules.filter { [.media, .mirror, .calendar, .notes, .timer, .tasks].contains($0) }
    }

    var body: some View {
        GeometryReader { geometry in
            let baseWidth = modules.reduce(CGFloat(0)) { $0 + width(for: $1) }
            let extra = max(0, geometry.size.width - baseWidth - CGFloat(max(0, modules.count - 1)) - 8) / CGFloat(max(1, modules.count))
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(modules.enumerated()), id: \.element.id) { index, module in
                        if index > 0 {
                            Rectangle().fill(.white.opacity(0.10)).frame(width: 1, height: 164)
                                .accessibilityHidden(true)
                        }
                        column(module).frame(width: width(for: module) + extra)
                    }
                    if modules.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your everyday tools").font(.headline)
                            Text("Enable Media, Mirror, Calendar, Notes, Timer, or Tasks in Settings to show them here.")
                                .font(.callout).foregroundStyle(DashboardStyle.secondary)
                        }.frame(width: 300, height: DashboardStyle.height, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                }.padding(.horizontal, 4)
            }.scrollIndicators(.hidden)
        }
        .frame(height: DashboardStyle.height)
        .foregroundStyle(.white)
        .tint(DashboardStyle.blue)
        .background(.black)
        .accessibilityIdentifier("island.dashboard")
    }

    @ViewBuilder
    private func column(_ module: IslandWidget) -> some View {
        switch module {
        case .media:
            DashboardMedia(model: widgets.media, open: { openModule(.media) })
        case .mirror:
            CameraMirrorWidget(model: widgets.mirror)
        case .calendar:
            DashboardCalendar(model: widgets.calendar, open: { openModule(.calendar) })
        case .notes:
            DashboardNotes(model: widgets.notes, open: { openModule(.notes) })
        case .timer:
            DashboardTimer(model: widgets.timer, open: { openModule(.timer) })
        case .tasks:
            TaskListWidget(model: widgets.tasks)
        default:
            EmptyView()
        }
    }

    private func width(for module: IslandWidget) -> CGFloat {
        switch module {
        case .media: 240
        case .mirror: 190
        case .calendar: 220
        default: 230
        }
    }
}

private enum DashboardStyle {
    static let height: CGFloat = 180
    static let secondary = Color(white: 0.58)
    static let inset = Color(white: 0.11)
    static let blue = Color(red: 0.05, green: 0.61, blue: 1)
}

private struct DashboardHeader: View {
    let title: String
    let open: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(DashboardStyle.secondary)
            Spacer(minLength: 0)
            Button(action: open) {
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }.buttonStyle(.plain).foregroundStyle(DashboardStyle.secondary)
                .help("Open \(title)").accessibilityLabel("Open \(title)")
        }
    }
}

private struct DashboardMedia: View {
    @ObservedObject var model: MediaModel
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DashboardHeader(title: model.sourceName, open: open)
                .help(model.capabilityDescription)
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.snapshot.trackCount > 0 ? model.snapshot.title : String(localized: "Make room for music"))
                        .font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    if model.snapshot.trackCount > 0 {
                        Text(model.snapshot.artist.isEmpty ? model.sourceName : model.snapshot.artist)
                            .font(.system(size: 11)).foregroundStyle(DashboardStyle.secondary).lineLimit(1)
                    } else {
                        Button("Choose Files…", action: model.chooseFiles)
                            .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DashboardStyle.blue)
                    }
                    HStack(spacing: 14) {
                        Button(action: model.previous) { Image(systemName: "backward.end.fill") }
                            .disabled(!model.snapshot.canGoBack)
                            .help("Previous track").accessibilityLabel("Previous track")
                        Button(action: model.playPause) {
                            Image(systemName: model.snapshot.isPlaying ? "pause.fill" : "play.fill")
                        }.disabled(!model.snapshot.canPlay)
                            .help(model.snapshot.isPlaying ? "Pause" : "Play")
                            .accessibilityLabel(model.snapshot.isPlaying ? String(localized: "Pause playback") : String(localized: "Play"))
                        Button(action: model.next) { Image(systemName: "forward.end.fill") }
                            .disabled(!model.snapshot.canGoForward)
                            .help("Next track").accessibilityLabel("Next track")
                    }.buttonStyle(.plain).font(.system(size: 13)).padding(.top, 5)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Slider(value: Binding(get: { model.snapshot.elapsed }, set: model.seek), in: 0...max(1, model.snapshot.duration))
                    .tint(.white).controlSize(.mini).disabled(model.snapshot.duration <= 0)
                    .accessibilityLabel("Playback position")
                HStack {
                    Text(time(model.snapshot.elapsed))
                    Spacer()
                    Text(time(model.snapshot.duration))
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(DashboardStyle.secondary)
            }
            if let error = model.snapshot.error {
                Text(error).font(.system(size: 10)).foregroundStyle(DashboardStyle.secondary)
                    .lineLimit(1).help(error)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(height: DashboardStyle.height)
        .accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.media")
    }

    private var artwork: some View {
        Group {
            if let image = model.snapshot.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 26, weight: .medium))
                    .foregroundStyle(DashboardStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DashboardStyle.inset)
            }
        }.frame(width: 70, height: 70).clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityHidden(true)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(Double(Int.max / 2), MediaPlaybackPolicy.validDuration(seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct DashboardCalendar: View {
    @ObservedObject var model: CalendarModel
    let open: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(context.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 27, weight: .semibold))
                    Spacer()
                    Button(action: open) {
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }.buttonStyle(.plain).foregroundStyle(DashboardStyle.secondary)
                        .help("Open Calendar").accessibilityLabel("Open Calendar")
                }
                weekStrip(around: context.date)
                Spacer(minLength: 0)
                if let event = model.upcoming.first {
                    Button(action: open) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(event.countdown(at: context.date)).font(.system(size: 10))
                                .foregroundStyle(DashboardStyle.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).help("View event details")
                } else if model.isAuthorized {
                    VStack(spacing: 7) {
                        Image(systemName: "calendar.badge.checkmark").font(.system(size: 17))
                        Text("Nothing coming up").font(.system(size: 12))
                    }.foregroundStyle(DashboardStyle.secondary).frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep your next event in view").font(.system(size: 11))
                            .foregroundStyle(DashboardStyle.secondary)
                        if model.canRequestAccess {
                            Button("Enable Calendar") { Task { await model.requestAccess() } }
                                .disabled(model.requesting)
                        } else {
                            Button("Calendar Settings", action: model.openSystemSettings)
                        }
                    }.font(.system(size: 11, weight: .medium)).buttonStyle(.plain)
                        .foregroundStyle(DashboardStyle.blue)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 8)
                .frame(height: DashboardStyle.height)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.calendar")
    }

    private func weekStrip(around date: Date) -> some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        return HStack(spacing: 0) {
            ForEach(dates, id: \.self) { day in
                let today = calendar.isDate(day, inSameDayAs: date)
                VStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DashboardStyle.secondary)
                    Text(day.formatted(.dateTime.day())).font(.system(size: 16, weight: today ? .bold : .medium))
                        .foregroundStyle(today ? DashboardStyle.blue : DashboardStyle.secondary)
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(today ? String(localized: "Today") : "")
            }
        }
    }
}

private struct DashboardNotes: View {
    @ObservedObject var model: NotesModel
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DashboardHeader(title: String(localized: "Quick Notes"), open: open)
            VStack(alignment: .leading, spacing: 4) {
                if model.selectedID != nil {
                    TextEditor(text: Binding(get: { model.selectedText }, set: model.update))
                        .font(.system(size: 13)).scrollContentBackground(.hidden)
                        .accessibilityLabel("Note text").accessibilityIdentifier("dashboard.note.editor")
                        .overlay(alignment: .topLeading) {
                            if model.selectedText.isEmpty {
                                Text("A thought to keep close…").font(.system(size: 13))
                                    .foregroundStyle(DashboardStyle.secondary)
                                    .padding(.horizontal, 5).padding(.top, 3).allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                } else {
                    Button(action: model.create) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A thought to keep close…").foregroundStyle(DashboardStyle.secondary)
                            Text("New note").foregroundStyle(.white)
                        }.font(.system(size: 13)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }.buttonStyle(.plain).accessibilityLabel("New note")
                }
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(DashboardStyle.blue).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Spacer()
                    if model.selectedID != nil {
                        Button(action: model.copySelected) { Image(systemName: "doc.on.doc") }
                            .disabled(model.selectedText.isEmpty).help("Copy note").accessibilityLabel("Copy note")
                        Button(action: model.create) { Image(systemName: "plus") }
                            .help("New note").accessibilityLabel("New note")
                    }
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(DashboardStyle.secondary)
            }.padding(10).background(DashboardStyle.inset, in: RoundedRectangle(cornerRadius: 13))
            if let error = model.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(1).help(error)
            }
        }.padding(.horizontal, 16).padding(.vertical, 8)
            .frame(height: DashboardStyle.height)
            .onDisappear { model.save() }
            .accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.notes")
    }
}

private struct DashboardTimer: View {
    @ObservedObject var model: TimerModel
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashboardHeader(title: model.mode.title, open: open)
            Text(model.display).font(.system(size: 37, weight: .light, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityLabel("Timer remaining").accessibilityValue(model.display)
            Text(model.status).font(.system(size: 10)).foregroundStyle(DashboardStyle.secondary).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach([1, 5, 25], id: \.self) { minutes in
                    Button { model.reset(seconds: Double(minutes * 60)) } label: {
                        Text("\(minutes)m").font(.system(size: 10, weight: .medium))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(DashboardStyle.inset, in: Capsule())
                    }.buttonStyle(.plain).disabled(model.isRunning)
                        .help("Set timer to \(minutes) minutes").accessibilityLabel("\(minutes) minute timer")
                }
            }
            HStack(spacing: 8) {
                Button {
                    if model.isRunning { model.pause() } else { model.start() }
                } label: {
                    Label(model.isRunning ? String(localized: "Pause") : String(localized: "Start"), systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity)
                        .padding(.vertical, 7).background(DashboardStyle.blue, in: Capsule())
                }.buttonStyle(.plain).disabled(!model.isRunning && model.mode != .stopwatch && model.remaining <= 0)
                    .accessibilityIdentifier("dashboard.timer.toggle")
                Button(action: model.resetCurrent) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 29).background(DashboardStyle.inset, in: Circle())
                }.buttonStyle(.plain).help("Reset timer").accessibilityLabel("Reset")
            }
        }.padding(.horizontal, 16).padding(.vertical, 8)
            .frame(height: DashboardStyle.height)
            .accessibilityElement(children: .contain).accessibilityIdentifier("dashboard.timer")
    }
}
