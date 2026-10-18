import AVFoundation
import SwiftUI

/// The capture queue serializes start/stop calls. AVFoundation owns the session's
/// internal synchronization while its preview layer reads it on the main thread.
private final class CameraSessionHandle: @unchecked Sendable {
    let session: AVCaptureSession
    init(_ session: AVCaptureSession) { self.session = session }
}

/// Owns only a live camera preview. No frames are recorded or saved.
@MainActor
final class CameraMirrorModel: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var isInterrupted = false
    @Published private(set) var error: String?

    private let captureQueue = DispatchQueue(label: "com.notchisland.camera-mirror.capture", qos: .userInitiated)
    private var generation = 0
    private var sessionObservers: [NSObjectProtocol] = []

    /// Call only in response to the user's Start Mirror action.
    func start() async {
        guard !isStarting, !isRunning else { return }
        generation += 1
        let request = generation
        isStarting = true
        isInterrupted = false
        error = nil

        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard request == generation else { return }
            if !granted {
                fail(String(localized: "Camera access was denied. Enable it in Privacy & Security settings."))
                return
            }
        } else if authorization != .authorized {
            fail(String(localized: "Camera access is unavailable. Check Privacy & Security settings."))
            return
        }

        guard request == generation else { return }
        guard let camera = AVCaptureDevice.default(for: .video) else {
            fail(String(localized: "No camera is available."))
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            let newSession = AVCaptureSession()
            newSession.beginConfiguration()
            newSession.sessionPreset = .medium
            guard newSession.canAddInput(input) else {
                newSession.commitConfiguration()
                fail(String(localized: "The camera could not be opened."))
                return
            }
            newSession.addInput(input)
            newSession.commitConfiguration()
            guard request == generation else { return }

            session = newSession
            observe(newSession)
            let handle = CameraSessionHandle(newSession)
            let running = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                captureQueue.async {
                    handle.session.startRunning()
                    continuation.resume(returning: handle.session.isRunning)
                }
            }
            guard request == generation else { return }
            isStarting = false
            isRunning = running
            if !running {
                stop()
                error = String(localized: "The camera could not start. It may be in use by another app.")
            }
        } catch {
            guard request == generation else { return }
            fail(String(localized: "The camera could not be opened: \(error.localizedDescription)"))
        }
    }

    /// Releases the camera when the island closes or moves to another page.
    func stop() {
        generation += 1
        isStarting = false
        isRunning = false
        isInterrupted = false
        removeSessionObservers()
        guard let oldSession = session else { return }
        session = nil
        let handle = CameraSessionHandle(oldSession)
        captureQueue.async {
            if handle.session.isRunning { handle.session.stopRunning() }
        }
    }

    func shutdown() { stop() }

    private func fail(_ message: String) {
        stop()
        error = message
    }

    private func observe(_ session: AVCaptureSession) {
        removeSessionObservers()
        let center = NotificationCenter.default
        let sessionID = ObjectIdentifier(session)
        sessionObservers = [
            center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let current = self.session, ObjectIdentifier(current) == sessionID else { return }
                    self.fail(String(localized: "The camera stopped unexpectedly. Try Start Mirror again."))
                }
            },
            center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let current = self.session, ObjectIdentifier(current) == sessionID else { return }
                    self.isInterrupted = true
                    self.error = String(localized: "The camera is temporarily unavailable.")
                }
            },
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let current = self.session, ObjectIdentifier(current) == sessionID else { return }
                    self.isInterrupted = false
                    self.error = nil
                }
            }
        ]
    }

    private func removeSessionObservers() {
        for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
        sessionObservers.removeAll()
    }
}
