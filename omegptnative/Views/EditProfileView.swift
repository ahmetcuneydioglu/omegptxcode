import PhotosUI
import SwiftUI

private let accentRed = Color(red: 0.93, green: 0.27, blue: 0.37)
private let cardBg = Color(.systemBackground)
private let pageBg = Color(.systemGroupedBackground)
private let turkeyPlaceSuggestions: [String] = [
    "Istanbul, Turkey",
    "Ankara, Turkey",
    "Izmir, Turkey",
    "Antalya, Turkey",
    "Bursa, Turkey",
    "Adana, Turkey",
    "Gaziantep, Turkey",
    "Konya, Turkey",
    "Mersin, Turkey",
    "Diyarbakir, Turkey",
    "Kayseri, Turkey",
    "Eskisehir, Turkey",
    "Samsun, Turkey",
    "Trabzon, Turkey",
    "Denizli, Turkey",
    "Sakarya, Turkey",
    "Kocaeli, Turkey",
    "Mugla, Turkey",
    "Hatay, Turkey",
    "Balikesir, Turkey",
    "Canakkale, Turkey",
    "Aydin, Turkey",
    "Manisa, Turkey",
    "Kahramanmaras, Turkey",
    "Sanliurfa, Turkey",
    "Malatya, Turkey",
    "Van, Turkey",
    "Rize, Turkey",
    "Ordu, Turkey",
    "Tekirdag, Turkey",
    "Edirne, Turkey",
    "Bodrum, Mugla, Turkey",
    "Fethiye, Mugla, Turkey",
    "Alanya, Antalya, Turkey",
    "Marmaris, Mugla, Turkey",
    "Cesme, Izmir, Turkey",
    "Kadikoy, Istanbul, Turkey",
    "Besiktas, Istanbul, Turkey",
    "Sisli, Istanbul, Turkey",
    "Uskudar, Istanbul, Turkey",
    "Beyoglu, Istanbul, Turkey",
    "Bakirkoy, Istanbul, Turkey",
    "Atasehir, Istanbul, Turkey",
    "Sariyer, Istanbul, Turkey",
    "Esenyurt, Istanbul, Turkey",
    "Cankaya, Ankara, Turkey",
    "Kecioren, Ankara, Turkey",
    "Yenimahalle, Ankara, Turkey",
    "Bornova, Izmir, Turkey",
    "Karsiyaka, Izmir, Turkey",
    "Konak, Izmir, Turkey",
    "Osmangazi, Bursa, Turkey",
    "Nilufer, Bursa, Turkey",
    "Seyhan, Adana, Turkey",
    "Cukurova, Adana, Turkey"
]
private let lookingForOptions: [String] = [
    "A long-term relationship",
    "Open to seeing where things go",
    "Marriage",
    "Something casual",
    "A life partner",
    "Ethical non-monogamy"
]

@MainActor
private func saveTextProfileField(
    _ value: String,
    currentValue: String,
    errorMessage: String,
    save: @escaping (String) async -> Bool
) async -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let currentTrimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        AppState.shared.showTimedToast("Bu alan bos birakilamaz.")
        return false
    }
    guard trimmed != currentTrimmed else { return true }

    let success = await save(trimmed)
    if !success {
        AppState.shared.showTimedToast(errorMessage)
    }
    return success
}

@MainActor
private func saveBirthDateProfileField(
    _ value: Date,
    currentBirthDateDisplay: String,
    errorMessage: String,
    save: @escaping (String) async -> Bool
) async -> Bool {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy"
    let formatted = formatter.string(from: value)
    guard formatted != currentBirthDateDisplay else { return true }

    let success = await save(formatted)
    if !success {
        AppState.shared.showTimedToast(errorMessage)
    }
    return success
}

@MainActor
private func saveHeightProfileField(
    _ value: Int,
    currentValue: Int?,
    errorMessage: String,
    save: @escaping (Int) async -> Bool
) async -> Bool {
    guard currentValue != value else { return true }

    let success = await save(value)
    if !success {
        AppState.shared.showTimedToast(errorMessage)
    }
    return success
}

struct EditProfileView: View {
    var appUserStore: AppUserStore
    @Environment(\.dismiss) private var dismiss
    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    @State private var draftName: String = ""
    @State private var draftEmail: String = ""
    @State private var draftBio: String = ""
    @State private var draftGender: String = ""
    @State private var draftBirthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .now
    @State private var hasBirthDateValue = false
    @State private var draftWork: String = ""
    @State private var draftEducation: String = ""
    @State private var draftLocation: String = ""
    @State private var draftHometown: String = ""
    @State private var draftHeight: Int?
    @State private var draftExercise: String = ""
    @State private var draftLookingFor: [String] = []
    @State private var draftInterests: [String] = []

    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var photoPickerItems: [PhotosPickerItem?] = Array(repeating: nil, count: 3)
    @State private var localAvatar: UIImage? = nil
    @State private var extraPhotoPayloads: [String?] = Array(repeating: nil, count: 3)
    @State private var extraPhotoImages: [UIImage?] = Array(repeating: nil, count: 3)

    @State private var showInterestPicker = false
    @State private var isSaving = false
    @State private var interestDraftBeforePicker: [String] = []

    private let genders = ["Erkek", "Kadın", "Belirtmek istemiyorum"]
    private let exerciseOptions = [
        "Aktif",
        "Bazen",
        "Neredeyse hic",
        "Her gun"
    ]
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

    private var profileDraftSyncKey: String {
        guard let user = appUserStore.currentUser else { return "" }
        let p1 = "\(user.name)|\(user.email ?? "")|\(user.bio ?? "")"
        let p2 = "|\(user.gender ?? "")|\(user.birthDate ?? "")|\(user.work ?? "")"
        let p3 = "|\(user.education ?? "")|\(user.location ?? "")|\(user.hometown ?? "")"
        let p4 = "|\(user.exercise ?? "")|\(user.height ?? -1)"
        let p5 = "|\(user.lookingFor.joined(separator: "~"))"
        return p1 + p2 + p3 + p4 + p5
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
        .onChange(of: profileDraftSyncKey) { _, _ in
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
        VStack(alignment: .leading, spacing: 26) {
            aboutYouBlock
            moreAboutYouBlock
        }
    }

    @ViewBuilder
    private var aboutYouBlock: some View {
        aboutSectionBlock(title: "About you", subtitle: "Temel profil bilgilerini daha net hale getirin.") {
            NavigationLink {
                EditProfileDirectTextDetailView(
                    fieldKey: "name",
                    title: "Name",
                    placeholder: "Adınızı girin",
                    initialValue: draftName
                )
            } label: {
                aboutRow(icon: "person.fill", title: "Name", value: displayOrAdd(draftName))
            }

            Divider().padding(.leading, 52)

            aboutStaticRow(icon: "envelope.fill", title: "Email", value: draftEmail.isEmpty ? "Linked account" : draftEmail)

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileGenderDetailView(
                    title: "Gender",
                    options: genders,
                    selectedValue: draftGender
                )
            } label: {
                aboutRow(icon: "figure.stand", title: "Gender", value: displayOrAdd(draftGender))
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileDateDetailView(
                    title: "Birth date",
                    initialDate: draftBirthDate,
                    minimumAge: 13
                ) { [bd = birthDateDisplay, s = appUserStore] value in
                    await saveBirthDateProfileField(value, currentBirthDateDisplay: bd,
                        errorMessage: s.authErrorMessage ?? "Dogum tarihi guncellenemedi.") { await s.updateProfile(birthDate: $0) }
                }
            } label: {
                aboutRow(icon: "calendar", title: "Age", value: ageDisplay)
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileDirectTextDetailView(
                    fieldKey: "work",
                    title: "Work",
                    placeholder: "Nerede calisiyorsun?",
                    initialValue: draftWork
                )
            } label: {
                aboutRow(icon: "briefcase", title: "Work", value: displayOrAdd(draftWork))
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileDirectTextDetailView(
                    fieldKey: "education",
                    title: "Education",
                    placeholder: "Okul veya bolum",
                    initialValue: draftEducation
                )
            } label: {
                aboutRow(icon: "graduationcap", title: "Education", value: displayOrAdd(draftEducation))
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfilePlacePickerDetailView(
                    fieldKey: "location",
                    title: "Location",
                    searchPlaceholder: "Find your location",
                    initialValue: draftLocation
                )
            } label: {
                aboutRow(icon: "mappin.and.ellipse", title: "Location", value: displayOrAdd(draftLocation))
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfilePlacePickerDetailView(
                    fieldKey: "hometown",
                    title: "Hometown",
                    searchPlaceholder: "Find your hometown",
                    initialValue: draftHometown
                )
            } label: {
                aboutRow(icon: "house", title: "Hometown", value: displayOrAdd(draftHometown))
            }
        }
    }

    @ViewBuilder
    private var moreAboutYouBlock: some View {
        aboutSectionBlock(title: "More about you", subtitle: "Insanlarin en cok merak ettigi bilgileri ekleyin.") {
            NavigationLink {
                EditProfileDirectHeightDetailView(initialHeight: draftHeight)
            } label: {
                aboutRow(icon: "ruler", title: "Height", value: heightDisplay)
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileExerciseDetailView(
                    title: "Exercise",
                    options: exerciseOptions,
                    selectedValue: draftExercise
                )
            } label: {
                aboutRow(icon: "dumbbell", title: "Exercise", value: displayOrAdd(draftExercise))
            }

            Divider().padding(.leading, 52)

            NavigationLink {
                EditProfileLookingForDetailView(
                    options: lookingForOptions,
                    selectedValues: draftLookingFor
                )
            } label: {
                aboutRow(icon: "magnifyingglass", title: "Looking for", value: lookingForDisplay)
            }
        }
    }

    // MARK: - Helpers

    private var birthDateDisplay: String {
        Self.birthDateFormatter.string(from: draftBirthDate)
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

    private func aboutSectionBlock<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.label))
            Text(subtitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            VStack(spacing: 0) {
                content()
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
        }
    }

    private func aboutRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(.label))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.label))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(value == "Add" ? Color(.tertiaryLabel) : Color(.secondaryLabel))
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .contentShape(Rectangle())
    }

    private func aboutStaticRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(.label))
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.label))

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private func displayOrAdd(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Add" : trimmed
    }

    private var ageDisplay: String {
        guard hasBirthDateValue else { return "Add" }
        let years = Calendar.current.dateComponents([.year], from: draftBirthDate, to: .now).year ?? 0
        return years > 0 ? "\(years)" : birthDateDisplay
    }

    private var heightDisplay: String {
        guard let draftHeight else { return "Add" }
        return "\(draftHeight) cm"
    }

    private var lookingForDisplay: String {
        guard !draftLookingFor.isEmpty else { return "Add" }
        return draftLookingFor.joined(separator: ", ")
    }

    @MainActor
    private func saveProfileTextField(
        _ value: String,
        currentValue: String,
        save: @escaping (String) async -> Bool
    ) async -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            AppState.shared.showTimedToast("Bu alan bos birakilamaz.")
            return false
        }
        guard trimmed != currentTrimmed else { return true }

        let success = await save(trimmed)
        if success {
            await MainActor.run {
                syncFromStore()
            }
        } else {
            await MainActor.run {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Profil guncellenemedi.")
            }
        }
        return success
    }

    @MainActor
    private func saveProfileChoiceField(
        _ value: String,
        currentValue: String,
        save: @escaping (String) async -> Bool
    ) async -> Bool {
        print("🧭 [EditProfile][choice] raw value='\(value)' current='\(currentValue)'")

        let normalizedValue = value
        let normalizedCurrentValue = currentValue

        guard !normalizedValue.isEmpty else {
            print("🧭 [EditProfile][choice] blocked: empty value")
            return false
        }
        guard normalizedValue != normalizedCurrentValue else {
            print("🧭 [EditProfile][choice] unchanged, skipping remote save")
            return true
        }

        print("🧭 [EditProfile][choice] sending update with value='\(normalizedValue)'")
        let success = await save(normalizedValue)
        if success {
            print("🧭 [EditProfile][choice] success")
            syncFromStore()
        } else {
            print("🧭 [EditProfile][choice] failed message='\(appUserStore.authErrorMessage ?? "nil")'")
            syncFromStore()
            AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Profil guncellenemedi.")
        }
        return success
    }

    @MainActor
    private func saveBirthDate(_ value: Date) async -> Bool {
        let formatted = Self.birthDateFormatter.string(from: value)
        guard formatted != birthDateDisplay else { return true }

        let success = await appUserStore.updateProfile(birthDate: formatted)
        if success {
            await MainActor.run {
                syncFromStore()
            }
        } else {
            await MainActor.run {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Dogum tarihi guncellenemedi.")
            }
        }
        return success
    }

    @MainActor
    private func saveHeight(_ value: Int) async -> Bool {
        guard draftHeight != value else { return true }

        let success = await appUserStore.updateProfile(height: value)
        if success {
            await MainActor.run {
                syncFromStore()
            }
        } else {
            await MainActor.run {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Boy bilgisi guncellenemedi.")
            }
        }
        return success
    }

    @MainActor
    private func syncFromStore() {
        guard let user = appUserStore.currentUser else { return }
        draftName = user.name
        draftEmail = user.email ?? ""
        draftBio = user.bio ?? ""
        draftGender = user.gender ?? ""
        draftWork = user.work ?? ""
        draftEducation = user.education ?? ""
        draftLocation = user.location ?? ""
        draftHometown = user.hometown ?? ""
        draftHeight = user.height
        draftExercise = user.exercise ?? ""
        draftLookingFor = user.lookingFor
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
            hasBirthDateValue = true
            if let d = Self.birthDateFormatter.date(from: bd) { draftBirthDate = d }
        } else if let age = user.age, age > 0 {
            hasBirthDateValue = true
            draftBirthDate = Calendar.current.date(byAdding: .year, value: -age, to: .now) ?? draftBirthDate
        } else {
            hasBirthDateValue = false
        }
    }

    @MainActor
    private func saveAll() async {
        let currentBio = (appUserStore.currentUser?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = draftBio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedBio != currentBio else { return }

        isSaving = true
        defer { isSaving = false }

        let success = await appUserStore.updateProfile(bio: trimmedBio)
        if success {
            await MainActor.run {
                syncFromStore()
            }
        } else {
            await MainActor.run {
                syncFromStore()
                AppState.shared.showTimedToast(appUserStore.authErrorMessage ?? "Profil guncellenemedi.")
            }
        }
    }

    @MainActor
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

private struct EditProfileTextDetailView: View {
    let title: String
    let placeholder: String
    let initialValue: String
    let buttonTitle: String
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(
        title: String,
        placeholder: String,
        initialValue: String,
        buttonTitle: String,
        onSave: @escaping (String) async -> Bool
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initialValue = initialValue
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            Text("Profilinde gorunecek bilgiyi duzenle.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBg)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(.label))
                    .frame(minHeight: 160)
                    .padding(12)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 160)

            Button {
                let valueToSave = text
                isSaving = true
                Task {
                    let success = await onSave(valueToSave)
                    await MainActor.run {
                        isSaving = false
                        if success {
                            dismiss()
                        }
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : buttonTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileDirectTextDetailView: View {
    let fieldKey: String
    let title: String
    let placeholder: String
    let initialValue: String

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(fieldKey: String, title: String, placeholder: String, initialValue: String) {
        self.fieldKey = fieldKey
        self.title = title
        self.placeholder = placeholder
        self.initialValue = initialValue
        _text = State(initialValue: initialValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            Text("Profilinde gorunecek bilgiyi duzenle.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color(.secondaryLabel))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBg)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(.label))
                    .frame(minHeight: 160)
                    .padding(12)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 160)

            Button {
                let valueToSave = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let initialTrimmed = initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🧭 [EditProfile][text] save tapped field='\(fieldKey)' value='\(valueToSave)' initial='\(initialTrimmed)'")

                if valueToSave.isEmpty {
                    AppState.shared.showTimedToast("Bu alan bos birakilamaz.")
                    return
                }

                if valueToSave == initialTrimmed {
                    dismiss()
                    return
                }

                isSaving = true
                Task { @MainActor in
                    print("🧭 [EditProfile][text] calling updateTextField field='\(fieldKey)'")
                    let success = await AuthManager.shared.updateTextField(fieldKey, value: valueToSave)
                    print("🧭 [EditProfile][text] updateTextField returned success=\(success) field='\(fieldKey)'")
                    isSaving = false
                    if success {
                        dismiss()
                    } else {
                        AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Profil guncellenemedi.")
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Uygula")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfilePlacePickerDetailView: View {
    let fieldKey: String
    let title: String
    let searchPlaceholder: String
    let initialValue: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var query: String = ""
    @State private var isSaving = false

    private var normalizedInitialValue: String {
        initialValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPlaces: [String] {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return Array(turkeyPlaceSuggestions.prefix(12)) }

        let lowercased = trimmed.lowercased()
        let prefixMatches = turkeyPlaceSuggestions.filter { $0.lowercased().hasPrefix(lowercased) }
        let containsMatches = turkeyPlaceSuggestions.filter {
            !$0.lowercased().hasPrefix(lowercased) && $0.lowercased().contains(lowercased)
        }
        return Array((prefixMatches + containsMatches).prefix(20))
    }

    private var canUseTypedValue: Bool {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return false }
        return !filteredPlaces.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(.secondaryLabel))

                    TextField(searchPlaceholder, text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(.label))
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button("Cancel") {
                    dismiss()
                }
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(Color(.label))
                .buttonStyle(.plain)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    if canUseTypedValue {
                        placeRow(title: "Use \"\(normalizedQuery)\"") {
                            await save(place: normalizedQuery)
                        }
                    }

                    ForEach(filteredPlaces, id: \.self) { place in
                        placeRow(title: place) {
                            await save(place: place)
                        }
                    }
                }
                .padding(.bottom, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(pageBg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            query = initialValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = true
            }
        }
    }

    @ViewBuilder
    private func placeRow(title: String, action: @escaping () async -> Void) -> some View {
        Button {
            guard !isSaving else { return }
            isSaving = true
            Task { @MainActor in
                await action()
                isSaving = false
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(.label))
                    .multilineTextAlignment(.leading)
                Spacer()
                if title == normalizedInitialValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accentRed)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    @MainActor
    private func save(place: String) async {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🧭 [EditProfile][place] save tapped field='\(fieldKey)' value='\(trimmed)' initial='\(normalizedInitialValue)'")

        guard !trimmed.isEmpty else {
            AppState.shared.showTimedToast("Lutfen bir yer secin.")
            return
        }

        if trimmed == normalizedInitialValue {
            dismiss()
            return
        }

        print("🧭 [EditProfile][place] calling updateTextField field='\(fieldKey)'")
        let success = await AuthManager.shared.updateTextField(fieldKey, value: trimmed)
        print("🧭 [EditProfile][place] updateTextField returned success=\(success) field='\(fieldKey)'")

        if success {
            dismiss()
        } else {
            AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Konum bilgisi guncellenemedi.")
        }
    }
}

private struct EditProfileOptionDetailView: View {
    let title: String
    let options: [String]
    let selectedValue: String
    let buttonTitle: String
    let onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var isSaving = false

    init(
        title: String,
        options: [String],
        selectedValue: String,
        buttonTitle: String,
        onSave: @escaping (String) async -> Bool
    ) {
        self.title = title
        self.options = options
        self.selectedValue = selectedValue
        self.buttonTitle = buttonTitle
        self.onSave = onSave
        _selection = State(initialValue: selectedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        print("🧭 [EditProfile][choice] tapped option='\(option)' previous='\(selection)'")
                        selection = option
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(.label))
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(accentRed)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)

                    if option != options.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

            Button {
                let valueToSave = selection
                isSaving = true
                print("🧭 [EditProfile][choice] save tapped selected='\(valueToSave)' initial='\(selectedValue)'")
                if valueToSave.isEmpty {
                    print("🧭 [EditProfile][choice] blocked because no option is selected")
                    AppState.shared.showTimedToast("Lutfen bir secim yap.")
                    isSaving = false
                    return
                }
                if valueToSave == selectedValue {
                    print("🧭 [EditProfile][choice] dismissing without save because value is unchanged")
                    isSaving = false
                    dismiss()
                    return
                }
                Task { @MainActor in
                    print("🧭 [EditProfile][choice] invoking onSave")
                    let success = await onSave(valueToSave)
                    print("🧭 [EditProfile][choice] onSave returned success=\(success)")
                    isSaving = false
                    if success {
                        dismiss()
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : buttonTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileGenderDetailView: View {
    let title: String
    let options: [String]
    let selectedValue: String

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var isSaving = false

    init(title: String, options: [String], selectedValue: String) {
        self.title = title
        self.options = options
        self.selectedValue = selectedValue
        _selection = State(initialValue: selectedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        print("🧭 [EditProfile][gender] tapped option='\(option)' previous='\(selection)'")
                        selection = option
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(.label))
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(accentRed)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)

                    if option != options.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

            Button {
                let valueToSave = selection
                print("🧭 [EditProfile][gender] save tapped selected='\(valueToSave)' initial='\(selectedValue)'")

                if valueToSave.isEmpty {
                    AppState.shared.showTimedToast("Lutfen bir secim yap.")
                    return
                }

                if valueToSave == selectedValue {
                    dismiss()
                    return
                }

                isSaving = true
                Task { @MainActor in
                    print("🧭 [EditProfile][gender] calling updateGender")
                    let success = await AuthManager.shared.updateGender(valueToSave)
                    print("🧭 [EditProfile][gender] updateGender returned success=\(success)")
                    isSaving = false
                    if success {
                        dismiss()
                    } else {
                        AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Profil guncellenemedi.")
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Seç")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileExerciseDetailView: View {
    let title: String
    let options: [String]
    let selectedValue: String

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var isSaving = false

    init(title: String, options: [String], selectedValue: String) {
        self.title = title
        self.options = options
        self.selectedValue = selectedValue
        _selection = State(initialValue: selectedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        print("🧭 [EditProfile][exercise] tapped option='\(option)' previous='\(selection)'")
                        selection = option
                    } label: {
                        HStack {
                            Text(option)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(.label))
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(accentRed)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)

                    if option != options.last {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)

            Button {
                let valueToSave = selection
                print("🧭 [EditProfile][exercise] save tapped selected='\(valueToSave)' initial='\(selectedValue)'")

                if valueToSave.isEmpty {
                    AppState.shared.showTimedToast("Lutfen bir secim yap.")
                    return
                }

                if valueToSave == selectedValue {
                    dismiss()
                    return
                }

                isSaving = true
                Task { @MainActor in
                    print("🧭 [EditProfile][exercise] calling updateExercise")
                    let success = await AuthManager.shared.updateExercise(valueToSave)
                    print("🧭 [EditProfile][exercise] updateExercise returned success=\(success)")
                    isSaving = false
                    if success {
                        dismiss()
                    } else {
                        AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Egzersiz bilgisi guncellenemedi.")
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Seç")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileLookingForDetailView: View {
    let options: [String]
    let selectedValues: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var selection: [String]
    @State private var isSaving = false

    init(options: [String], selectedValues: [String]) {
        self.options = options
        self.selectedValues = selectedValues
        _selection = State(initialValue: selectedValues)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(.label))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: 160, height: 5)

                Spacer()

                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 18)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50, weight: .regular))
                            .foregroundStyle(Color(.label))
                            .padding(.top, 28)

                        Text("What do you want from your dates?")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(.label))
                            .multilineTextAlignment(.center)

                        Text("You can choose 1 or 2 options.")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(.secondaryLabel))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 16) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                toggle(option)
                            } label: {
                                HStack(spacing: 14) {
                                    Spacer(minLength: 0)

                                    Text(option)
                                        .font(.system(size: 19, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(.label))
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)

                                    selectionIndicator(isSelected: selection.contains(option))
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(cardBg)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color(.systemGray5), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }

            Button {
                guard !selection.isEmpty else {
                    AppState.shared.showTimedToast("Lutfen en az bir secim yap.")
                    return
                }
                if selection == selectedValues {
                    dismiss()
                    return
                }

                isSaving = true
                Task { @MainActor in
                    print("🧭 [EditProfile][lookingFor] calling updateLookingFor values='\(selection)'")
                    let success = await AuthManager.shared.updateLookingFor(selection)
                    print("🧭 [EditProfile][lookingFor] updateLookingFor returned success=\(success)")
                    isSaving = false
                    if success {
                        dismiss()
                    } else {
                        AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Aradigin iliski tipi guncellenemedi.")
                    }
                }
            } label: {
                Text(isSaving ? "Saving..." : "Save and close")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(.label), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .background(pageBg)
        }
        .background(pageBg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ option: String) {
        if let index = selection.firstIndex(of: option) {
            selection.remove(at: index)
            return
        }

        guard selection.count < 2 else {
            AppState.shared.showTimedToast("En fazla 2 secim yapabilirsin.")
            return
        }

        selection.append(option)
    }

    @ViewBuilder
    private func selectionIndicator(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color(.label), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.systemGray3), lineWidth: 1.5)
                .frame(width: 42, height: 42)
        }
    }
}

private struct EditProfileDirectHeightDetailView: View {
    let initialHeight: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedHeight: Int
    @State private var isSaving = false

    init(initialHeight: Int?) {
        self.initialHeight = initialHeight
        _selectedHeight = State(initialValue: initialHeight ?? 170)
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("Height")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            Text("\(selectedHeight) cm")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(accentRed)

            Picker("Height", selection: $selectedHeight) {
                ForEach(120...220, id: \.self) { height in
                    Text("\(height) cm").tag(height)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Button {
                let valueToSave = selectedHeight
                print("🧭 [EditProfile][height] save tapped selected='\(valueToSave)' initial='\(initialHeight ?? -1)'")

                if valueToSave == initialHeight {
                    dismiss()
                    return
                }

                isSaving = true
                Task { @MainActor in
                    print("🧭 [EditProfile][height] calling updateHeight")
                    let success = await AuthManager.shared.updateHeight(valueToSave)
                    print("🧭 [EditProfile][height] updateHeight returned success=\(success)")
                    isSaving = false
                    if success {
                        dismiss()
                    } else {
                        AppState.shared.showTimedToast(AuthManager.shared.authErrorMessage ?? "Boy bilgisi guncellenemedi.")
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Uygula")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileHeightDetailView: View {
    let initialHeight: Int?
    let onSave: (Int) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedHeight: Int
    @State private var isSaving = false

    init(initialHeight: Int?, onSave: @escaping (Int) async -> Bool) {
        self.initialHeight = initialHeight
        self.onSave = onSave
        _selectedHeight = State(initialValue: initialHeight ?? 170)
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("Height")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            Text("\(selectedHeight) cm")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(accentRed)

            Picker("Height", selection: $selectedHeight) {
                ForEach(120...220, id: \.self) { height in
                    Text("\(height) cm").tag(height)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Button {
                let valueToSave = selectedHeight
                isSaving = true
                Task {
                    let success = await onSave(valueToSave)
                    await MainActor.run {
                        isSaving = false
                        if success {
                            dismiss()
                        }
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Uygula")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditProfileDateDetailView: View {
    let title: String
    let initialDate: Date
    let minimumAge: Int
    let onSave: (Date) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    @State private var isSaving = false

    init(
        title: String,
        initialDate: Date,
        minimumAge: Int,
        onSave: @escaping (Date) async -> Bool
    ) {
        self.title = title
        self.initialDate = initialDate
        self.minimumAge = minimumAge
        self.onSave = onSave
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(spacing: 22) {
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Color(.label))

            DatePicker(
                "",
                selection: $selectedDate,
                in: ...Calendar.current.date(byAdding: .year, value: -minimumAge, to: .now)!,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()

            Button {
                let valueToSave = selectedDate
                isSaving = true
                Task {
                    let success = await onSave(valueToSave)
                    await MainActor.run {
                        isSaving = false
                        if success {
                            dismiss()
                        }
                    }
                }
            } label: {
                Text(isSaving ? "Kaydediliyor..." : "Uygula")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .background(pageBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

// EditProfileView.swift
