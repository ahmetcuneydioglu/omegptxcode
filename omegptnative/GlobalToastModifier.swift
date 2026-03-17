import SwiftUI

struct GlobalToastModifier: ViewModifier {
    private var appState = AppState.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.showToast {
                    VStack {
                        GlobalToastBanner(message: appState.toastMessage)
                            .padding(.top, 60)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                    .ignoresSafeArea()
                    .zIndex(999)
                    .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: appState.showToast)
    }
}

extension View {
    func globalToastOverlay() -> some View {
        modifier(GlobalToastModifier())
    }
}
