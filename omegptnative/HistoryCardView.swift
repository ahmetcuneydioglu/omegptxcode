import SwiftUI

struct HistoryCardView: View {
    let history: MatchHistory
    let onToggleFollow: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 14) {
            avatarView

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(countryFlag)
                        .font(.system(size: 13))

                    Text(partnerName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(timeAgoText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 5) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(durationText)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.78))
                }

                Spacer(minLength: 0)

                Button {
                    onToggleFollow()
                } label: {
                    Text(history.isFollowing ? "Takip Ediliyor" : "Takip Et")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(history.isFollowing ? Color.black.opacity(0.82) : .white)
                        .frame(minWidth: 118)
                        .padding(.vertical, 10)
                        .background(
                            history.isFollowing
                                ? Color.white.opacity(0.74)
                                : Color.black.opacity(0.74)
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(history.isFollowing ? 0.14 : 0.2), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
    }

    private var avatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let avatar = history.partner.avatar,
               let url = URL(string: avatar),
               !avatar.isEmpty {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.18))
                ) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            placeholderBackground
                            ProgressView()
                                .tint(.white.opacity(0.9))
                        }

                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .failure:
                        placeholderAvatar

                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }

        }
        .frame(width: 100, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var placeholderAvatar: some View {
        ZStack {
            placeholderBackground

            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: backgroundGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var partnerName: String {
        let trimmed = history.partner.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private var durationText: String {
        let minutes = history.duration / 60
        let seconds = history.duration % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private var timeAgoText: String {
        Self.relativeFormatter.localizedString(for: history.createdAt, relativeTo: .now)
    }

    private var countryFlag: String {
        if let explicitFlag = history.partner.countryFlag, !explicitFlag.isEmpty {
            return explicitFlag
        }
        guard let country = history.partner.country, !country.isEmpty else { return "🌍" }
        return CountryDataProvider.flagEmoji(forRegionCode: country)
    }

    private var backgroundGradientColors: [Color] {
        let seed = partnerName.lowercased()
        switch seed.hashValue.magnitude % 4 {
        case 0:
            return [Color(red: 0.18, green: 0.24, blue: 0.38), Color(red: 0.08, green: 0.1, blue: 0.18)]
        case 1:
            return [Color(red: 0.23, green: 0.2, blue: 0.34), Color(red: 0.1, green: 0.09, blue: 0.16)]
        case 2:
            return [Color(red: 0.18, green: 0.28, blue: 0.24), Color(red: 0.07, green: 0.12, blue: 0.14)]
        default:
            return [Color(red: 0.3, green: 0.2, blue: 0.16), Color(red: 0.12, green: 0.09, blue: 0.08)]
        }
    }
}

struct FollowingUserRowView: View {
    let user: FollowingUser
    let requestPhase: PrivateCallRequestPhase?
    let onToggleFollow: () -> Void
    let onPrimaryAction: () -> Void
    let onCancelRequest: () -> Void
    let onBusyTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            avatarView

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(countryFlag)
                                .font(.system(size: 13))

                            Text(displayName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }

                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 0)

                    AnimatedStatusIndicator(status: user.status)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button(action: onToggleFollow) {
                        Text("Takibi Birak")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .frame(minWidth: 118)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.74))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: primaryButtonAction) {
                        HStack(spacing: 6) {
                            if requestPhase != nil {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(primaryButtonTitle)
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 92)
                        .padding(.vertical, 10)
                        .background(primaryButtonBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(primaryButtonStroke, lineWidth: 0.6)
                        )
                        .opacity(user.status == .busy && requestPhase == nil ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(user.status == .busy && requestPhase == nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            guard requestPhase == nil, user.status == .busy else { return }
            onBusyTap()
        }
    }

    private var displayName: String {
        let trimmed = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private var primaryButtonTitle: String {
        switch requestPhase {
        case .checking:
            return "Vazgec"
        case .calling:
            return "Vazgec"
        case nil:
            switch user.status {
            case .online:
                return "Ara"
            case .busy:
                return "Mesgul"
            case .offline:
                return "Profil"
            }
        }
    }

    private var statusText: String {
        switch user.status {
        case .online:
            return "Su an online"
        case .busy:
            return "Su an mesgul"
        case .offline:
            return "Su an offline"
        }
    }

    private var primaryButtonAction: () -> Void {
        if requestPhase != nil {
            return onCancelRequest
        }
        if user.status == .busy {
            return onBusyTap
        }
        return onPrimaryAction
    }

    private var primaryButtonBackground: Color {
        if requestPhase != nil {
            return Color.red.opacity(0.78)
        }
        switch user.status {
        case .online:
            return Color.green.opacity(0.78)
        case .busy:
            return Color.red.opacity(0.7)
        case .offline:
            return Color.white.opacity(0.14)
        }
    }

    private var primaryButtonStroke: Color {
        if requestPhase != nil {
            return Color.white.opacity(0.18)
        }
        switch user.status {
        case .online:
            return Color.white.opacity(0.14)
        case .busy:
            return Color.red.opacity(0.45)
        case .offline:
            return Color.white.opacity(0.22)
        }
    }

    private var countryFlag: String {
        if let explicitFlag = user.countryFlag, !explicitFlag.isEmpty {
            return explicitFlag
        }
        guard let country = user.country, !country.isEmpty else { return "🌍" }
        return CountryDataProvider.flagEmoji(forRegionCode: country)
    }

    private var avatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: backgroundGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let avatar = user.avatar,
               let url = URL(string: avatar),
               !avatar.isEmpty {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.18))
                ) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            placeholderBackground
                            ProgressView()
                                .tint(.white.opacity(0.9))
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }

        }
        .frame(width: 100, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }

    private var placeholderAvatar: some View {
        ZStack {
            placeholderBackground
            Image(systemName: "person.crop.square.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: backgroundGradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundGradientColors: [Color] {
        let seed = displayName.lowercased()
        switch seed.hashValue.magnitude % 4 {
        case 0:
            return [Color(red: 0.18, green: 0.24, blue: 0.38), Color(red: 0.08, green: 0.1, blue: 0.18)]
        case 1:
            return [Color(red: 0.23, green: 0.2, blue: 0.34), Color(red: 0.1, green: 0.09, blue: 0.16)]
        case 2:
            return [Color(red: 0.18, green: 0.28, blue: 0.24), Color(red: 0.07, green: 0.12, blue: 0.14)]
        default:
            return [Color(red: 0.3, green: 0.2, blue: 0.16), Color(red: 0.12, green: 0.09, blue: 0.08)]
        }
    }
}

private struct AnimatedStatusIndicator: View {
    let status: UserStatus
    @State private var isAnimating = false
    @State private var isVisible = false

    var body: some View {
        Circle()
            .fill(fillColor)
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .shadow(color: glowColor, radius: 10, x: 0, y: 0)
            .onAppear {
                isVisible = true
                restartAnimationIfNeeded()
            }
            .onChange(of: status) { _, _ in
                restartAnimationIfNeeded()
            }
            .onDisappear {
                isVisible = false
                isAnimating = false
            }
    }

    private var shouldAnimate: Bool {
        status != .offline
    }

    private var animation: Animation {
        switch status {
        case .online:
            return .easeInOut(duration: 1.25)
        case .busy:
            return .easeInOut(duration: 0.65)
        case .offline:
            return .linear(duration: 0)
        }
    }

    private var fillColor: Color {
        switch status {
        case .online:
            return .green
        case .busy:
            return .red
        case .offline:
            return Color.gray.opacity(0.65)
        }
    }

    private var glowColor: Color {
        switch status {
        case .online:
            return Color.green.opacity(0.7)
        case .busy:
            return Color.red.opacity(0.75)
        case .offline:
            return .clear
        }
    }

    private var scale: CGFloat {
        guard shouldAnimate, isVisible else { return 1 }
        return isAnimating ? 1.2 : 1.0
    }

    private var opacity: Double {
        guard shouldAnimate, isVisible else { return 0.72 }
        return isAnimating ? 0.7 : 1.0
    }

    private func restartAnimationIfNeeded() {
        isAnimating = false
        guard shouldAnimate, isVisible else { return }
        withAnimation(animation.repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }
}
