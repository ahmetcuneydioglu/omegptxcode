import Foundation
import SwiftUI
import StoreKit
import Observation

struct StorePackage: Identifiable {
    let productId: String
    var id: String { productId }
    let gemAmount: Int
    let gemAmountTitle: String
    let comparisonLabel: String?
    let saveText: String
    let unitPriceText: String
    let priceText: String
    let originalPriceText: String?
    let gradientColors: [Color]
}

@MainActor
@Observable
final class StoreViewModel {
    var gems: Int = 0
    var dailyStreak: Int = 0
    var canClaim: Bool = false
    var isLoading: Bool = false
    var isPurchasing: Bool = false
    var countdownText: String = "--:--:--"
    var claimPulseID = UUID()
    var isGuestMode: Bool = false
    var purchaseErrorMessage: String?
    var packages: [StorePackage]

    let dailyRewards: [Int] = [5, 10, 15, 20, 25, 30, 50]

    private let storeKitManager = StoreKitManager.shared
    private let appUserStore = AppUserStore.shared
    private let networkManager = NetworkManager()
    private var currentDbUserId: String?
    private var countdownTimer: Timer?

    init() {
        self.packages = Self.buildDynamicPackages()
    }

    func fetchStoreStatus(dbUserId: String?) async {
        currentDbUserId = dbUserId
        guard let dbUserId, !dbUserId.isEmpty else {
            enterGuestMode()
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let json = try await networkManager.postJSON(path: "/api/store/status")
            applyStoreStatus(json)
        } catch NetworkError.unauthorized {
            appUserStore.handleUnauthorized()
        } catch {
            print("⚠️ fetchStoreStatus failed: \(error.localizedDescription)")
        }
    }

    func loadProducts(dbUserId: String?) async {
        currentDbUserId = dbUserId
        do {
            let products = try await storeKitManager.requestProducts()
            applyStoreProducts(products)
        } catch {
            print("⚠️ requestProducts failed: \(error.localizedDescription)")
        }
    }

    func buyPackage(_ package: StorePackage, dbUserId: String?) async {
        await purchasePackage(package, dbUserId: dbUserId)
    }

    func purchasePackage(_ package: StorePackage, dbUserId: String?) async {
        guard let dbUserId, !dbUserId.isEmpty else {
            purchaseErrorMessage = "Satın alma için giriş yapman gerekiyor."
            return
        }

        guard !isPurchasing else { return }
        purchaseErrorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        currentDbUserId = dbUserId

        do {
            guard let product = await storeKitManager.product(for: package.productId) else {
                purchaseErrorMessage = "Ürün bilgisi yüklenemedi. Lütfen tekrar dene."
                return
            }

            let purchaseResult = try await storeKitManager.purchase(product)

            // CRITICAL: Backend verification right after Apple success.
            let backendJSON = try await verifyPurchaseOnBackend(
                productId: purchaseResult.productId,
                transactionId: purchaseResult.transactionId,
                receiptData: purchaseResult.receiptData
            )

            let isVerified = boolValue(in: backendJSON, keys: ["success", "ok"], defaultValue: false)
            guard isVerified else {
                purchaseErrorMessage = (backendJSON["message"] as? String) ?? "Satın alma doğrulanamadı."
                return
            }

            // Only now we finalize StoreKit transaction.
            await purchaseResult.transaction.finish()

            // Only update local gems after backend success.
            applyStoreStatus(backendJSON)
            let newBalance = intValue(in: backendJSON, keys: ["newBalance", "gems", "balance", "tickets"], defaultValue: gems)
            gems = newBalance
            appUserStore.updateGemBalance(newBalance)

            if backendJSON["newBalance"] == nil,
               backendJSON["gems"] == nil,
               backendJSON["balance"] == nil,
               backendJSON["tickets"] == nil {
                await fetchStoreStatus(dbUserId: dbUserId)
            }
        } catch let error as StoreKitManagerError {
            switch error {
            case .userCancelled:
                purchaseErrorMessage = "Satın alma iptal edildi."
            case .pending:
                purchaseErrorMessage = "Satın alma onay bekliyor."
            default:
                purchaseErrorMessage = error.localizedDescription
            }
            print("⚠️ purchasePackage failed: \(error.localizedDescription)")
        } catch NetworkError.unauthorized {
            purchaseErrorMessage = "Oturumun sona erdi. Lutfen tekrar giris yap."
            appUserStore.handleUnauthorized()
        } catch NetworkError.serverError(let message) {
            if message.localizedCaseInsensitiveContains("duplicate") {
                purchaseErrorMessage = "Bu satin alma daha once dogrulanmis."
            } else {
                purchaseErrorMessage = message
            }
            print("⚠️ purchasePackage backend error: \(message)")
        } catch {
            purchaseErrorMessage = error.localizedDescription
            print("⚠️ purchasePackage failed: \(error.localizedDescription)")
        }
    }

    func claimDailyReward(dbUserId: String?) async {
        guard let dbUserId, !dbUserId.isEmpty, canClaim else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let json = try await networkManager.postJSON(path: "/api/store/claim")
            applyStoreStatus(json)
            claimPulseID = UUID()
        } catch NetworkError.unauthorized {
            appUserStore.handleUnauthorized()
        } catch {
            print("⚠️ claimDailyReward failed: \(error.localizedDescription)")
        }
    }

    func startCountdownTimer() {
        guard !isGuestMode else {
            stopCountdownTimer()
            return
        }
        stopCountdownTimer()
        updateCountdownText()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateCountdownText()
            }
        }
    }

    func stopCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    func state(for index: Int) -> DailyRewardCardState {
        if index < dailyStreak {
            return .claimed
        }
        if index == dailyStreak && canClaim {
            return .claimable
        }
        return .locked
    }

    func countdown(for index: Int) -> String? {
        guard !isGuestMode else { return nil }
        let nextIndex = min(max(dailyStreak, 0), dailyRewards.count - 1)
        if !canClaim && index == nextIndex {
            return countdownText
        }
        return nil
    }

    func enterGuestMode() {
        gems = 0
        dailyStreak = 0
        canClaim = false
        isLoading = false
        isGuestMode = true
        countdownText = "--:--:--"
        stopCountdownTimer()
    }

    private func updateCountdownText() {
        let now = Date()
        guard let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else {
            countdownText = "--:--:--"
            return
        }

        let interval = max(0, Int(nextMidnight.timeIntervalSince(now)))
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        let seconds = interval % 60
        countdownText = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func applyStoreProducts(_ products: [Product]) {
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        packages = packages.map { package in
            guard let product = productsByID[package.productId] else { return package }
            return StorePackage(
                productId: package.productId,
                gemAmount: package.gemAmount,
                gemAmountTitle: package.gemAmountTitle,
                comparisonLabel: package.comparisonLabel,
                saveText: package.saveText,
                unitPriceText: package.unitPriceText,
                priceText: product.displayPrice,
                originalPriceText: package.originalPriceText,
                gradientColors: package.gradientColors
            )
        }
    }

    private func applyStoreStatus(_ json: [String: Any]) {
        isGuestMode = false
        gems = intValue(in: json, keys: ["gems", "balance", "tickets"], defaultValue: gems)
        dailyStreak = min(max(intValue(in: json, keys: ["dailyStreak", "streak", "day"], defaultValue: dailyStreak), 0), dailyRewards.count - 1)
        canClaim = boolValue(in: json, keys: ["canClaim", "claimAvailable"], defaultValue: canClaim)
    }

    private func intValue(in json: [String: Any], keys: [String], defaultValue: Int) -> Int {
        for key in keys {
            if let intValue = json[key] as? Int { return intValue }
            if let stringValue = json[key] as? String, let intValue = Int(stringValue) { return intValue }
        }
        return defaultValue
    }

    private func boolValue(in json: [String: Any], keys: [String], defaultValue: Bool) -> Bool {
        for key in keys {
            if let boolValue = json[key] as? Bool { return boolValue }
            if let intValue = json[key] as? Int { return intValue != 0 }
            if let stringValue = json[key] as? String {
                let lowercased = stringValue.lowercased()
                if lowercased == "true" || lowercased == "1" { return true }
                if lowercased == "false" || lowercased == "0" { return false }
            }
        }
        return defaultValue
    }

    func verifyPurchaseOnBackend(
        productId: String,
        transactionId: UInt64,
        receiptData: String
    ) async throws -> [String: Any] {
        guard currentDbUserId != nil else {
            throw NetworkError.unauthorized
        }

        print("DEBUG: Sending purchase to backend for product: \(productId)")

        let body: [String: Any] = [
            "platform": "ios",
            "productId": productId,
            "transactionId": String(transactionId),
            "receiptData": receiptData
        ]

        return try await networkManager.postJSON(
            path: "/api/store/verify-purchase",
            body: body
        )
    }

    private static func buildDynamicPackages() -> [StorePackage] {
        let tiers = [120, 400, 820, 1700, 4500, 10_000]
        let productIDs = StoreKitManager.productIDs
        let discounts = [0, 4, 8, 12, 16, 20]
        let gradients: [[Color]] = [
            [Color(hex: "6A11CB"), Color(hex: "2575FC")],
            [Color(hex: "4FACFE"), Color(hex: "00F2FE")],
            [Color(hex: "F093FB"), Color(hex: "F5576C")],
            [Color(hex: "3B82F6"), Color(hex: "2563EB")],
            [Color(hex: "FB923C"), Color(hex: "F97316")],
            [Color(red: 0.89, green: 0.89, blue: 0.9), Color(red: 0.84, green: 0.84, blue: 0.86)]
        ]

        let baselineTierPrice = 4.99
        let baseUnit = baselineTierPrice / Double(tiers[0])

        return tiers.enumerated().map { index, gemAmount in
            let requestedDiscount = discounts[index]
            let fullPrice = baseUnit * Double(gemAmount)
            let discountedRaw = fullPrice * (1.0 - Double(requestedDiscount) / 100.0)
            let finalPrice = psychologicalRound(discountedRaw, useNinety: gemAmount >= 4500)
            let unitPrice = finalPrice / Double(gemAmount)

            let label: String? = {
                switch gemAmount {
                case 120:
                    return "Starter"
                case 820:
                    return "Most Popular"
                case 10_000:
                    return "Best Value / Mega Pack"
                default:
                    return nil
                }
            }()

            return StorePackage(
                productId: productIDs[index],
                gemAmount: gemAmount,
                gemAmountTitle: "\(gemAmount)",
                comparisonLabel: label,
                saveText: "Save \(requestedDiscount)%",
                unitPriceText: "$\(money(unitPrice))/gem",
                priceText: "$\(money(finalPrice))",
                originalPriceText: requestedDiscount == 0 ? nil : "$\(money(fullPrice))",
                gradientColors: gradients[index]
            )
        }
    }

    private static func psychologicalRound(_ value: Double, useNinety: Bool) -> Double {
        guard value > 0 else { return 0.99 }
        let floorValue = floor(value)
        let ending = useNinety ? 0.90 : 0.99
        let candidate = floorValue + ending
        if candidate >= value { return candidate }
        return floorValue + 1 + ending
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var intValue: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&intValue)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (intValue >> 16, intValue >> 8 & 0xFF, intValue & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1.0
        )
    }
}
