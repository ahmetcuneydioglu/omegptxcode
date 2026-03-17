import Foundation
import Combine

@MainActor
final class JoinNotificationViewModel: ObservableObject {
    @Published private(set) var currentUser: FakeUser?

    private var appearTimer: Timer?
    private var hideTimer: Timer?

    func start() {
        guard appearTimer == nil, hideTimer == nil else { return }
        scheduleNextAppearance()
    }

    func stop() {
        appearTimer?.invalidate()
        hideTimer?.invalidate()
        appearTimer = nil
        hideTimer = nil
        currentUser = nil
    }

    private func scheduleNextAppearance() {
        appearTimer?.invalidate()
        let delay = TimeInterval.random(in: 1...3)

        appearTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showRandomUser()
            }
        }
    }

    private func showRandomUser() {
        currentUser = FakeUserData.globalUsers.randomElement()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.currentUser = nil
                self?.scheduleNextAppearance()
            }
        }
    }
}
