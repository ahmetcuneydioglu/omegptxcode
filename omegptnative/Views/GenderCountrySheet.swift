import SwiftUI

struct GenderSelectionSheet: View {
    var appUserStore: AppUserStore
    @Binding var selectedOption: GenderFilterOption
    let onMatchNow: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tappedOption: GenderFilterOption?
    @State private var animateSelection = false
    @State private var showLoginRequiredSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cinsiyet Filtresi")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)

            Text("Eşleşme tercihi")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))

            HStack(spacing: 12) {
                ForEach(GenderFilterOption.allCases) { option in
                    genderCard(for: option)
                }
            }

            Spacer(minLength: 8)

            matchNowButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            Color.black.opacity(0.18)
                .background(.ultraThinMaterial)
        )
        .onAppear {
            animateSelection = true
        }
        .sheet(isPresented: $showLoginRequiredSheet) {
            LoginRequiredSheet(authManager: appUserStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private func genderCard(for option: GenderFilterOption) -> some View {
        let isSelected = selectedOption == option
        let isTapped = tappedOption == option
        let breathingScale = isSelected && animateSelection ? 1.018 : 1.0
        let breathingRotation = isSelected && animateSelection ? 0.8 : 0.0

        return Button {
            guard appUserStore.isLoggedIn || option == .all else {
                showLoginRequiredSheet = true
                return
            }

            withAnimation(.spring(response: 0.28, dampingFraction: 0.52)) {
                tappedOption = option
                selectedOption = option
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                    if tappedOption == option {
                        tappedOption = nil
                    }
                }
            }
        } label: {
            VStack(spacing: 10) {
                genderIcon(for: option)
                    .frame(height: 38)
                    .symbolEffect(.pulse, options: isSelected ? .repeating : .nonRepeating, value: isSelected)

                Text(option.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? Color.green.opacity(0.95) : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                    .blendMode(.plusLighter)
            }
            .shadow(
                color: isSelected ? Color.green.opacity(0.26) : Color.black.opacity(0.16),
                radius: isSelected ? 14 : 8,
                x: 0,
                y: isSelected ? 7 : 4
            )
            .shadow(
                color: isSelected ? Color.mint.opacity(0.28) : Color.clear,
                radius: 18,
                x: 0,
                y: 0
            )
        }
        .scaleEffect(isTapped ? 1.05 : breathingScale)
        .rotationEffect(.degrees(breathingRotation))
        .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: animateSelection)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: tappedOption)
        .hoverEffect(.lift)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func genderIcon(for option: GenderFilterOption) -> some View {
        switch option {
        case .all:
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.6), Color.clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 24
                        )
                    )
                    .frame(width: 36, height: 36)

                Image(systemName: "person.2.fill")
                    .font(.system(size: 24, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        Color.white,
                        Color.cyan.opacity(0.95),
                        Color.pink.opacity(0.95)
                    )
                    .shadow(color: Color.cyan.opacity(0.35), radius: 5, x: 0, y: 1)

                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(y: -14)
            }
        case .female:
            Image(systemName: "figure.dress.line.vertical.figure")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.pink.opacity(0.96), Color.orange.opacity(0.85))
                .font(.system(size: 28, weight: .bold))
                .shadow(color: Color.pink.opacity(0.35), radius: 6, x: 0, y: 1)
        case .male:
            Image(systemName: "figure.strengthtraining.traditional")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.blue.opacity(0.96), Color.cyan.opacity(0.85))
                .font(.system(size: 28, weight: .bold))
                .shadow(color: Color.blue.opacity(0.35), radius: 6, x: 0, y: 1)
        }
    }

    private var matchNowButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onMatchNow()
            }
        } label: {
            Text("Hemen Eşleş")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.green.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct CountrySelectionSheet: View {
    var appUserStore: AppUserStore
    @Binding var selectedCountry: String
    let onMatchNow: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showLoginRequiredSheet = false

    private let countries = CountryDataProvider.localizedCountries()

    private var filteredCountries: [CountryOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }

        return countries.filter { country in
            country.name.localizedCaseInsensitiveContains(query)
                || country.regionCode.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                globalRow

                ForEach(filteredCountries) { country in
                    countryRow(country)
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Ülke ara")
            .navigationTitle("Ülke Filtresi")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                matchNowButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Ülke Filtresi")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Eşleştirmek için bir ülke seçin")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }
        }
        .background(
            Color.black.opacity(0.18)
                .background(.ultraThinMaterial)
        )
        .sheet(isPresented: $showLoginRequiredSheet) {
            LoginRequiredSheet(authManager: appUserStore)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var globalRow: some View {
        Button {
            guard appUserStore.isLoggedIn else {
                showLoginRequiredSheet = true
                return
            }
            selectedCountry = "Global"
            dismiss()
        } label: {
            rowContent(
                title: "Global",
                leading: AnyView(
                    Image(systemName: "globe")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.7, green: 0.96, blue: 0.8))
                ),
                isSelected: selectedCountry == "Global"
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func countryRow(_ country: CountryOption) -> some View {
        Button {
            guard appUserStore.isLoggedIn else {
                showLoginRequiredSheet = true
                return
            }
            selectedCountry = country.name
            dismiss()
        } label: {
            rowContent(
                title: country.name,
                leading: AnyView(
                    Text(country.flag)
                        .font(.system(size: 24))
                ),
                isSelected: selectedCountry == country.name
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func rowContent(title: String, leading: AnyView, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            leading
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var matchNowButton: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onMatchNow()
            }
        } label: {
            Text("Hemen Eşleş")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.green.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

enum CountryDataProvider {
    static func localizedCountries(locale: Locale = .autoupdatingCurrent) -> [CountryOption] {
        Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            guard let localizedName = locale.localizedString(forRegionCode: code) else {
                return nil
            }

            return CountryOption(
                regionCode: code,
                name: localizedName,
                flag: flagEmoji(for: code)
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func regionCode(forLocalizedName localizedName: String, locale: Locale = .autoupdatingCurrent) -> String? {
        localizedCountries(locale: locale)
            .first(where: { $0.name.localizedCaseInsensitiveCompare(localizedName) == .orderedSame })?
            .regionCode
    }

    static func flagEmoji(forRegionCode regionCode: String) -> String {
        flagEmoji(for: regionCode)
    }

    // Converts an ISO region code such as "TR" into a regional-indicator flag emoji.
    private static func flagEmoji(for regionCode: String) -> String {
        let base: UInt32 = 127_397
        let scalars = regionCode.uppercased().unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let transformed = UnicodeScalar(base + scalar.value) else { return nil }
            return transformed
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

struct MatchRadarView: View {
    let isIntensified: Bool

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                RadarRing(
                    index: index,
                    isIntensified: isIntensified
                )
            }

            SwipeArrowIndicator(isIntensified: isIntensified)
        }
        .frame(width: 230, height: 230)
        .animation(.easeInOut(duration: 0.2), value: isIntensified)
    }
}
