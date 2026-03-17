import SafariServices
import SwiftUI

struct SettingsView: View {
    let onLogout: () -> Void
    @State private var selectedLegalDestination: LegalDestination?

    var body: some View {
        List {
            Section {
                legalRow(destination: .privacyPolicy)
                legalRow(destination: .termsOfService)
                legalRow(destination: .purchaseTerms)
            }

            Section {
                settingsRow(title: "Hesap ve Gizlilik")
                settingsRow(title: "Bildirimler")
            }

            Section {
                settingsRow(title: "Satin Alimlari Geri Getir")
            }

            Section {
                Button(action: onLogout) {
                    Text("Oturumu Kapat")
                        .foregroundStyle(.red)
                }
            } footer: {
                HStack {
                    Spacer()
                    Text("Omegpt v1.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 24)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ayarlar")
        .navigationBarTitleDisplayMode(.large)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(item: $selectedLegalDestination) { destination in
            NavigationStack {
                SafariSheetView(url: destination.url)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Bitti") {
                                selectedLegalDestination = nil
                            }
                        }
                    }
            }
        }
    }

    private func settingsRow(title: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }

    private func legalRow(destination: LegalDestination) -> some View {
        Button {
            selectedLegalDestination = destination
        } label: {
            settingsRow(title: destination.title)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private enum LegalDestination: String, Identifiable {
    case privacyPolicy
    case termsOfService
    case purchaseTerms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy:
            return "Gizlilik Politikasi"
        case .termsOfService:
            return "Hizmet Kosullari"
        case .purchaseTerms:
            return "Satin Alma Sartlari"
        }
    }

    var url: URL {
        switch self {
        case .privacyPolicy:
            return URL(string: "https://omegpt.com/privacy-policy")!
        case .termsOfService:
            return URL(string: "https://omegpt.com/terms-of-service")!
        case .purchaseTerms:
            return URL(string: "https://omegpt.com/purchase-terms")!
        }
    }
}

private struct SafariSheetView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
