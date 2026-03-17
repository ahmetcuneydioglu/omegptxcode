import SwiftUI
import AVFoundation
import UIKit
import Observation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }
}



extension UIApplication {
    var bottomSafeAreaInset: CGFloat {
        let scenes = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return scenes.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }

    func endEditing() {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.endEditing(true) }
    }
}

@Observable
final class CameraManager {
    let session = AVCaptureSession()
    private(set) var isAuthorized = false

    // Camera operations are done on a dedicated queue to keep UI responsive.
    private let sessionQueue = DispatchQueue(label: "com.omegptnative.camera.session")
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false

    // Checks permission, requests access if needed, then configures and starts capture.
    func handleCameraPermissionAndStart() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            configureSessionIfNeeded()
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                }
                if granted {
                    self.configureSessionIfNeeded()
                    self.startSession()
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        @unknown default:
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }

    // Configures the capture session once with a front camera input as default.
    private func configureSessionIfNeeded() {
        sessionQueue.async {
            guard !self.isConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            do {
                guard let device = self.cameraDevice(for: .front) else {
                    self.session.commitConfiguration()
                    return
                }

                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                    self.isConfigured = true
                }
            } catch {
                self.session.commitConfiguration()
                return
            }

            self.session.commitConfiguration()
        }
    }

    // Starts the session if configured and not already running.
    func startSession() {
        sessionQueue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // Stops the session to release camera resources while preserving configuration.
    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // Switches between front and back cameras by swapping session inputs.
    func flipCamera() {
        sessionQueue.async {
            guard self.isConfigured, let currentInput = self.videoInput else { return }

            let currentPosition = currentInput.device.position
            let targetPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front

            guard let targetDevice = self.cameraDevice(for: targetPosition) else { return }

            do {
                let targetInput = try AVCaptureDeviceInput(device: targetDevice)
                self.session.beginConfiguration()
                self.session.removeInput(currentInput)

                if self.session.canAddInput(targetInput) {
                    self.session.addInput(targetInput)
                    self.videoInput = targetInput
                } else {
                    if self.session.canAddInput(currentInput) {
                        self.session.addInput(currentInput)
                    }
                }

                self.session.commitConfiguration()
            } catch {
                return
            }
        }
    }

    private func cameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }
}

struct PremiumGenderIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color(red: 0.32, green: 0.68, blue: 1.0)],
                        center: .topLeading,
                        startRadius: 1,
                        endRadius: 16
                    )
                )
                .frame(width: 18, height: 18)
                .offset(x: -4, y: -2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.9), Color(red: 1.0, green: 0.44, blue: 0.72)],
                        center: .top,
                        startRadius: 1,
                        endRadius: 16
                    )
                )
                .frame(width: 18, height: 18)
                .offset(x: 5, y: 2)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.9), Color.pink.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 16, height: 6)
                .rotationEffect(.degrees(-26))

            Circle()
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 0.8)
                .frame(width: 23, height: 23)
                .blendMode(.plusLighter)

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 5, height: 5)
                .offset(x: -8, y: -8)
        }
        .frame(width: 24, height: 24)
        .shadow(color: Color.cyan.opacity(0.35), radius: 3, x: -1, y: 0)
        .shadow(color: Color.pink.opacity(0.35), radius: 3, x: 1, y: 1)
    }
}

#Preview {
    MainCameraView()
}
