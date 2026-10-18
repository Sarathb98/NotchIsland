import SwiftUI

struct CalendarPreviewWidget: View {
    @ObservedObject var model: CalendarModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !model.isAuthorized {
                    Label(model.title, systemImage: "calendar").font(.headline)
                    Text(model.detail).font(.caption).foregroundStyle(.secondary)
                    if model.canRequestAccess {
                        Button("Enable Calendar") { Task { await model.requestAccess() } }
                            .disabled(model.requesting).buttonStyle(.borderedProminent)
                    } else {
                        Button("Open System Settings") { model.openSystemSettings() }.buttonStyle(.bordered)
                    }
                } else if model.upcoming.isEmpty {
                    Label("Nothing coming up", systemImage: "calendar").font(.headline)
                    Text("Your next 24 hours are clear.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(model.upcoming) { event in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.calendarName).font(.caption).foregroundStyle(.secondary)
                                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let location = event.location, !location.isEmpty {
                                    Label(location, systemImage: "mappin.and.ellipse").font(.caption).textSelection(.enabled)
                                }
                                if let notes = event.notes, !notes.isEmpty {
                                    Text(notes).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                if event.meetingURL != nil {
                                    Button("Open Meeting Link") { model.openMeeting(event) }.controlSize(.small)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                                    TimelineView(.periodic(from: .now, by: 30)) { context in
                                        Text(event.countdown(at: context.date)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 4)
                                if event.meetingURL != nil {
                                    Button { model.openMeeting(event) } label: { Image(systemName: "video") }
                                        .buttonStyle(.bordered).controlSize(.small)
                                        .help("Open meeting link").accessibilityLabel("Open meeting link for \(event.title)")
                                }
                            }
                        }
                        if event.id != model.upcoming.last?.id { Divider() }
                    }
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
        }.frame(maxHeight: 200).onAppear { model.refresh() }.accessibilityIdentifier("widget.calendar")
    }
}
