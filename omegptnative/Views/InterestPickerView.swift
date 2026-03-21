import SwiftUI

struct InterestCategory {
    let title: String
    let items: [String]
}

let interestCategories: [InterestCategory] = [
    InterestCategory(title: "Wellness kulübü", items: [
        "🏋️ Evde antrenman", "#Cilt bakımı", "#Sağlık",
        "🧘 Meditasyon", "🏋️ Vücut geliştirmeci", "🎤 Aktif yaşam",
        "💄 Kendine bakım", "#Yürümek", "#Seyahat", "#Koşmak", "#Fitness"
    ]),
    InterestCategory(title: "Ev kuşları", items: [
        "#Bahçecilik", "#Kahve", "#Suşi", "🏎️ F1",
        "🏀 NBA", "👨‍🍳 Aşçılık", "🐕 Evcil hayvan", "#Ev",
        "#Yemek Yapmak", "#Dizi İzlemek", "#Film İzlemek"
    ]),
    InterestCategory(title: "Müzik severler", items: [
        "#Trap müzik", "#J-Pop", "🎸 Elektronik",
        "#Davulcu", "#Şarkı yazarı", "#Koro", "#K-Pop", "🎸 Müzik"
    ]),
    InterestCategory(title: "İçerik üreticileri", items: [
        "#Twitch", "#SMM", "#YouTube", "🐤 Twitter",
        "#Pinterest", "😀 Mizah", "#Instagram", "#TikTok", "🕵️ İçerik"
    ]),
    InterestCategory(title: "Yaratıcı zihinler", items: [
        "✨ Astroloji", "#Dövme", "🖼️ Sergiler", "👗 Moda",
        "#Görsel", "👟 Spor ayakkabı", "🎨 Sanat", "📷 Fotoğraf"
    ]),
    InterestCategory(title: "Oyuncular", items: [
        "#Aramızda", "#Zindanlar", "🕹️ E-Spor",
        "#Xbox", "VR", "#Roblox", "🎮 Oyun", "#Fortnite"
    ]),
    InterestCategory(title: "Pop müzik hayranları", items: [
        "#BTS", "#Disney", "#Cosplay", "🦸 Marvel", "📚 Anime", "#Dans"
    ]),
    InterestCategory(title: "İş dünyasının zihinleri", items: [
        "🚀 Startuplar", "#NFT", "🕵️ Teknoloji",
        "📈 Borsa", "🗂️ Gayrimenkul", "💼 Girişimcilik"
    ]),
    InterestCategory(title: "Kitapseverler", items: [
        "#Şiir", "📗 Kitap kurdu", "✏️ Harry Potter",
        "📖 Manga", "#Okumak"
    ]),
    InterestCategory(title: "Akıllı merkez", items: [
        "🌿 İklim", "#Dünya Barışı", "#Dil", "🎧 Podcastler"
    ])
]

// MARK: - Wrapping Layout (iOS 16+)

struct WrapLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = makeRows(width: proposal.width ?? 300, subviews: subviews)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * vSpacing
        return CGSize(width: proposal.width ?? 300, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = makeRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.view.sizeThatFits(.unspecified)
                item.view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }

    private struct RowItem { let view: LayoutSubview; let width: CGFloat }
    private struct Row { let items: [RowItem]; let height: CGFloat }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var rowItems: [RowItem] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let needed = rowItems.isEmpty ? size.width : rowWidth + hSpacing + size.width
            if !rowItems.isEmpty && needed > width {
                rows.append(Row(items: rowItems, height: rowHeight))
                rowItems = []
                rowWidth = 0
                rowHeight = 0
            }
            rowItems.append(RowItem(view: view, width: size.width))
            rowWidth = rowItems.count == 1 ? size.width : rowWidth + hSpacing + size.width
            rowHeight = max(rowHeight, size.height)
        }
        if !rowItems.isEmpty { rows.append(Row(items: rowItems, height: rowHeight)) }
        return rows
    }
}

// MARK: - InterestPickerView

struct InterestPickerView: View {
    @Binding var selectedInterests: Set<String>
    @Environment(\.dismiss) private var dismiss
    let onSave: (([String]) async -> Bool)?

    @State private var isSaving = false

    private let maxSelection = 5
    private let screenBackgroundColor = Color(red: 0.95, green: 0.95, blue: 0.96)
    private let chipDefaultFill = Color.white
    private let chipSelectedFill = Color(red: 0.14, green: 0.14, blue: 0.16)
    private let chipDefaultText = Color(red: 0.23, green: 0.23, blue: 0.27)
    private let saveButtonColor = Color(red: 0.94, green: 0.19, blue: 0.33)
    private let allInterestItems = Set(interestCategories.flatMap(\.items))

    init(
        selectedInterests: Binding<Set<String>>,
        onSave: (([String]) async -> Bool)? = nil
    ) {
        self._selectedInterests = selectedInterests
        self.onSave = onSave
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            screenBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        headerSection

                        ForEach(interestCategories, id: \.title) { category in
                            categorySection(category)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 124)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            saveButton
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
                .background(
                    LinearGradient(
                        colors: [screenBackgroundColor.opacity(0), screenBackgroundColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                )
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear {
            normalizeSelectedInterests()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.9))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Seçili \(selectedInterests.count) / \(maxSelection)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.72))
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("İlgi alanları...")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.black.opacity(0.92))

            Text("5'e kadar seçim yaparak ortak ilgi alanları olan arkadaşlarla tanışın. Profilinizde görüneceklerdir.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.58, green: 0.58, blue: 0.60))
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 255, alignment: .leading)
        }
    }

    private func categorySection(_ category: InterestCategory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(category.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.black.opacity(0.9))

            WrapLayout(hSpacing: 8, vSpacing: 12) {
                ForEach(category.items, id: \.self) { item in
                    chipButton(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chipButton(_ item: String) -> some View {
        let isSelected = selectedInterests.contains(item)
        let isMaxedOut = selectedInterests.count >= maxSelection && !isSelected

        return Button {
            toggleSelection(for: item)
        } label: {
            Text(item)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : chipDefaultText.opacity(isMaxedOut ? 0.35 : 1))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? chipSelectedFill : chipDefaultFill)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(isSelected ? 0 : 0.03), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .opacity(isMaxedOut ? 0.55 : 1)
    }

    private var saveButton: some View {
        Button {
            Task {
                await saveSelections()
            }
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text("Kaydet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(saveButtonColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func toggleSelection(for interest: String) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
            return
        }

        guard selectedInterests.count < maxSelection else { return }
        selectedInterests.insert(interest)
    }

    private func normalizeSelectedInterests() {
        let validSelections = selectedInterests.filter { allInterestItems.contains($0) }.sorted()
        selectedInterests = Set(validSelections.prefix(maxSelection))
    }

    @MainActor
    private func saveSelections() async {
        let updatedInterests = Array(selectedInterests).sorted()
        guard let onSave else {
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        let success = await onSave(updatedInterests)
        if success {
            dismiss()
        }
    }
}
