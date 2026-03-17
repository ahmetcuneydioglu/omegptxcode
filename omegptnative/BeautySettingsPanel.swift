import SwiftUI

enum BeautyTab: String, CaseIterable, Identifiable {
    case beauty = "Güzellik"
    case filters = "Filtreler"
    var id: String { rawValue }
}

enum BeautyTool: String, CaseIterable, Identifiable {
    case brighten = "Aydınlat"
    case smooth = "Cilt"
    case eye = "Göz"
    case nose = "Burun"
    case jawline = "Çene"
    case teeth = "Diş"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .brighten: return "sun.max.fill"
        case .smooth: return "drop.fill"
        case .eye: return "eye.fill"
        case .nose: return "nose.fill"
        case .jawline: return "face.smiling.fill"
        case .teeth: return "sparkles"
        }
    }
}

struct BeautySettingsPanel: View {
    @StateObject private var webRTCManager = WebRTCManager.shared
    @Binding var smoothness: Double
    @Binding var vibrance: Double
    @Binding var exposure: Double
    @Binding var selectedPreset: ProfessionalColorPreset
    @Binding var selectedTab: BeautyTab
    @Binding var selectedBeautyTool: BeautyTool
    @Binding var intensity: Double
    @Binding var teethLuminanceMin: Double
    @Binding var teethChromaMax: Double
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            headerRow
            tabSwitcher

            BeautySliderRow(
                title: selectedTab == .beauty ? selectedBeautyTool.rawValue : "Filtre Yoğunluğu",
                icon: selectedTab == .beauty ? selectedBeautyTool.icon : "camera.filters",
                value: $intensity,
                tint: Color(red: 0.56, green: 0.94, blue: 0.9),
                valueFormat: .percent
            )

            if selectedTab == .beauty {
                beautyToolsSelector
                if selectedBeautyTool == .teeth {
                    teethMaskControls
                }
            } else {
                presetSelector
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 6)
        .onAppear {
            if selectedTab == .filters {
                webRTCManager.refreshFilterPreviewImages()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .filters {
                webRTCManager.refreshFilterPreviewImages()
            }
        }
    }

    private var headerRow: some View {
        HStack {
            Label(selectedTab.rawValue, systemImage: selectedTab == .beauty ? "wand.and.stars" : "camera.filters")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Button("Reset", action: onReset)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(BeautyTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(selectedTab == tab ? 1 : 0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedTab == tab ? Color.white.opacity(0.16) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedTab == tab ? Color.white.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var beautyToolsSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Güzellik")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(BeautyTool.allCases) { tool in
                        Button {
                            selectedBeautyTool = tool
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.35))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: tool.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.95))
                                }
                                .overlay(
                                    Circle().stroke(
                                        selectedBeautyTool == tool ? Color.green.opacity(0.95) : Color.white.opacity(0.18),
                                        lineWidth: selectedBeautyTool == tool ? 2.0 : 0.8
                                    )
                                )

                                Text(tool.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var presetSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Filtreler")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ProfessionalColorPreset.allCases) { preset in
                        presetItem(for: preset)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var teethMaskControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diş Maskesi")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            BeautySliderRow(
                title: "Parlaklık Eşiği",
                icon: "sun.max",
                value: $teethLuminanceMin,
                tint: Color(red: 0.98, green: 0.88, blue: 0.56),
                valueFormat: .percent
            )

            BeautySliderRow(
                title: "Renk Eşiği",
                icon: "drop.triangle",
                value: $teethChromaMax,
                tint: Color(red: 0.7, green: 0.84, blue: 1.0),
                valueFormat: .percent
            )
        }
    }

    private func presetItem(for preset: ProfessionalColorPreset) -> some View {
        Button {
            selectedPreset = preset
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let uiImage = webRTCManager.filterPreviewImages[preset] {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: previewColors(for: preset),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: preset.systemIcon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                }
                .overlay(
                    Circle()
                        .stroke(
                            selectedPreset == preset
                                ? Color.green.opacity(0.95)
                                : Color.white.opacity(0.26),
                            lineWidth: selectedPreset == preset ? 2.4 : 0.8
                        )
                )
                .background(
                    Group {
                        if selectedPreset == preset {
                            Circle().fill(.ultraThinMaterial)
                        } else {
                            Circle().fill(Color.clear)
                        }
                    }
                    .frame(width: 52, height: 52)
                )

                Text(preset.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.plain)
    }

    private func previewColors(for preset: ProfessionalColorPreset) -> [Color] {
        switch preset {
        case .none:
            return [Color.gray.opacity(0.45), Color.black.opacity(0.55)]
        case .analog:
            return [Color.orange.opacity(0.9), Color(red: 0.58, green: 0.39, blue: 0.23)]
        case .ash:
            return [Color.gray.opacity(0.95), Color(red: 0.2, green: 0.24, blue: 0.29)]
        case .bright:
            return [Color.yellow.opacity(0.95), Color(red: 1.0, green: 0.67, blue: 0.32)]
        case .clean:
            return [Color(red: 0.72, green: 0.9, blue: 1.0), Color(red: 0.34, green: 0.66, blue: 1.0)]
        case .retro:
            return [Color(red: 0.86, green: 0.59, blue: 0.36), Color(red: 0.42, green: 0.25, blue: 0.18)]
        case .vivid:
            return [Color(red: 1.0, green: 0.34, blue: 0.44), Color(red: 0.36, green: 0.24, blue: 1.0)]
        case .cool:
            return [Color(red: 0.54, green: 0.82, blue: 1.0), Color(red: 0.16, green: 0.38, blue: 0.9)]
        case .warm:
            return [Color(red: 1.0, green: 0.72, blue: 0.36), Color(red: 0.88, green: 0.34, blue: 0.18)]
        case .bw:
            return [Color.white.opacity(0.88), Color.black.opacity(0.88)]
        case .dramatic:
            return [Color(red: 0.16, green: 0.18, blue: 0.24), Color.black]
        case .softFocus:
            return [Color(red: 0.95, green: 0.84, blue: 0.88), Color(red: 0.76, green: 0.82, blue: 0.95)]
        case .cinematic:
            return [Color(red: 0.14, green: 0.58, blue: 0.62), Color(red: 0.96, green: 0.46, blue: 0.24)]
        case .pastel:
            return [Color(red: 0.94, green: 0.78, blue: 0.88), Color(red: 0.74, green: 0.84, blue: 0.98)]
        case .noir:
            return [Color(red: 0.3, green: 0.3, blue: 0.34), Color.black.opacity(0.98)]
        case .sunset:
            return [Color(red: 1.0, green: 0.56, blue: 0.34), Color(red: 0.82, green: 0.18, blue: 0.34)]
        case .mocha:
            return [Color(red: 0.72, green: 0.52, blue: 0.38), Color(red: 0.32, green: 0.2, blue: 0.15)]
        case .fresh:
            return [Color(red: 0.56, green: 0.96, blue: 0.76), Color(red: 0.2, green: 0.72, blue: 0.54)]
        case .glow:
            return [Color(red: 1.0, green: 0.9, blue: 0.52), Color(red: 1.0, green: 0.58, blue: 0.7)]
        case .tealOrange:
            return [Color(red: 0.18, green: 0.76, blue: 0.74), Color(red: 0.98, green: 0.46, blue: 0.16)]
        }
    }
}

struct BeautySliderRow: View {
    enum ValueFormat {
        case decimal
        case percent
    }

    let title: String
    let icon: String
    @Binding var value: Double
    let tint: Color
    let valueFormat: ValueFormat
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text(displayValueText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }

            GeometryReader { geometry in
                let knobTravel = max(0, geometry.size.width - 28)
                let xOffset = knobTravel * CGFloat(value)

                ZStack(alignment: .topLeading) {
                    Slider(
                        value: $value,
                        in: 0...1,
                        onEditingChanged: { editing in
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isEditing = editing
                            }
                        }
                    )
                    .tint(tint)
                    .padding(.top, 8)

                    if isEditing {
                        Text(displayValueText)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.58))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.7)
                            )
                            .offset(x: xOffset, y: -6)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 34)
        }
    }

    private var displayValueText: String {
        switch valueFormat {
        case .decimal:
            return String(format: "%.2f", value)
        case .percent:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}
