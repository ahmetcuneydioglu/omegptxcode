import Foundation
#if canImport(RevenueCat)
import RevenueCat
#endif

struct RevenueCatStorePackage {
    let productId: String
    let localizedPriceText: String
}

enum RevenueCatManagerError: LocalizedError {
    case missingAPIKey
    case missingProduct(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "RevenueCat anahtari bulunamadi."
        case .missingProduct(let productId):
            return "\(productId) urunu RevenueCat offering icinde bulunamadi."
        }
    }
}

@MainActor
final class RevenueCatManager {
    static let shared = RevenueCatManager()

    private var isConfiguredInternally = false
    #if canImport(RevenueCat)
    private var cachedPackages: [String: Package] = [:]
    #endif

    var isConfigured: Bool {
        #if canImport(RevenueCat)
        return revenueCatAPIKey != nil
        #else
        return false
        #endif
    }

    private var revenueCatAPIKey: String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("YOUR_"), trimmed != "REVENUECAT_PUBLIC_SDK_KEY" else {
            return nil
        }

        return trimmed
    }

    func configureIfNeeded(appUserID: String?) {
        #if canImport(RevenueCat)
        guard !isConfiguredInternally else {
            syncUser(appUserID: appUserID)
            return
        }

        guard let apiKey = revenueCatAPIKey else {
            print("⚠️ RevenueCat public SDK key eksik. StoreKit fallback aktif kalacak.")
            return
        }

        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey, appUserID: sanitizedAppUserID(appUserID))
        isConfiguredInternally = true
        print("💎 RevenueCat configured. appUserID=\(sanitizedAppUserID(appUserID) ?? "anonymous")")
        #else
        _ = appUserID
        #endif
    }

    func syncUser(appUserID: String?) {
        #if canImport(RevenueCat)
        guard isConfigured else { return }

        if !isConfiguredInternally {
            configureIfNeeded(appUserID: appUserID)
            return
        }

        guard let sanitizedUserID = sanitizedAppUserID(appUserID) else {
            Task {
                do {
                    _ = try await logOut()
                } catch {
                    print("⚠️ RevenueCat logout failed: \(error.localizedDescription)")
                }
            }
            return
        }

        guard Purchases.shared.appUserID != sanitizedUserID else { return }

        Task {
            do {
                _ = try await logIn(appUserID: sanitizedUserID)
            } catch {
                print("⚠️ RevenueCat login failed: \(error.localizedDescription)")
            }
        }
        #else
        _ = appUserID
        #endif
    }

    func fetchPackages() async throws -> [RevenueCatStorePackage] {
        #if canImport(RevenueCat)
        guard isConfigured else {
            throw RevenueCatManagerError.missingAPIKey
        }

        let offerings = try await getOfferings()
        let availablePackages = offerings.current?.availablePackages ?? []
        cachedPackages = Dictionary(uniqueKeysWithValues: availablePackages.map { ($0.storeProduct.productIdentifier, $0) })
        return availablePackages.map {
            RevenueCatStorePackage(
                productId: $0.storeProduct.productIdentifier,
                localizedPriceText: $0.storeProduct.localizedPriceString
            )
        }
        #else
        throw RevenueCatManagerError.missingAPIKey
        #endif
    }

    func purchase(productId: String) async throws {
        #if canImport(RevenueCat)
        guard isConfigured else {
            throw RevenueCatManagerError.missingAPIKey
        }

        if cachedPackages[productId] == nil {
            _ = try await fetchPackages()
        }

        guard let package = cachedPackages[productId] else {
            throw RevenueCatManagerError.missingProduct(productId)
        }

        _ = try await purchase(package: package)
        #else
        _ = productId
        throw RevenueCatManagerError.missingAPIKey
        #endif
    }

    #if canImport(RevenueCat)
    private func sanitizedAppUserID(_ appUserID: String?) -> String? {
        guard let appUserID else { return nil }
        let trimmed = appUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func getOfferings() async throws -> Offerings {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.getOfferings { offerings, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let offerings else {
                    continuation.resume(throwing: RevenueCatManagerError.missingAPIKey)
                    return
                }

                continuation.resume(returning: offerings)
            }
        }
    }

    private func purchase(package: Package) async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.purchase(package: package) { _, customerInfo, error, userCancelled in
                if userCancelled {
                    continuation.resume(throwing: StoreKitManagerError.userCancelled)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let customerInfo else {
                    continuation.resume(throwing: RevenueCatManagerError.missingProduct(package.storeProduct.productIdentifier))
                    return
                }

                continuation.resume(returning: customerInfo)
            }
        }
    }

    private func logIn(appUserID: String) async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.logIn(appUserID) { customerInfo, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let customerInfo else {
                    continuation.resume(throwing: RevenueCatManagerError.missingAPIKey)
                    return
                }

                continuation.resume(returning: customerInfo)
            }
        }
    }

    private func logOut() async throws -> CustomerInfo {
        try await withCheckedThrowingContinuation { continuation in
            Purchases.shared.logOut { customerInfo, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let customerInfo else {
                    continuation.resume(throwing: RevenueCatManagerError.missingAPIKey)
                    return
                }

                continuation.resume(returning: customerInfo)
            }
        }
    }
    #endif
}
