import SwiftUI
import Observation

struct OnlineMatchChatView: View {
    let partnerId: String
    let partnerInfo: PartnerFoundPayload?
    let onNextPartner: () -> Void
    let onEnd: () -> Void

    @Bindable private var socketService = SocketService.shared
    @StateObject private var webRTCManager = WebRTCManager.shared
    @State private var chatText = ""
    @State private var typingStopWorkItem: DispatchWorkItem?
    @State private var hasSentTyping = false
    @State private var isMuted = false

    private var resolvedPartner: PartnerFoundPayload? {
        socketService.activeMatch ?? partnerInfo
    }

    private var partnerName: String {
        resolvedPartner?.partnerName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? resolvedPartner?.partnerName ?? "Someone online"
            : "Someone online"
    }

    private var partnerAvatarURL: URL? {
        let raw = resolvedPartner?.partnerAvatarURL
            ?? resolvedPartner?.partnerAvatar
            ?? resolvedPartner?.partnerProfilePic
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: raw)
    }

    private var partnerAgeLine: String {
        if let age = resolvedPartner?.partnerAge, age > 0 {
            return "\(partnerName), \(age)"
        }
        return partnerName
    }

    private var partnerMetaLines: [String] {
        [
            resolvedPartner?.partnerWork,
            resolvedPartner?.partnerEducation
        ]
        .compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private var partnerBio: String? {
        guard let bio = resolvedPartner?.partnerBio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return nil
        }
        return bio
    }

    private var highlightChips: [String] {
        let lookingFor = resolvedPartner?.partnerLookingFor.prefix(2).map { $0 } ?? []
        let interests = resolvedPartner?.partnerInterests.prefix(3).map { $0 } ?? []
        return Array(lookingFor + interests)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.92, green: 0.94, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        topBar
                        partnerHeroCard
                        if socketService.sessionStage == .voiceCall {
                            voiceCallBanner
                        }
                        messagesCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .safeAreaInset(edge: .bottom) {
                    bottomComposer
                }
                .onChange(of: socketService.messages) { _, updated in
                    guard let lastId = updated.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .onDisappear {
            socketService.sendStoppedTyping(to: partnerId)
            typingStopWorkItem?.cancel()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Text(socketService.sessionStage == .voiceCall ? "Voice active" : "Online match")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))

            Spacer(minLength: 8)

            Button(action: onNextPartner) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.9), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var partnerHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let partnerAvatarURL {
                        AsyncImage(url: partnerAvatarURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                heroPlaceholder
                            }
                        }
                    } else {
                        heroPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipped()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.12), Color.black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(partnerAgeLine)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    ForEach(partnerMetaLines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .lineLimit(1)
                    }
                }
                .padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)

            if let partnerBio {
                Text(partnerBio)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(.label))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !highlightChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(highlightChips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(.label))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.systemGray6), in: Capsule())
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    if socketService.sessionStage == .voiceCall {
                        socketService.endVoiceCall()
                    } else {
                        socketService.requestVoiceCall(partnerId: partnerId)
                    }
                } label: {
                    Label(
                        socketService.sessionStage == .voiceCall ? "End voice" : "Start voice",
                        systemImage: socketService.sessionStage == .voiceCall ? "phone.down.fill" : "waveform"
                    )
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(socketService.sessionStage == .voiceCall ? Color.red.opacity(0.85) : Color(.label), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onNextPartner) {
                    Text("Next")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(.label))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var messagesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))

            if socketService.messages.isEmpty {
                Text("Say hi and start the conversation.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(socketService.messages) { message in
                        HStack {
                            if message.isFromMe { Spacer(minLength: 36) }

                            Text(message.text)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(message.isFromMe ? .white : Color(.label))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    message.isFromMe
                                        ? Color(.label)
                                        : Color(.systemGray6),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                                )

                            if !message.isFromMe { Spacer(minLength: 36) }
                        }
                        .id(message.id)
                    }
                }
            }

            if socketService.isPartnerTyping {
                PartnerTypingIndicatorView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 6)
    }

    private var voiceCallBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)

            Text("Voice call is active")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))

            Spacer()

            Button {
                isMuted.toggle()
                webRTCManager.setAudioMuted(isMuted)
            } label: {
                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 5)
    }

    private var bottomComposer: some View {
        HStack(spacing: 10) {
            TextField("Mesaj yaz...", text: $chatText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.sentences)
                .onChange(of: chatText) { _, newValue in
                    handleTypingStateChange(newValue)
                }

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(.label), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 6)
        )
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.clear)
    }

    private var heroPlaceholder: some View {
        LinearGradient(
            colors: [Color(red: 0.90, green: 0.92, blue: 0.97), Color(red: 0.82, green: 0.87, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "person.fill")
                .font(.system(size: 72, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    private func sendMessage() {
        let trimmed = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        socketService.sendChatMessage(to: partnerId, message: trimmed)
        chatText = ""
        socketService.sendStoppedTyping(to: partnerId)
        hasSentTyping = false
        typingStopWorkItem?.cancel()
    }

    private func handleTypingStateChange(_ newValue: String) {
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
}
