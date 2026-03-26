import SwiftUI
import Observation
import UIKit

struct OnlineMatchChatView: View {
    let partnerId: String
    let partnerInfo: PartnerFoundPayload?
    let onNextPartner: () -> Void
    let onEnd: () -> Void

    @Bindable private var socketService = SocketService.shared
    @State private var chatText = ""
    @State private var typingStopWorkItem: DispatchWorkItem?
    @State private var hasSentTyping = false
    @State private var heartTapped = false
    @State private var localSessionLikes = 0
    @State private var partnerLikes = 0
    @State private var heartPulse = false
    @State private var heartParticles: [HeartParticle] = []
    @State private var isComposerVisible = false
    @State private var isChatOverlayVisible = false
    @State private var unreadCount = 0
    @State private var incomingPreviewMessage: ChatMessage?
    @State private var keyboardHeight: CGFloat = 0
    @State private var baseSafeBottomInset: CGFloat = 0
    @State private var showMatchArrival = false
    @State private var heroIntroPulse = false
    @FocusState private var isComposerFocused: Bool

    private let bottomAnchorId = "online-match-bottom-anchor"
    private let typingAnchorId = "online-match-typing-anchor"
    private let pageBackgroundTop = Color(red: 0.98, green: 0.985, blue: 1.0)
    private let pageBackgroundBottom = Color(red: 0.91, green: 0.95, blue: 1.0)
    private let lavender = Color(red: 0.84, green: 0.80, blue: 1.0)
    private let periwinkle = Color(red: 0.74, green: 0.80, blue: 1.0)
    private let accentStart = Color(red: 0.40, green: 0.51, blue: 0.94)
    private let accentEnd = Color(red: 0.49, green: 0.35, blue: 0.74)
    private let primaryText = Color(red: 0.18, green: 0.22, blue: 0.32)
    private let secondaryText = Color(red: 0.48, green: 0.56, blue: 0.70)
    private let mutedText = Color(red: 0.64, green: 0.70, blue: 0.80)
    private let softCardFill = Color.white.opacity(0.96)

    private static let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var resolvedPartner: PartnerFoundPayload? {
        socketService.activeMatch ?? partnerInfo
    }

    private var partnerName: String {
        resolvedPartner?.partnerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? resolvedPartner?.partnerName ?? "Someone online"
            : "Someone online"
    }

    private var partnerAvatarPresentation: PartnerAvatarPresentation {
        PartnerAvatarPresentation(payload: resolvedPartner)
    }

    private var partnerAgeLine: String {
        if let age = resolvedPartner?.partnerAge, age > 0 {
            return "\(partnerName), \(age)"
        }
        return partnerName
    }

    private var partnerPronoun: String {
        switch resolvedPartner?.partnerGender.lowercased() {
        case "female":
            return "She"
        case "male":
            return "He"
        default:
            return "They"
        }
    }

    private var matchStatusHeadline: String {
        "Matched with \(partnerName)"
    }

    private var matchIntroDetail: String {
        "\(partnerPronoun) can see your profile now"
    }

    private var partnerAttentionText: String {
        if socketService.isPartnerTyping {
            return "\(partnerName) is typing..."
        }
        if socketService.isPartnerViewingProfile {
            return "\(partnerName) is viewing your profile"
        }
        if socketService.sessionStage == .voiceCall {
            return "Voice connected"
        }
        if socketService.messages.isEmpty {
            return "Profile open"
        }
        return "Chat connected"
    }

    private var partnerAttentionTint: Color {
        if socketService.isPartnerTyping {
            return accentStart
        }
        if socketService.isPartnerViewingProfile {
            return Color(red: 0.96, green: 0.64, blue: 0.32)
        }
        if socketService.sessionStage == .voiceCall {
            return accentEnd
        }
        return .green
    }

    private var partnerBio: String {
        if let bio = resolvedPartner?.partnerBio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
            return bio
        }
        return "Online right now. Look through the profile and open with something personal."
    }

    private var profileMetaRows: [(icon: String, text: String)] {
        var rows: [(String, String)] = []

        let work = resolvedPartner?.partnerWork?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !work.isEmpty {
            rows.append(("briefcase", work))
        }

        let education = resolvedPartner?.partnerEducation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !education.isEmpty {
            rows.append(("graduationcap", education))
        }

        let country = resolvedPartner?.country.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !country.isEmpty {
            rows.append(("location", country))
        }

        return rows
    }

    private var lookingForChips: [String] {
        resolvedPartner?.partnerLookingFor.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    private var interestChips: [String] {
        resolvedPartner?.partnerInterests.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    private var languageChips: [String] {
        resolvedPartner?.partnerLanguages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    private var partnerPhotoSources: [MatchPhotoSource] {
        let photos = resolvedPartner?.partnerPhotos ?? []
        let avatarCandidates = Set([
            resolvedPartner?.partnerAvatarURL,
            resolvedPartner?.partnerAvatar,
            resolvedPartner?.partnerProfilePic
        ].compactMap { candidate in
            candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        return photos.compactMap { raw in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !avatarCandidates.contains(trimmed) else { return nil }
            return MatchPhotoSource(rawValue: trimmed)
        }
    }

    private var resolvedTargetPartnerId: String {
        let active = socketService.activePartnerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !active.isEmpty {
            return active
        }
        return partnerId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSendMessage: Bool {
        !chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bubbleMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.68, 300)
    }

    private var introHintText: String {
        if socketService.isPartnerViewingProfile {
            return "Your profile is visible to \(partnerName) now."
        }
        return "Say hi before the moment cools off."
    }

    private var overlayMessages: [ChatMessage] {
        Array(socketService.messages.suffix(isComposerVisible ? 5 : 2))
    }

    private var isKeyboardVisible: Bool {
        keyboardHeight > 0
    }

    private var inputKeyboardOffset: CGFloat {
        max(0, keyboardHeight - baseSafeBottomInset)
    }

    private var inputBaseBottomInset: CGFloat {
        max(8, baseSafeBottomInset == 0 ? 10 : 4)
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 16
            let contentWidth = min(max(geometry.size.width - (horizontalPadding * 2), 0), 430)

            ZStack {
                backgroundLayer

                swipeableContent(
                    contentWidth: contentWidth,
                    geometry: geometry,
                    horizontalPadding: horizontalPadding
                )

                heartParticleLayer(geometry: geometry)

                if let incomingPreviewMessage {
                    incomingToast(message: incomingPreviewMessage)
                        .padding(.horizontal, 16)
                        .padding(.bottom, incomingToastBottomPadding(safeBottom: geometry.safeAreaInsets.bottom))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .preferredColorScheme(.light)
            .clipped()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.endEditing()
                }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isComposerVisible {
                    bottomOverlay(
                        safeBottom: geometry.safeAreaInsets.bottom,
                        contentWidth: contentWidth
                    )
                }
            }
            .onAppear {
                baseSafeBottomInset = UIApplication.shared.bottomSafeAreaInset
                partnerLikes = resolvedPartner?.partnerLikes ?? partnerInfo?.partnerLikes ?? 0
                triggerMatchArrivalIfNeeded()
                socketService.sendProfileViewState(isActive: true)
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    heartPulse = true
                }
            }
            .onChange(of: socketService.matchedAt) { _, _ in
                triggerMatchArrivalIfNeeded()
            }
            .onChange(of: resolvedPartner?.partnerLikes) { _, newValue in
                partnerLikes = newValue ?? partnerLikes
            }
            .onChange(of: socketService.incomingLikeBurstID) { _, _ in
                spawnHeartBurst(count: Int.random(in: 5...9))
            }
            .onChange(of: isComposerVisible) { _, visible in
                if visible {
                    isChatOverlayVisible = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isComposerFocused = true
                    }
                    unreadCount = 0
                } else {
                    isComposerFocused = false
                }
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
            .onChange(of: socketService.messages) { oldValue, newValue in
                guard newValue.count >= oldValue.count, let latest = newValue.last else { return }
                guard !latest.isFromMe else { return }

                if !isChatOverlayVisible && !isComposerVisible {
                    unreadCount += 1
                    showIncomingPreview(for: latest)
                } else {
                    unreadCount = 0
                }
            }
            .onDisappear {
                socketService.sendProfileViewState(isActive: false)
                let targetId = resolvedTargetPartnerId
                if !targetId.isEmpty {
                    socketService.sendStoppedTyping(to: targetId)
                }
                typingStopWorkItem?.cancel()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [pageBackgroundTop, pageBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [lavender.opacity(0.30), .clear],
                        center: .center,
                        startRadius: 24,
                        endRadius: 260
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 14)
                .offset(x: -120, y: -250)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [periwinkle.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 300
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 10)
                .offset(x: 140, y: -120)
        }
    }

    private func profileHeroCard(width: CGFloat) -> some View {
        let heroHeight = min(max(width * 1.12, 360), 560)

        return ZStack(alignment: .bottomLeading) {
            heroMedia
                .frame(width: width, height: heroHeight)
                .frame(height: heroHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.02),
                            Color.black.opacity(0.14),
                            Color.black.opacity(0.68)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            VStack(spacing: 14) {
                HStack {
                    persistentMatchStatusBar
                    Spacer(minLength: 0)
                }

                if showMatchArrival {
                    matchArrivalCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 10) {
                    Text(partnerAgeLine)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    if !profileMetaRows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(profileMetaRows.prefix(2).enumerated()), id: \.offset) { entry in
                                let row = entry.element
                                Label(row.text, systemImage: row.icon)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.94))
                                    .lineLimit(1)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Text("Mutual match")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.94))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.14), in: Capsule())

                        matchedTimePill
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(width: width, height: heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.46, green: 0.54, blue: 0.72).opacity(0.18), radius: 26, x: 0, y: 18)
    }

    private func swipeableContent(
        contentWidth: CGFloat,
        geometry: GeometryProxy,
        horizontalPadding: CGFloat
    ) -> some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    Color.clear
                        .frame(height: max(geometry.safeAreaInsets.top + 8, 24))

                    profileHeroCard(width: contentWidth)
                        .frame(width: contentWidth)

                    infoCard(
                        title: "My bio",
                        text: partnerBio
                    )
                    .frame(width: contentWidth)

                    if !profileMetaRows.isEmpty {
                        detailCard(
                            title: "About me",
                            rows: profileMetaRows
                        )
                        .frame(width: contentWidth)
                    }

                    if !lookingForChips.isEmpty {
                        chipSectionCard(
                            title: "Looking for",
                            chips: lookingForChips
                        )
                        .frame(width: contentWidth)
                    }

                    if let firstPhoto = partnerPhotoSources.first {
                        profilePhotoCard(source: firstPhoto, width: contentWidth)
                            .frame(width: contentWidth)
                    }

                    if !languageChips.isEmpty {
                        chipSectionCard(
                            title: "Languages",
                            chips: languageChips
                        )
                        .frame(width: contentWidth)
                    }

                    if partnerPhotoSources.indices.contains(1) {
                        profilePhotoCard(source: partnerPhotoSources[1], width: contentWidth)
                            .frame(width: contentWidth)
                    }

                    if !interestChips.isEmpty {
                        chipSectionCard(
                            title: "Interests",
                            chips: interestChips
                        )
                        .frame(width: contentWidth)
                    }

                    if partnerPhotoSources.count > 2 {
                        ForEach(Array(partnerPhotoSources.dropFirst(2).enumerated()), id: \.offset) { entry in
                            profilePhotoCard(source: entry.element, width: contentWidth)
                                .frame(width: contentWidth)
                        }
                    }

                    Color.clear
                        .frame(height: bottomScrollSpacing(safeBottom: geometry.safeAreaInsets.bottom))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 4)
            }

            if shouldShowChatOverlay {
                overlayConversationStack(contentWidth: contentWidth)
                    .padding(.horizontal, 16)
                    .padding(.bottom, overlayBottomPadding(safeBottom: geometry.safeAreaInsets.bottom))
                    .offset(y: isComposerVisible ? -inputKeyboardOffset : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    @ViewBuilder
    private var heroMedia: some View {
        if let remoteURL = partnerAvatarPresentation.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    heroPlaceholder
                }
            }
        } else if let inlineImage = partnerAvatarPresentation.inlineImage {
            Image(uiImage: inlineImage)
                .resizable()
                .scaledToFill()
        } else if let guestAssetName = partnerAvatarPresentation.guestAssetName {
            Image(guestAssetName)
                .resizable()
                .scaledToFill()
        } else {
            heroPlaceholder
        }
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.77, green: 0.81, blue: 1.0),
                    Color(red: 0.61, green: 0.68, blue: 0.96),
                    Color(red: 0.49, green: 0.40, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 220, height: 220)

            OnlineMatchAvatarView(
                url: partnerAvatarPresentation.remoteURL,
                inlineImage: partnerAvatarPresentation.inlineImage,
                guestAssetName: partnerAvatarPresentation.guestAssetName,
                fallbackName: partnerName,
                size: 124
            )
        }
    }

    private func infoCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func detailCard(title: String, rows: [(icon: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                    let row = entry.element
                    HStack(spacing: 12) {
                        Image(systemName: row.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accentEnd)
                            .frame(width: 20)

                        Text(row.text)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                    )
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func chipSectionCard(title: String, chips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(red: 0.97, green: 0.98, blue: 1.0))
                        )
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func profilePhotoCard(source: MatchPhotoSource, width: CGFloat) -> some View {
        let photoHeight = min(max(width * 1.22, 280), 520)

        return ZStack(alignment: .bottomLeading) {
            MatchPhotoView(source: source)
                .frame(width: width, height: photoHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.04),
                            Color.black.opacity(0.10),
                            Color.black.opacity(0.44)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 12, weight: .bold))
                Text("More from \(partnerName)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.96))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.black.opacity(0.24), in: Capsule())
            .padding(18)
        }
        .frame(width: width, height: photoHeight)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 10)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(softCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.84), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.46, green: 0.54, blue: 0.72).opacity(0.10), radius: 18, x: 0, y: 10)
    }

    private func bottomOverlay(safeBottom: CGFloat, contentWidth: CGFloat) -> some View {
        Group {
            HStack(spacing: 12) {
                heartActionButton

                actionButton(
                    icon: socketService.sessionStage == .voiceCall ? "phone.down.fill" : "waveform",
                    background: socketService.sessionStage == .voiceCall
                        ? Color(red: 1.0, green: 0.88, blue: 0.90)
                        : Color.white,
                    foreground: socketService.sessionStage == .voiceCall
                        ? Color(red: 0.85, green: 0.22, blue: 0.28)
                        : primaryText,
                    outlined: socketService.sessionStage != .voiceCall,
                    action: toggleVoiceCall
                )

                messageActionButton

                actionButton(
                    icon: "arrow.right",
                    background: Color.black,
                    foreground: .white,
                    outlined: false,
                    emphasized: true,
                    action: onNextPartner
                )
            }
            .frame(width: contentWidth)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, max(10, safeBottom == 0 ? 12 : safeBottom))
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.92))
                .background(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(height: 1)
                }
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isComposerVisible)
    }

    private var shouldShowChatOverlay: Bool {
        isChatOverlayVisible || isComposerVisible
    }

    private func overlayBottomPadding(safeBottom: CGFloat) -> CGFloat {
        if isComposerVisible || isKeyboardVisible {
            return inputBaseBottomInset
        }
        return max(safeBottom, 12) + 92
    }

    private func incomingToastBottomPadding(safeBottom: CGFloat) -> CGFloat {
        let overlayPadding = overlayBottomPadding(safeBottom: safeBottom)
        return overlayPadding + (isComposerVisible ? 136 : 148)
    }

    private func overlayConversationStack(contentWidth: CGFloat) -> some View {
        glassChatOverlay(width: contentWidth)
            .frame(width: contentWidth)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isComposerVisible)
    }

    private func glassChatOverlay(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                glassOverlayHeader

                overlayMessagesScroll(proxy: proxy)
                    .frame(height: overlayHeight(for: width))
                    .onTapGesture {
                        unreadCount = 0
                    }

                if isComposerVisible {
                    panelComposer
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(isComposerVisible ? 16 : 14)
            .background(glassBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
            .onAppear {
                scrollConversationToBottom(with: proxy, animated: false)
            }
            .onChange(of: socketService.messages) { _, _ in
                scrollConversationToBottom(with: proxy)
            }
            .onChange(of: socketService.isPartnerTyping) { _, _ in
                scrollConversationToBottom(with: proxy)
            }
        }
    }

    private var glassOverlayHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isComposerVisible ? "Matched conversation" : "Matched conversation")
                    .font(.system(size: isComposerVisible ? 17 : 16, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)

                Text(isComposerVisible ? "Keep the profile open while you reply." : "You are both inside the same match now.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(mutedText)
            }

            Spacer()

            if unreadCount > 0 {
                Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(red: 1, green: 0.34, blue: 0.44), in: Capsule())
            }

            if isComposerVisible {
                Button {
                    closeChatOverlay()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.82), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(isComposerVisible ? 0.16 : 0.12))
            )
    }

    private func overlayMessagesScroll(proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                if socketService.messages.isEmpty {
                    glassEmptyState
                } else {
                    ForEach(overlayMessages) { message in
                        OnlineMatchMessageRow(
                            message: message,
                            maxBubbleWidth: bubbleMaxWidth,
                            timeText: formattedTime(message.timestamp),
                            accentStart: accentStart.opacity(0.94),
                            accentEnd: accentEnd.opacity(0.94),
                            primaryText: primaryText,
                            secondaryText: secondaryText
                        )
                        .id(message.id)
                    }
                }

                if socketService.isPartnerTyping {
                    HStack {
                        SoftTypingIndicatorView(
                            primaryText: primaryText,
                            secondaryText: secondaryText
                        )
                        Spacer(minLength: 44)
                    }
                    .id(typingAnchorId)
                }

                Color.clear
                    .frame(height: 4)
                    .id(bottomAnchorId)
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }

    private var glassEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your profile is visible to \(partnerName) now.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(introHintText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var panelComposer: some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Type a message...", text: $chatText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(primaryText)
                    .tint(accentStart)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(sendMessage)
                    .onChange(of: chatText) { _, newValue in
                        handleTypingStateChange(newValue)
                    }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [periwinkle.opacity(0.72), lavender.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
            )

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: canSendMessage
                                ? [accentStart, accentEnd]
                                : [Color(red: 0.83, green: 0.86, blue: 0.92), Color(red: 0.74, green: 0.78, blue: 0.86)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSendMessage)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.84), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 8)
        )
    }

    private var messageActionButton: some View {
        Button {
            openChatOverlay()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: (isComposerVisible || isChatOverlayVisible) ? "message.fill" : "message")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle((isComposerVisible || isChatOverlayVisible) ? accentEnd : primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        ((isComposerVisible || isChatOverlayVisible) ? Color(red: 0.92, green: 0.94, blue: 1.0) : Color.white),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(red: 0.92, green: 0.94, blue: 0.98), lineWidth: 1)
                    )
                    .shadow(
                        color: Color(red: 0.50, green: 0.56, blue: 0.70).opacity(0.08),
                        radius: 12,
                        x: 0,
                        y: 8
                    )

                if unreadCount > 0 {
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color(red: 1, green: 0.34, blue: 0.44), in: Capsule())
                        .offset(x: 7, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var heartActionButton: some View {
        Button {
            let targetId = resolvedTargetPartnerId
            guard !targetId.isEmpty else { return }
            localSessionLikes += 1
            partnerLikes += 1
            socketService.sendLike(targetId: targetId, currentSessionLikes: localSessionLikes)
            spawnHeartBurst(count: Int.random(in: 5...10))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                heartTapped = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    heartTapped = false
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.30, blue: 0.42))
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.91, blue: 0.94), Color(red: 1.0, green: 0.82, blue: 0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Circle()
                    )
                    .shadow(color: Color.red.opacity(0.14), radius: 12, x: 0, y: 8)

                Text("\(partnerLikes)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(red: 1, green: 0.34, blue: 0.44), in: Capsule())
                    .offset(x: 6, y: -4)
                    .opacity(partnerLikes > 0 ? 1 : 0)
            }
            .scaleEffect(heartTapped ? 1.22 : (heartPulse ? 1.03 : 0.98))
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        icon: String,
        background: Color,
        foreground: Color,
        outlined: Bool,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(outlined ? Color(red: 0.92, green: 0.94, blue: 0.98) : Color.clear, lineWidth: 1)
                )
                .shadow(
                    color: emphasized ? Color.black.opacity(0.14) : Color(red: 0.50, green: 0.56, blue: 0.70).opacity(0.08),
                    radius: 12,
                    x: 0,
                    y: 8
                )
        }
        .buttonStyle(.plain)
    }

    private func bottomScrollSpacing(safeBottom: CGFloat) -> CGFloat {
        return shouldShowChatOverlay ? 260 + max(safeBottom, 12) : 124 + max(safeBottom, 12)
    }

    private func openChatOverlay() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isChatOverlayVisible = true
            isComposerVisible = true
        }
        unreadCount = 0
    }

    private func closeChatOverlay() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isChatOverlayVisible = false
            isComposerVisible = false
        }

        let targetId = resolvedTargetPartnerId
        if !targetId.isEmpty {
            socketService.sendStoppedTyping(to: targetId)
        }
        hasSentTyping = false
        typingStopWorkItem?.cancel()
        UIApplication.shared.endEditing()
    }

    private func toggleVoiceCall() {
        if socketService.sessionStage == .voiceCall {
            socketService.endVoiceCall()
            return
        }
        socketService.requestVoiceCall(partnerId: partnerId)
    }

    private func sendMessage() {
        let trimmed = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetId = resolvedTargetPartnerId
        guard !targetId.isEmpty else {
            print("⚠️ [OnlineMatchChat] sendMessage aborted because target partner id is empty")
            return
        }
        chatText = ""
        socketService.sendChatMessage(to: targetId, message: trimmed)
        socketService.sendStoppedTyping(to: targetId)
        hasSentTyping = false
        typingStopWorkItem?.cancel()
        unreadCount = 0
        if !isChatOverlayVisible || !isComposerVisible {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isChatOverlayVisible = true
                isComposerVisible = true
            }
        }
    }

    private func spawnHeartBurst(count: Int) {
        let palette: [Color] = [
            Color(red: 1.0, green: 0.26, blue: 0.38),
            Color(red: 1.0, green: 0.45, blue: 0.58),
            Color(red: 0.95, green: 0.2, blue: 0.5),
            Color(red: 1.0, green: 0.62, blue: 0.78)
        ]

        let burst = (0..<count).map { index in
            HeartParticle(
                startXRatio: CGFloat.random(in: 0.12...0.88),
                drift: CGFloat.random(in: 18...44),
                size: CGFloat.random(in: 16...28),
                duration: Double.random(in: 1.6...2.4),
                delay: Double(index) * 0.05,
                color: palette.randomElement() ?? .pink
            )
        }
        heartParticles.append(contentsOf: burst)

        let maxDuration = burst.map(\.duration).max() ?? 2.4
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration + 0.8) {
            let ids = Set(burst.map(\.id))
            heartParticles.removeAll { ids.contains($0.id) }
        }
    }

    private func heartParticleLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(heartParticles) { particle in
                HeartParticleView(
                    particle: particle,
                    containerHeight: geometry.size.height
                )
                .position(
                    x: geometry.size.width * particle.startXRatio,
                    y: geometry.size.height + 24
                )
                .id(particle.id)
            }
        }
        .allowsHitTesting(false)
    }

    private func handleTypingStateChange(_ newValue: String) {
        let targetId = resolvedTargetPartnerId
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            typingStopWorkItem?.cancel()
            if hasSentTyping && !targetId.isEmpty {
                socketService.sendStoppedTyping(to: targetId)
                hasSentTyping = false
            }
            return
        }

        guard !targetId.isEmpty else { return }

        if !hasSentTyping {
            socketService.sendTyping(to: targetId)
            hasSentTyping = true
        }

        typingStopWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            socketService.sendStoppedTyping(to: targetId)
            hasSentTyping = false
        }
        typingStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func formattedTime(_ date: Date) -> String {
        Self.messageTimeFormatter.string(from: date)
    }

    private func overlayHeight(for width: CGFloat) -> CGFloat {
        if isComposerVisible {
            return min(max(width * 0.42, 150), 220)
        }
        return min(max(width * 0.28, 108), 146)
    }

    private func scrollConversationToBottom(with proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            let anchorId = socketService.isPartnerTyping ? typingAnchorId : bottomAnchorId
            if animated {
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(anchorId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(anchorId, anchor: .bottom)
            }
        }
    }

    private func showIncomingPreview(for message: ChatMessage) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            incomingPreviewMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            guard incomingPreviewMessage?.id == message.id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                incomingPreviewMessage = nil
            }
        }
    }

    private func incomingToast(message: ChatMessage) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentStart.opacity(0.92), accentEnd.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)

                Image(systemName: "message.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(partnerName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)

                Text(message.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.84), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
        )
    }

    private var persistentMatchStatusBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(matchStatusHeadline)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(matchIntroDetail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            OnlinePresenceChip(text: partnerAttentionText, tint: partnerAttentionTint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var matchArrivalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You matched with \(partnerName)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text(matchIntroDetail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.86))

            HStack(spacing: 10) {
                Text("Mutual match")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.14), in: Capsule())

                matchedTimePill
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .scaleEffect(heroIntroPulse ? 1.02 : 0.98)
    }

    private var matchedTimePill: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text("Matched \(elapsedMatchTime(at: context.date)) ago")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
    }

    private func elapsedMatchTime(at date: Date) -> String {
        guard let matchedAt = socketService.matchedAt else { return "00:00" }
        let elapsed = max(0, Int(date.timeIntervalSince(matchedAt)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func triggerMatchArrivalIfNeeded() {
        guard socketService.matchedAt != nil else { return }
        heroIntroPulse = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            showMatchArrival = true
        }
        withAnimation(.easeInOut(duration: 1.1).repeatCount(2, autoreverses: true)) {
            heroIntroPulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.26)) {
                showMatchArrival = false
            }
        }
    }

private struct OnlinePresenceChip: View {
    let text: String
    let tint: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.26))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 1.28 : 0.88)
                    .opacity(pulse ? 0.0 : 0.85)

                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.22), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

private struct MatchPhotoSource {
    let remoteURL: URL?
    let inlineImage: UIImage?

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            self.remoteURL = url
            self.inlineImage = nil
            return
        }

        if let image = PartnerAvatarPresentation.decodeInlineImage(from: trimmed) {
            self.remoteURL = nil
            self.inlineImage = image
            return
        }

        return nil
    }
}

private struct MatchPhotoView: View {
    let source: MatchPhotoSource

    var body: some View {
        Group {
            if let remoteURL = source.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else if let inlineImage = source.inlineImage {
                Image(uiImage: inlineImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.84, green: 0.88, blue: 0.98),
                Color(red: 0.73, green: 0.79, blue: 0.95),
                Color(red: 0.60, green: 0.67, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct OnlineMatchAvatarView: View {
    let url: URL?
    let inlineImage: UIImage?
    let guestAssetName: String?
    let fallbackName: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else if let inlineImage {
                Image(uiImage: inlineImage)
                    .resizable()
                    .scaledToFill()
            } else if let guestAssetName {
                Image(guestAssetName)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.92), lineWidth: 2)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.72, green: 0.78, blue: 0.98), Color(red: 0.58, green: 0.66, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initials)
                .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initials: String {
        let pieces = fallbackName
            .split(separator: " ")
            .prefix(2)
            .map { String($0.prefix(1)).uppercased() }
        let joined = pieces.joined()
        return joined.isEmpty ? "?" : joined
    }
}

private struct OnlineMatchMessageRow: View {
    let message: ChatMessage
    let maxBubbleWidth: CGFloat
    let timeText: String
    let accentStart: Color
    let accentEnd: Color
    let primaryText: Color
    let secondaryText: Color

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 7) {
            HStack {
                if message.isFromMe {
                    Spacer(minLength: 44)
                }

                Text(message.text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(message.isFromMe ? Color.white : primaryText)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                if !message.isFromMe {
                    Spacer(minLength: 44)
                }
            }

            Text(timeText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryText.opacity(0.88))
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isFromMe {
            LinearGradient(
                colors: [accentStart, accentEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            LinearGradient(
                colors: [Color.white.opacity(0.98), Color(red: 0.96, green: 0.97, blue: 1.0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct SoftTypingIndicatorView: View {
    let primaryText: Color
    let secondaryText: Color
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(primaryText.opacity(0.52))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.62)
                    .opacity(animate ? 1.0 : 0.42)
                    .animation(
                        .easeInOut(duration: 0.65)
                            .repeatForever()
                            .delay(Double(index) * 0.14),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.76), lineWidth: 1)
                )
        )
        .overlay(alignment: .bottomLeading) {
            Text("typing...")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(secondaryText.opacity(0.88))
                .offset(x: 14, y: 22)
        }
        .padding(.bottom, 12)
        .onAppear {
            animate = true
        }
        .onDisappear {
            animate = false
        }
    }
}

}
