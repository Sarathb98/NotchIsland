import SwiftUI

struct SystemWidget: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var audio: AudioMonitor
    let recorder: ScreenRecorder
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Network", value: system.network)
                LabeledContent("CPU", value: system.cpuUsage.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("Memory in use", value: ByteCountFormatter.string(fromByteCount: Int64(system.memoryUsed), countStyle: .memory))
                LabeledContent("Disk available", value: ByteCountFormatter.string(fromByteCount: system.diskFree, countStyle: .file))
                Divider()
                Label(audio.outputName, systemImage: "headphones")
                if let volume = audio.volume {
                    Slider(value: Binding(get: { audio.volume ?? volume }, set: audio.setVolume), in: 0...1) { Text("Volume") }
                        .disabled(!audio.canSetVolume).accessibilityLabel("Output volume")
                } else { Text("Adjust volume using the output device’s controls.").font(.caption).foregroundStyle(.secondary) }
                LabeledContent("Input device", value: audio.inputActive ? String(localized: "In use") : String(localized: "Idle"))
                Text("Input activity is reported by the audio driver; individual apps are not identified.").font(.caption2).foregroundStyle(.secondary)
                Divider()
                ScreenRecordingWidget(recorder: recorder)
                DeviceStatusWidget()
                Divider()
                DisclosureGroup("Additional system capabilities") {
                    Text(system.brightness.capability.explanation)

                }.font(.caption)
                if let error = audio.error { Text(error).foregroundStyle(.red) }
            }.font(.callout).padding(.vertical, 4)
        }.onAppear { system.startSampling(); audio.refreshInputActivity() }
            .onDisappear { system.stopSampling() }
    }
}
