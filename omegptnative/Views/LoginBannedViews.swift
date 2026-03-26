import SwiftUI

enum LoginRequiredContext {
    case filters
    case history
    case store
    case profile
    case guestUpgrade

    var title: String {
        switch self {
        case .filters:
            return "Giris Gerekli"
        case .history:
            return "Gecmis Icin Giris Yap"
        case .store:
            return "Magaza Icin Giris Yap"
        case .profile:
            return "Profil Icin Giris Yap"
        case .guestUpgrade:
            return "Devam Etmek Icin Giris Yap"
        }
    }

    var message: String {
        switch self {
        case .filters:
            return "Cinsiyet ve ulke filtrelerini kullanmak icin Google ile giris yapin."
        case .history:
            return "Gecmis, takip ve ozel arama gibi kalici sosyal ozellikler icin giris yapin."
        case .store:
            return "Gem yuklemek ve magaza avantajlarini kullanmak icin Google ile giris yapin."
        case .profile:
            return "Profilini kaydetmek, duzenlemek ve sosyal ozellikleri kullanmak icin giris yapin."
        case .guestUpgrade:
            return "Ilk eslesmeni kullandin. Yeni bir eslesmeye gecmek ve profil ozelliklerini acmak icin giris yapin."
        }
    }
}

struct LoginRequiredSheet: View {
    var authManager: AppUserStore
    var context: LoginRequiredContext = .filters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))

            Text(context.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text(context.message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                Task {
                    await authManager.signInWithGoogle()
                    if authManager.isLoggedIn {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                    Text(authManager.isLoading ? "Giris Yapiliyor..." : "Google ile Giris Yap")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.97, blue: 0.48),
                            Color(red: 0.06, green: 0.77, blue: 0.36)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(authManager.isLoading)

            if let error = authManager.authErrorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red.opacity(0.95))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color.black.opacity(0.22)
                .background(.ultraThinMaterial)
        )
    }
}

struct BannedView: View {
    let reason: String
    let expireAt: Date?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.13, green: 0.03, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.red.opacity(0.95))

                Text("Hesabin Gecici Olarak Engellendi")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(reason)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                if let expireAt {
                    Text("Bitis: \(expireAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(28)
        }
    }
}
