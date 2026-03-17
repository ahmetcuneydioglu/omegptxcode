import SwiftUI
import StoreKit

struct StoreView: View {
    let dbUserId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = StoreViewModel()
    private var appUserStore = AppUserStore.shared
    @State private var showGuestSignInSheet = false

    init(dbUserId: String?) {
        self.dbUserId = dbUserId
    }

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 14)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.94, blue: 0.96),
                    Color(red: 0.91, green: 0.92, blue: 0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .opacity(0.45)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    //.background(.ultraThinMaterial)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Ücretsiz günlük ödüller")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(viewModel.dailyRewards.enumerated()), id: \.offset) { index, reward in
                                    let rewardState = viewModel.state(for: index)
                                    DailyRewardCardView(
                                        dayIndex: index,
                                        reward: reward,
                                        state: rewardState,
                                        countdown: viewModel.countdown(for: index),
                                        pulseID: viewModel.claimPulseID,
                                        onTap: {
                                            if viewModel.isGuestMode {
                                                showGuestSignInSheet = true
                                            } else if rewardState == .claimable {
                                                Task {
                                                    await viewModel.claimDailyReward(dbUserId: dbUserId)
                                                }
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                        }
                        .padding(8)
                       // .background(.ultraThinMaterial)
                       // .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Text("Bilet al")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .padding(.top, 4)

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(viewModel.packages) { package in
                                StorePackageCard(package: package) {
                                    if viewModel.isGuestMode {
                                        showGuestSignInSheet = true
                                    } else {
                                        Task {
                                            await viewModel.buyPackage(package, dbUserId: dbUserId)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 22)
                }
            }

            if let purchaseErrorMessage = viewModel.purchaseErrorMessage {
                Text(purchaseErrorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 70)
                    .padding(.horizontal, 18)
            }

            if viewModel.isLoading || viewModel.isPurchasing {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.black)
                    Text(viewModel.isPurchasing ? "İşlem işleniyor..." : "Yükleniyor...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.8))
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear {
            Task {
                await viewModel.loadProducts(dbUserId: dbUserId)
                await viewModel.fetchStoreStatus(dbUserId: dbUserId)
            }
            if dbUserId == nil {
                viewModel.enterGuestMode()
            } else {
                viewModel.startCountdownTimer()
            }
        }
        .onDisappear {
            viewModel.stopCountdownTimer()
        }
        .sheet(isPresented: $showGuestSignInSheet) {
            StoreGuestGateSheet(appUserStore: appUserStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Text("Bakiye:")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.58))
                Image(systemName: "diamond.fill")
                    .font(.system(size: 13, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(red: 0.97, green: 0.24, blue: 0.34), Color(red: 1.0, green: 0.67, blue: 0.25))
                Text("\(viewModel.gems)")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.86))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.76))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}

struct DailyRewardCardView: View {
    let dayIndex: Int
    let reward: Int
    let state: DailyRewardCardState
    let countdown: String?
    let pulseID: UUID
    let onTap: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 12, weight: .black))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.cyan.opacity(0.7))
                    .padding(.top, 8)

                Text("\(reward)")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                if let countdown {
                    Text(countdown)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Text("Gün \(dayIndex + 1)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.bottom, 8)
            }
            .frame(width: 88, height: 108)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.82)
                }
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 1)
                    .blur(radius: 0.3)
                    .mask(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            .overlay(alignment: .topTrailing) {
                if state == .claimed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.green)
                        .background(Color.white, in: Circle())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .opacity(state == .claimed ? 0.62 : 1.0)
            .saturation(state == .locked ? 0.18 : 1.0)
            .blur(radius: state == .locked ? 0.5 : 0)
            .shadow(color: shadowColor, radius: 14, x: 0, y: 8)
            .scaleEffect(state == .claimable && pulse ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .onAppear {
            if state == .claimable {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
        .onChange(of: pulseID) { _, _ in
            pulse = false
        }
    }

    private var gradientColors: [Color] {
        switch state {
        case .claimed:
            return [Color.green.opacity(0.35), Color.blue.opacity(0.35)]
        case .claimable:
            return [Color(red: 0.08, green: 0.28, blue: 0.76), Color(red: 0.16, green: 0.44, blue: 0.98)]
        case .locked:
            return [Color.gray.opacity(0.45), Color.gray.opacity(0.30)]
        }
    }

    private var borderColor: Color {
        switch state {
        case .claimed:
            return Color.green.opacity(0.95)
        case .claimable:
            return Color.cyan.opacity(0.95)
        case .locked:
            return Color.white.opacity(0.25)
        }
    }

    private var borderWidth: CGFloat {
        state == .claimable ? 2.0 : 1.0
    }

    private var shadowColor: Color {
        switch state {
        case .claimable:
            return Color.cyan.opacity(0.35)
        case .claimed:
            return Color.green.opacity(0.16)
        case .locked:
            return Color.black.opacity(0.08)
        }
    }
}

struct StorePackageCard: View {
    let package: StorePackage
    let onTap: () -> Void

    private var hasDiscount: Bool {
        package.originalPriceText != nil
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 46, height: 46)
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 20, weight: .black))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                Color(red: 0.97, green: 0.28, blue: 0.38),
                                Color(red: 1.0, green: 0.70, blue: 0.34)
                            )
                    }

                    Spacer()

                    if hasDiscount {
                        discountRibbon
                    }
                }

                Text(package.gemAmountTitle)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Text(package.comparisonLabel ?? package.unitPriceText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    if let originalPrice = package.originalPriceText {
                        Text(originalPrice)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .strikethrough(true, color: .white.opacity(0.7))
                    }

                    Spacer(minLength: 6)

                    Text(package.priceText)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: package.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(0.84)
                }
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.33), lineWidth: 1)
                    .blur(radius: 0.4)
                    .mask(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.black.opacity(0.16), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var discountRibbon: some View {
        Text(package.saveText.uppercased())
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [Color.pink.opacity(0.95), Color.red.opacity(0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .rotationEffect(.degrees(12))
    }
}

struct StoreGuestGateSheet: View {
    var appUserStore: AppUserStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("İşlem yapmak için giriş yapmalısın.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Günlük ödülleri toplamak ve taş satın almak için hesabınla giriş yap.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                Task {
                    await appUserStore.signInWithGoogle()
                    if appUserStore.isLoggedIn {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text(appUserStore.isLoading ? "Giriş Yapılıyor..." : "Giriş Yap")
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
            .disabled(appUserStore.isLoading)

            if let error = appUserStore.authErrorMessage {
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
