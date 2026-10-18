import AppKit
import Foundation
import SwiftUI

@MainActor
final class DownloadModel: ObservableObject {
    enum State: Equatable { case idle, choosingDestination, downloading, cancelling, completed, cancelled, failed }
    @Published var address = ""
    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double?
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64 = 0
    @Published private(set) var error: String?
    @Published private(set) var savedURL: URL?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var transferID: UUID?
    private var scopedDestination: URL?

    var isBusy: Bool { state == .choosingDestination || state == .downloading || state == .cancelling }

    static func validatedURL(_ address: String) -> URL? {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, let url = components.url else { return nil }
        return url
    }

    func start() async {
        guard !isBusy else { return }
        guard let url = Self.validatedURL(address) else {
            error = String(localized: "Enter a valid HTTPS URL without a username or password.")
            state = .failed
            return
        }
        error = nil
        state = .choosingDestination
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Download")
        panel.message = String(localized: "Choose where to save this file. Downloads are never opened automatically.")
        panel.prompt = String(localized: "Download")
        panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? String(localized: "Download") : url.lastPathComponent
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let destination = panel.url else { state = .idle; return }
        let id = UUID()
        transferID = id
        savedURL = nil
        progress = nil
        receivedBytes = 0
        expectedBytes = 0
        if destination.startAccessingSecurityScopedResource() { scopedDestination = destination }
        let delegate = DownloadDelegate(destination: destination,
            onProgress: { [weak self] received, expected in
                Task { @MainActor [weak self] in
                    guard let self, transferID == id, state == .downloading else { return }
                    receivedBytes = received
                    expectedBytes = expected
                    progress = expected > 0 ? min(1, Double(received) / Double(expected)) : nil
                }
            },
            onCompletion: { [weak self] saved, message, cancelled in
                Task { @MainActor [weak self] in self?.complete(id: id, saved: saved, message: message, cancelled: cancelled) }
            })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 12
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.session = session
        downloadTask = task
        state = .downloading
        task.resume()
    }

    func cancel() {
        guard state == .downloading else { return }
        state = .cancelling
        downloadTask?.cancel()
    }
    func reveal() {
        guard let savedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
    }
    private func complete(id: UUID, saved: URL?, message: String?, cancelled: Bool) {
        guard transferID == id else { return }
        transferID = nil
        downloadTask = nil
        session?.finishTasksAndInvalidate()
        session = nil
        scopedDestination?.stopAccessingSecurityScopedResource()
        scopedDestination = nil
        savedURL = saved
        error = message
        state = cancelled ? .cancelled : saved != nil ? .completed : .failed
        if saved != nil { progress = 1 }
    }
    deinit {
        session?.invalidateAndCancel()
        scopedDestination?.stopAccessingSecurityScopedResource()
    }
}

/// URLSession owns this delegate for one transfer. Its callbacks run serially on
/// the session's delegate queue, including the temporary-file move.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private let onCompletion: @Sendable (URL?, String?, Bool) -> Void
    private var savedURL: URL?
    private var failure: String?
    init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void,
         onCompletion: @escaping @Sendable (URL?, String?, Bool) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, DownloadURLPolicy.permits(url) else {
            failure = String(localized: "The server redirected this download to an unsupported or insecure URL.")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard failure == nil else { return }
        guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
            failure = status.map { String(localized: "The server returned HTTP \($0).") } ?? String(localized: "The server did not return a valid HTTP response.")
            return
        }
        let manager = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".notch-download-\(UUID().uuidString)")
        do {
            // Move from URLSession's temporary file while the delegate callback is
            // active. Replace the user's file only after a successful transfer.
            try manager.copyItem(at: location, to: staging)
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }
            savedURL = destination
        } catch {
            failure = String(localized: "Could not save the download: \(error.localizedDescription)")
            try? manager.removeItem(at: staging)
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let cancelled = (error as? URLError)?.code == .cancelled
        let message = cancelled ? nil : failure ?? error?.localizedDescription
        onCompletion(savedURL, message, cancelled)
    }
}

private enum DownloadURLPolicy {
    static func permits(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}

struct DownloadsWidget: View {
    @ObservedObject var model: DownloadModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloads").font(.headline)
            TextField("https://example.com/file", text: $model.address)
                .textFieldStyle(.roundedBorder).disabled(model.isBusy)
                .onSubmit { Task { await model.start() } }
                .accessibilityLabel("Download URL")
            HStack {
                Button(model.state == .choosingDestination ? String(localized: "Choose a File…") : String(localized: "Download…")) { Task { await model.start() } }
                    .disabled(model.isBusy)
                if model.state == .downloading || model.state == .cancelling {
                    Button(model.state == .cancelling ? String(localized: "Cancelling…") : String(localized: "Cancel")) { model.cancel() }
                        .disabled(model.state == .cancelling)
                }
                if model.savedURL != nil { Button("Show in Finder") { model.reveal() } }
            }
            if model.state == .downloading || model.state == .cancelling {
                if let progress = model.progress { ProgressView(value: progress) }
                else { ProgressView().controlSize(.small) }
                Text(progressDescription).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if model.state == .completed { Label("Download complete", systemImage: "checkmark.circle").font(.caption) }
            if model.state == .cancelled { Text("Download cancelled").font(.caption).foregroundStyle(.secondary) }
            Text("Only transfers started here appear in this list. Files stay at the location you choose.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private var progressDescription: String {
        let received = ByteCountFormatter.string(fromByteCount: model.receivedBytes, countStyle: .file)
        guard model.expectedBytes > 0 else { return String(localized: "\(received) downloaded") }
        let expected = ByteCountFormatter.string(fromByteCount: model.expectedBytes, countStyle: .file)
        return String(localized: "\(received) of \(expected)")
    }
}
