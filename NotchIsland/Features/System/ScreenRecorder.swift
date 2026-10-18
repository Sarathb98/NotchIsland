import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

/// Screen recording is started only by an explicit user action. This model never
/// attempts to discover recordings owned by other applications.
@MainActor
final class ScreenRecorder: ObservableObject {
    enum State: Equatable { case idle, choosingDestination, starting, recording, stopping }
    @Published private(set) var state: State = .idle
    @Published private(set) var error: String?
    @Published private(set) var lastRecordingURL: URL?
    let recordingState: AppRecordingState
    private var session: (any ScreenRecordingSessionControlling)?
    private var sessionID: UUID?
    private var destinationURL: URL?
    private var stagingURL: URL?

    init(recordingState: AppRecordingState) { self.recordingState = recordingState }

    var isSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    func start() async {
        guard state == .idle else { return }
        error = nil
        guard #available(macOS 15.0, *) else {
            error = String(localized: "Recording requires macOS 15 or later. You can use the macOS Screenshot app on this Mac.")
            return
        }
        state = .choosingDestination
        let savePanel = NSSavePanel()
        savePanel.title = String(localized: "Record Main Display")
        savePanel.message = String(localized: "Record your main display and cursor without audio. macOS may request screen recording access after you choose a file.")
        savePanel.prompt = String(localized: "Start Recording")
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.nameFieldStringValue = String(localized: "Notch Island Recording") + ".mp4"
        savePanel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            savePanel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let destination = savePanel.url else { state = .idle; return }

        let id = UUID()
        // Write beside the chosen file and replace it only after successful
        // finalization. A denied permission or failed start cannot erase a file.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".notch-island-recording-\(id.uuidString).mp4")
        sessionID = id
        destinationURL = destination
        stagingURL = staging
        state = .starting
        let capture = ScreenRecordingSession(
            onStarted: { [weak self] in
                guard let self, sessionID == id, state == .starting else { return }
                state = .recording
                recordingState.didStartOwnedSession(id)
            },
            onFinished: { [weak self] failure in self?.finish(session: id, failure: failure) }
        )
        session = capture
        do {
            try await capture.start(url: staging, displayID: CGMainDisplayID())
        } catch {
            finish(session: id, failure: error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .recording, let session, let id = sessionID else { return }
        state = .stopping
        do { try await session.stop() }
        catch {
            guard sessionID == id else { return }
            // Preserve the session so the user can retry stopping the capture.
            state = .recording
            self.error = String(localized: "Could not stop recording: \(error.localizedDescription)")
        }
    }

    func revealLastRecording() {
        guard let lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecordingURL])
    }

    private func finish(session id: UUID, failure: String?) {
        guard sessionID == id else { return }
        recordingState.didStopOwnedSession(id)
        sessionID = nil
        session = nil
        state = .idle
        defer { destinationURL = nil; stagingURL = nil }
        if let failure {
            error = String(localized: "Recording failed: \(failure)")
            // Keep any partial file available for recovery rather than deleting it.
            if let stagingURL, FileManager.default.fileExists(atPath: stagingURL.path) {
                lastRecordingURL = stagingURL
            }
            return
        }
        guard let destinationURL, let stagingURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
            }
            lastRecordingURL = destinationURL
            error = nil
        } catch {
            lastRecordingURL = stagingURL
            self.error = String(localized: "The recording finished, but could not be moved to your chosen file: \(error.localizedDescription). Use Show in Finder to recover it.")
        }
    }
}

@MainActor
private protocol ScreenRecordingSessionControlling: AnyObject {
    func start(url: URL, displayID: CGDirectDisplayID) async throws
    func stop() async throws
}

@available(macOS 15.0, *)
@MainActor
private final class ScreenRecordingSession: NSObject, ScreenRecordingSessionControlling, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var hasFinished = false
    private let onStarted: @MainActor () -> Void
    private let onFinished: @MainActor (String?) -> Void

    init(onStarted: @escaping @MainActor () -> Void, onFinished: @escaping @MainActor (String?) -> Void) {
        self.onStarted = onStarted
        self.onFinished = onFinished
    }

    func start(url: URL, displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingError.displayUnavailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        // SCDisplay reports points. Respect Retina scale, with a 3840-pixel cap
        // to keep capture memory bounded on very large external displays.
        let pixelWidth = Double(display.width) * Double(filter.pointPixelScale)
        let pixelHeight = Double(display.height) * Double(filter.pointPixelScale)
        let scale = min(1.0, 3840.0 / max(1, max(pixelWidth, pixelHeight)))
        configuration.width = max(2, Int(pixelWidth * scale) / 2 * 2)
        configuration.height = max(2, Int(pixelHeight * scale) / 2 * 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        self.output = output
        do {
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
        } catch {
            hasFinished = true
            try? await stream.stopCapture()
            self.stream = nil
            self.output = nil
            throw error
        }
    }

    func stop() async throws { try await stream?.stopCapture() }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, !hasFinished else { return }
            onStarted()
        }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in self?.complete(failure: nil) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.complete(failure: message) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.complete(failure: message) }
    }

    private func complete(failure: String?) {
        guard !hasFinished else { return }
        hasFinished = true
        let finishingStream = stream
        stream = nil
        output = nil
        Task { @MainActor in
            // A writer failure does not necessarily stop capture. Explicitly close
            // the stream before reporting completion and releasing its owner.
            try? await finishingStream?.stopCapture()
            onFinished(failure)
        }
    }

    private enum RecordingError: LocalizedError {
        case displayUnavailable
        var errorDescription: String? { String(localized: "The main display is no longer available. Try again after reconnecting the display.") }
    }
}

struct ScreenRecordingWidget: View {
    @ObservedObject var recorder: ScreenRecorder
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Screen Recording", systemImage: "record.circle")
                Spacer()
                if recorder.state == .recording {
                    Button("Stop Recording") { Task { await recorder.stop() } }
                        .tint(.red)
                } else {
                    Button(buttonTitle) { Task { await recorder.start() } }
                        .disabled(!recorder.isSupported || recorder.state != .idle)
                }
            }
            Text(recorder.isSupported ? String(localized: "Main display and cursor · No audio") : String(localized: "Recording requires macOS 15 or later"))
                .font(.caption).foregroundStyle(.secondary)
            if let error = recorder.error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if recorder.lastRecordingURL != nil {
                Button("Show Recording in Finder") { recorder.revealLastRecording() }
                    .font(.caption)
            }
        }.accessibilityElement(children: .contain)
    }
    private var buttonTitle: String {
        switch recorder.state {
        case .idle: return String(localized: "Record Main Display…")
        case .choosingDestination: return String(localized: "Choose a File…")
        case .starting: return String(localized: "Starting…")
        case .recording: return String(localized: "Recording")
        case .stopping: return String(localized: "Finishing…")
        }
    }
}
