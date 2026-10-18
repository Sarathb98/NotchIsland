import AVFoundation
import SwiftUI

/// Circular live preview sized to sit beside the dashboard's other cards.
struct CameraMirrorWidget: View {
    @ObservedObject var model: CameraMirrorModel
    var height: CGFloat = 180

    private var circleSize: CGFloat {
        max(96, min(model.error == nil ? 196 : 150, height - (model.error == nil ? 42 : 68)))
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color(white: 0.11))
                if let session = model.session, model.isRunning, !model.isInterrupted {
                    CameraPreview(session: session)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                } else {
                    VStack(spacing: 7) {
                        Image(systemName: model.isInterrupted ? "video.slash" : "web.camera")
                            .font(.system(size: 26, weight: .light))
                        Text("Mirror")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.68))
                    .accessibilityHidden(true)
                }
            }
            .frame(width: circleSize, height: circleSize)
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Camera mirror")
            .accessibilityValue(model.isRunning ? String(localized: "Live camera preview") : String(localized: "Off"))

            Button(model.isRunning || model.isStarting ? String(localized: "Stop Mirror") : String(localized: "Start Mirror")) {
                if model.isRunning || model.isStarting { model.stop() }
                else { Task { await model.start() } }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(model.isRunning ? Color.white.opacity(0.65) : Color(red: 0.05, green: 0.61, blue: 1))
            .accessibilityIdentifier("mirror.toggle")

            if let error = model.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .help(error)
                    .accessibilityIdentifier("mirror.status")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.mirror")
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.setSession(session)
        return view
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.setSession(session)
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }

        func setSession(_ session: AVCaptureSession) {
            if previewLayer.session !== session { previewLayer.session = session }
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}
