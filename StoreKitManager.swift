import Foundation
import StoreKit

enum StoreKitManagerError: LocalizedError {
    case missingTransactionVerification
    case userCancelled
    case pending
    case productNotFound

    var errorDescription: String? {
        switch self {
        case .missingTransactionVerification:
            return "Satın alma doğrulanamadı."
        case .userCancelled:
            return "Satın alma iptal edildi."
        case .pending:
            return "Satın alma işlemi onay bekliyor."
        case .productNotFound:
            return "Ürün bilgisi alınamadı."
        }
    }
}

struct StoreKitPurchaseResult {
    let productId: String
    let transactionId: UInt64
    let transaction: Transaction
    let receiptData: String
}

actor StoreKitManager {
    static let shared = StoreKitManager()

    static var isLocalStoreKitTestingEnabled: Bool {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-omegpt-local-storekit") {
            return true
        }

        guard let rawValue = processInfo.environment["OMEGPT_LOCAL_STOREKIT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }

        return rawValue == "1" || rawValue == "true" || rawValue == "yes"
    }

    static let gemPackages: [String: Int] = [
        "com.omegpt.gem120": 120,
        "com.omegpt.gem400": 400,
        "com.omegpt.gem820": 820,
        "com.omegpt.gem1700": 1700,
        "com.omegpt.gem4500": 4500,
        "com.omegpt.gem10000": 10000
    ]

    static let productIDs: [String] = [
        "com.omegpt.gem120",
        "com.omegpt.gem400",
        "com.omegpt.gem820",
        "com.omegpt.gem1700",
        "com.omegpt.gem4500",
        "com.omegpt.gem10000"
    ]

    private var cachedProducts: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    func requestProducts() async throws -> [Product] {
        ensureTransactionObservationStarted()
        let products = try await Product.products(for: Self.productIDs)
        var cache: [String: Product] = [:]
        for product in products {
            cache[product.id] = product
        }
        cachedProducts = cache
        return Self.productIDs.compactMap { cache[$0] }
    }

    func product(for id: String) -> Product? {
        cachedProducts[id]
    }

    // Handles Apple purchase only; backend verification is performed in StoreViewModel.
    func purchase(_ product: Product) async throws -> StoreKitPurchaseResult {
        ensureTransactionObservationStarted()
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            return StoreKitPurchaseResult(
                productId: transaction.productID,
                transactionId: transaction.id,
                transaction: transaction,
                receiptData: Self.loadReceiptData() ?? String(transaction.id)
            )
        case .userCancelled:
            throw StoreKitManagerError.userCancelled
        case .pending:
            throw StoreKitManagerError.pending
        @unknown default:
            throw StoreKitManagerError.missingTransactionVerification
        }
    }

    private func ensureTransactionObservationStarted() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            await observeTransactionUpdates()
        }
    }

    // Keeps transaction pipeline alive for interrupted/background flows.
    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            do {
                let transaction = try verifiedTransaction(from: update)
                print("🧾 Transaction update received: \(transaction.id), product: \(transaction.productID)")
                // Do not finish here; app flow finishes after backend verification.
            } catch {
                print("⚠️ Transaction update verification failed: \(error.localizedDescription)")
            }
        }
    }

    private func verifiedTransaction(from verification: VerificationResult<Transaction>) throws -> Transaction {
        switch verification {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw StoreKitManagerError.missingTransactionVerification
        }
    }

    private static func loadReceiptData() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let data = try? Data(contentsOf: receiptURL),
              !data.isEmpty else {
            return nil
        }
        return data.base64EncodedString()
    }
}
