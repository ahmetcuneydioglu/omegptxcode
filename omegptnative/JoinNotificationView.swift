import SwiftUI

struct JoinNotificationView: View {
    @StateObject private var viewModel = JoinNotificationViewModel()

    var body: some View {
        ZStack {
            if let user = viewModel.currentUser {
                HStack(spacing: 8) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("\(user.countryFlag) \(user.name) joined")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.24))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.leading, 16)
        .padding(.bottom, 90)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentUser)
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
