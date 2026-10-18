import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct MediaSnapshot {
    var title = String(localized: "Choose audio or video files")
    var artist = ""
    var artwork: NSImage?
    var elapsed: TimeInterval = 0
    var duration: TimeInterval = 0
    var isPlaying = false
    var canPlay = false
    var canGoBack = false
    var canGoForward = false
    var trackIndex = 0
    var trackCount = 0
    var error: String?
}

/// Implement adapters only for media sources with a supported public API.
/// Local playback does not read or control another application's Now Playing.
@MainActor
protocol NowPlayingAdapter: AnyObject {
    var sourceName: String { get }
    var capabilityDescription: String { get }
    var onUpdate: ((MediaSnapshot) -> Void)? { get set }
    func load(_ urls: [URL])
    func playPause()
    func previous()
    func next()
    func seek(to seconds: TimeInterval)
    func stop()
    func shutdown()
}

enum MediaPlaybackPolicy {
    static func validDuration(_ value: TimeInterval) -> TimeInterval { value.isFinite && value > 0 ? value : 0 }
    static func seekPosition(_ value: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        return min(validDuration(duration), max(0, value))
    }
    static func previousIndex(current: Int, count: Int, elapsed: TimeInterval) -> Int? {
        guard count > 0, current >= 0, current < count else { return nil }
        return elapsed > 3 ? current : max(0, current - 1)
    }
    static func nextIndex(current: Int, count: Int) -> Int? {
        guard current >= 0, current < count - 1 else { return nil }
        return current + 1
    }
}

@MainActor
final class LocalAVPlayerAdapter: NSObject, NowPlayingAdapter {
    let sourceName = String(localized: "Local Media")
    let capabilityDescription = String(localized: "Plays files you choose. Global Now Playing from other apps is unavailable without a separately supported adapter.")
    var onUpdate: ((MediaSnapshot) -> Void)?
    private let player = AVPlayer()
    private var playlist: [URL] = []
    private var index = 0
    private var snapshot = MediaSnapshot()
    private var playbackObservation: NSKeyValueObservation?
    private var itemObservation: NSKeyValueObservation?
    private var endObservation: NSObjectProtocol?
    private var timeObserver: Any?
    private var metadataTask: Task<Void, Never>?
    private var generation = UUID()
    private var scopedURL: URL?
    private var activeAsset: AVURLAsset?

    override init() {
        super.init()
        playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.playbackChanged() }
        }
    }
    func load(_ urls: [URL]) {
        var seen = Set<URL>()
        playlist = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL).inserted }
        index = 0
        selectCurrent(autoplay: false)
    }
    func playPause() {
        guard player.currentItem != nil else { return }
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }
    func previous() {
        guard let previous = MediaPlaybackPolicy.previousIndex(current: index, count: playlist.count, elapsed: snapshot.elapsed) else { return }
        if previous == index { seek(to: 0); return }
        let playing = player.timeControlStatus != .paused
        index = previous
        selectCurrent(autoplay: playing)
    }
    func next() {
        guard let next = MediaPlaybackPolicy.nextIndex(current: index, count: playlist.count) else { return }
        let playing = player.timeControlStatus != .paused
        index = next
        selectCurrent(autoplay: playing)
    }
    func seek(to seconds: TimeInterval) {
        guard snapshot.duration > 0 else { return }
        let seconds = MediaPlaybackPolicy.seekPosition(seconds, duration: snapshot.duration)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        snapshot.elapsed = seconds
        publish()
    }
    func stop() { player.pause(); seek(to: 0) }
    func shutdown() {
        player.pause()
        removeCurrentObservers()
        player.replaceCurrentItem(with: nil)
        playlist = []
        snapshot = MediaSnapshot()
        publish()
    }

    private func selectCurrent(autoplay: Bool) {
        player.pause()
        removeCurrentObservers()
        snapshot = MediaSnapshot()
        guard playlist.indices.contains(index) else { player.replaceCurrentItem(with: nil); publish(); return }
        let url = playlist[index]
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let asset = AVURLAsset(url: url)
        activeAsset = asset
        let item = AVPlayerItem(asset: asset)
        snapshot.title = url.deletingPathExtension().lastPathComponent
        snapshot.trackIndex = index
        snapshot.trackCount = playlist.count
        snapshot.canGoBack = index > 0
        snapshot.canGoForward = index < playlist.count - 1
        let currentGeneration = generation
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, generation == currentGeneration, let item = player.currentItem else { return }
                snapshot.canPlay = item.status == .readyToPlay
                if item.status == .failed { snapshot.error = item.error?.localizedDescription ?? String(localized: "This media file could not be played.") }
                publish()
            }
        }
        endObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == currentGeneration else { return }
                if let next = MediaPlaybackPolicy.nextIndex(current: index, count: playlist.count) {
                    index = next
                    selectCurrent(autoplay: true)
                } else { stop() }
            }
        }
        player.replaceCurrentItem(with: item)
        metadataTask = Task { [weak self] in
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            let duration = try? await asset.load(.duration)
            let titleItem = metadata.first { $0.commonKey == .commonKeyTitle }
            let artistItem = metadata.first { $0.commonKey == .commonKeyArtist }
            let artworkItem = metadata.first { $0.commonKey == .commonKeyArtwork }
            let title = try? await titleItem?.load(.stringValue)
            let artist = try? await artistItem?.load(.stringValue)
            let artwork = try? await artworkItem?.load(.dataValue)
            guard !Task.isCancelled, let self, generation == currentGeneration else { return }
            if let title, !title.isEmpty { snapshot.title = title }
            snapshot.artist = artist ?? ""
            snapshot.duration = MediaPlaybackPolicy.validDuration(duration?.seconds ?? 0)
            if let artwork, artwork.count <= 5 * 1024 * 1024 { snapshot.artwork = NSImage(data: artwork) }
            publish()
        }
        publish()
        if autoplay { player.play() }
    }
    private func playbackChanged() {
        snapshot.isPlaying = player.timeControlStatus != .paused
        if player.timeControlStatus == .playing, timeObserver == nil {
            let observerGeneration = generation
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, generation == observerGeneration else { return }
                    snapshot.elapsed = MediaPlaybackPolicy.seekPosition(time.seconds, duration: snapshot.duration)
                    snapshot.canGoBack = index > 0 || snapshot.elapsed > 3
                    publish()
                }
            }
        } else if player.timeControlStatus != .playing, let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        publish()
    }
    private func removeCurrentObservers() {
        generation = UUID()
        metadataTask?.cancel()
        metadataTask = nil
        activeAsset?.cancelLoading()
        activeAsset = nil
        itemObservation = nil
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        endObservation = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
    private func publish() { onUpdate?(snapshot) }
    deinit {
        metadataTask?.cancel()
        activeAsset?.cancelLoading()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObservation { NotificationCenter.default.removeObserver(endObservation) }
        scopedURL?.stopAccessingSecurityScopedResource()
    }
}

@MainActor
final class MediaModel: ObservableObject {
    @Published private(set) var snapshot = MediaSnapshot()
    private let adapter: any NowPlayingAdapter
    var sourceName: String { adapter.sourceName }
    var capabilityDescription: String { adapter.capabilityDescription }
    init(adapter: (any NowPlayingAdapter)? = nil) {
        self.adapter = adapter ?? LocalAVPlayerAdapter()
        self.adapter.onUpdate = { [weak self] snapshot in self?.snapshot = snapshot }
    }
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Local Media")
        panel.prompt = String(localized: "Load Playlist")
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor [weak self] in self?.adapter.load(panel.urls) }
        }
    }
    func playPause() { adapter.playPause() }
    func previous() { adapter.previous() }
    func next() { adapter.next() }
    func seek(to seconds: TimeInterval) { adapter.seek(to: seconds) }
    func stop() { adapter.stop() }
    func shutdown() { adapter.shutdown() }
}

struct MediaWidget: View {
    @ObservedObject var model: MediaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.sourceName).font(.headline).help(model.capabilityDescription)
                Spacer()
                Button("Choose Files…") { model.chooseFiles() }.controlSize(.small)
            }
            HStack(spacing: 10) {
                Group {
                    if let artwork = model.snapshot.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
                }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.snapshot.title).font(.callout.weight(.medium)).lineLimit(1)
                    if !model.snapshot.artist.isEmpty { Text(model.snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if model.snapshot.trackCount > 0 { Text("\(model.snapshot.trackIndex + 1) of \(model.snapshot.trackCount) files").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(time(model.snapshot.elapsed)).monospacedDigit()
                Slider(value: Binding(get: { model.snapshot.elapsed }, set: { model.seek(to: $0) }), in: 0...max(1, model.snapshot.duration))
                    .disabled(model.snapshot.duration <= 0).accessibilityLabel("Playback position")
                Text(time(model.snapshot.duration)).monospacedDigit()
            }.font(.caption2)
            HStack(spacing: 20) {
                Spacer()
                Button { model.previous() } label: { Image(systemName: "backward.end.fill") }
                    .disabled(!model.snapshot.canGoBack).accessibilityLabel("Previous track")
                Button { model.playPause() } label: { Image(systemName: model.snapshot.isPlaying ? "pause.fill" : "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(!model.snapshot.canPlay)
                    .accessibilityLabel(model.snapshot.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
                Button { model.next() } label: { Image(systemName: "forward.end.fill") }
                    .disabled(!model.snapshot.canGoForward).accessibilityLabel("Next track")
                Button { model.stop() } label: { Image(systemName: "stop.fill") }
                    .disabled(!model.snapshot.canPlay).accessibilityLabel("Stop playback")
                Spacer()
            }.buttonStyle(.borderless)
            if let error = model.snapshot.error { Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2).help(error) }
            Text("Other apps require a separately supported media adapter.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(min(Double(Int.max / 2), MediaPlaybackPolicy.validDuration(seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
