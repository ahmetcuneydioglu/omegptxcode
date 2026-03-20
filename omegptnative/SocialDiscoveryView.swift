import PhotosUI
import SwiftUI
import UIKit

struct SocialDiscoveryView: View {
    var appUserStore: AppUserStore
    let onClose: () -> Void
    let onLogout: () -> Void

    @State private var isEditing = false
    @State private var showInterestPicker = false
    @State private var draftBio = ""
    @State private var selectedInterests: Set<String> = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var localPhotoData: [Data] = []

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
        GeometryReader { geometry in
            let contentWidth = min(geometry.size.width - 32, 460)

            VStack(spacing: 0) {
                header
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, 16)
                    .padding(.top, max(geometry.safeAreaInsets.top, 14))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        photosSection
                        identitySection
                        statsSection
                        bioSection
                        interestsSection
                        badgesSection
                        editButton
                        logoutButton
                    }
                    .frame(maxWidth: contentWidth)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 28))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(backgroundGradient.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .task {
            syncDraftState()
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task { await loadSelectedPhotos(from: newItems) }
        }
        .onChange(of: appUserStore.currentUser?.bio) { _, _ in
            if !isEditing {
                syncDraftState()
            }
        }
        .onChange(of: appUserStore.currentUser?.interests) { _, _ in
            if !isEditing {
                syncDraftState()
            }
        }
        .fullScreenCover(isPresented: $showInterestPicker) {
            InterestPickerView(selectedInterests: $selectedInterests)
                .preferredColorScheme(.dark)
                .onDisappear {
                    Task {
                        await appUserStore.updateProfile(interests: Array(selectedInterests).sorted())
                    }
                }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            Text("Profil")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Button(action: {}) {
                Label("Onizleme", systemImage: "eye.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Fotograf & Video")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        photoCard(at: index)
                    }
                }
            }

            Text("Profilinizde uygunsuz icerik veya kisisel bilgi paylasmayin. Tum yuklemeler incelenir ve denetlenir.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func photoCard(at index: Int) -> some View {
        let slot = index < profilePhotos.count ? profilePhotos[index] : nil

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .background(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )

            if let slot {
                photoContent(for: slot)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text("Foto ekle")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            if isEditing, slot != nil {
                Button(action: {}) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 104, height: 132)
        .overlay(alignment: .bottomTrailing) {
            if isEditing, index == 0 {
                Text("Ana Ekran")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(8)
            }
        }
    }

    private func photoContent(for slot: ProfilePhotoSlot) -> some View {
        Group {
            switch slot {
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        photoPlaceholder
                    }
                }
            case .local(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(profileNameLine)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(profileCountryLine)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer(minLength: 0)

                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.white.opacity(0.82))
                                        .padding(12)
                                )
                        }
                    }
                    .frame(width: 62, height: 62)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            statBlock(title: "Takip", value: "\(appUserStore.currentUser?.followingCount ?? 0)", icon: nil)
            statDivider
            statBlock(title: "Takipci", value: "\(appUserStore.currentUser?.followersCount ?? 0)", icon: nil)
            statDivider
            statBlock(title: "Begeni", value: "\(appUserStore.currentUser?.likes ?? 0)", icon: "heart.fill")
            statDivider
            statBlock(title: "Gem", value: "\(appUserStore.currentUser?.gems ?? 0)", icon: "diamond.fill")
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(glassCard(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        )
    }

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Bio")
                Spacer(minLength: 0)
                Text("+10%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.green.opacity(0.9))
            }

            Group {
                if isEditing {
                    TextField("Kendiniz hakkinda biraz bir sey paylasin.", text: $draftBio, axis: .vertical)
                        .lineLimit(4...6)
                        .textInputAutocapitalization(.sentences)
                        .foregroundStyle(.white)
                } else {
                    Text(displayBio)
                        .foregroundStyle(.white.opacity(displayBioIsPlaceholder ? 0.5 : 0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(glassCard(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("Ilgi Alanlari")
                Spacer(minLength: 0)
                Text("Seçili \(selectedInterests.count) / 5")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Button {
                showInterestPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("5'e kadar seçim yaparak ortak ilgi alanları olan arkadaşlarla tanışın. Profilinizde görüneceklerdir.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)

                    if selectedInterests.isEmpty {
                        Text("İlgi alanları seç")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                            )
                    } else {
                        FlowLayout(Array(selectedInterests).sorted(), spacing: 8, lineSpacing: 10) { interest in
                            Text(interest)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.96))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(glassCard(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Rozetler")

            if displayBadges.isEmpty {
                Text("Henuz rozet yok.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(displayBadges, id: \.self) { badge in
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.yellow.opacity(0.95), Color.orange.opacity(0.95)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                Text(badge)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .background(glassCard(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditing.toggle()
            }
        } label: {
            Text(isEditing ? "Duzenlemeyi Bitir" : "Profili Duzenle")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.32, green: 0.55, blue: 1.0),
                            Color(red: 0.48, green: 0.34, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.blue.opacity(0.22), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var logoutButton: some View {
        Button(action: onLogout) {
            Text("Cikis Yap")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.red.opacity(0.92))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red.opacity(0.04))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.red.opacity(0.42), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func statBlock(title: String, value: String, icon: String?) -> some View {
        VStack(spacing: 8) {
            if let icon {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(title == "Gem" ? Color.cyan.opacity(0.92) : Color.pink.opacity(0.9))
                    Text(value)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else {
                Text(value)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 42)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func glassCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .background(.ultraThinMaterial)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.05),
                Color(red: 0.02, green: 0.02, blue: 0.03),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var profileNameLine: String {
        let name = appUserStore.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name?.isEmpty == false ? name! : "Kullanici")
        if let age = appUserStore.currentUser?.age {
            return "\(resolvedName), \(age)"
        }
        return resolvedName
    }

    private var profileCountryLine: String {
        appUserStore.currentUser?.country?.isEmpty == false ? appUserStore.currentUser!.country! : "Turkiye"
    }

    private var displayBio: String {
        draftBio.isEmpty ? "Kendiniz hakkinda biraz bir sey paylasin." : draftBio
    }

    private var displayBioIsPlaceholder: Bool {
        draftBio.isEmpty
    }

    private var displayBadges: [String] {
        let badges = appUserStore.currentUser?.badges ?? []
        return badges.isEmpty ? ["Yeni Uye"] : badges
    }

    private var avatarURL: URL? {
        guard let raw = appUserStore.currentUser?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("data:image") else {
            return nil
        }
        return URL(string: raw)
    }

    private var profilePhotos: [ProfilePhotoSlot] {
        var slots: [ProfilePhotoSlot] = localPhotoData.compactMap { data in
            guard let image = UIImage(data: data) else { return nil }
            return .local(image)
        }

        let remote = (appUserStore.currentUser?.photos ?? []).compactMap { raw -> ProfilePhotoSlot? in
            guard let url = URL(string: raw), !raw.isEmpty else { return nil }
            return .remote(url)
        }

        slots.append(contentsOf: remote)
        return Array(slots.prefix(3))
    }

    private func syncDraftState() {
        draftBio = appUserStore.currentUser?.bio ?? ""
        selectedInterests = Set(appUserStore.currentUser?.interests ?? [])
    }

    private func loadSelectedPhotos(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var loaded: [Data] = []

        for item in items.prefix(3) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }

        await MainActor.run {
            localPhotoData = loaded
        }
    }
}

private enum ProfilePhotoSlot: Equatable {
    case remote(URL)
    case local(UIImage)
}

private struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    private let data: Data
    private let spacing: CGFloat
    private let lineSpacing: CGFloat
    private let content: (Data.Element) -> Content

    init(
        _ data: Data,
        spacing: CGFloat = 8,
        lineSpacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }

    var body: some View {
        _FlowLayout(data: Array(data), spacing: spacing, lineSpacing: lineSpacing, content: content)
    }
}

private struct _FlowLayout<Item: Hashable, Content: View>: View {
    let data: [Item]
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let content: (Item) -> Content

    var body: some View {
        GeometryReader { geometry in
            self.generateContent(in: geometry)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(data, id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, lineSpacing)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > geometry.size.width {
                            width = 0
                            height -= dimension.height + lineSpacing
                        }
                        let result = width
                        if item == data.last {
                            width = 0
                        } else {
                            width -= dimension.width + spacing
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == data.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
