import Foundation
import SwiftUI

enum GenderFilterOption: String, CaseIterable, Identifiable {
    case all = "Tümü"
    case female = "Kadın"
    case male = "Erkek"

    var id: String { rawValue }

    var socketValue: String {
        switch self {
        case .all:
            return "all"
        case .female:
            return "female"
        case .male:
            return "male"
        }
    }
}

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)
}

enum PrivateCallRequestPhase: Equatable {
    case checking
    case calling
}

enum PrivateCallAlertKind: String, Identifiable {
    case targetBusy
    case insufficientGems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .targetBusy:
            return "Kullanici Mesgul"
        case .insufficientGems:
            return "Yetersiz Gem"
        }
    }

    var message: String {
        switch self {
        case .targetBusy:
            return "Aradiginiz kisi su anda baska bir gorusmede. Lutfen daha sonra tekrar deneyin."
        case .insufficientGems:
            return "Ozel arama yapabilmek icin 50 Gem gereklidir. Magazaya gidip Gem almak ister misiniz?"
        }
    }
}

enum GlobalAlertContext {
    case none
    case targetBusy
    case insufficientGems
}

enum DailyRewardCardState {
    case claimed
    case claimable
    case locked
}
