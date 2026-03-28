import SwiftUI
import AVFoundation

struct MainCameraView: View {
    private var appUserStore = AppUserStore.shared
    @StateObject private var webRTCManager = WebRTCManager.shared
    @Bindable private var socketService = SocketService.shared
    @State private var isCameraOn = true
    @State private var isMuted = false
    @State private var showGenderSheet = false
    @State private var showCountrySheet = false
    @State private var showLoginRequiredSheet = false
    @State private var showInsufficientGemsSheet = false
    @State private var loginRequiredContext: LoginRequiredContext = .filters
    @State private var insufficientGemsMessage = "Bu islem icin yeterli Gem bulunmuyor."
    @State private var showProfileSheet = false
    @State private var showHistorySheet = false
    @State private var hasShownGuestUpgradePrompt = false
    @State private var lastActivePartnerId: String?
    @State private var animateGuestProfileBadge = false
    @State private var currentGender = "male"
    @State private var selectedGender: GenderFilterOption = .all
    @State private var selectedCountry = "Global"
    @State private var isRadarIntensified = false
    @State private var searchCountryCode = "all"
    @State private var searchGenderCode = "all"
    @State private var searchScopeBadge = "Global 🌎"
    @State private var fallbackTriggered = false
    @State private var isStorePresented = false
    @State private var showGemToast = false
    @State private var gemToastMessage = ""
    @State private var showBeautyPanel = false
    @State private var beautySmoothness: Double = 0.0
    @State private var beautyVibrance: Double = 0.0
    @State private var beautyExposure: Double = 0.0
    @State private var beautyEye: Double = 0.0
    @State private var beautyNose: Double = 0.0
    @State private var beautyJawline: Double = 0.0
    @State private var beautyTeeth: Double = 0.0
    @State private var teethLuminanceMin: Double = 0.46
    @State private var teethChromaMax: Double = 0.38
    @State private var filterIntensity: Double = 0.0
    @State private var selectedBeautyPreset: ProfessionalColorPreset = .none
    @State private var selectedBeautyTab: BeautyTab = .beauty
    @State private var selectedBeautyTool: BeautyTool = .brighten

    var body: some View {
        GeometryReader { geometry in
            mainScene(geometry: geometry)
        }
    }

    private func mainScene(geometry: GeometryProxy) -> some View {
        let transition = AnyTransition.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )

        let scene: AnyView
        if let activePartnerId = socketService.activePartnerId {
            switch socketService.sessionStage {
            case .videoCall:
                scene = AnyView(
                    VideoChatView(
                        partnerId: activePartnerId,
                        partnerInfo: socketService.activeMatch,
                        onEnd: {
                            skipToNextPartner()
                        },
                        onFlipCamera: {
                            WebRTCManager.shared.switchCamera()
                        },
                        onNextPartner: {
                            skipToNextPartner()
                        }
                    )
                    .transition(transition)
                )
            default:
                scene = AnyView(
                    OnlineMatchChatView(
                        partnerId: activePartnerId,
                        partnerInfo: socketService.activeMatch,
                        onNextPartner: {
                            skipToNextPartner()
                        },
                        onEnd: {
                            socketService.endCall()
                        }
                    )
                    .transition(transition)
                )
            }
        } else {
            scene = AnyView(
                discoveryScene(geometry: geometry)
                    .transition(transition)
            )
        }

        let core = applyCoreSceneModifiers(to: scene)
        let withStateObservers = applySceneStateObservers(to: core)
        return applyScenePresentations(to: withStateObservers)
    }

    private func applyCoreSceneModifiers<Content: View>(to view: Content) -> some View {
        view
            .animation(.easeInOut(duration: 0.3), value: socketService.activePartnerId)
            .animation(.easeInOut(duration: 0.25), value: socketService.isSearching)
            .contentShape(Rectangle())
            .simultaneousGesture(universalSwipeGesture, including: .all)
            .overlay(alignment: .top) {
                OnlineNotificationBannerHost()
                    .zIndex(300)
            }
            .onAppear {
                socketService.connect(dbUserId: appUserStore.currentUser?.id)
            }
            .onDisappear {
                socketService.disconnect()
            }
    }

    private func applySceneStateObservers<Content: View>(to view: Content) -> some View {
        applyAuthAndSocketObservers(to: view)
    }

    private func applyCameraAndBeautyObservers<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: isCameraOn) { _, isEnabled in
                if isEnabled {
                    webRTCManager.startPreviewCapture()
                    webRTCManager.setVideoEnabled(true)
                } else {
                    webRTCManager.setVideoEnabled(false)
                }
            }
            .onChange(of: beautySmoothness) { _, _ in applyBeautySettings() }
            .onChange(of: beautyVibrance) { _, _ in applyBeautySettings() }
            .onChange(of: beautyExposure) { _, _ in applyBeautySettings() }
            .onChange(of: selectedBeautyPreset) { _, _ in applyBeautySettings() }
            .onChange(of: selectedBeautyTab) { _, _ in applyBeautySettings() }
            .onChange(of: selectedBeautyTool) { _, _ in applyBeautySettings() }
            .onChange(of: beautyEye) { _, _ in applyBeautySettings() }
            .onChange(of: beautyNose) { _, _ in applyBeautySettings() }
            .onChange(of: beautyJawline) { _, _ in applyBeautySettings() }
            .onChange(of: beautyTeeth) { _, _ in applyBeautySettings() }
            .onChange(of: teethLuminanceMin) { _, _ in applyBeautySettings() }
            .onChange(of: teethChromaMax) { _, _ in applyBeautySettings() }
            .onChange(of: filterIntensity) { _, _ in applyBeautySettings() }
    }

    private func applyAuthAndSocketObservers<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: appUserStore.isLoggedIn) { _, _ in
                hasShownGuestUpgradePrompt = false
                socketService.resetGuestMatchProgress()
                socketService.disconnect()
                socketService.connect(dbUserId: appUserStore.currentUser?.id)
            }
            .onChange(of: appUserStore.currentUser?.id) { _, newUserId in
                print("👤 Auth user changed. Reconnecting socket with dbUserId: \(newUserId ?? "guest")")
                socketService.disconnect()
                socketService.connect(dbUserId: newUserId)
            }
            .onChange(of: socketService.activePartnerId) { _, newPartnerId in
                if newPartnerId != nil {
                    isRadarIntensified = false
                }

                if lastActivePartnerId != nil,
                   newPartnerId == nil,
                   !appUserStore.isLoggedIn,
                   socketService.guestMatchCount >= 5,
                   !hasShownGuestUpgradePrompt {
                    presentLoginRequiredSheet(.guestUpgrade)
                    hasShownGuestUpgradePrompt = true
                }

                lastActivePartnerId = newPartnerId
            }
            .onChange(of: socketService.storePresentationRequestID) { _, _ in
                guard socketService.storePresentationRequestID != nil else { return }
                guard !showProfileSheet, !showHistorySheet else { return }
                if appUserStore.isLoggedIn {
                    insufficientGemsMessage = socketService.storePresentationMessage
                    showInsufficientGemsSheet = true
                } else {
                    presentLoginRequiredSheet(.store)
                }
                socketService.consumeStorePresentationRequest()
            }
    }

    private func applyScenePresentations<Content: View>(to view: Content) -> some View {
        view
            .sheet(isPresented: $showGenderSheet) {
                GenderSelectionSheet(
                    appUserStore: appUserStore,
                    selectedOption: $selectedGender,
                    onMatchNow: startMatching
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showCountrySheet) {
                CountrySelectionSheet(
                    appUserStore: appUserStore,
                    selectedCountry: $selectedCountry,
                    onMatchNow: startMatching
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showLoginRequiredSheet) {
                LoginRequiredSheet(authManager: appUserStore, context: loginRequiredContext)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showInsufficientGemsSheet) {
                InsufficientGemsSheet(
                    message: insufficientGemsMessage,
                    currentGems: appUserStore.currentUser?.gems ?? 0,
                    onStore: {
                        isStorePresented = true
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showProfileSheet) {
                ProfileView(
                    appUserStore: appUserStore,
                    onClose: {
                        showProfileSheet = false
                    },
                    onLogout: {
                        appUserStore.logout()
                        socketService.disconnect()
                        socketService.connect(dbUserId: nil)
                        showProfileSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showHistorySheet) {
                HistoryView(currentUserId: appUserStore.currentUser?.id)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
            .fullScreenCover(item: $socketService.banEvent) { banEvent in
                BannedView(
                    reason: banEvent.reason,
                    expireAt: banEvent.expireAt
                )
            }
            .fullScreenCover(isPresented: $isStorePresented) {
                StoreView(dbUserId: appUserStore.currentUser?.id)
            }
    }

    private func discoveryScene(geometry: GeometryProxy) -> some View {
        ZStack {
            cameraPlaceholderBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topOverlay
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        onlineDiscoveryCard
                            .padding(.top, 26)

                        if !socketService.isSearching {
                            JoinNotificationView()
                        }

                        bottomControls
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18) + 28)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            MatchRadarView(isIntensified: isRadarIntensified)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18) + 120)
                .allowsHitTesting(false)
                .opacity(socketService.isSearching ? 0.22 : 0.22)

            if socketService.isSearching {
                SearchingOverlayView(
                    scopeBadge: searchScopeBadge,
                    canFallbackToGlobal: searchCountryCode != "all" && !fallbackTriggered,
                    onCancelSearch: {
                        socketService.stopSearch()
                    },
                    onGlobalFallback: {
                        triggerGlobalFallback()
                    }
                )
                .transition(.opacity)
            }

            if showGemToast {
                Text(gemToastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.34))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, geometry.safeAreaInsets.top + 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(120)
            }
        }
    }

    private var matchSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onChanged { value in
                if value.translation.width < -10 {
                    isRadarIntensified = true
                }
            }
            .onEnded { value in
                defer {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isRadarIntensified = false
                    }
                }

                let isHorizontalSwipe = abs(value.translation.height) < 120
                let didSwipeLeft = value.translation.width < 0
                guard isHorizontalSwipe, didSwipeLeft else { return }

                print("🔍 Swipe detected! Sending find_partner to backend...")
                let preferredGender = selectedGender.socketValue
                let preferredCountry = selectedCountry == "Global"
                    ? "all"
                    : (CountryDataProvider.regionCode(forLocalizedName: selectedCountry) ?? "all")
                guard validateFilterCostsOrPresentStore(preferredGender: preferredGender, preferredCountry: preferredCountry) else {
                    return
                }
                appUserStore.preferredGender = preferredGender
                appUserStore.preferredCountry = preferredCountry
                let feedback = UIImpactFeedbackGenerator(style: .heavy)
                feedback.impactOccurred()
                socketService.findPartner(
                    myGender: appUserStore.currentUser?.gender ?? currentGender,
                    searchGender: appUserStore.preferredGender,
                    selectedCountry: appUserStore.preferredCountry
                )
            }
    }

    private var universalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                if value.translation.width < -10 {
                    isRadarIntensified = true
                }
            }
            .onEnded { value in
                defer {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isRadarIntensified = false
                    }
                }

                let dx = value.translation.width
                let dy = value.translation.height
                let isSignificantlyHorizontal = abs(dx) > abs(dy) * 1.4
                let didSwipeLeft = dx < -50
                guard isSignificantlyHorizontal, didSwipeLeft else { return }

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                print("⏭️ Universal swipe recognized. Skipping to next/search.")
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    skipToNextPartner()
                }
            }
    }

    private func startMatching() {
        guard !socketService.isFindPartnerLocked,
              !socketService.isAwaitingSearchStart,
              !(socketService.isSearching && socketService.activePartnerId == nil) else {
            print("⏳ startMatching ignored: matchmaking already pending/searching")
            return
        }

        guard !shouldRequireLoginBeforeNextGuestMatch() else { return }

        let preferredGender = selectedGender.socketValue
        let preferredCountry = selectedCountry == "Global"
            ? "all"
            : (CountryDataProvider.regionCode(forLocalizedName: selectedCountry) ?? "all")

        guard validateFilterCostsOrPresentStore(preferredGender: preferredGender, preferredCountry: preferredCountry) else {
            return
        }

        configureSearchScope(countryCode: preferredCountry, genderCode: preferredGender)

        socketService.findPartner(
            myGender: currentGender,
            searchGender: preferredGender,
            selectedCountry: preferredCountry
        )
    }

    private func skipToNextPartner() {
        guard !socketService.isFindPartnerLocked,
              !socketService.isAwaitingSearchStart,
              !(socketService.isSearching && socketService.activePartnerId == nil) else {
            print("⏳ skipToNextPartner ignored: matchmaking already pending/searching")
            return
        }

        if shouldRequireLoginBeforeNextGuestMatch() {
            socketService.endCall()
            return
        }

        let preferredGender = selectedGender.socketValue
        let preferredCountry = selectedCountry == "Global"
            ? "all"
            : (CountryDataProvider.regionCode(forLocalizedName: selectedCountry) ?? "all")

        guard validateFilterCostsOrPresentStore(preferredGender: preferredGender, preferredCountry: preferredCountry) else {
            return
        }

        configureSearchScope(countryCode: preferredCountry, genderCode: preferredGender)

        socketService.swipeToNextAndSearch(
            myGender: appUserStore.currentUser?.gender ?? currentGender,
            searchGender: preferredGender,
            selectedCountry: preferredCountry
        )
    }

    private func configureSearchScope(countryCode: String, genderCode: String) {
        searchCountryCode = countryCode
        searchGenderCode = genderCode
        fallbackTriggered = false
        searchScopeBadge = makeScopeBadge(countryCode: countryCode, genderCode: genderCode)
    }

    private func triggerGlobalFallback() {
        guard socketService.isSearching, searchCountryCode != "all", !fallbackTriggered else { return }
        fallbackTriggered = true
        searchCountryCode = "all"
        searchScopeBadge = "Global 🌎"
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        socketService.findPartner(
            myGender: appUserStore.currentUser?.gender ?? currentGender,
            searchGender: searchGenderCode,
            selectedCountry: "all"
        )
    }

    private func makeScopeBadge(countryCode: String, genderCode: String) -> String {
        let countryPart: String = {
            if countryCode == "all" { return "Global 🌎" }
            return "\(countryCode) \(CountryDataProvider.flagEmoji(forRegionCode: countryCode))"
        }()

        let genderPart: String = {
            switch genderCode {
            case "female":
                return "Kadın 👩"
            case "male":
                return "Erkek 👨"
            default:
                return "Tümü ✨"
            }
        }()

        return "\(countryPart) • \(genderPart)"
    }

    private func validateFilterCostsOrPresentStore(preferredGender: String, preferredCountry: String) -> Bool {
        let gems = appUserStore.currentUser?.gems ?? 0
        var required = 0
        if preferredGender == "female" { required += 8 }
        if preferredCountry != "all" { required += 4 }
        guard required > 0 else { return true }

        if gems < required {
            insufficientGemsMessage = "Secili filtreleri kullanabilmek icin en az \(required) Gem gerekiyor."
            showInsufficientGemsSheet = true
            return false
        }
        return true
    }

    private func applyBeautySettings() {
        webRTCManager.setBeautyFilterEnabled(true)
        webRTCManager.updateBeautyConfiguration(
            smoothing: Float(beautySmoothness),
            eyeEnhance: Float(beautyEye),
            noseContour: Float(beautyNose),
            jawlineContour: Float(beautyJawline),
            teethWhitening: Float(beautyTeeth),
            teethLuminanceMin: Float(teethLuminanceMin),
            teethChromaMax: Float(teethChromaMax),
            vibrance: Float(beautyVibrance),
            exposure: Float(beautyExposure),
            presetIntensity: Float(filterIntensity),
            preset: selectedBeautyPreset
        )
    }

    private func resetBeautySettings() {
        beautySmoothness = 0.0
        beautyVibrance = 0.0
        beautyExposure = 0.0
        beautyEye = 0.0
        beautyNose = 0.0
        beautyJawline = 0.0
        beautyTeeth = 0.0
        teethLuminanceMin = 0.46
        teethChromaMax = 0.38
        filterIntensity = 0.0
        selectedBeautyPreset = .none
        selectedBeautyTab = .beauty
        selectedBeautyTool = .brighten
        applyBeautySettings()
    }

    private var selectedIntensityBinding: Binding<Double> {
        Binding(
            get: {
                switch selectedBeautyTab {
                case .beauty:
                    switch selectedBeautyTool {
                    case .brighten: return beautyExposure
                    case .smooth: return beautySmoothness
                    case .eye: return beautyEye
                    case .nose: return beautyNose
                    case .jawline: return beautyJawline
                    case .teeth: return beautyTeeth
                    }
                case .filters:
                    return filterIntensity
                }
            },
            set: { newValue in
                switch selectedBeautyTab {
                case .beauty:
                    switch selectedBeautyTool {
                    case .brighten: beautyExposure = newValue
                    case .smooth: beautySmoothness = newValue
                    case .eye: beautyEye = newValue
                    case .nose: beautyNose = newValue
                    case .jawline: beautyJawline = newValue
                    case .teeth: beautyTeeth = newValue
                    }
                case .filters:
                    filterIntensity = newValue
                }
            }
        )
    }

    private var cameraPlaceholderBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.985, green: 0.975, blue: 0.995),
                    Color(red: 0.972, green: 0.966, blue: 0.992),
                    Color(red: 0.964, green: 0.972, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )

            Circle()
                .fill(Color(red: 0.76, green: 0.35, blue: 0.98).opacity(0.18))
                .frame(width: 290, height: 290)
                .blur(radius: 28)
                .offset(x: -130, y: -250)

            Circle()
                .fill(Color(red: 1.0, green: 0.44, blue: 0.72).opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 24)
                .offset(x: 135, y: -80)

            Circle()
                .fill(Color(red: 0.46, green: 0.56, blue: 1.0).opacity(0.10))
                .frame(width: 250, height: 250)
                .blur(radius: 28)
                .offset(x: 120, y: 320)

            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color(red: 0.63, green: 0.61, blue: 0.74).opacity(0.16))
        }
    }

    private var onlineDiscoveryCard: some View {
        VStack(alignment: .center, spacing: 18) {
            VStack(alignment: .center, spacing: 12) {
                Text("Online eslesme")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.52, green: 0.21, blue: 0.97),
                                Color(red: 0.98, green: 0.30, blue: 0.66)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(discoveryDescription)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 18) {
                discoveryBullet(
                    icon: "camera.fill",
                    title: "Photo-first",
                    detail: "Eslesme geldiginde kamera degil, fotograf ve kisa profil acilir."
                )
                discoveryBullet(
                    icon: "bubble.left",
                    title: "Direkt chat",
                    detail: "Eslesme aninda yazismaya baslayabilirsiniz."
                )
                discoveryBullet(
                    icon: "waveform",
                    title: "Opsiyonel voice",
                    detail: "Istersen sonradan ucretsiz sesli gorusme istegi gonder."
                )
                discoveryBullet(
                    icon: "video.fill",
                    title: "Video gorusme",
                    detail: "Text veya voice sonrasinda istersen video daveti baslat."
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .background(Color.white.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.78, green: 0.70, blue: 0.88).opacity(0.18), radius: 26, x: 0, y: 12)
            .padding(.bottom, 82)

            Button {
                if socketService.isSearching {
                    socketService.stopSearch()
                } else {
                    startMatching()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: socketService.isSearching ? "xmark.circle.fill" : "heart.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(socketService.isSearching ? "Aramayi Durdur" : "Online Kisi Bul")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.64, green: 0.25, blue: 0.98),
                            Color(red: 0.98, green: 0.33, blue: 0.68),
                            Color(red: 0.40, green: 0.39, blue: 0.94)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: Color(red: 0.70, green: 0.33, blue: 0.92).opacity(0.26), radius: 20, x: 0, y: 10)
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                Label("Guvenli ve gizli", systemImage: "lock.fill")
                Label("Aninda eslesme", systemImage: "bolt.fill")
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.61, green: 0.60, blue: 0.68))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private func discoveryBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.72, green: 0.28, blue: 0.96))
                .frame(width: 42, height: 42)
                .background(Color(red: 0.97, green: 0.89, blue: 0.98), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.27, blue: 0.35))
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 0.45, green: 0.47, blue: 0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var discoveryDescription: AttributedString {
        var text = AttributedString("Sadece su anda aktif olan kisilerle esles. Once profil ve mesaj, sonra istersen sesli veya video gorusme.")
        text.foregroundColor = UIColor(
            red: 0.35,
            green: 0.37,
            blue: 0.46,
            alpha: 1
        )

        if let range = text.range(of: "sonra istersen") {
            text[range].foregroundColor = UIColor(
                red: 0.98,
                green: 0.30,
                blue: 0.66,
                alpha: 1
            )
        }

        return text
    }

    private var topOverlay: some View {
        HStack(alignment: .center) {
            Text("MAX'I AI")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.41, green: 0.36, blue: 0.62))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.78))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    guard appUserStore.isLoggedIn else {
                        presentLoginRequiredSheet(.history)
                        return
                    }
                    showHistorySheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.57, green: 0.34, blue: 0.94), Color(red: 0.95, green: 0.42, blue: 0.70)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    print("DEBUG: Gem icon tapped")
                    guard appUserStore.isLoggedIn else {
                        presentLoginRequiredSheet(.store)
                        return
                    }
                    isStorePresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.57, green: 0.34, blue: 0.94), Color(red: 0.95, green: 0.42, blue: 0.70)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("\(appUserStore.currentUser?.gems ?? 0)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.34, green: 0.33, blue: 0.42))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button {
                    if appUserStore.isLoggedIn {
                        showProfileSheet = true
                    } else {
                        presentLoginRequiredSheet(.profile)
                    }
                } label: {
                    Group {
                        if appUserStore.isLoggedIn,
                           let avatar = appUserStore.currentUser?.avatar,
                           let avatarURL = URL(string: avatar) {
                            AsyncImage(url: avatarURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(7)
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color(red: 0.57, green: 0.34, blue: 0.94), Color(red: 0.95, green: 0.42, blue: 0.70)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                            }
                        } else {
                            guestProfileAvatar
                        }
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.74))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.74, green: 0.70, blue: 0.86).opacity(0.18), radius: 14, x: 0, y: 6)
        }
        .padding(.top, 2)
    }

    private var leftFloatingMenu: some View {
        VStack(spacing: 14) {
            Button {
                webRTCManager.switchCamera()
            } label: {
                Image(systemName: "camera.rotate.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                isMuted.toggle()
                webRTCManager.setAudioMuted(isMuted)
            } label: {
                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isMuted ? .white.opacity(0.65) : .white)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button {
                isCameraOn.toggle()
                webRTCManager.setVideoEnabled(isCameraOn)
            } label: {
                Image(systemName: isCameraOn ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isCameraOn ? .white : .white.opacity(0.65))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.18))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
    }

    private var leftControlColumn: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    showBeautyPanel.toggle()
                }
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)

            leftFloatingMenu
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            genderSelectionButton
            countrySelectionButton
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private var genderSelectionButton: some View {
        Button {
            guard appUserStore.isLoggedIn else {
                presentLoginRequiredSheet(.filters)
                return
            }
            showGenderSheet = true
        } label: {
            HStack(spacing: 10) {
                PremiumGenderIcon()
                    .shadow(color: selectedGender != .all ? Color(red: 0.80, green: 0.45, blue: 0.95).opacity(0.35) : .clear, radius: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Cinsiyet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.29, green: 0.30, blue: 0.38))
                    if selectedGender == .female {
                        HStack(spacing: 4) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.70))
                            Text("8")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.69, green: 0.59, blue: 0.76))
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.58, green: 0.57, blue: 0.67))
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selectedGender != .all ? Color(red: 0.91, green: 0.51, blue: 0.84).opacity(0.7) : Color.white.opacity(0.92), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var countrySelectionButton: some View {
        Button {
            guard appUserStore.isLoggedIn else {
                presentLoginRequiredSheet(.filters)
                return
            }
            showCountrySheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.66, green: 0.32, blue: 0.96))
                    .shadow(color: selectedCountry != "Global" ? Color(red: 0.80, green: 0.45, blue: 0.95).opacity(0.35) : .clear, radius: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedCountry)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.29, green: 0.30, blue: 0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if selectedCountry != "Global" {
                        HStack(spacing: 4) {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.70))
                            Text("4")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.69, green: 0.59, blue: 0.76))
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.58, green: 0.57, blue: 0.67))
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(Color.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selectedCountry != "Global" ? Color(red: 0.91, green: 0.51, blue: 0.84).opacity(0.7) : Color.white.opacity(0.92), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func shouldRequireLoginBeforeNextGuestMatch() -> Bool {
        guard !appUserStore.isLoggedIn, socketService.guestMatchCount >= 5 else { return false }
        presentLoginRequiredSheet(.guestUpgrade)
        hasShownGuestUpgradePrompt = true
        return true
    }

    private func presentLoginRequiredSheet(_ context: LoginRequiredContext) {
        loginRequiredContext = context
        showLoginRequiredSheet = true
    }

    private var guestProfileAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.22, blue: 0.36),
                            Color(red: 0.27, green: 0.12, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.08))
                .scaleEffect(animateGuestProfileBadge ? 1.1 : 0.8)
                .blur(radius: 2)

            HStack(spacing: -3) {
                Image(systemName: "figure.stand.dress.line.vertical.figure")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.67))
                    .offset(y: animateGuestProfileBadge ? -0.8 : 0.8)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.43, green: 0.78, blue: 1.0))
                    .offset(y: animateGuestProfileBadge ? 0.8 : -0.8)
            }
        }
        .onAppear {
            guard !animateGuestProfileBadge else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                animateGuestProfileBadge = true
            }
        }
    }
}
