import Combine
import Foundation
import SwiftUI

struct OnlineFollowNotification: Identifiable, Equatable {
    let id = UUID()
    let userId: String
    let name: String
}

@MainActor
final class OnlineNotificationCenter: ObservableObject {
    static let shared = OnlineNotificationCenter()

    @Published private(set) var currentBanner: OnlineFollowNotification?
    private var dismissTask: Task<Void, Never>?

    func showOnlineBanner(userId: String, name: String) {
        dismissTask?.cancel()
        currentBanner = OnlineFollowNotification(userId: userId, name: name)

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    self?.currentBanner = nil
                }
            }
        }
    }
}

struct OnlineNotificationBannerHost: View {
    @ObservedObject private var center = OnlineNotificationCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            if let banner = center.currentBanner {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Selam! Takip ettiğin \(banner.name) şu an online, hemen eşleşebilirsin!")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.24))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: center.currentBanner)
        .allowsHitTesting(false)
    }
}
