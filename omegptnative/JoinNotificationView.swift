import SwiftUI

struct JoinNotificationView: View {
    @StateObject private var viewModel = JoinNotificationViewModel()

    var body: some View {
        ZStack {
            if let user = viewModel.currentUser {
                HStack(spacing: 8) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.71, green: 0.31, blue: 0.95))

                    Text("\(user.countryFlag) \(user.name) joined")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.33, green: 0.34, blue: 0.42))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.84))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.96), lineWidth: 1)
                )
                .shadow(color: Color(red: 0.75, green: 0.68, blue: 0.86).opacity(0.20), radius: 12, x: 0, y: 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
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
