import Foundation
import Observation
import UIKit

@Observable
final class AppState {
    static let shared = AppState()

    var alertTitle = ""
    var alertMessage = ""
    var showAlert = false
    var alertContext: GlobalAlertContext = .none
    var toastMessage = ""
    var showToast = false
    var forceDismissCall = false

    private init() {}

    func showGlobalAlert(title: String, message: String, context: GlobalAlertContext) {
        alertTitle = title
        alertMessage = message
        alertContext = context
        showAlert = true
    }

    func resetAlert() {
        showAlert = false
        alertTitle = ""
        alertMessage = ""
        alertContext = .none
    }

    func showToastMessage(_ message: String) {
        toastMessage = message
        showToast = true
    }

    func showTimedToast(_ message: String, duration: TimeInterval = 3) {
        toastMessage = message
        showToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.toastMessage == message {
                self.resetToast()
            }
        }
    }

    func resetToast() {
        toastMessage = ""
        showToast = false
    }

    func triggerForceDismissCall() {
        forceDismissCall = true
        Task { @MainActor in
            self.forceDismissCall = false
        }
    }
}
