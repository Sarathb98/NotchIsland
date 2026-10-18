import SwiftUI

/// A compact live preview below the physical camera housing.
struct CollapsedIsland: View {
    @ObservedObject var media: MediaModel
    @ObservedObject var timer: TimerModel
    @ObservedObject var battery: BatteryMonitor
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = media.snapshot.artwork, media.snapshot.canPlay {
                    Image(nsImage: artwork).resizable().scaledToFill()
                } else {
                    Image(systemName: timer.isRunning ? "timer" : "rectangle.topthird.inset.filled")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white.opacity(0.1))
                }
            }.frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                if media.snapshot.canPlay {
                    Text(media.snapshot.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(media.snapshot.isPlaying ? String(localized: "Playing") : String(localized: "Paused"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else if timer.isRunning {
                    Text(timer.display).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(timer.status).font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("Notch Island").font(.system(size: 11, weight: .semibold))
                    Text("Click to open your island").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 6)
            if timer.isRunning && media.snapshot.canPlay {
                Text(timer.display).font(.caption).monospacedDigit().foregroundStyle(.blue)
            } else {
                BatteryView(model: battery)
            }
        }.padding(.horizontal, 22).padding(.bottom, 6)
    }
}
