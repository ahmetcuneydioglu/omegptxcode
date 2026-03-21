import PhotosUI
import SwiftUI

private let accentRed = Color(red: 0.93, green: 0.27, blue: 0.37)
private let cardBg = Color(.systemBackground)
private let pageBg = Color(.systemGroupedBackground)

struct EditProfileView: View {
    var appUserStore: AppUserStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var draftEmail: String = ""
    @State private var draftBio: String = ""
    @State private var draftGender: String = "Erkek"
    @State private var draftBirthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .now
    @State private var draftInterests: [String] = []

    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var photoPickerItems: [PhotosPickerItem?] = Array(repeating: nil, count: 3)
    @State private var localAvatar: UIImage? = nil
    @State private var extraPhotoPayloads: [String?] = Array(repeating: nil, count: 3)
    @State private var extraPhotoImages: [UIImage?] = Array(repeating: nil, count: 3)

    @State private var showInterestPicker = false
    @State private var showGenderPicker = false
    @State private var showDatePicker = false
    @State private var isSaving = false
    @State private var interestDraftBeforePicker: [String] = []

    private let genders = ["Erkek", "Kadın", "Belirtmek istemiyorum"]
    private let maxAdditionalPhotos = 3
    private let maxEncodedImageLength = 1_900_000
    private var completionPercent: Int {
        var score = 0
        if !draftName.isEmpty { score += 20 }
        if localAvatar != nil || (appUserStore.currentUser?.avatar != nil) { score += 20 }
        if !draftBio.isEmpty { score += 20 }
        if !draftInterests.isEmpty { score += 20 }
        if !draftGender.isEmpty { score += 20 }
        return score
    }

    private var profileAvatarURL: URL? {
        guard let raw = appUserStore.currentUser?.avatar,
              !raw.hasPrefix("data:"), !raw.hasPrefix("local://") else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    pageTitle
                    completionCard.padding(.top, 20)
                    photoSection.padding(.top, 28)
                    interestsSection.padding(.top, 28)
                    bioSection.padding(.top, 28)
                    generalSection.padding(.top, 28)
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(pageBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: avatarPickerItem) { _, item in
                Task { await loadAvatar(item) }
            }
            .sheet(isPresented: $showInterestPicker) {
                InterestPickerView(selectedInterests: Binding(
                    get: { Set(draftInterests) },
                    set: { draftInterests = Array($0).sorted() }
                ))
                .onAppear {
                    interestDraftBeforePicker = draftInterests
                }
                .onDisappear {
                    Task {
                        await saveInterestsIfNeededAfterPicker()
                    }
                }
                .presentationBackground(.clear)
            }
            .confirmationDialog("Cinsiyet Seçin", isPresented: $showGenderPicker, titleVisibility: .visible) {
                ForEach(genders, id: \.self) { g in
                    Button(g) { draftGender = g }
                }
            }
            .sheet(isPresented: $showDatePicker) { datePicker }
        }
        .colorScheme(.light)
        .onAppear { syncFromStore() }
        .onChange(of: appUserStore.currentUser?.interests) { _, _ in
            syncFromStore()
        }
        .onChange(of: appUserStore.currentUser?.photos) { _, _ in
            syncFromStore()
        }
        .onChange(of: appUserStore.currentUser?.avatar) { _, _ in
            syncFromStore()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(.label))
            }
        }
        ToolbarItem(placement: .principal) {
            Text("Hesabı düzenle")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(.label))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await saveAll() }
            } label: {
                if isSaving {
                    ProgressView().tint(.gray)
                } else {
                    Text("Kaydet")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
            .disabled(isSaving)
        }
    }

    // MARK: - Page Title

    private var pageTitle: some View {
        Text("Hesabı düzenle")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(Color(.label))
            .padding(.top, 8)
    }

    // MARK: - Completion Card

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Profili tamamla")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(.label))
                Spacer()
                Text("\(completionPercent)% tamamlandı")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accentRed)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                        .frame(height: 6)
                    Capsule().fill(accentRed)
                        .frame(width: geo.size.width * CGFloat(completionPercent) / 100, height: 6)
                        .animation(.easeInOut(duration: 0.4), value: completionPercent)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Profil fotoğrafı", badge: "+20%")
            Text("Daha fazla ilgi çekmek için en iyi fotoğrafınızı ekleyin, ilk izlenim önemlidir!")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            photoGrid
                .padding(.top, 4)

            if extraPhotoPayloads.contains(where: { $0 != nil }) || extraPhotoImages.contains(where: { $0 != nil }) {
                Button {
                    Task { await clearAllExtraPhotos() }
                } label: {
                    Text("Ek fotoğrafları temizle")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(accentRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(accentRed.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private var photoGrid: some View {
        let slotW = (UIScreen.main.bounds.width - 40 - 24) / 3
        let slotH = slotW * 1.25
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(0..<(maxAdditionalPhotos + 1), id: \.self) { i in
                photoSlot(index: i)
                    .frame(width: slotW, height: slotH)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func photoSlot(index: Int) -> some View {
        if index == 0 {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                slotBase(index: index)
                    .overlay(alignment: .topTrailing) {
                        badgeIcon(name: hasAvatar ? "pencil" : "plus", filled: hasAvatar)
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
        } else {
            let photoIndex = index - 1
            let binding = Binding<[PhotosPickerItem]>(
                get: { photoPickerItems[photoIndex].map { [$0] } ?? [] },
                set: { photoPickerItems[photoIndex] = $0.first }
            )

            if hasExtraPhoto(at: photoIndex) {
                slotBase(index: index)
            } else {
                PhotosPicker(selection: binding, matching: .images) {
                    slotBase(index: index)
                        .overlay(alignment: .topTrailing) {
                            badgeIcon(name: "plus", filled: false)
                                .padding(6)
                        }
                }
                .buttonStyle(.plain)
                .onChange(of: photoPickerItems[photoIndex]) { _, item in
                    Task { await loadPhoto(item, index: photoIndex) }
                }
            }
        }
    }

    @ViewBuilder
    private func slotBase(index: Int) -> some View {
        ZStack {
            if index == 0, let avatar = resolvedAvatarImage {
                Image(uiImage: avatar).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color(.systemFill))
            } else if index == 0, let url = profileAvatarURL {
                AsyncImage(url: url) { p in
                    switch p {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    default:
                        Color(.systemFill)
                    }
                }
            } else if index > 0, let img = resolvedExtraPhotoImage(at: index - 1) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color(.systemFill))
            } else if index > 0, let url = resolvedExtraPhotoURL(at: index - 1) {
                AsyncImage(url: url) { p in
                    switch p {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    default:
                        Color(.systemFill)
                    }
                }
            } else {
                Color(.systemFill)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBg)
        .contentShape(Rectangle())
    }

    private func badgeIcon(name: String, filled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(filled ? .white : Color(.tertiaryLabel))
            .padding(6)
            .background(Circle().fill(filled ? Color.black.opacity(0.45) : Color.clear))
    }

    // MARK: - Interests Section

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("İlgi alanlarım", badge: "+10%")
            Text("Sevdiğiniz şeyler hakkında daha spesifik olun")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            HStack(alignment: .top, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(cardBg)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)

                    if draftInterests.isEmpty {
                        Text("İlgi alanları rozeti ekle")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .padding(14)
                    } else {
                        interestChipsFlow
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)

                Button { showInterestPicker = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(accentRed, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var interestChipsFlow: some View {
        WrapLayout(hSpacing: 8, vSpacing: 8) {
            ForEach(draftInterests, id: \.self) { interest in
                Text(interest)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: chipGradient(for: interest),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
            }
        }
    }

    private func chipGradient(for item: String) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.93, green: 0.27, blue: 0.37), Color(red: 1.0, green: 0.55, blue: 0.35)],
            [Color(red: 0.44, green: 0.28, blue: 1.0), Color(red: 0.22, green: 0.60, blue: 1.0)],
            [Color(red: 0.22, green: 0.80, blue: 0.60), Color(red: 0.10, green: 0.60, blue: 0.90)],
            [Color(red: 1.0, green: 0.55, blue: 0.10), Color(red: 0.93, green: 0.27, blue: 0.37)],
            [Color(red: 0.55, green: 0.10, blue: 0.80), Color(red: 0.93, green: 0.27, blue: 0.80)],
        ]
        let idx = abs(item.hashValue) % palettes.count
        return palettes[idx]
    }

    // MARK: - Bio Section

    private var bioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Biyografi", badge: "+10%")
            Text("Daha fazla takipçi kazanmak için kendinizi tanıtın")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBg)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                    .frame(minHeight: 110)

                TextEditor(text: $draftBio)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(.label))
                    .frame(minHeight: 110)
                    .padding(10)

                if draftBio.isEmpty {
                    Text("Kendinizi tanıtıcı bir şeyler yazın")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - General Section

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(.secondaryLabel))
                Text("Genel")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(.label))
            }

            VStack(spacing: 0) {
                inputRow(icon: "person", placeholder: "Adınızı girin", value: $draftName)
                Divider().padding(.leading, 50)
                inputRow(icon: "envelope", placeholder: "Gerçek e-posta adresinizi girin", value: Binding(
                    get: { draftEmail },
                    set: { draftEmail = $0 }
                ), keyboardType: .emailAddress, isEditable: false)
                Divider().padding(.leading, 50)
                dropdownRow(
                    icon: "person.2",
                    title: "Cinsiyet",
                    value: draftGender
                ) { showGenderPicker = true }
                Divider().padding(.leading, 50)
                dropdownRow(
                    icon: "calendar",
                    title: "Yaş",
                    value: birthDateDisplay
                ) { showDatePicker = true }
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private func inputRow(
        icon: String,
        placeholder: String,
        value: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        isEditable: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 22)
            TextField(placeholder, text: value)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(isEditable ? Color(.label) : Color(.secondaryLabel))
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .disabled(!isEditable)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func dropdownRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(.secondaryLabel))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(.secondaryLabel))
                    Text(value)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.label))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Picker Sheet

    private var datePicker: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color(.quaternaryLabel))
                .frame(width: 42, height: 5)
                .padding(.top, 8)
            Text("Doğum Tarihi")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            DatePicker(
                "",
                selection: $draftBirthDate,
                in: ...Calendar.current.date(byAdding: .year, value: -13, to: .now)!,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            Button {
                showDatePicker = false
            } label: {
                Text("Tamam")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Helpers

    private var birthDateDisplay: String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy"
        return f.string(from: draftBirthDate)
    }

    private func sectionHeader(_ title: String, badge: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))
            Spacer()
            Text(badge)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(accentRed)
        }
    }

    private func syncFromStore() {
        guard let user = appUserStore.currentUser else { return }
        draftName = user.name
        draftEmail = user.email ?? ""
        draftBio = user.bio ?? ""
        draftGender = user.gender ?? "Erkek"
        draftInterests = user.interests
        if user.avatar == nil {
            localAvatar = nil
            appUserStore.clearAvatarCache()
        } else {
            localAvatar = appUserStore.cachedAvatarImage()
        }
        let userPhotos = Array(user.photos.prefix(maxAdditionalPhotos))
        let cachedPhotos = Array(appUserStore.cachedPhotos().prefix(maxAdditionalPhotos))
        extraPhotoPayloads = userPhotos.map(Optional.some)
            + Array(repeating: nil, count: max(0, maxAdditionalPhotos - userPhotos.count))
        extraPhotoImages = Array(repeating: nil, count: maxAdditionalPhotos)
        for index in 0..<maxAdditionalPhotos {
            if let payload = extraPhotoPayloads[index] {
                extraPhotoImages[index] = image(from: payload)
            }
            if extraPhotoImages[index] == nil, cachedPhotos.indices.contains(index) {
                extraPhotoImages[index] = cachedPhotos[index]
                if extraPhotoPayloads[index] == nil {
                    extraPhotoPayloads[index] = "local://photo_cache/\(index)"
                }
            }
        }
        photoPickerItems = Array(repeating: nil, count: maxAdditionalPhotos)

        if let bd = user.birthDate {
            let f = DateFormatter()
            f.dateFormat = "dd.MM.yyyy"
            if let d = f.date(from: bd) { draftBirthDate = d }
        } else if let age = user.age, age > 0 {
            draftBirthDate = Calendar.current.date(byAdding: .year, value: -age, to: .now) ?? draftBirthDate
        }
    }

    private func saveAll() async {
        isSaving = true
        defer { isSaving = false }
        let dateStr = birthDateDisplay
        let success = await appUserStore.updateProfile(
            name: draftName.isEmpty ? nil : draftName,
            bio: draftBio.isEmpty ? nil : draftBio,
            interests: draftInterests,
            gender: draftGender,
            birthDate: dateStr
        )
        if !success {
            syncFromStore()
            AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Profil guncellenemedi.")
        }
    }

    private func saveInterestsIfNeededAfterPicker() async {
        let oldValue = interestDraftBeforePicker.sorted()
        let newValue = draftInterests.sorted()
        guard oldValue != newValue else { return }

        let success = await appUserStore.updateProfile(interests: newValue)
        if !success {
            await MainActor.run {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Ilgi alanlari kaydedilemedi.")
            }
        }
    }

    private func loadAvatar(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data),
              let prepared = prepareUploadImage(from: img) else {
            await MainActor.run {
                AppState.shared.showTimedToast("Fotograf islenemedi. Lutfen daha kucuk bir gorsel secin.")
            }
            return
        }
        appUserStore.saveAvatarToCache(prepared.data)
        await MainActor.run { localAvatar = prepared.previewImage }
        let b64 = prepared.base64
        await appUserStore.updateProfile(avatarBase64: b64)
    }

    private func loadPhoto(_ item: PhotosPickerItem?, index: Int) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data),
              let prepared = prepareUploadImage(from: img) else {
            await MainActor.run {
                AppState.shared.showTimedToast("Fotograf islenemedi. Lutfen daha kucuk bir gorsel secin.")
            }
            return
        }
        let payload = "data:image/jpeg;base64,\(prepared.base64)"
        await MainActor.run {
            extraPhotoPayloads[index] = payload
            extraPhotoImages[index] = prepared.previewImage
            photoPickerItems[index] = nil
        }
        await persistExtraPhotos()
    }

    private func clearAllExtraPhotos() async {
        await MainActor.run {
            extraPhotoPayloads = Array(repeating: nil, count: maxAdditionalPhotos)
            extraPhotoImages = Array(repeating: nil, count: maxAdditionalPhotos)
            photoPickerItems = Array(repeating: nil, count: maxAdditionalPhotos)
        }

        let success = await appUserStore.updateProfile(photos: [])
        await MainActor.run {
            if success {
                appUserStore.clearPhotosCache()
            } else {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Fotograflar silinemedi.")
            }
        }
    }

    private func persistExtraPhotos() async {
        let payloads = extraPhotoPayloads.enumerated().compactMap { index, payload -> String? in
            if let payload, !payload.hasPrefix("local://") {
                return payload
            }
            guard extraPhotoImages.indices.contains(index),
                  let image = extraPhotoImages[index],
                  let prepared = prepareUploadImage(from: image) else { return nil }
            return "data:image/jpeg;base64,\(prepared.base64)"
        }
        let success = await appUserStore.updateProfile(photos: payloads)
        await MainActor.run {
            if success {
                extraPhotoPayloads = payloads.map(Optional.some)
                    + Array(repeating: nil, count: max(0, maxAdditionalPhotos - payloads.count))
                appUserStore.savePhotosToCache(extraPhotoImages.compactMap { $0 })
            } else {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Fotograflar guncellenemedi.")
            }
        }
    }

    private var resolvedAvatarImage: UIImage? {
        localAvatar ?? appUserStore.cachedAvatarImage()
    }

    private var hasAvatar: Bool {
        resolvedAvatarImage != nil || profileAvatarURL != nil
    }

    private func resolvedExtraPhotoImage(at index: Int) -> UIImage? {
        guard extraPhotoImages.indices.contains(index) else { return nil }
        return extraPhotoImages[index]
    }

    private func resolvedExtraPhotoURL(at index: Int) -> URL? {
        guard extraPhotoPayloads.indices.contains(index),
              let payload = extraPhotoPayloads[index],
              !payload.hasPrefix("data:") else { return nil }
        return URL(string: payload)
    }

    private func hasExtraPhoto(at index: Int) -> Bool {
        guard extraPhotoPayloads.indices.contains(index) else { return false }
        if extraPhotoPayloads[index] != nil {
            return true
        }
        if extraPhotoImages.indices.contains(index), extraPhotoImages[index] != nil {
            return true
        }
        return resolvedExtraPhotoURL(at: index) != nil
    }

    private func image(from payload: String) -> UIImage? {
        if payload.hasPrefix("data:"),
           let base64 = payload.components(separatedBy: ",").last,
           let data = Data(base64Encoded: base64) {
            return UIImage(data: data)
        }
        return nil
    }

    private func prepareUploadImage(from image: UIImage) -> (data: Data, base64: String, previewImage: UIImage)? {
        let maxDimensions: [CGFloat] = [1600, 1400, 1200, 1000, 840, 720, 600]
        let qualities: [CGFloat] = [0.72, 0.6, 0.5, 0.4, 0.3, 0.22, 0.16]

        for maxDimension in maxDimensions {
            let scaledImage = resizedImageIfNeeded(image, maxDimension: maxDimension)
            for quality in qualities {
                guard let jpegData = scaledImage.jpegData(compressionQuality: quality) else { continue }
                let base64 = jpegData.base64EncodedString()
                if base64.count <= maxEncodedImageLength {
                    return (jpegData, base64, UIImage(data: jpegData) ?? scaledImage)
                }
            }
        }

        return nil
    }

    private func resizedImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension, longestSide > 0 else { return image }

        let scaleRatio = maxDimension / longestSide
        let newSize = CGSize(
            width: max(1, floor(image.size.width * scaleRatio)),
            height: max(1, floor(image.size.height * scaleRatio))
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// EditProfileView.swift
