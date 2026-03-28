import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    var appUserStore: AppUserStore
    let onClose: () -> Void
    let onLogout: () -> Void
    private var socketService = SocketService.shared
    private var appState = AppState.shared

    @State private var profileVM = ProfileViewModel()
    @State private var selectedTab = 0
    @State private var showEditSheet = false
    @State private var showStoreSheet = false
    @State private var showInsufficientGemsSheet = false
    @State private var activeEditor: ProfileEditorSheet?
    @State private var selectedPreviewUser: FollowingUser?
    @State private var insufficientGemsMessage = "Bu islem icin yeterli Gem bulunmuyor."
    @State private var draftName = ""
    @State private var draftBio = ""
    @State private var selectedInterests: Set<String> = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var localPhotos: [UIImage] = []
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var localAvatar: UIImage? = nil

    private let availableInterests = [
        "Muzik", "Spor", "Sinema", "Seyahat", "Teknoloji",
        "Sanat", "Moda", "Kahve", "Oyun", "Sokak Yemekleri"
    ]

    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.44, green: 0.28, blue: 1.0), Color(red: 0.22, green: 0.60, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    init(
        appUserStore: AppUserStore,
        onClose: @escaping () -> Void = {},
        onLogout: @escaping () -> Void = {}
    ) {
        self.appUserStore = appUserStore
        self.onClose = onClose
        self.onLogout = onLogout
    }

    var body: some View {
        profileRoot
    }

    private var profileRoot: some View {
        NavigationStack {
            profileScrollContent
                .background(profileBackground)
                .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await handleInitialTask()
        }
        .onChange(of: appUserStore.currentUser?.name) { _, _ in
            handleNameChange()
        }
        .onChange(of: appUserStore.currentUser?.interests) { _, _ in
            handleInterestsChange()
        }
        .onChange(of: photoPickerItems) { _, newValue in
            handlePhotoPickerChange(newValue)
        }
        .onChange(of: avatarPickerItem) { _, newValue in
            handleAvatarPickerChange(newValue)
        }
        .onChange(of: socketService.activePartnerId) { _, newPartnerId in
            guard newPartnerId != nil else { return }
            onClose()
        }
        .onChange(of: socketService.incomingPrivateCall) { _, incomingCall in
            guard incomingCall != nil else { return }
            onClose()
        }
        .onChange(of: socketService.storePresentationRequestID) { _, newValue in
            guard newValue != nil else { return }
            insufficientGemsMessage = socketService.storePresentationMessage
            showInsufficientGemsSheet = true
            socketService.consumeStorePresentationRequest()
        }
        .sheet(isPresented: $showEditSheet, content: editProfileSheet)
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
        .sheet(item: $selectedPreviewUser) { user in
            FollowingUserProfileSheet(user: user)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var profileScrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                headerButtons
                profileHero
                statsSectionView
                tabBarSection
                tabContentSection
            }
            .padding(.bottom, 34)
        }
    }

    private var statsSectionView: some View {
        statsBar
            .padding(.horizontal, 20)
            .padding(.top, 28)
    }

    private var tabBarSection: some View {
        tabBar
            .padding(.horizontal, 20)
            .padding(.top, 24)
    }

    private var tabContentSection: some View {
        tabContent
            .padding(.top, 16)
    }

    private var profileBackground: some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.99)
                .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.77, green: 0.46, blue: 1.0).opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 16)
                .offset(x: 124, y: -236)

            Circle()
                .fill(Color(red: 1.0, green: 0.56, blue: 0.78).opacity(0.16))
                .frame(width: 230, height: 230)
                .blur(radius: 24)
                .offset(x: -120, y: -120)

            Circle()
                .fill(Color(red: 0.57, green: 0.71, blue: 1.0).opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: 0, y: 310)
        }
    }

    private func editProfileSheet() -> some View {
        EditProfileView(appUserStore: appUserStore)
    }

    private func handleInitialTask() async {
        syncDrafts()
        if localAvatar == nil {
            localAvatar = appUserStore.cachedAvatarImage()
        }
        if localPhotos.isEmpty {
            localPhotos = appUserStore.cachedPhotos()
        }
        if let uid = appUserStore.currentUser?.id {
            await profileVM.fetchAll(userId: uid)
        }
    }

    private func handleNameChange() {
        syncDrafts()
    }

    private func handleInterestsChange() {
        syncDrafts()
    }

    private func handlePhotoPickerChange(_ newValue: [PhotosPickerItem]) {
        Task { await loadSelectedPhotos(from: newValue) }
    }

    private func handleAvatarPickerChange(_ newValue: PhotosPickerItem?) {
        Task { await loadAvatarPhoto(from: newValue) }
    }

    // MARK: - Header Buttons

    private var headerButtons: some View {
        HStack {
            Button(action: onClose) {
                headerCircleButton(icon: "arrow.left")
            }
            .buttonStyle(.plain)

            Button { showEditSheet = true } label: {
                headerCircleButton(icon: "pencil")
            }
            .buttonStyle(.plain)

            Spacer()

            NavigationLink {
                SettingsView(onLogout: onLogout)
            } label: {
                headerCircleButton(icon: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
    }

    // MARK: - Profile Hero

    private var profileHero: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.61, green: 0.28, blue: 1.0),
                                    Color(red: 1.0, green: 0.38, blue: 0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 126, height: 126)
                        .blur(radius: 14)
                        .opacity(0.30)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.98),
                                    Color(red: 0.99, green: 0.93, blue: 0.98)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 122, height: 122)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.63, green: 0.31, blue: 1.0),
                                            Color(red: 1.0, green: 0.40, blue: 0.72),
                                            Color.white.opacity(0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 4
                                )
                        )

                    avatarView
                        .frame(width: 102, height: 102)
                        .clipShape(Circle())
                }
                .shadow(color: Color(red: 0.76, green: 0.42, blue: 1.0).opacity(0.28), radius: 24, x: 0, y: 8)

                Circle()
                    .fill(Color(red: 0.23, green: 0.84, blue: 0.45))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: -2, y: -4)

                PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.82, green: 0.41, blue: 1.0),
                                        Color(red: 1.0, green: 0.43, blue: 0.73)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                            .shadow(color: Color(red: 0.79, green: 0.42, blue: 1.0).opacity(0.28), radius: 10, x: 0, y: 6)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 4)
            }
            .padding(.top, 18)

            Text(displayName)
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.20, blue: 1.0),
                            Color(red: 0.95, green: 0.31, blue: 0.67)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                Text(displayCountry)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.44, green: 0.46, blue: 0.55))
            .padding(.top, -2)
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            statItem(icon: "person.2.fill", value: "\(appUserStore.currentUser?.followingCount ?? 0)", title: "Takip", color: Color(red: 0.45, green: 0.60, blue: 1.0))
            statItem(icon: "person.3.fill", value: "\(appUserStore.currentUser?.followersCount ?? 0)", title: "Takipci", color: Color(red: 0.79, green: 0.44, blue: 0.98))
            statItem(icon: "heart.fill", value: "\(appUserStore.currentUser?.likes ?? 0)", title: "Begeni", color: Color(red: 1.0, green: 0.43, blue: 0.58))
            statItem(icon: "diamond.fill", value: "\(appUserStore.currentUser?.gems ?? 0)", title: "Gem", color: Color(red: 1.0, green: 0.72, blue: 0.20))
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .modifier(ProfileGlassCard(cornerRadius: 28))
    }

    private func statItem(icon: String, value: String, title: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.40, green: 0.43, blue: 0.52))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 10) {
            tabButton("Takip", index: 0)
            tabButton("Takipci", index: 1)
        }
        .padding(8)
        .modifier(ProfileGlassCard(cornerRadius: 22))
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = index }
        } label: {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(
                    selectedTab == index
                        ? AnyShapeStyle(accentGradient)
                        : AnyShapeStyle(Color(red: 0.48, green: 0.50, blue: 0.58))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(selectedTab == index ? Color.white.opacity(0.88) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ZStack {
            if profileVM.isLoading {
                ProgressView()
                    .tint(Color(red: 0.56, green: 0.28, blue: 1.0))
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity)
            } else if !appUserStore.isLoggedIn {
                notLoggedInPlaceholder
            } else if selectedTab == 0 {
                followList(users: profileVM.followingUsers, emptyLabel: "Henuz kimseyi takip etmiyorsun")
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
            } else {
                followList(users: profileVM.followerUsers, emptyLabel: "Henuz takipci yok")
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedTab)
        .animation(.easeInOut(duration: 0.2), value: profileVM.isLoading)
    }

    private var notLoggedInPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color(red: 0.63, green: 0.62, blue: 0.72))
            Text("Takip listesini gormek icin giris yap")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.55))
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    private func followList(users: [FollowingUser], emptyLabel: String) -> some View {
        VStack(spacing: 14) {
            if users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color(red: 0.63, green: 0.62, blue: 0.72))
                    Text(emptyLabel)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.45, green: 0.46, blue: 0.55))
                }
                .padding(.top, 60)
                .frame(maxWidth: .infinity)
            } else {
                ForEach(users) { user in
                    followUserRow(user: user)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func followUserRow(user: FollowingUser) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: user.avatar ?? "")) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Circle().fill(Color.white.opacity(0.8))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.76)))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(user.name ?? "Kullanici")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.20, green: 0.23, blue: 0.30))
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.43, green: 0.46, blue: 0.56))
                    if let flag = user.countryFlag {
                        Text(flag)
                            .font(.system(size: 11))
                    }
                    Text((user.country ?? "TR").uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.46, blue: 0.56))
                    Text("•")
                        .foregroundStyle(Color(red: 0.70, green: 0.71, blue: 0.78))
                    Text(user.status == .online ? "Cevrimici" : "Cevrimdisi")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(user.status == .online ? Color(red: 0.25, green: 0.76, blue: 0.45) : Color(red: 0.58, green: 0.60, blue: 0.67))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                Button {
                    selectedPreviewUser = user
                } label: {
                    Text("Profil")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.31, green: 0.34, blue: 0.43))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(minWidth: 88)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.94))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.76), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                if user.status == .online || outgoingRequestPhase(for: user) != nil {
                    Button {
                        handlePrimaryAction(for: user)
                    } label: {
                        HStack(spacing: 6) {
                            if outgoingRequestPhase(for: user) != nil {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(outgoingRequestPhase(for: user) != nil ? "Vazgec" : "Ara")
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .frame(minWidth: 88)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(outgoingRequestPhase(for: user) != nil ? Color.red.opacity(0.82) : Color.green.opacity(0.82))
                        )
                    }
                    .buttonStyle(.plain)
                } else if user.status == .busy {
                    Button {
                        appState.showTimedToast("Kullanici su an baska bir gorusmede.")
                    } label: {
                        Text("Mesgul")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .frame(minWidth: 88)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.red.opacity(0.68))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task {
                        if let uid = appUserStore.currentUser?.id {
                            await profileVM.toggleFollow(targetId: user.id, currentUserId: uid)
                        }
                    }
                } label: {
                    Text(user.isFollowing ? "Takiptesin" : "Takip Et")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(user.isFollowing ? .white : Color(red: 0.49, green: 0.33, blue: 0.96))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    user.isFollowing
                                        ? LinearGradient(
                                            colors: [
                                                Color(red: 0.57, green: 0.26, blue: 1.0),
                                                Color(red: 0.97, green: 0.33, blue: 0.67)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.95), Color.white.opacity(0.88)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(user.isFollowing ? 0.0 : 0.55), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .modifier(ProfileGlassCard(cornerRadius: 24))
    }

    private func outgoingRequestPhase(for user: FollowingUser) -> PrivateCallRequestPhase? {
        socketService.outgoingPrivateCallTargetId == user.id ? socketService.outgoingPrivateCallPhase : nil
    }

    private func handlePrimaryAction(for user: FollowingUser) {
        if outgoingRequestPhase(for: user) != nil {
            socketService.cancelPrivateCall(targetId: user.id)
            return
        }

        switch user.status {
        case .online:
            socketService.requestPrivateCall(targetUserId: user.id)
        case .busy:
            appState.showTimedToast("Kullanici su an baska bir gorusmede.")
        case .offline:
            selectedPreviewUser = user
        }
    }

    private func headerCircleButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(red: 0.36, green: 0.38, blue: 0.47))
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.68), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.72), lineWidth: 1))
            .shadow(color: Color(red: 0.56, green: 0.49, blue: 0.78).opacity(0.12), radius: 18, x: 0, y: 8)
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    photosEditSection
                    interestsEditSection
                    profileInfoEditSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.09).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showEditSheet = false
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .principal) {
                    Text("Profili Duzenle")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditSheet = false
                    } label: {
                        Text("Bitti")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 1.0))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $activeEditor) { editor in
                editorSheet(for: editor)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    private var photosEditSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editSectionHeader("Fotograf & Video", icon: "photo.on.rectangle.angled", iconColor: Color(red: 0.44, green: 0.28, blue: 1.0))

            let slotSize = (UIScreen.main.bounds.width - 40 - 24) / 3
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { index in
                    editPhotoSlot(at: index)
                        .frame(width: slotSize, height: slotSize * 1.3)
                        .clipped()
                }
                Spacer()
            }
        }
    }

    private func editPhotoSlot(at index: Int) -> some View {
        let hasImage = index == 0
            ? (localAvatar != nil || profileAvatarURL != nil)
            : (localPhotos.indices.contains(index - 1) || profilePhotos.indices.contains(index - 1))

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))

            if index == 0 {
                if let localAvatar {
                    Image(uiImage: localAvatar)
                        .resizable()
                        .scaledToFill()
                } else if profileAvatarURL != nil {
                    photoContent(from: profileAvatarURL)
                }
            } else if localPhotos.indices.contains(index - 1) {
                Image(uiImage: localPhotos[index - 1])
                    .resizable()
                    .scaledToFill()
            } else if profilePhotos.indices.contains(index - 1) {
                photoContent(from: profilePhotos[index - 1])
            }

            if hasImage {
                VStack {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: photoPickerBinding(for: index), matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.55))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    Spacer()
                }
            } else {
                PhotosPicker(selection: photoPickerBinding(for: index), matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var profileInfoEditSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            editSectionHeader("Profil Bilgileri", icon: "pencil.and.list.clipboard", iconColor: Color(red: 0.44, green: 0.28, blue: 1.0))

            VStack(spacing: 0) {
                editFieldRow(
                    title: "Ad",
                    value: displayName,
                    icon: "person.fill",
                    iconBg: Color(red: 0.44, green: 0.28, blue: 1.0),
                    isFirst: true,
                    isLast: false
                ) { activeEditor = .name }

                editFieldRow(
                    title: "Bio",
                    value: displayBio,
                    icon: "pencil.line",
                    iconBg: Color(red: 0.22, green: 0.45, blue: 0.85),
                    isPlaceholder: displayBioIsPlaceholder,
                    isFirst: false,
                    isLast: true
                ) { activeEditor = .bio }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }

    private var interestsEditSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                editSectionHeader("İlgi alanlarım", icon: "guitars", iconColor: Color(red: 1.0, green: 0.35, blue: 0.55))
                Spacer()
                Text("+ 10%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.25, blue: 0.45))
            }

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    if selectedInterests.isEmpty {
                        HStack {
                            Text("İlgi alanları rozeti ekle")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.3))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    } else {
                        FlexibleSelectionLayout(
                            options: Array(selectedInterests).sorted(),
                            selected: selectedInterests
                        ) { _ in }
                        .padding(14)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

                NavigationLink(destination: interestPickerDestination) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.44, green: 0.28, blue: 1.0))
                            .frame(width: 30, height: 30)
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private var interestPickerDestination: some View {
        InterestPickerView(selectedInterests: $selectedInterests) { updatedInterests in
            await persistSelectedInterests(updatedInterests)
        }
    }

    private func editSectionHeader(_ title: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func editFieldRow(
        title: String,
        value: String,
        icon: String,
        iconBg: Color,
        isPlaceholder: Bool = false,
        isFirst: Bool,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(value)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isPlaceholder ? 0.3 : 0.9))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.leading, 70)
            }
        }
    }

    // MARK: - Editor Sheet (name/bio/interests)

    private func editorSheet(for editor: ProfileEditorSheet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)

            Text(editor.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(editor.helper)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))

            switch editor {
            case .name:
                editorInputCapsule(height: 60) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.46))
                        TextField("Ad", text: $draftName)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                }
                counterLabel("\(draftName.count)/40")

            case .bio:
                editorInputCapsule(height: 156, alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: $draftBio)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                        Text("\(draftBio.count)/250")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                    }
                }

            case .location:
                editorInputCapsule(height: 60) {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.46))
                        Text(displayCountry)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 18)
                }
            }

            Spacer(minLength: 0)

            Button {
                applyEditorChanges(editor)
            } label: {
                Text("Uygula")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(canApply(editor) ? 1 : 0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(canApply(editor) ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canApply(editor))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.12, blue: 0.13), Color(red: 0.08, green: 0.08, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func editorInputCapsule<Content: View>(
        height: CGFloat,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            content()
        }
    }

    private func counterLabel(_ value: String) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Helpers

    private func photoContent(from url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.white.opacity(0.04)
                    }
                }
            } else {
                Color.white.opacity(0.04)
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let localAvatar {
                Image(uiImage: localAvatar)
                    .resizable()
                    .scaledToFill()
            } else if let profileAvatarURL {
                AsyncImage(url: profileAvatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(10)
                            )
                    }
                }
            } else {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(10)
                    )
            }
        }
    }

    private func applyEditorChanges(_ editor: ProfileEditorSheet) {
        activeEditor = nil
        let store = appUserStore
        switch editor {
        case .name:
            let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { await store.updateProfile(name: trimmed) }
        case .bio:
            let trimmed = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
            Task { await store.updateProfile(bio: trimmed) }
        case .location:
            break
        }
    }

    private func syncDrafts() {
        draftName = appUserStore.currentUser?.name ?? ""
        draftBio = appUserStore.currentUser?.bio ?? ""
        selectedInterests = Set(appUserStore.currentUser?.interests ?? [])
    }

    private func persistSelectedInterests(_ updatedInterests: [String]) async -> Bool {
        let success = await appUserStore.updateProfile(interests: updatedInterests)
        if !success {
            syncDrafts()
            AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Ilgi alanlari kaydedilemedi.")
        }
        return success
    }

    private func toggleInterest(_ interest: String) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else if selectedInterests.count < 10 {
            selectedInterests.insert(interest)
        }
    }

    private func canApply(_ editor: ProfileEditorSheet) -> Bool {
        switch editor {
        case .name:
            let t = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            let o = (appUserStore.currentUser?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t != o && draftName.count <= 40
        case .bio:
            let t = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
            let o = (appUserStore.currentUser?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t != o && draftBio.count <= 250
        case .location:
            return false
        }
    }

    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        var base64Photos: [String] = []
        for item in items.prefix(3) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            loaded.append(image)
            let compressed = image.jpegData(compressionQuality: 0.6) ?? data
            base64Photos.append("data:image/jpeg;base64,\(compressed.base64EncodedString())")
        }
        await MainActor.run { localPhotos = loaded }
        appUserStore.savePhotosToCache(loaded)
        if !base64Photos.isEmpty {
            await appUserStore.updateProfile(photos: base64Photos)
        }
    }

    private func loadAvatarPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let compressed = image.jpegData(compressionQuality: 0.6) ?? data
        appUserStore.saveAvatarToCache(compressed)
        await MainActor.run { localAvatar = UIImage(data: compressed) ?? image }
        let base64 = compressed.base64EncodedString()
        await appUserStore.updateProfile(avatarBase64: base64)
    }

    private func photoPickerBinding(for index: Int) -> Binding<[PhotosPickerItem]> {
        if index == 0 {
            return Binding(
                get: { avatarPickerItem.map { [$0] } ?? [] },
                set: { newValue in avatarPickerItem = newValue.first }
            )
        }
        return Binding(
            get: { photoPickerItems },
            set: { newValue in photoPickerItems = Array(newValue.prefix(1)) }
        )
    }

    private var displayName: String {
        let raw = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Kullanici" : raw
    }

    private var displayCountry: String {
        let raw = appUserStore.currentUser?.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "TR" : raw.uppercased()
    }

    private var displayBio: String {
        draftBio.isEmpty ? "Kendiniz hakkinda biraz bir sey paylasin." : draftBio
    }

    private var displayBioIsPlaceholder: Bool { draftBio.isEmpty }

    private var interestsSummary: String {
        let values = Array(selectedInterests).sorted()
        return values.isEmpty ? "Ilgi alanlarini sec" : values.joined(separator: ", ")
    }

    private var profileAvatarURL: URL? {
        guard let raw = appUserStore.currentUser?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("data:"),
              !raw.hasPrefix("local://") else { return nil }
        return URL(string: raw)
    }

    private var profilePhotos: [URL] {
        (appUserStore.currentUser?.photos ?? []).compactMap { raw in
            guard !raw.isEmpty, !raw.hasPrefix("data:") else { return nil }
            return URL(string: raw)
        }
    }
}

// MARK: - Supporting Types

private enum ProfileEditorSheet: String, Identifiable {
    case name, bio, location
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Ad"
        case .bio: return "Bio"
        case .location: return "Konum"
        }
    }

    var helper: String {
        switch self {
        case .name: return "Profilinizde gosterilecek adinizi duzenleyin."
        case .bio: return "Kendiniz hakkinda biraz bir sey paylasin."
        case .location: return "Bulundugunuz konumu burada goruntuleyebilirsiniz."
        }
    }
}

private struct ProfileGlassCard: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.42))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.62, green: 0.54, blue: 0.82).opacity(0.14), radius: 24, x: 0, y: 12)
            )
    }
}

private struct FollowingUserProfileSheet: View {
    let user: FollowingUser
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.96, blue: 0.99),
                        Color(red: 0.95, green: 0.94, blue: 0.98)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        avatar
                            .padding(.top, 24)

                        VStack(spacing: 8) {
                            Text(displayName)
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.55, green: 0.20, blue: 1.0),
                                            Color(red: 0.95, green: 0.31, blue: 0.67)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                Text(countryLine)
                                Text("•")
                                Text(statusLine)
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.43, green: 0.46, blue: 0.56))
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            profileInfoRow(icon: "person.crop.circle", title: "Durum", value: statusLine)
                            profileInfoRow(icon: "mappin.and.ellipse", title: "Bolge", value: countryLine)
                            profileInfoRow(icon: "heart.circle", title: "Baglanti", value: user.isFollowing ? "Takiptesin" : "Henuz takip etmiyorsun")
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.60))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.32, green: 0.35, blue: 0.44))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.72), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayName: String {
        let trimmed = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Kullanici" : trimmed
    }

    private var countryLine: String {
        let code = (user.country ?? "TR").uppercased()
        if let flag = user.countryFlag, !flag.isEmpty {
            return "\(flag) \(code)"
        }
        return "\(CountryDataProvider.flagEmoji(forRegionCode: code)) \(code)"
    }

    private var statusLine: String {
        switch user.status {
        case .online:
            return "Su an online"
        case .busy:
            return "Su an mesgul"
        case .offline:
            return "Su an offline"
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.30, blue: 1.0),
                            Color(red: 0.98, green: 0.42, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 132, height: 132)
                .blur(radius: 14)
                .opacity(0.24)

            AsyncImage(url: URL(string: user.avatar ?? "")) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Color(red: 0.68, green: 0.67, blue: 0.76))
                        )
                }
            }
            .frame(width: 112, height: 112)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.20, blue: 1.0),
                                Color(red: 0.95, green: 0.31, blue: 0.67)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
            )
        }
    }

    private func profileInfoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.56, green: 0.28, blue: 1.0))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.60))
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.22, green: 0.24, blue: 0.32))
            }

            Spacer()
        }
    }
}

private struct FlexibleSelectionLayout: View {
    let options: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        WrappingFlowLayout(items: options) { option in
            Button { onTap(option) } label: {
                Text(option)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selected.contains(option)
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.44, green: 0.28, blue: 1.0), Color(red: 0.22, green: 0.60, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.white.opacity(0.06)),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WrappingFlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            generateContent(in: geometry)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + 8
                        }
                        let result = width
                        if item == items.last { width = 0 } else { width -= dimension.width + 8 }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last { height = 0 }
                        return result
                    }
            }
        }
    }
}
