import Foundation
import Combine
import AVFoundation
import WebRTC

final class WebRTCManager: NSObject, ObservableObject {
    static let shared = WebRTCManager()

    @Published var localVideoTrack: RTCVideoTrack?
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var isConnectionStable = false

    let peerConnectionFactory: RTCPeerConnectionFactory
    let encoderFactory: RTCDefaultVideoEncoderFactory
    let decoderFactory: RTCDefaultVideoDecoderFactory
    var peerConnection: RTCPeerConnection?
    var videoCapturer: RTCCameraVideoCapturer?
    var localVideoSource: RTCVideoSource?
    var localAudioTrack: RTCAudioTrack?
    var currentPartnerId: String?
    private var isUsingSimulatorMedia = false
    private let beautyFilterProvider = BeautyFilterProvider()
    private var beautyFrameProcessor: BeautyFrameProcessorDelegate?
    @Published var isBeautyFilterEnabled = true
    @Published private(set) var isCameraAuthorized = false
    @Published private(set) var beautySmoothness: Float = 0.0
    @Published private(set) var beautyVibrance: Float = 0.0
    @Published private(set) var beautyExposure: Float = 0.0
    @Published private(set) var beautySharpness: Float = 0.0
    @Published private(set) var beautyNoseContour: Float = 0.0
    @Published private(set) var beautyJawlineContour: Float = 0.0
    @Published private(set) var beautyTeethWhitening: Float = 0.0
    @Published private(set) var beautyTeethLuminanceMin: Float = 0.46
    @Published private(set) var beautyTeethChromaMax: Float = 0.38
    @Published private(set) var filterPresetIntensity: Float = 0.0
    @Published private(set) var selectedColorPreset: ProfessionalColorPreset = .none
    @Published private(set) var filterPreviewImages: [ProfessionalColorPreset: UIImage] = [:]

    var onSignalGenerated: (([String: Any]) -> Void)?

    override init() {
        print("🧪 WebRTCManager init started")
        RTCInitializeSSL()

        encoderFactory = RTCDefaultVideoEncoderFactory()
        decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )

        super.init()

        print("✅ WebRTCManager initialized")
        print("📦 RTCPeerConnectionFactory: \(type(of: peerConnectionFactory))")
        print("📦 RTCDefaultVideoEncoderFactory: \(type(of: encoderFactory))")
        print("📦 RTCDefaultVideoDecoderFactory: \(type(of: decoderFactory))")

        if let h264Codec = encoderFactory.supportedCodecs().first(where: { codec in
            codec.name.lowercased().contains("h264")
        }) {
            encoderFactory.preferredCodec = h264Codec
            print("🎥 H.264 preferred codec enabled: \(h264Codec.name)")
        } else {
            print("ℹ️ H.264 codec not found in supportedCodecs; default codec ordering will be used.")
        }
        updateBeautyConfiguration(
            smoothing: beautySmoothness,
            eyeEnhance: beautySharpness,
            noseContour: beautyNoseContour,
            jawlineContour: beautyJawlineContour,
            teethWhitening: beautyTeethWhitening,
            teethLuminanceMin: beautyTeethLuminanceMin,
            teethChromaMax: beautyTeethChromaMax,
            vibrance: beautyVibrance,
            exposure: beautyExposure,
            presetIntensity: filterPresetIntensity
        )
    }

    func startSession(partnerId: String, isInitiator: Bool) {
        currentPartnerId = partnerId
        setupPeerConnection()
        startMedia()
        if isInitiator {
            createOffer()
        }
    }

    func endSession() {
        peerConnection?.close()
        peerConnection = nil
        currentPartnerId = nil
        remoteVideoTrack = nil
        isConnectionStable = false
    }

    func endCall() {
        endSession()
    }

    func handleIncomingSignal(_ signal: [String: Any], from senderId: String) {
        if currentPartnerId == nil {
            currentPartnerId = senderId
        }

        if let type = signal["type"] as? String,
           let sdp = signal["sdp"] as? String {
            let descriptionType: RTCSdpType = type == "offer" ? .offer : .answer
            let remoteSDP = RTCSessionDescription(type: descriptionType, sdp: sdp)
            peerConnection?.setRemoteDescription(remoteSDP) { [weak self] error in
                if let error {
                    print("❌ setRemoteDescription error: \(error.localizedDescription)")
                    return
                }
                if descriptionType == .offer {
                    self?.createAnswer()
                }
            }
            return
        }

        if signal["candidate"] != nil {
            addIceCandidate(candidateData: signal)
        }
    }

    func handleRemoteOffer(sdp: String) {
        if peerConnection == nil {
            setupPeerConnection()
            startLocalCapture()
        }
        let remoteSDP = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection?.setRemoteDescription(remoteSDP) { [weak self] error in
            if let error {
                print("❌ handleRemoteOffer setRemoteDescription error: \(error.localizedDescription)")
                return
            }
            self?.createAnswer()
        }
    }

    func handleRemoteAnswer(sdp: String) {
        if peerConnection == nil {
            setupPeerConnection()
            startLocalCapture()
        }
        let remoteSDP = RTCSessionDescription(type: .answer, sdp: sdp)
        peerConnection?.setRemoteDescription(remoteSDP) { error in
            if let error {
                print("❌ handleRemoteAnswer setRemoteDescription error: \(error.localizedDescription)")
            }
        }
    }

    func addIceCandidate(candidateData: [String: Any]) {
        addIceCandidate(from: candidateData)
    }

    func handleIncomingCandidate(_ payload: [String: Any]) {
        addIceCandidate(candidateData: payload)
    }

    func setupPeerConnection() {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = peerConnectionFactory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        #if targetEnvironment(simulator)
        localAudioTrack = nil
        print("🧪 Simulator detected: skipping RTCAudioTrack initialization.")
        #else
        let audioSource = peerConnectionFactory.audioSource(
            with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        )
        let audioTrack = peerConnectionFactory.audioTrack(with: audioSource, trackId: "audio0")
        localAudioTrack = audioTrack
        _ = peerConnection?.add(audioTrack, streamIds: ["stream0"])
        #endif

        if localVideoTrack == nil {
            localVideoSource = peerConnectionFactory.videoSource()
            if let localVideoSource {
                localVideoTrack = peerConnectionFactory.videoTrack(with: localVideoSource, trackId: "video0")
            }
        }

        if let localVideoTrack {
            _ = peerConnection?.add(localVideoTrack, streamIds: ["stream0"])
            applyVideoSenderBitrate()
        }
    }

    func startMedia() {
        #if targetEnvironment(simulator)
        isUsingSimulatorMedia = true
        ensureSimulatorDummyVideoTrack()
        print("🧪 Simulator media mode active. Using dummy RTCVideoTrack.")
        #else
        isUsingSimulatorMedia = false
        startLocalCapture()
        #endif
    }

    func startPreviewCapture() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.isCameraAuthorized = true
            }
            ensurePreviewPipeline()
            startLocalCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.isCameraAuthorized = granted
                }
                guard granted else { return }
                self.ensurePreviewPipeline()
                self.startLocalCapture()
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
            }
        @unknown default:
            DispatchQueue.main.async {
                self.isCameraAuthorized = false
            }
        }
    }

    func stopPreviewCapture() {
        guard let videoCapturer else { return }
        videoCapturer.stopCapture {
            print("🛑 Preview capture stopped.")
        }
    }

    func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                if let error { print("❌ offer error: \(error.localizedDescription)") }
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { setError in
                if let setError {
                    print("❌ setLocalDescription(offer) error: \(setError.localizedDescription)")
                    return
                }
                self.onSignalGenerated?(["type": "offer", "sdp": sdp.sdp])
            }
        }
    }

    func createAnswer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp else {
                if let error { print("❌ answer error: \(error.localizedDescription)") }
                return
            }

            self.peerConnection?.setLocalDescription(sdp) { setError in
                if let setError {
                    print("❌ setLocalDescription(answer) error: \(setError.localizedDescription)")
                    return
                }
                self.onSignalGenerated?(["type": "answer", "sdp": sdp.sdp])
            }
        }
    }

    func addIceCandidate(from payload: [String: Any]) {
        let rawCandidate = payload["candidate"]
        let candidateString = rawCandidate as? String
            ?? (rawCandidate as? [String: Any])?["candidate"] as? String
        guard let candidate = candidateString else { return }

        let candidateDict = rawCandidate as? [String: Any]
        let sdpMid = (payload["sdpMid"] as? String) ?? (candidateDict?["sdpMid"] as? String)
        let sdpMLineIndex: Int32
        if let index = (payload["sdpMLineIndex"] as? NSNumber)?.int32Value {
            sdpMLineIndex = index
        } else if let index = payload["sdpMLineIndex"] as? Int {
            sdpMLineIndex = Int32(index)
        } else if let index = (candidateDict?["sdpMLineIndex"] as? NSNumber)?.int32Value {
            sdpMLineIndex = index
        } else if let index = candidateDict?["sdpMLineIndex"] as? Int {
            sdpMLineIndex = Int32(index)
        } else {
            sdpMLineIndex = 0
        }

        let ice = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection?.add(ice, completionHandler: { error in
            if let error {
                print("❌ addIceCandidate error: \(error.localizedDescription)")
            }
        })
    }

    func setAudioMuted(_ isMuted: Bool) {
        localAudioTrack?.isEnabled = !isMuted
        print("🎙️ Local audio muted: \(isMuted)")
    }

    func setVideoEnabled(_ isEnabled: Bool) {
        localVideoTrack?.isEnabled = isEnabled
        print("🎥 Local video enabled: \(isEnabled)")
    }

    func switchCamera() {
        guard let videoCapturer else { return }
        let currentInputs = videoCapturer.captureSession.inputs.compactMap { $0 as? AVCaptureDeviceInput }
        let currentPosition = currentInputs.first?.device.position ?? .front
        let targetPosition: AVCaptureDevice.Position = currentPosition == .front ? .back : .front

        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let targetDevice = devices.first(where: { $0.position == targetPosition }) else { return }
        guard let format = bestHDFormat(for: targetDevice) else { return }
        let fps = bestFPS(for: format)

        videoCapturer.stopCapture { [weak self] in
            videoCapturer.startCapture(with: targetDevice, format: format, fps: fps)
            print("🔄 Camera switched to \(targetPosition == .front ? "front" : "back")")
            self?.applyVideoSenderBitrate()
        }
    }

    func startLocalCapture() {
        guard let localVideoSource else { return }

        if videoCapturer == nil {
            let processor = BeautyFrameProcessorDelegate(
                videoSource: localVideoSource,
                filterProvider: beautyFilterProvider
            )
            processor.isEnabled = isBeautyFilterEnabled
            beautyFrameProcessor = processor
            videoCapturer = RTCCameraVideoCapturer(delegate: processor)
        }
        if let videoCapturer, videoCapturer.captureSession.isRunning {
            return
        }
        do {
            let captureSetup = try resolveCaptureSetup()
            captureSetup.capturer.startCapture(
                with: captureSetup.device,
                format: captureSetup.format,
                fps: captureSetup.fps
            )
            print("🎥 Local capture started at target HD profile: 1280x720 @ \(captureSetup.fps)fps")
            applyVideoSenderBitrate()
        } catch {
            print("⚠️ startLocalCapture failed: \(error.localizedDescription)")
        }
    }

    func setBeautyFilterEnabled(_ isEnabled: Bool) {
        isBeautyFilterEnabled = isEnabled
        beautyFrameProcessor?.isEnabled = isEnabled
        print("✨ Beauty filter enabled: \(isEnabled)")
    }

    func updateBeautyConfiguration(
        smoothing: Float = 0.0,
        eyeEnhance: Float = 0.0,
        noseContour: Float = 0.0,
        jawlineContour: Float = 0.0,
        teethWhitening: Float = 0.0,
        teethLuminanceMin: Float = 0.46,
        teethChromaMax: Float = 0.38,
        vibrance: Float = 0.0,
        exposure: Float = 0.0,
        presetIntensity: Float = 0.0,
        preset: ProfessionalColorPreset? = nil
    ) {
        let resolvedPreset = preset ?? selectedColorPreset
        beautySmoothness = smoothing
        beautySharpness = eyeEnhance
        beautyNoseContour = noseContour
        beautyJawlineContour = jawlineContour
        beautyTeethWhitening = teethWhitening
        beautyTeethLuminanceMin = teethLuminanceMin
        beautyTeethChromaMax = teethChromaMax
        beautyVibrance = vibrance
        beautyExposure = exposure
        filterPresetIntensity = presetIntensity
        selectedColorPreset = resolvedPreset
        beautyFilterProvider.updateConfiguration(
            .init(
                smoothing: smoothing,
                eyeEnhance: eyeEnhance,
                noseContour: noseContour,
                jawlineContour: jawlineContour,
                teethWhitening: teethWhitening,
                teethLuminanceMin: teethLuminanceMin,
                teethChromaMax: teethChromaMax,
                vibrance: vibrance,
                exposure: exposure,
                colorPreset: resolvedPreset,
                presetIntensity: presetIntensity
            )
        )
    }

    func refreshFilterPreviewImages() {
        let cgImages = beautyFilterProvider.generatePreviewImages(intensity: filterPresetIntensity)
        let uiImages = cgImages.reduce(into: [ProfessionalColorPreset: UIImage]()) { partialResult, entry in
            partialResult[entry.key] = UIImage(cgImage: entry.value)
        }
        DispatchQueue.main.async {
            self.filterPreviewImages = uiImages
        }
    }

    private func ensurePreviewPipeline() {
        if localVideoSource == nil {
            localVideoSource = peerConnectionFactory.videoSource()
        }
        if localVideoTrack == nil, let localVideoSource {
            localVideoTrack = peerConnectionFactory.videoTrack(with: localVideoSource, trackId: "video0")
        }
        if beautyFrameProcessor == nil, let localVideoSource {
            let processor = BeautyFrameProcessorDelegate(
                videoSource: localVideoSource,
                filterProvider: beautyFilterProvider
            )
            processor.isEnabled = isBeautyFilterEnabled
            beautyFrameProcessor = processor
        }
    }

    private enum MediaCaptureError: LocalizedError {
        case missingCapturer
        case noCameraDevice
        case noCaptureFormat

        var errorDescription: String? {
            switch self {
            case .missingCapturer:
                return "RTCCameraVideoCapturer is not initialized."
            case .noCameraDevice:
                return "No camera device found for local capture."
            case .noCaptureFormat:
                return "No supported capture format found."
            }
        }
    }

    private func resolveCaptureSetup() throws -> (
        capturer: RTCCameraVideoCapturer,
        device: AVCaptureDevice,
        format: AVCaptureDevice.Format,
        fps: Int
    ) {
        guard let capturer = videoCapturer else { throw MediaCaptureError.missingCapturer }
        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let device = devices.first(where: { $0.position == .front }) ?? devices.first else {
            throw MediaCaptureError.noCameraDevice
        }
        guard let format = bestHDFormat(for: device) else {
            throw MediaCaptureError.noCaptureFormat
        }
        return (capturer, device, format, bestFPS(for: format))
    }

    private func ensureSimulatorDummyVideoTrack() {
        if localVideoSource == nil {
            localVideoSource = peerConnectionFactory.videoSource()
        }
        if localVideoTrack == nil, let localVideoSource {
            localVideoTrack = peerConnectionFactory.videoTrack(with: localVideoSource, trackId: "sim-video0")
        }
        if let localVideoTrack {
            _ = peerConnection?.add(localVideoTrack, streamIds: ["stream0"])
        }
    }

    private func bestHDFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        return formats.max(by: { lhs, rhs in
            let lSize = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rSize = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let lScore = abs(Int(lSize.width) - 1280) + abs(Int(lSize.height) - 720)
            let rScore = abs(Int(rSize.width) - 1280) + abs(Int(rSize.height) - 720)
            return lScore > rScore
        })
    }

    private func bestFPS(for format: AVCaptureDevice.Format) -> Int {
        let maxFrameRate = format.videoSupportedFrameRateRanges
            .map(\.maxFrameRate)
            .max() ?? 30
        return Int(min(maxFrameRate, 30))
    }

    private func applyVideoSenderBitrate() {
        guard let sender = peerConnection?.senders.first(where: { $0.track?.kind == kRTCMediaStreamTrackKindVideo }) else { return }
        var parameters = sender.parameters
        if parameters.encodings.isEmpty {
            parameters.encodings = [RTCRtpEncodingParameters()]
        }
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: 2_000_000)
            encoding.maxFramerate = NSNumber(value: 30)
        }
        sender.parameters = parameters
        print("📶 Video sender tuned: maxBitrate=2000kbps, fps=30")
    }
}

extension WebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            DispatchQueue.main.async { self.remoteVideoTrack = track }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            self.isConnectionStable = (newState == .connected || newState == .completed)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onSignalGenerated?([
            "type": "candidate",
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": Int(candidate.sdpMLineIndex)
            ]
        ])
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if let track = transceiver.receiver.track as? RTCVideoTrack {
            DispatchQueue.main.async { self.remoteVideoTrack = track }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            DispatchQueue.main.async { self.remoteVideoTrack = track }
        }
    }
}
