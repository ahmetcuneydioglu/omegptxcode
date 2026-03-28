import SwiftUI

struct IncomingCallView: View {
    let callerName: String
    let callerAvatarURL: String?
    let mode: CallRequestMode
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Text(mode.incomingTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))

                avatarView

                Text(callerName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                HStack(spacing: 18) {
                    Button(action: onReject) {
                        Label("Reddet", systemImage: "phone.down.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.82))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        Label(mode.acceptLabel, systemImage: mode == .voice ? "waveform" : "phone.fill")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.82))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let callerAvatarURL,
               let url = URL(string: callerAvatarURL),
               !callerAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallbackAvatar
                    @unknown default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white.opacity(0.8))
            .padding(18)
    }
}

struct PrivateCallNoticeBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.badge.waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
    }
}

struct PrivateCallLoadingOverlay: View {
    let phase: PrivateCallRequestPhase
    let mode: CallRequestMode
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.15)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                Button(action: onCancel) {
                    Text("Iptal Et")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 104)
                        .padding(.vertical, 11)
                        .background(Color.red.opacity(0.76))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.26))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }

    private var title: String {
        switch phase {
        case .checking:
            return mode == .voice ? "Sesli istek kontrol ediliyor..." : "Video istegi kontrol ediliyor..."
        case .calling:
            return mode == .voice ? "Sesli istek gonderiliyor..." : "Video daveti gonderiliyor..."
        }
    }

    private var subtitle: String {
        switch phase {
        case .checking:
            return mode == .voice ? "Eslesen kisi su an sesli gorusmeye uygun mu bakiyoruz." : "Eslestigin kisinin su an video icin uygun olup olmadigina bakiyoruz."
        case .calling:
            return mode == .voice ? "Sesli gorusme istegi karsi tarafa iletiliyor." : "Video daveti karsi tarafa iletiliyor."
        }
    }
}

struct GlobalToastBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.down.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.82, green: 0.12, blue: 0.12).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
        )
        .shadow(color: Color.red.opacity(0.22), radius: 16, x: 0, y: 10)
    }
}
