import SwiftUI
import AVFoundation
import UIKit
import WebRTC

struct VideoChatView: View {
    let partnerId: String
    let partnerInfo: PartnerFoundPayload?
    let onEnd: () -> Void
    let onFlipCamera: () -> Void
    let onNextPartner: () -> Void
    @StateObject private var webRTCManager = WebRTCManager.shared
    private var socketService = SocketService.shared
    @State private var isMuted = false
    @State private var isCameraOff = false
    @State private var heartTapped = false
    @State private var chatText = ""
    @State private var localSessionLikes = 0
    @State private var partnerLikes = 0
    @State private var isZoomedLocal = false
    @State private var heartPulse = false
    @State private var showHeartHint = true
    @State private var showPiPControls = false
    @State private var pipTapScale: CGFloat = 1.0
    @State private var baseSafeBottomInset: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var heartParticles: [HeartParticle] = []
    @State private var typingStopWorkItem: DispatchWorkItem?
    @State private var hasSentTyping = false
    @State private var showReportModal = false
    @State private var showReportToast = false
    @State private var showMatchBanner = false
    @FocusState private var isChatFocused: Bool

    init(
        partnerId: String,
        partnerInfo: PartnerFoundPayload?,
        onEnd: @escaping () -> Void,
        onFlipCamera: @escaping () -> Void,
        onNextPartner: @escaping () -> Void
    ) {
        self.partnerId = partnerId
        self.partnerInfo = partnerInfo
        self.onEnd = onEnd
        self.onFlipCamera = onFlipCamera
        self.onNextPartner = onNextPartner
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base layer: full-screen remote video that never moves with keyboard.
                mainVideoLayer
                .ignoresSafeArea(.all)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .zIndex(0)

                LinearGradient(
                    colors: [Color.black.opacity(0.48), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 210)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(.all)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .zIndex(1)

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .zIndex(1)

                // Top UI layer
                ZStack {
                    VStack {
                        topOverlayBar
                            .padding(.horizontal, 14)
                            .padding(.top, max(geometry.safeAreaInsets.top, 10))

                        Spacer()

                        partnerIdentity
                            .padding(.leading, 14)
                            .padding(.bottom, max(baseSafeBottomInset, 12) + 56)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .ignoresSafeArea(.keyboard, edges: .bottom)

                    VStack(spacing: 6) {
                        if showHeartHint {
                            Text("Say Hi with a Heart")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .background(Color.black.opacity(0.16))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .transition(.opacity)
                        }

                        heartActionButton
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 20)
                    .padding(.bottom, max(baseSafeBottomInset, 12) + 78)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .zIndex(25)

                    // PiP stays fixed above the input area and ignores keyboard.
                    pipWindow
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 16)
                        .padding(.bottom, max(baseSafeBottomInset, 12) + 82)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .zIndex(20)
                }
                .zIndex(2)

                GeometryReader { particleGeometry in
                    ZStack {
                        ForEach(heartParticles) { particle in
                            HeartParticleView(
                                particle: particle,
                                containerHeight: particleGeometry.size.height
                            )
                            .position(
                                x: particleGeometry.size.width * particle.startXRatio,
                                y: particleGeometry.size.height + 24
                            )
                            .id(particle.id)
                        }
                    }
                }
                .allowsHitTesting(false)
                .zIndex(7)


                ChatOverlayView(
                    messages: socketService.messages,
                    partnerName: partnerDisplayName,
                    partnerAvatarURL: validatedPartnerAvatarURL,
                    partnerInlineAvatar: validatedPartnerInlineAvatar,
                    guestAvatarAssetName: partnerAvatarPresentation.guestAssetName
                )
                    .padding(.leading, 14)
                    .padding(.trailing, 72)
                    .padding(.bottom, max(baseSafeBottomInset, 12) + 116)
                    .offset(y: -inputKeyboardOffset)
                    .animation(.interactiveSpring(), value: isKeyboardVisible)
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.5, alignment: .bottomLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .allowsHitTesting(false)
                    .zIndex(8)

                if socketService.isPartnerTyping {
                    VStack {
                        Spacer(minLength: 0)
                        PartnerTypingIndicatorView()
                            .offset(y: -inputKeyboardOffset)
                    }
                    .padding(.leading, 14)
                    .padding(.bottom, max(baseSafeBottomInset, 12) + 66)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .zIndex(9)
                }

                VStack {
                    Spacer(minLength: 0)
                    chatInputBar()
                        .offset(y: -inputKeyboardOffset)
                        .animation(.interactiveSpring(), value: isKeyboardVisible)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, inputBaseBottomInset)
                .zIndex(10)

                if showReportToast {
                    Text("Thank you, we are investigating")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.28))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, max(geometry.safeAreaInsets.top, 12) + 50)
                        .zIndex(30)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showReportModal {
                    ReportModalView(
                        partners: socketService.recentPartners,
                        currentPartnerId: socketService.activePartnerId,
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showReportModal = false
                            }
                        },
                        onSubmit: { partner, shouldBlock in
                            socketService.reportPartner(partner, shouldBlock: shouldBlock)
                            withAnimation(.easeOut(duration: 0.2)) {
                                showReportModal = false
                                showReportToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    showReportToast = false
                                }
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(40)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.endEditing()
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 18).onEnded { value in
                    if value.translation.height > 28 {
                        UIApplication.shared.endEditing()
                    }
                }
            )
            .onAppear {
                baseSafeBottomInset = UIApplication.shared.bottomSafeAreaInset
                partnerLikes = partnerInfo?.partnerLikes ?? 0
                socketService.sendProfileViewState(isActive: false)
                triggerMatchBannerIfNeeded()
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    heartPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showHeartHint = false
                    }
                }
            }
            .onChange(of: partnerInfo?.partnerLikes) { _, newValue in
                partnerLikes = newValue ?? partnerLikes
            }
            .onChange(of: socketService.matchedAt) { _, _ in
                triggerMatchBannerIfNeeded()
            }
            .onChange(of: socketService.incomingLikeBurstID) { _, _ in
                spawnHeartBurst(count: Int.random(in: 5...10))
            }
            .onChange(of: chatText) { _, newValue in
                handleTypingStateChange(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard
                    let userInfo = note.userInfo,
                    let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
                else { return }

                let overlap = max(0, UIScreen.main.bounds.height - endFrame.minY)
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardHeight = overlap
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.2
                withAnimation(.easeInOut(duration: duration)) {
                    keyboardHeight = 0
                }
            }
            .onDisappear {
                socketService.sendProfileViewState(isActive: false)
                typingStopWorkItem?.cancel()
                if hasSentTyping {
                    socketService.sendStoppedTyping(to: partnerId)
                    hasSentTyping = false
                }
            }
        }
        .globalToastOverlay()
    }
}

struct RemoteVideoView: View {
    let partnerId: String
    #if canImport(WebRTC)
    let videoTrack: RTCVideoTrack?
    #else
    let videoTrack: Any?
    #endif

    var body: some View {
        ZStack {
            #if canImport(WebRTC)
            if let videoTrack {
                WebRTCVideoRendererView(
                    videoTrack: videoTrack,
                    captureKey: "remote-\(partnerId)"
                )
                    .ignoresSafeArea()
            }
            #endif

            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.15),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(
                {
                    #if canImport(WebRTC)
                    return videoTrack == nil ? 1.0 : 0.0
                    #else
                    return 1.0
                    #endif
                }()
            )

            #if canImport(WebRTC)
            if videoTrack == nil {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("RemoteVideoView")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Partner: \(partnerId)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            #else
            VStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("RemoteVideoView")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Partner: \(partnerId)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            #endif
        }
    }
}

struct LocalVideoView: View {
    #if canImport(WebRTC)
    let videoTrack: RTCVideoTrack?
    #else
    let videoTrack: Any?
    #endif

    var body: some View {
        ZStack {
            #if canImport(WebRTC)
            if let videoTrack {
                WebRTCVideoRendererView(videoTrack: videoTrack, captureKey: nil)
            }
            #endif

            LinearGradient(
                colors: [
                    Color.black.opacity(0.62),
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(
                {
                    #if canImport(WebRTC)
                    return videoTrack == nil ? 1.0 : 0.0
                    #else
                    return 1.0
                    #endif
                }()
            )

            #if canImport(WebRTC)
            if videoTrack == nil {
                VStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("LocalVideoView")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            #else
            VStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("LocalVideoView")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            #endif
        }
    }
}

struct ChatOverlayView: View {
    let messages: [ChatMessage]
    let partnerName: String
    let partnerAvatarURL: String?
    let partnerInlineAvatar: UIImage?
    let guestAvatarAssetName: String?
    private var appUserStore = AppUserStore.shared

    init(messages: [ChatMessage], partnerName: String, partnerAvatarURL: String?, partnerInlineAvatar: UIImage?, guestAvatarAssetName: String?) {
        self.messages = messages
        self.partnerName = partnerName
        self.partnerAvatarURL = partnerAvatarURL
        self.partnerInlineAvatar = partnerInlineAvatar
        self.guestAvatarAssetName = guestAvatarAssetName
    }

    var body: some View {
        let visibleMessages = Array(messages.suffix(15))

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                        chatRow(message: message, fadeIndex: index, totalCount: visibleMessages.count)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .mask(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .black, .black, .black]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: visibleMessages) { _, updated in
                guard let lastId = updated.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: visibleMessages)
        }
    }

    @ViewBuilder
    private func chatRow(message: ChatMessage, fadeIndex: Int, totalCount: Int) -> some View {
        let fade = max(0.35, Double(fadeIndex + 1) / Double(max(totalCount, 1)))
        HStack(spacing: 6) {
            avatarView(for: message, isMine: message.isFromMe)
            bubble(for: message, isMine: message.isFromMe)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(fade)
    }

    private func bubble(for message: ChatMessage, isMine: Bool) -> some View {
        Text(message.text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.98))
            .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
            .lineLimit(4)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isMine
                    ? Color.blue.opacity(0.8)
                    : Color.black.opacity(0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.22), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
    }

    @ViewBuilder
    private func avatarView(for message: ChatMessage, isMine: Bool) -> some View {
        let myAvatar = appUserStore.currentUser?.avatar
        let avatarURLString = isMine
            ? validatedURLString(message.senderProfilePic ?? myAvatar)
            : validatedURLString(message.senderProfilePic ?? partnerAvatarURL)
        let inlineAvatar = isMine
            ? PartnerAvatarPresentation.decodeInlineImage(from: message.senderProfilePic ?? myAvatar)
            : PartnerAvatarPresentation.decodeInlineImage(from: message.senderProfilePic) ?? partnerInlineAvatar
        if let avatarURLString, let url = URL(string: avatarURLString), !avatarURLString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    InitialAvatarView(
                        name: isMine ? (appUserStore.currentUser?.name ?? "Me") : partnerName,
                        size: 20
                    )
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else if let inlineAvatar {
            Image(uiImage: inlineAvatar)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        } else if !isMine, let guestAvatarAssetName {
            Image(guestAvatarAssetName)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
        } else {
            InitialAvatarView(
                name: isMine ? (appUserStore.currentUser?.name ?? "Me") : partnerName,
                size: 30
            )
        }
    }

    private func validatedURLString(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return raw
    }
}

struct ReportModalView: View {
    let partners: [MatchedPartner]
    let currentPartnerId: String?
    let onDismiss: () -> Void
    let onSubmit: (MatchedPartner, Bool) -> Void

    @State private var selectedPartnerId: String?
    @State private var isPresented = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Kötüye Kullanımı Bildir")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if partners.isEmpty {
                    Text("Henüz raporlanabilir eşleşme yok.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Spacer(minLength: 0)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(partners.prefix(3)) { partner in
                                reportCard(for: partner)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 212)
                    Spacer(minLength: 0)
                }

                Text("Bu kullanıcı için gerçekten kötüye kullanımı bildirmek istiyor musun?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Button("İPTAL", action: onDismiss)
                        .buttonStyle(ModernFooterButtonStyle(
                            background: Color.white.opacity(0.12),
                            foreground: .white
                        ))

                    Button("BİLDİR") {
                        guard
                            let selectedPartnerId,
                            let selectedPartner = partners.first(where: { $0.id == selectedPartnerId })
                        else { return }
                        onSubmit(selectedPartner, false)
                    }
                    .buttonStyle(ModernFooterButtonStyle(
                        background: Color(red: 0.84, green: 0.22, blue: 0.20).opacity(0.92),
                        foreground: .white
                    ))
                    .disabled(selectedPartnerId == nil)
                    .opacity(selectedPartnerId == nil ? 0.5 : 1.0)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .frame(maxWidth: 430)
            .padding(.horizontal, 18)
            .scaleEffect(isPresented ? 1.0 : 0.94)
            .opacity(isPresented ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isPresented = true
                }
            }
        }
    }

    private func reportCard(for partner: MatchedPartner) -> some View {
        let isSelected = selectedPartnerId == partner.id

        return VStack(spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                cardMedia(for: partner)
                    .frame(width: 120, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(partner.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(countryFlag(for: partner.country)) \(partner.country)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.red.opacity(0.95) : Color.white.opacity(0.2), lineWidth: isSelected ? 3.0 : 0.8)
            )
            .onTapGesture {
                selectedPartnerId = partner.id
            }
        }
    }

    @ViewBuilder
    private func cardMedia(for partner: MatchedPartner) -> some View {
        if partner.screenshot.size.width > 0 {
            Image(uiImage: partner.screenshot)
                .resizable()
                .scaledToFill()
        } else if let avatarURL = partner.avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    InitialAvatarView(name: partner.name, size: 112)
                }
            }
        } else {
            InitialAvatarView(name: partner.name, size: 112)
        }
    }

    private func countryFlag(for code: String) -> String {
        let uppercase = code.uppercased()
        guard uppercase.count == 2 else { return "🌍" }
        return uppercase.unicodeScalars.compactMap { scalar -> String? in
            guard let regional = UnicodeScalar(127397 + scalar.value) else { return nil }
            return String(regional)
        }.joined()
    }
}

struct ModernFooterButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .opacity(configuration.isPressed ? 0.88 : 1.0)
    }
}

struct PartnerTypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .scaleEffect(animate ? 1.0 : 0.65)
                    .opacity(animate ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.18))
        .clipShape(Capsule())
        .onAppear {
            animate = true
        }
        .onDisappear {
            animate = false
        }
    }
}

struct HeartParticleView: View {
    let particle: HeartParticle
    let containerHeight: CGFloat
    @State private var flyUp = false
    @State private var sway = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: particle.size, weight: .bold))
            .foregroundStyle(particle.color)
            .shadow(color: particle.color.opacity(0.45), radius: 8, x: 0, y: 2)
            .offset(x: sway ? particle.drift : -particle.drift, y: flyUp ? -containerHeight * 1.08 : 0)
            .opacity(flyUp ? 0.0 : 0.95)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(particle.delay)
                ) {
                    sway = true
                }
                withAnimation(
                    .easeOut(duration: particle.duration)
                        .delay(particle.delay)
                ) {
                    flyUp = true
                }
            }
    }
}

#if canImport(WebRTC)
struct WebRTCVideoRendererView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?
    let captureKey: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        context.coordinator.currentView = view
        context.coordinator.captureKey = captureKey
        if let captureKey {
            RemoteVideoCaptureRegistry.shared.register(view: view, for: captureKey)
        }
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.captureKey = captureKey
        if let captureKey {
            RemoteVideoCaptureRegistry.shared.register(view: uiView, for: captureKey)
        }
        context.coordinator.bind(track: videoTrack, to: uiView)
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        if let captureKey = coordinator.captureKey {
            RemoteVideoCaptureRegistry.shared.unregister(for: captureKey)
        }
    }

    final class Coordinator {
        weak var currentView: RTCMTLVideoView?
        private var currentTrack: RTCVideoTrack?
        var captureKey: String?

        func bind(track: RTCVideoTrack?, to view: RTCMTLVideoView) {
            if currentTrack === track { return }
            if let currentTrack, let currentView {
                currentTrack.remove(currentView)
            }
            currentTrack = track
            currentView = view
            track?.add(view)
        }
    }
}
#endif

private extension VideoChatView {
    @ViewBuilder
    var mainVideoLayer: some View {
        if isZoomedLocal {
            LocalVideoView(videoTrack: webRTCManager.localVideoTrack)
        } else {
            RemoteVideoView(
                partnerId: partnerId,
                videoTrack: webRTCManager.remoteVideoTrack
            )
        }
    }

    @ViewBuilder
    var pipVideoLayer: some View {
        if isZoomedLocal {
            RemoteVideoView(
                partnerId: partnerId,
                videoTrack: webRTCManager.remoteVideoTrack
            )
        } else {
            LocalVideoView(videoTrack: webRTCManager.localVideoTrack)
        }
    }

    var topOverlayBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(countryFlag)
                    .font(.system(size: 20))
                Text(countryNameUppercased)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                Image(systemName: genderIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(genderIconColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.22))
            .clipShape(Capsule())

            Spacer()

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showReportModal = true
                    }
                } label: {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.system(size: 15, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.24))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    onEnd()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial)
                        .background(Color.black.opacity(0.24))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var heartActionButton: some View {
        Button {
            localSessionLikes += 1
            partnerLikes += 1
            socketService.sendLike(targetId: partnerId, currentSessionLikes: localSessionLikes)
            spawnHeartBurst(count: Int.random(in: 5...10))
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                heartTapped = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    heartTapped = false
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 20, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 1, green: 0.28, blue: 0.4))

                Text("\(partnerLikes)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
            .background(Color.red.opacity(0.2))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
            .scaleEffect(heartTapped ? 1.3 : (heartPulse ? 1.04 : 0.98))
            .shadow(color: Color.red.opacity(0.4), radius: 10, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .opacity(0.95)
    }

    var partnerIdentity: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showMatchBanner && !isPrivateCallFlow {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("You matched with \(partnerDisplayName)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.10), in: Capsule())
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            HStack(spacing: 10) {
                partnerAvatarView
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isPrivateCallFlow ? partnerDisplayName : "Matched with \(partnerDisplayName)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(partnerAttentionText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                }
            }

            if !isPrivateCallFlow {
                HStack(spacing: 8) {
                    Text("Mutual match")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10), in: Capsule())

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Matched \(elapsedMatchTime(at: context.date)) ago")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    func chatInputBar() -> some View {
        HStack(spacing: 8) {
            TextField("Send a message...", text: $chatText)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.95))
                .tint(.white)
                .focused($isChatFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    var isKeyboardVisible: Bool {
        keyboardHeight > 0
    }

    var inputKeyboardOffset: CGFloat {
        max(0, keyboardHeight - baseSafeBottomInset)
    }

    var inputBaseBottomInset: CGFloat {
        max(8, baseSafeBottomInset == 0 ? 10 : 4)
    }

    var pipWindow: some View {
        pipVideoLayer
        .frame(width: 124, height: 184)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .scaleEffect(pipTapScale)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .bottom) {
            if !isZoomedLocal {
                HStack(spacing: 8) {
                    pipButton(icon: isMuted ? "mic.slash.fill" : "mic.fill") {
                        isMuted.toggle()
                        webRTCManager.setAudioMuted(isMuted)
                    }
                    pipButton(icon: "camera.rotate.fill") {
                        onFlipCamera()
                    }
                    pipButton(icon: isCameraOff ? "video.fill" : "video.slash.fill") {
                        isCameraOff.toggle()
                        webRTCManager.setVideoEnabled(!isCameraOff)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.12))
                .clipShape(Capsule())
                .padding(.bottom, 6)
                .opacity(showPiPControls ? 0.96 : 0.28)
                .animation(.easeInOut(duration: 0.2), value: showPiPControls)
            }
        }
        .overlay {
            if isCameraOff && !isZoomedLocal {
                Color.black.opacity(0.42)
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
        }
        .shadow(color: Color.black.opacity(0.38), radius: 14, x: 0, y: 6)
        .highPriorityGesture(
            TapGesture().onEnded {
                toggleVideoSwap()
            }
        )
        .onLongPressGesture(minimumDuration: 0.3) {
            guard !isZoomedLocal else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showPiPControls.toggle()
            }
            if showPiPControls {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPiPControls = false
                    }
                }
            }
        }
    }

    func pipButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    func toggleVideoSwap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.16, dampingFraction: 0.7)) {
            pipTapScale = 0.94
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                pipTapScale = 1.0
            }
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isZoomedLocal.toggle()
        }
    }

    func sendMessage() {
        let trimmed = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        socketService.sendChatMessage(to: partnerId, message: trimmed)
        chatText = ""
        socketService.sendStoppedTyping(to: partnerId)
        hasSentTyping = false
        typingStopWorkItem?.cancel()
    }

    func handleTypingStateChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            typingStopWorkItem?.cancel()
            if hasSentTyping {
                socketService.sendStoppedTyping(to: partnerId)
                hasSentTyping = false
            }
            return
        }

        if !hasSentTyping {
            socketService.sendTyping(to: partnerId)
            hasSentTyping = true
        }

        typingStopWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            socketService.sendStoppedTyping(to: partnerId)
            hasSentTyping = false
        }
        typingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func spawnHeartBurst(count: Int) {
        let palette: [Color] = [
            Color(red: 1.0, green: 0.26, blue: 0.38),
            Color(red: 1.0, green: 0.45, blue: 0.58),
            Color(red: 0.95, green: 0.2, blue: 0.5),
            Color(red: 1.0, green: 0.62, blue: 0.78)
        ]

        let burst = (0..<count).map { index in
            HeartParticle(
                startXRatio: CGFloat.random(in: 0.15...0.85),
                drift: CGFloat.random(in: 18...46),
                size: CGFloat.random(in: 18...30),
                duration: Double.random(in: 1.8...2.8),
                delay: Double(index) * 0.04,
                color: palette.randomElement() ?? .pink
            )
        }
        heartParticles.append(contentsOf: burst)

        let maxDuration = burst.map(\.duration).max() ?? 2.8
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration + 0.8) {
            let ids = Set(burst.map(\.id))
            heartParticles.removeAll { ids.contains($0.id) }
        }
    }

    var partnerDisplayName: String {
        if let rawName = socketService.partnerName, !rawName.isEmpty {
            return rawName
        }
        if let rawName = partnerInfo?.partnerName, !rawName.isEmpty {
            return rawName
        }
        return "Partner"
    }

    var isPrivateCallFlow: Bool {
        (socketService.activeMatch ?? partnerInfo)?.privateCall == true
    }

    var partnerAttentionText: String {
        if socketService.isPartnerTyping {
            return "\(partnerDisplayName) is typing..."
        }
        if socketService.isPartnerViewingProfile {
            return "\(partnerDisplayName) is viewing your profile"
        }
        if socketService.sessionStage == .videoCall {
            return "Video connected"
        }
        if socketService.sessionStage == .voiceCall {
            return "Voice connected"
        }
        if socketService.messages.isEmpty {
            return "\(partnerDisplayName) is here with you"
        }
        return "Chat connected"
    }

    var partnerAvatarPresentation: PartnerAvatarPresentation {
        PartnerAvatarPresentation(payload: socketService.activeMatch ?? partnerInfo)
    }

    @ViewBuilder
    var partnerAvatarView: some View {
        if let avatar = validatedPartnerAvatarURL,
           let url = URL(string: avatar) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "person.circle")
                        .resizable()
                        .scaledToFit()
                        .padding(6)
                        .foregroundStyle(.white.opacity(0.9))
                        .background(Color.white.opacity(0.12))
                }
            }
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
        } else if let inlineAvatar = validatedPartnerInlineAvatar {
            Image(uiImage: inlineAvatar)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
        } else if let guestAssetName = partnerAvatarPresentation.guestAssetName {
            Image(guestAssetName)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                )
        } else {
            InitialAvatarView(name: partnerDisplayName, size: 32)
        }
    }

    var validatedPartnerAvatarURL: String? {
        let candidate = socketService.partnerAvatarURL
            ?? partnerInfo?.partnerAvatarURL
            ?? partnerInfo?.partnerProfilePic
            ?? partnerInfo?.partnerAvatar
        return validatedURLString(candidate)
    }

    var validatedPartnerInlineAvatar: UIImage? {
        let candidate = socketService.partnerAvatarURL
            ?? partnerInfo?.partnerAvatarURL
            ?? partnerInfo?.partnerProfilePic
            ?? partnerInfo?.partnerAvatar
        return PartnerAvatarPresentation.decodeInlineImage(from: candidate)
    }

    func validatedURLString(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return raw
    }

    func elapsedMatchTime(at date: Date) -> String {
        guard let matchedAt = socketService.matchedAt else { return "00:00" }
        let elapsed = max(0, Int(date.timeIntervalSince(matchedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func triggerMatchBannerIfNeeded() {
        guard !isPrivateCallFlow else {
            showMatchBanner = false
            return
        }
        guard socketService.matchedAt != nil else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            showMatchBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeInOut(duration: 0.22)) {
                showMatchBanner = false
            }
        }
    }

    var countryFlag: String {
        guard let region = partnerInfo?.country, !region.isEmpty else { return "🌍" }
        return CountryDataProvider.flagEmoji(forRegionCode: region)
    }

    var countryNameUppercased: String {
        guard let region = partnerInfo?.country, !region.isEmpty else { return "GLOBAL" }
        let localized = Locale.current.localizedString(forRegionCode: region) ?? region
        return localized.uppercased()
    }

    var genderIconName: String {
        switch partnerInfo?.partnerGender.lowercased() {
        case "female":
            return "figure.stand.dress"
        case "male":
            return "figure.stand"
        default:
            return "person.2.fill"
        }
    }

    var genderIconColor: Color {
        switch partnerInfo?.partnerGender.lowercased() {
        case "female":
            return Color(red: 1.0, green: 0.48, blue: 0.78)
        case "male":
            return Color(red: 0.4, green: 0.72, blue: 1.0)
        default:
            return .white.opacity(0.92)
        }
    }
}

struct InitialAvatarView: View {
    let name: String
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map { String($0) }.joined()
        return chars.isEmpty ? "?" : chars.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.67, blue: 0.98),
                            Color(red: 0.15, green: 0.92, blue: 0.58)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
        )
    }
}
