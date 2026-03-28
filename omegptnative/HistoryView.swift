import SwiftUI

private enum HistoryTab: String, CaseIterable, Identifiable {
    case history = "Gecmis"
    case following = "Takip Ettiklerim"

    var id: String { rawValue }
}

struct HistoryView: View {
    let currentUserId: String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = HistoryViewModel()
    private var socketService = SocketService.shared
    private var appState = AppState.shared
    private var appUserStore = AppUserStore.shared
    @State private var selectedTab: HistoryTab = .history
    @State private var showStoreSheet = false
    @State private var showInsufficientGemsSheet = false
    @State private var insufficientGemsMessage = "Bu islem icin yeterli Gem bulunmuyor."

    init(currentUserId: String?) {
        self.currentUserId = currentUserId
    }

    var body: some View {
        historyRoot
    }

    private var historyRoot: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                VStack(spacing: 14) {
                    tabPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    content
                        .padding(.horizontal, 16)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.26), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                Task { await loadSelectedTab() }
            }
            .onChange(of: selectedTab) { _, _ in
                Task { await loadSelectedTab() }
            }
            .onChange(of: socketService.activePartnerId) { _, newPartnerId in
                guard newPartnerId != nil else { return }
                dismiss()
            }
            .onChange(of: socketService.incomingPrivateCall) { _, incomingCall in
                guard incomingCall != nil else { return }
                dismiss()
            }
            .onChange(of: socketService.storePresentationRequestID) { _, newValue in
                guard newValue != nil else { return }
                insufficientGemsMessage = socketService.storePresentationMessage
                showInsufficientGemsSheet = true
                socketService.consumeStorePresentationRequest()
            }
            .onChange(of: socketService.userOnlineStates) { _, states in
                viewModel.applyOnlineStates(states)
            }
        }
        .sheet(isPresented: $showStoreSheet) {
            StoreView(dbUserId: appUserStore.currentUser?.id)
        }
        .sheet(isPresented: $showInsufficientGemsSheet) {
            InsufficientGemsSheet(
                message: insufficientGemsMessage,
                currentGems: appUserStore.currentUser?.gems ?? 0,
                onStore: {
                    showStoreSheet = true
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
        }
        .globalToastOverlay()
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.1),
                Color(red: 0.09, green: 0.11, blue: 0.15),
                Color(red: 0.12, green: 0.14, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var tabPicker: some View {
        HStack(spacing: 8) {
            ForEach(HistoryTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(selectedTab == tab ? 1 : 0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedTab == tab ? Color.white.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    selectedTab == tab ? Color.white.opacity(0.28) : Color.white.opacity(0.08),
                                    lineWidth: 0.7
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.white)
                Text("Loading match history...")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.76))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(errorMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(selectedTab == .history ? "No matches yet" : "No following users yet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(selectedTab == .history ? "Your completed calls will appear here." : "Users you follow will appear here.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    if selectedTab == .history {
                        ForEach(viewModel.items) { history in
                            HistoryCardView(history: history) {
                                Task {
                                    await viewModel.toggleFollow(partnerId: history.partner.id)
                                }
                            }
                        }
                    } else {
                        ForEach(viewModel.followingUsers) { user in
                            FollowingUserRowView(
                                user: user,
                                requestPhase: socketService.outgoingPrivateCallTargetId == user.id
                                    ? socketService.outgoingPrivateCallPhase
                                    : nil
                            ) {
                                Task {
                                    await viewModel.toggleFollow(partnerId: user.id)
                                }
                            } onPrimaryAction: {
                                guard user.status == .online else { return }
                                socketService.requestPrivateCall(targetUserId: user.id)
                            } onCancelRequest: {
                                socketService.cancelPrivateCall(targetId: user.id)
                            } onBusyTap: {
                                appState.showTimedToast("Kullanici su an baska bir gorusmede.")
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func loadSelectedTab() async {
        switch selectedTab {
        case .history:
            await viewModel.fetchHistory(currentUserId: currentUserId)
        case .following:
            await viewModel.fetchFollowing(currentUserId: currentUserId)
        }
        socketService.requestUserStatus(for: viewModel.allTrackedUserIds(includeFollowing: selectedTab == .following))
        viewModel.applyOnlineStates(socketService.userOnlineStates)
    }
}
