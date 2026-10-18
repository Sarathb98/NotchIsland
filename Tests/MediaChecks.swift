import Foundation

@MainActor
private final class RecordingMediaAdapter: NowPlayingAdapter {
    let sourceName = "Test Media"
    let capabilityDescription = "In-memory adapter; no playback or file access"
    var onUpdate: ((MediaSnapshot) -> Void)?
    var calls: [String] = []
    var position: TimeInterval?
    func load(_ urls: [URL]) { calls.append("load") }
    func playPause() { calls.append("playPause") }
    func previous() { calls.append("previous") }
    func next() { calls.append("next") }
    func seek(to seconds: TimeInterval) { calls.append("seek"); position = seconds }
    func stop() { calls.append("stop") }
    func shutdown() { calls.append("shutdown") }
}

@main
struct MediaChecks {
    @MainActor static func main() {
        checkPlaybackPolicy()
        checkAdapterForwarding()
        print("PASS: media duration/seek/playlist policy and adapter updates/controls (no AVPlayer, playback, file picker or user media access)")
    }
    private static func checkPlaybackPolicy() {
        for value: TimeInterval in [-1, 0, .nan, .infinity, -.infinity] {
            expect(MediaPlaybackPolicy.validDuration(value) == 0, "Unplayable durations have no seek range")
        }
        expect(MediaPlaybackPolicy.validDuration(123.5) == 123.5, "Valid durations retain their precision")
        expect(MediaPlaybackPolicy.seekPosition(-1, duration: 60) == 0, "Cannot seek before the beginning")
        expect(MediaPlaybackPolicy.seekPosition(90, duration: 60) == 60, "Cannot seek beyond the end")
        expect(MediaPlaybackPolicy.seekPosition(.nan, duration: 60) == 0, "NaN seeks are safe")
        expect(MediaPlaybackPolicy.seekPosition(30, duration: .infinity) == 0, "Unknown duration does not expose invalid seek values")
        expect(MediaPlaybackPolicy.previousIndex(current: 2, count: 3, elapsed: 4) == 2, "Previous restarts the current track after three seconds")
        expect(MediaPlaybackPolicy.previousIndex(current: 2, count: 3, elapsed: 2) == 1, "Previous near the beginning selects the preceding track")
        expect(MediaPlaybackPolicy.previousIndex(current: 0, count: 3, elapsed: 2) == 0, "Previous stays within the playlist")
        expect(MediaPlaybackPolicy.previousIndex(current: 0, count: 0, elapsed: 2) == nil, "An empty playlist has no previous track")
        expect(MediaPlaybackPolicy.nextIndex(current: 0, count: 3) == 1, "Next advances by one track")
        expect(MediaPlaybackPolicy.nextIndex(current: 2, count: 3) == nil, "Last track does not wrap automatically")
        expect(MediaPlaybackPolicy.nextIndex(current: -1, count: 3) == nil, "Invalid current index cannot advance")
        expect(MediaPlaybackPolicy.nextIndex(current: 0, count: 0) == nil, "An empty playlist has no next track")
    }
    @MainActor private static func checkAdapterForwarding() {
        let adapter = RecordingMediaAdapter()
        let model = MediaModel(adapter: adapter)
        expect(model.sourceName == "Test Media", "Source name belongs to the adapter")
        expect(!model.snapshot.isPlaying && !model.snapshot.canPlay, "Initial snapshot does not claim playback")
        var snapshot = MediaSnapshot()
        snapshot.title = "A local track"
        snapshot.artist = "Test Artist"
        snapshot.duration = 90
        snapshot.elapsed = 12
        snapshot.isPlaying = true
        snapshot.canPlay = true
        snapshot.trackCount = 2
        adapter.onUpdate?(snapshot)
        expect(model.snapshot.title == "A local track" && model.snapshot.artist == "Test Artist", "Metadata passes through the supported adapter")
        expect(model.snapshot.isPlaying && model.snapshot.elapsed == 12 && model.snapshot.duration == 90, "Playback state and progress reach the shared model")
        model.playPause()
        model.previous()
        model.next()
        model.seek(to: 25)
        model.stop()
        model.shutdown()
        expect(adapter.calls == ["playPause", "previous", "next", "seek", "stop", "shutdown"], "Media controls route only to their selected adapter")
        expect(adapter.position == 25, "Seek value reaches the adapter")
    }
    private static func expect(_ value: @autoclosure () -> Bool, _ message: String,
                               file: StaticString = #file, line: UInt = #line) {
        precondition(value(), message, file: file, line: line)
    }
}
