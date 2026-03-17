import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    var appUserStore: AppUserStore
    let onClose: () -> Void
    let onLogout: () -> Void

    @State private var activeEditor: ProfileEditorSheet?
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
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    VStack(spacing: 20) {
                        statsBar
                        photosSection
                        editFieldsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.09).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { syncDrafts() }
        .onChange(of: appUserStore.currentUser?.name) { _, _ in syncDrafts() }
        .onChange(of: photoPickerItems) { _, newValue in
            Task { await loadSelectedPhotos(from: newValue) }
        }
        .onChange(of: avatarPickerItem) { _, newValue in
            Task { await loadAvatarPhoto(from: newValue) }
        }
        .sheet(item: $activeEditor) { editor in
            editorSheet(for: editor)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var heroSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.10, blue: 0.38),
                        Color(red: 0.08, green: 0.14, blue: 0.32),
                        Color(red: 0.06, green: 0.06, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geo.size.width, height: 340)

                Circle()
                    .fill(Color(red: 0.44, green: 0.28, blue: 1.0).opacity(0.25))
                    .frame(width: 200, height: 200)
                    .blur(radius: 55)
                    .offset(x: -geo.size.width * 0.25, y: -60)

                Circle()
                    .fill(Color(red: 0.22, green: 0.60, blue: 1.0).opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 45)
                    .offset(x: geo.size.width * 0.25, y: -20)

                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accentGradient.opacity(0.35))
                            .frame(width: 100, height: 100)
                            .blur(radius: 18)

                        avatarView
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(accentGradient, lineWidth: 2.5))
                            .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 5).scaleEffect(1.12))

                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.44, green: 0.28, blue: 1.0))
                                    .frame(width: 26, height: 26)
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .offset(x: 28, y: 28)
                    }

                    Text(displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 4) {
                        Image(systemName: "mappin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 1.0))
                        Text(displayCountry)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.bottom, 24)

                NavigationLink {
                    SettingsView(onLogout: onLogout)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 60)
                .padding(.trailing, 20)
            }
            .frame(width: geo.size.width, height: 340)
            .clipped()
        }
        .frame(height: 340)
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            statItem(
                title: "Takip",
                value: "\(appUserStore.currentUser?.followingCount ?? 0)",
                icon: "person.badge.plus",
                color: Color(red: 0.44, green: 0.28, blue: 1.0)
            )
            statDivider
            statItem(
                title: "Takipci",
                value: "\(appUserStore.currentUser?.followersCount ?? 0)",
                icon: "person.2.fill",
                color: Color(red: 0.22, green: 0.60, blue: 1.0)
            )
            statDivider
            statItem(
                title: "Begeni",
                value: "\(appUserStore.currentUser?.likes ?? 0)",
                icon: "heart.fill",
                color: Color(red: 1.0, green: 0.35, blue: 0.55)
            )
            statDivider
            statItem(
                title: "Gem",
                value: "\(appUserStore.currentUser?.gems ?? 0)",
                icon: "diamond.fill",
                color: Color(red: 0.98, green: 0.78, blue: 0.25)
            )
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 36)
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Fotograf & Video", icon: "photo.on.rectangle.angled")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { index in
                        photoSlot(at: index)
                            .frame(width: 110, height: 147)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func photoSlot(at index: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )

            if index == 0 {
                photoContent(from: profilePhotos.first ?? profileAvatarURL)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if localPhotos.indices.contains(index - 1) {
                Image(uiImage: localPhotos[index - 1])
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if profilePhotos.indices.contains(index) {
                photoContent(from: profilePhotos[index])
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                PhotosPicker(selection: photoPickerBinding(for: index - 1), matching: .images) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var editFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Profil Bilgileri", icon: "pencil.and.list.clipboard")

            VStack(spacing: 2) {
                profileFieldRow(
                    title: "Ad",
                    value: displayName,
                    icon: "person.fill",
                    iconColor: Color(red: 0.44, green: 0.28, blue: 1.0),
                    isFirst: true,
                    isLast: false
                ) { activeEditor = .name }

                profileFieldRow(
                    title: "Bio",
                    value: displayBio,
                    icon: "quote.bubble.fill",
                    iconColor: Color(red: 0.22, green: 0.60, blue: 1.0),
                    isPlaceholder: displayBioIsPlaceholder,
                    isFirst: false,
                    isLast: false
                ) { activeEditor = .bio }

                profileFieldRow(
                    title: "Ilgi Alanlari",
                    value: interestsSummary,
                    icon: "tag.fill",
                    iconColor: Color(red: 1.0, green: 0.55, blue: 0.20),
                    isPlaceholder: selectedInterests.isEmpty,
                    isFirst: false,
                    isLast: false
                ) { activeEditor = .interests }

                profileFieldRow(
                    title: "Konum",
                    value: displayCountry,
                    icon: "mappin.circle.fill",
                    iconColor: Color(red: 0.98, green: 0.78, blue: 0.25),
                    isFirst: false,
                    isLast: true
                ) { activeEditor = .location }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
    }

    private func profileFieldRow(
        title: String,
        value: String,
        icon: String,
        iconColor: Color,
        isPlaceholder: Bool = false,
        isFirst: Bool,
        isLast: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(value)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(isPlaceholder ? 0.38 : 0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, 64)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 1.0))
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

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

            sectionLabel(editor.title)

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
                            .background(Color.clear)
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
                            .background(Color.clear)

                        Text("\(draftBio.count)/250")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                    }
                }

            case .interests:
                editorInputCapsule(height: 176, alignment: .topLeading) {
                    ScrollView(showsIndicators: false) {
                        FlexibleSelectionLayout(options: availableInterests, selected: selectedInterests) { interest in
                            toggleInterest(interest)
                        }
                        .padding(16)
                    }
                }
                counterLabel("\(selectedInterests.count)/10")

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
                colors: [
                    Color(red: 0.12, green: 0.12, blue: 0.13),
                    Color(red: 0.08, green: 0.08, blue: 0.09)
                ],
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
    }

    private func photoContent(from url: URL?) -> some View {
        Group {
            if let url {
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
            } else {
                photoPlaceholder
            }
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))

            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.white.opacity(0.72))
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
        case .interests:
            Task { await store.updateProfile(interests: Array(selectedInterests)) }
        case .location:
            break
        }
    }

    private func syncDrafts() {
        draftName = appUserStore.currentUser?.name ?? ""
        draftBio = appUserStore.currentUser?.bio ?? ""
        selectedInterests = Set(appUserStore.currentUser?.interests ?? [])
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
            let trimmedDraft = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = (appUserStore.currentUser?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedDraft.isEmpty && trimmedDraft != original && draftName.count <= 40
        case .bio:
            let trimmedDraft = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = (appUserStore.currentUser?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedDraft.isEmpty && trimmedDraft != original && draftBio.count <= 250
        case .interests:
            let original = Set(appUserStore.currentUser?.interests ?? [])
            return selectedInterests != original
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

        if !base64Photos.isEmpty {
            await appUserStore.updateProfile(photos: base64Photos)
        }
    }

    private func loadAvatarPhoto(from item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run { localAvatar = image }

        let compressed = image.jpegData(compressionQuality: 0.6)
        let base64 = compressed?.base64EncodedString() ?? data.base64EncodedString()
        await appUserStore.updateProfile(avatarBase64: base64)
    }

    private func photoPickerBinding(for index: Int) -> Binding<[PhotosPickerItem]> {
        Binding(
            get: { photoPickerItems },
            set: { newValue in
                photoPickerItems = Array(newValue.prefix(max(index + 1, 1)))
            }
        )
    }

    private var displayName: String {
        let raw = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Kullanici" : raw
    }

    private var displayCountry: String {
        let raw = appUserStore.currentUser?.country?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Turkiye" : raw
    }

    private var displayBio: String {
        draftBio.isEmpty ? "Kendiniz hakkinda biraz bir sey paylasin." : draftBio
    }

    private var displayBioIsPlaceholder: Bool {
        draftBio.isEmpty
    }

    private var interestsSummary: String {
        let values = Array(selectedInterests).sorted()
        return values.isEmpty ? "Ilgi alanlarini sec" : values.joined(separator: ", ")
    }

    private var profileAvatarURL: URL? {
        guard let raw = appUserStore.currentUser?.avatar?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              !raw.hasPrefix("data:image") else {
            return nil
        }
        return URL(string: raw)
    }

    private var profilePhotos: [URL] {
        (appUserStore.currentUser?.photos ?? []).compactMap { raw in
            guard !raw.isEmpty else { return nil }
            return URL(string: raw)
        }
    }
}

private enum ProfileEditorSheet: String, Identifiable {
    case name
    case bio
    case interests
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Ad"
        case .bio: return "Bio"
        case .interests: return "Ilgi Alanlari"
        case .location: return "Konum"
        }
    }

    var helper: String {
        switch self {
        case .name: return "Profilinizde gosterilecek adinizi duzenleyin."
        case .bio: return "Kendiniz hakkinda biraz bir sey paylasin."
        case .interests: return "Profilinizde one cikarmak istediginiz alanlari secin."
        case .location: return "Bulundugunuz konumu burada goruntuleyebilirsiniz."
        }
    }
}

private struct FlexibleSelectionLayout: View {
    let options: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        WrappingFlowLayout(items: options) { option in
            Button {
                onTap(option)
            } label: {
                Text(option)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        selected.contains(option)
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.44, green: 0.28, blue: 1.0),
                                    Color(red: 0.22, green: 0.60, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
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
                        if item == items.last {
                            width = 0
                        } else {
                            width -= dimension.width + 8
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
    }
}
