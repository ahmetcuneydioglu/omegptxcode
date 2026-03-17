import SwiftUI
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(SocketIO)
import SocketIO
#endif

struct ContentView: View {
    @Bindable private var appState = AppState.shared
    private var socketService = SocketService.shared
    private var appUserStore = AppUserStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            MainCameraView()

            if let incomingCall = socketService.incomingPrivateCall,
               !appState.forceDismissCall {
                IncomingCallView(
                    callerName: incomingCall.callerName,
                    callerAvatarURL: incomingCall.callerAvatarURL,
                    onAccept: {
                        socketService.acceptPrivateCall(callerId: incomingCall.callerId)
                    },
                    onReject: {
                        socketService.rejectPrivateCall(callerId: incomingCall.callerId)
                    }
                )
                .zIndex(1000)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            VStack {
                if let notice = socketService.privateCallNotice {
                    PrivateCallNoticeBanner(message: notice.message)
                        .padding(.top, 18)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1001)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.24), value: socketService.privateCallNotice)
            .allowsHitTesting(false)

            if let phase = socketService.outgoingPrivateCallPhase,
               socketService.activePartnerId == nil {
                PrivateCallLoadingOverlay(
                    phase: phase,
                    onCancel: {
                        if let targetId = socketService.outgoingPrivateCallTargetId {
                            socketService.cancelPrivateCall(targetId: targetId)
                        }
                    }
                )
                    .zIndex(999)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

        }
        .animation(.easeInOut(duration: 0.22), value: socketService.outgoingPrivateCallPhase)
        .alert(appState.alertTitle, isPresented: $appState.showAlert) {
            if appState.alertContext == .insufficientGems {
                Button("Vazgec", role: .cancel) {
                    appState.resetAlert()
                }
                Button("Magazaya Git") {
                    socketService.storePresentationMessage = "Ozel arama yapabilmek icin 50 Gem gereklidir."
                    socketService.storePresentationRequestID = UUID()
                    appState.resetAlert()
                }
            } else {
                Button("Tamam", role: .cancel) {
                    appState.resetAlert()
                }
            }
        } message: {
            Text(appState.alertMessage)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                socketService.connect(dbUserId: appUserStore.currentUser?.id)
            case .inactive, .background:
                socketService.disconnect()
            @unknown default:
                break
            }
        }
    }
}
