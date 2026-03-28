import Foundation
import UIKit
import Observation
#if canImport(SocketIO)
import SocketIO
#endif

final class RemoteVideoCaptureRegistry {
    static let shared = RemoteVideoCaptureRegistry()

    private let viewTable = NSMapTable<NSString, UIView>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    private let lock = NSLock()

    private init() {}

    func register(view: UIView, for key: String) {
        lock.lock()
        viewTable.setObject(view, forKey: key as NSString)
        lock.unlock()
    }

    func unregister(for key: String) {
        lock.lock()
        viewTable.removeObject(forKey: key as NSString)
        lock.unlock()
    }

    func captureSnapshot(for key: String) -> UIImage? {
        if Thread.isMainThread {
            return captureSnapshotOnMain(for: key)
        }
        return DispatchQueue.main.sync {
            captureSnapshotOnMain(for: key)
        }
    }

    private func captureSnapshotOnMain(for key: String) -> UIImage? {
        lock.lock()
        let view = viewTable.object(forKey: key as NSString)
        lock.unlock()

        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        return renderer.image { context in
            if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
                view.layer.render(in: context.cgContext)
            }
        }
    }
}

@Observable
final class SocketService {
    static let shared = SocketService()
    private(set) var partner: PartnerFoundPayload?
    var activePartnerId: String? = nil
    private(set) var activeMatch: PartnerFoundPayload?
    private(set) var sessionStage: MatchSessionStage = .idle
    private(set) var activeCallMode: CallRequestMode?
    private(set) var isSearching = false
    private(set) var totalReceivedLikes = 0
    var banEvent: BanEvent?
    var messages: [ChatMessage] = []
    var isPartnerTyping = false
    private(set) var isPartnerViewingProfile = false
    private(set) var matchedAt: Date?
    var partnerName: String?
    var partnerAvatarURL: String?
    var incomingLikeBurstID = UUID()
    var recentPartners: [MatchedPartner] = []
    var storePresentationRequestID: UUID?
    var storePresentationMessage = "Filtre kullanmak için yeterli taşın yok! Mağazadan hemen yükleyebilirsin."
    private(set) var isFindPartnerLocked = false
    var incomingPrivateCall: IncomingPrivateCall?
    var privateCallNotice: PrivateCallNotice?
    private(set) var outgoingPrivateCallTargetId: String?
    private(set) var outgoingPrivateCallPhase: PrivateCallRequestPhase?
    private(set) var outgoingCallMode: CallRequestMode?
    private(set) var userOnlineStates: [String: UserStatus] = [:]
    private(set) var myStatus: UserStatus = .offline
    private(set) var isAwaitingSearchStart = false
    private(set) var guestMatchCount = 0
    private var currentSearchPayload: MatchSearchPayload?
    private var findPartnerUnlockWorkItem: DispatchWorkItem?
    private var autoRematchWorkItem: DispatchWorkItem?
    private var privateCallPhaseWorkItem: DispatchWorkItem?
    private var lastGemBalanceValue: Int?
    private var lastGemBalanceUpdateAt: Date?
    private var observedStatusUserIds: Set<String> = []
    private var localProfileViewStateIsActive = false
    private let webRTCManager = WebRTCManager.shared
    private let appUserStore = AppUserStore.shared
    private let appState = AppState.shared

    #if canImport(SocketIO)
    private var socketManager: SocketManager?
    private var socket: SocketIOClient?
    #endif

    init() {
        webRTCManager.onSignalGenerated = { [weak self] signal in
            self?.emitSignal(signal)
        }
    }

    func connect(dbUserId _: String?) {
        #if canImport(SocketIO)
        let token = AuthManager.shared.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔌 Socket connect requested. authenticated=\(token?.isEmpty == false)")
        disconnect()

        guard let url = URL(string: "https://videochat-1qxi.onrender.com") else { return }

        let config: SocketIOClientConfiguration = [
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .log(true)
        ]

        let manager = SocketManager(socketURL: url, config: config)
        let socket = manager.defaultSocket

        socketManager = manager
        self.socket = socket

        registerHandlers(for: socket)
        if let token, !token.isEmpty {
            socket.connect(withPayload: ["token": token])
        } else {
            socket.connect()
        }
        #endif
    }

    func disconnect() {
        #if canImport(SocketIO)
        socket?.emit("manual_offline")
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        socketManager = nil
        #endif
        myStatus = .offline
        webRTCManager.endSession()
        isSearching = false
        sessionStage = .idle
        activeCallMode = nil
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        matchedAt = nil
        messages.removeAll()
        isPartnerTyping = false
        isPartnerViewingProfile = false
        localProfileViewStateIsActive = false
        partnerName = nil
        partnerAvatarURL = nil
        recentPartners.removeAll()
        incomingPrivateCall = nil
        privateCallNotice = nil
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
        outgoingCallMode = nil
        markObservedUsersOffline()
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
        autoRematchWorkItem?.cancel()
        autoRematchWorkItem = nil
        isAwaitingSearchStart = false
        unlockFindPartnerEmit(reason: "disconnect")
    }

    func updateSearchCriteria(myGender: String, searchGender: String, selectedCountry: String) {
        currentSearchPayload = MatchSearchPayload(
            myGender: myGender,
            searchGender: searchGender,
            selectedCountry: selectedCountry
        )
    }

    func findPartner() {
        guard let payload = currentSearchPayload else { return }
        #if canImport(SocketIO)
        guard let socket else { return }
        print("Socket Status: \(socket.status)")

        guard !isFindPartnerLocked, !isAwaitingSearchStart, !(isSearching && activePartnerId == nil) else {
            print("⏳ find_partner ignored because matchmaking is already pending/searching.")
            return
        }

        if socket.status != .connected {
            print("⚠️ Socket is not connected. Reconnecting before find_partner...")
            socket.connect()
            return
        }

        lockFindPartnerEmit(for: 8.0)
        isAwaitingSearchStart = true
        sessionStage = .searching

        let currentGender: String? = payload.myGender
        let preferredGender: String? = payload.searchGender
        let preferredCountry: String? = payload.selectedCountry

        let emitPayload: [String: Any] = [
            "myGender": currentGender ?? "male",
            "searchGender": preferredGender ?? "all",
            "selectedCountry": preferredCountry ?? "all"
        ]

        print("DEBUG: find_partner emitted with gender: \(preferredGender ?? "all")")
        print("📤 Emitting find_partner payload: \(emitPayload)")
        socket.emitWithAck("find_partner", emitPayload).timingOut(after: 5) { [weak self] data in
            self?.handleFindPartnerAck(data)
        }
        isSearching = true
        sessionStage = .searching
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        matchedAt = nil
        isPartnerViewingProfile = false
        localProfileViewStateIsActive = false
        #endif
    }

    func findPartner(myGender: String, searchGender: String, selectedCountry: String) {
        #if canImport(SocketIO)
        if let socket {
            print("📡 SocketService: findPartner function called. Current socket status: \(socket.status)")
        } else {
            print("📡 SocketService: findPartner function called, but socket is nil")
        }
        #endif
        updateSearchCriteria(
            myGender: myGender,
            searchGender: searchGender,
            selectedCountry: selectedCountry
        )
        findPartner()
    }

    func stopSearch() {
        #if canImport(SocketIO)
        socket?.emit("stop_search")
        #endif
        isSearching = false
        isAwaitingSearchStart = false
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
        unlockFindPartnerEmit(reason: "stop_search")
    }

    func skipToNextAndSearch(myGender: String, searchGender: String, selectedCountry: String) {
        #if canImport(SocketIO)
        socket?.emit("stop_search")
        #endif
        webRTCManager.endCall()
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        matchedAt = nil
        isPartnerViewingProfile = false
        localProfileViewStateIsActive = false
        isSearching = false
        isAwaitingSearchStart = false

        updateSearchCriteria(
            myGender: myGender,
            searchGender: searchGender,
            selectedCountry: selectedCountry
        )
        findPartner()
    }

    func swipeToNextAndSearch(myGender: String, searchGender: String, selectedCountry: String) {
        #if canImport(SocketIO)
        socket?.emit("next_user")
        #endif
        webRTCManager.endCall()
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        matchedAt = nil
        messages.removeAll()
        isPartnerTyping = false
        isPartnerViewingProfile = false
        localProfileViewStateIsActive = false
        partnerName = nil
        partnerAvatarURL = nil
        isSearching = false
        isAwaitingSearchStart = false

        updateSearchCriteria(
            myGender: myGender,
            searchGender: searchGender,
            selectedCountry: selectedCountry
        )
        findPartner()
    }

    func likePartner(targetId: String, currentSessionLikes: Int) {
        #if canImport(SocketIO)
        socket?.emit("like_partner", [
            "targetId": targetId,
            "increaseCounter": true,
            "currentSessionLikes": currentSessionLikes
        ])
        #endif
    }

    func sendLike(targetId: String, currentSessionLikes: Int) {
        #if canImport(SocketIO)
        let payload: [String: Any] = [
            "targetId": targetId,
            "increaseCounter": true,
            "currentSessionLikes": currentSessionLikes
        ]
        socket?.emit("send_like", payload)
        socket?.emit("like_partner", payload)
        #endif
    }

    func sendChatMessage(to targetId: String, message: String) {
        #if canImport(SocketIO)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let senderName = appUserStore.currentUser?.name ?? "Misafir"
        let profilePic = appUserStore.currentUser?.avatar ?? ""
        let payload: [String: Any] = [
            "to": targetId,
            "text": trimmed,
            "senderName": senderName,
            "profilePic": profilePic
        ]
        print("📤 Sending message to \(targetId): \(trimmed)")
        socket?.emit("chat_message", payload)
        let mySenderId = socket?.sid ?? "me"
        appendMessage(
            ChatMessage(
                senderId: mySenderId,
                senderName: senderName,
                senderProfilePic: profilePic.isEmpty ? nil : profilePic,
                text: trimmed,
                isFromMe: true,
                timestamp: Date()
            )
        )
        #endif
    }

    func sendTyping(to targetId: String) {
        #if canImport(SocketIO)
        socket?.emit("typing", ["to": targetId])
        #endif
    }

    func sendStoppedTyping(to targetId: String) {
        #if canImport(SocketIO)
        socket?.emit("stopped_typing", ["to": targetId])
        #endif
    }

    func sendProfileViewState(isActive: Bool) {
        #if canImport(SocketIO)
        guard let targetId = activePartnerId, !targetId.isEmpty else {
            localProfileViewStateIsActive = false
            return
        }
        guard localProfileViewStateIsActive != isActive else { return }
        localProfileViewStateIsActive = isActive
        socket?.emit("profile_view_state", [
            "to": targetId,
            "state": isActive ? "active" : "inactive"
        ])
        #endif
    }

    func reportUser(reportedId: String) {
        #if canImport(SocketIO)
        socket?.emit("report_user", [
            "reportedId": reportedId,
            "screenshot": ""
        ])
        #endif
    }

    func reportPartner(_ partner: MatchedPartner, shouldBlock: Bool = false) {
        #if canImport(SocketIO)
        guard let base64Screenshot = imageToBase64JPEG(partner.screenshot, compressionQuality: 0.5) else {
            print("⚠️ Report aborted: screenshot Base64 conversion failed for partner \(partner.id)")
            return
        }

        if base64Screenshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ Report aborted: screenshot Base64 is empty for partner \(partner.id)")
            return
        }

        let payload: [String: Any] = [
            "reportedId": partner.id,
            "screenshot": base64Screenshot
        ]
        socket?.emit("report_user", payload)
        print("📤 report_user emitted with payload keys: \(payload.keys.sorted())")
        #endif

        if shouldBlock {
            print("⛔️ Partner blocked locally: \(partner.id)")
        }

        if activePartnerId == partner.id {
            nextUser()
        }
    }

    func nextUser() {
        saveCurrentPartnerToRecentHistory()
        #if canImport(SocketIO)
        socket?.emit("next_user")
        #endif
        activePartnerId = nil
        activeMatch = nil
        sessionStage = .idle
        activeCallMode = nil
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        outgoingPrivateCallTargetId = nil
        incomingPrivateCall = nil
        outgoingPrivateCallPhase = nil
        outgoingCallMode = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
    }

    func endCall() {
        saveCurrentPartnerToRecentHistory()
        #if canImport(SocketIO)
        socket?.emit("end_call")
        socket?.emit("stop_search")
        #endif
        webRTCManager.endSession()
        activePartnerId = nil
        activeMatch = nil
        sessionStage = .idle
        activeCallMode = nil
        isSearching = false
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        outgoingPrivateCallTargetId = nil
        incomingPrivateCall = nil
        outgoingPrivateCallPhase = nil
        outgoingCallMode = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
    }

    func consumeStorePresentationRequest() {
        storePresentationRequestID = nil
    }

    func resetGuestMatchProgress() {
        guestMatchCount = 0
    }

    func requestPrivateCall(targetUserId: String) {
        #if canImport(SocketIO)
        guard appUserStore.isLoggedIn else {
            appState.showTimedToast("Ozel arama icin giris yapman gerekiyor.")
            return
        }
        guard !targetUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let payload: [String: Any] = [
            "targetUserId": targetUserId,
            "mode": CallRequestMode.video.rawValue
        ]
        print("DEBUG: Calling target with DB ID: \(targetUserId)")
        print("Socket: Emitting private_call_request for \(targetUserId)")
        print("📞 Emitting private_call_request: \(payload)")
        outgoingPrivateCallTargetId = targetUserId
        outgoingPrivateCallPhase = .checking
        outgoingCallMode = .video
        privateCallPhaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.outgoingPrivateCallTargetId == targetUserId else { return }
            self.outgoingPrivateCallPhase = .calling
        }
        privateCallPhaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
        socket?.emit("private_call_request", payload)
        #endif
    }

    func requestVoiceCall(partnerId: String) {
        #if canImport(SocketIO)
        let trimmedPartnerId = partnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPartnerId.isEmpty else { return }
        let payload: [String: Any] = ["targetId": trimmedPartnerId]
        outgoingPrivateCallTargetId = trimmedPartnerId
        outgoingPrivateCallPhase = .checking
        outgoingCallMode = .voice
        privateCallPhaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.outgoingPrivateCallTargetId == trimmedPartnerId, self.outgoingCallMode == .voice else { return }
            self.outgoingPrivateCallPhase = .calling
        }
        privateCallPhaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
        socket?.emit("voice_request", payload)
        #endif
    }

    func requestVideoCall(partnerId: String) {
        #if canImport(SocketIO)
        let trimmedPartnerId = partnerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPartnerId.isEmpty else { return }
        guard sessionStage == .textChat else { return }
        let payload: [String: Any] = ["targetId": trimmedPartnerId]
        outgoingPrivateCallTargetId = trimmedPartnerId
        outgoingPrivateCallPhase = .checking
        outgoingCallMode = .video
        privateCallPhaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.outgoingPrivateCallTargetId == trimmedPartnerId,
                  self.outgoingCallMode == .video else { return }
            self.outgoingPrivateCallPhase = .calling
        }
        privateCallPhaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
        socket?.emit("video_request", payload)
        #endif
    }

    func cancelPrivateCall(targetId: String) {
        let trimmedTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTargetId.isEmpty else {
            print("DEBUG: cancelPrivateCall aborted because targetId is empty")
            DispatchQueue.main.async {
                self.clearOutgoingPrivateCallState()
            }
            return
        }

        #if canImport(SocketIO)
        guard let socket else {
            print("DEBUG: cancelPrivateCall aborted because socket is nil")
            DispatchQueue.main.async {
                self.clearOutgoingPrivateCallState()
            }
            return
        }

        let payload: [String: Any] = ["targetId": trimmedTargetId]
        if outgoingCallMode == .voice {
            socket.emit("cancel_voice_call", payload)
        } else if activeMatch?.partnerId == trimmedTargetId {
            socket.emit("cancel_video_call", payload)
        } else {
            print("DEBUG: ATTEMPTING EMIT cancel_private_call to \(trimmedTargetId)")
            print("DEBUG: Sending cancel for \(trimmedTargetId)")
            print("📴 Emitting cancel_private_call: \(payload)")
            socket.emitWithAck("cancel_private_call", payload).timingOut(after: 3) { data in
                print("DEBUG: Server acknowledged the cancel event with items: \(data)")
            }
        }
        #endif

        DispatchQueue.main.async {
            self.clearOutgoingPrivateCallState()
        }
    }

    func acceptPrivateCall(callerId: String) {
        #if canImport(SocketIO)
        let payload: [String: Any] = ["callerId": callerId]
        if incomingPrivateCall?.mode == .voice {
            socket?.emit("voice_accepted", payload)
        } else if activePartnerId == callerId || activeMatch?.partnerId == callerId {
            socket?.emit("video_accepted", payload)
        } else {
            print("✅ Emitting private_call_accepted: \(payload)")
            socket?.emit("private_call_accepted", payload)
        }
        #endif
        incomingPrivateCall = nil
    }

    func rejectPrivateCall(callerId: String) {
        #if canImport(SocketIO)
        let payload: [String: Any] = ["callerId": callerId]
        if incomingPrivateCall?.mode == .voice {
            socket?.emit("voice_rejected", payload)
        } else if activePartnerId == callerId || activeMatch?.partnerId == callerId {
            socket?.emit("video_rejected", payload)
        } else {
            print("❌ Emitting private_call_rejected: \(payload)")
            socket?.emit("private_call_rejected", payload)
        }
        #endif
        incomingPrivateCall = nil
    }

    func endVoiceCall() {
        #if canImport(SocketIO)
        if let activePartnerId {
            socket?.emit("voice_ended", ["targetId": activePartnerId])
        }
        #endif
        webRTCManager.endSession()
        activeCallMode = nil
        if activePartnerId != nil {
            sessionStage = .textChat
        } else {
            sessionStage = .idle
        }
    }

    func endVideoCall() {
        #if canImport(SocketIO)
        if let activePartnerId {
            socket?.emit("video_ended", ["targetId": activePartnerId])
        }
        #endif
        webRTCManager.endSession()
        activeCallMode = nil
        if activePartnerId != nil {
            sessionStage = .textChat
        } else {
            sessionStage = .idle
        }
    }

    func clearPrivateCallNotice() {
        privateCallNotice = nil
    }

    func requestUserStatus(for userIds: [String]) {
        let normalizedIds = Set(
            userIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalizedIds.isEmpty else { return }

        observedStatusUserIds.formUnion(normalizedIds)
        let payload = Array(normalizedIds)

        #if canImport(SocketIO)
        print("🟢 Requesting user status for ids: \(payload)")
        socket?.emit("get_user_status", payload)
        #endif
    }

    private func clearOutgoingPrivateCallState() {
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
        outgoingCallMode = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
    }

    private func markObservedUsersOffline() {
        guard !observedStatusUserIds.isEmpty else { return }
        userOnlineStates = Dictionary(uniqueKeysWithValues: observedStatusUserIds.map { ($0, .offline) })
    }

    private func dismissIncomingPrivateCall() {
        incomingPrivateCall = nil
    }

    private func handleIncomingPrivateCallCancelled(eventName: String, items: [Any]) {
        DispatchQueue.main.async {
            print("DEBUG: Received \(eventName) with items: \(items)")
            let payload = items.first as? [String: Any]
            let callerId = (payload?["callerId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetId =
                (payload?["targetId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (payload?["targetUserId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let activeIncomingCall = self.incomingPrivateCall {
                let matchesCaller = callerId == nil || callerId == activeIncomingCall.callerId
                let matchesTarget = targetId == nil || targetId == self.appUserStore.currentUser?.id
                guard matchesCaller && matchesTarget else {
                    print("DEBUG: Ignoring \(eventName) because payload does not match active incoming call.")
                    return
                }
            }

            self.incomingPrivateCall = nil
            self.appState.showTimedToast("Arama iptal edildi")
        }
    }

    private func applyUserStatusSnapshot(from items: [Any]) {
        DispatchQueue.main.async {
            let dictionaries: [[String: Any]]
            if let array = items.first as? [[String: Any]] {
                dictionaries = array
            } else if let container = items.first as? [String: Any],
                      let array = container["users"] as? [[String: Any]] ?? container["data"] as? [[String: Any]] {
                dictionaries = array
            } else {
                print("DEBUG: Unsupported user status snapshot payload: \(items)")
                return
            }

            var updatedStates = self.userOnlineStates
            for dictionary in dictionaries {
                guard let userId = (dictionary["userId"] as? String) ?? (dictionary["id"] as? String) else { continue }
                let status = self.parseUserStatus(from: dictionary)
                updatedStates[userId] = status
                self.observedStatusUserIds.insert(userId)
            }
            self.userOnlineStates = updatedStates
        }
    }

    private func applyUserStatusChange(from items: [Any]) {
        DispatchQueue.main.async {
            guard let dictionary = items.first as? [String: Any] else {
                print("DEBUG: Unsupported user_status_changed payload: \(items)")
                return
            }
            guard let userId = (dictionary["userId"] as? String) ?? (dictionary["id"] as? String) else { return }
            let status = self.parseUserStatus(from: dictionary)
            self.observedStatusUserIds.insert(userId)
            self.userOnlineStates[userId] = status
        }
    }

    private func parseUserStatus(from dictionary: [String: Any]) -> UserStatus {
        if let statusString = dictionary["status"] as? String {
            return UserStatus(rawServerValue: statusString)
        }
        if let isBusy = dictionary["isBusy"] as? Bool, isBusy {
            return .busy
        }
        let isOnline = (dictionary["isOnline"] as? Bool) ?? (dictionary["online"] as? Bool) ?? false
        return UserStatus(isOnline: isOnline)
    }

    private func schedulePrivateCallNotice(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.privateCallNotice = PrivateCallNotice(message: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if self.privateCallNotice?.message == message {
                    self.privateCallNotice = nil
                }
            }
        }
    }

    private func showGlobalPrivateCallAlert(_ alert: PrivateCallAlertKind) {
        DispatchQueue.main.async {
            self.outgoingPrivateCallPhase = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil

            switch alert {
            case .targetBusy:
                self.appState.showGlobalAlert(
                    title: "Kullanici Mesgul",
                    message: "Aradiginiz kisi su anda baska bir gorusmede. Lutfen daha sonra tekrar deneyin.",
                    context: .targetBusy
                )
            case .insufficientGems:
                self.appState.showGlobalAlert(
                    title: "Yetersiz Gem",
                    message: "Ozel arama yapabilmek icin 50 Gem gereklidir. Magazaya gidip Gem almak ister misiniz?",
                    context: .insufficientGems
                )
            }
        }
    }

    private func showPrivateCallToast(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.appState.showTimedToast(message)
        }
    }

    private func lockFindPartnerEmit(for duration: TimeInterval) {
        print("🔒 find_partner lock acquired (\(duration)s)")
        isFindPartnerLocked = true
        findPartnerUnlockWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.unlockFindPartnerEmit(reason: "timeout")
        }
        findPartnerUnlockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func unlockFindPartnerEmit(reason: String) {
        findPartnerUnlockWorkItem?.cancel()
        findPartnerUnlockWorkItem = nil
        if isFindPartnerLocked {
            print("🔓 find_partner lock released (\(reason))")
        }
        isFindPartnerLocked = false
    }

    private func handleFindPartnerAck(_ data: [Any]) {
        DispatchQueue.main.async {
            print("DEBUG: find_partner callback payload: \(data)")
            self.autoRematchWorkItem?.cancel()
            self.autoRematchWorkItem = nil

            guard let payload = self.extractAckDictionary(from: data) else {
                self.isAwaitingSearchStart = false
                self.unlockFindPartnerEmit(reason: "find_partner_ack_timeout_or_invalid")
                return
            }

            let isOK = (payload["ok"] as? Bool) ?? false
            let status = (payload["status"] as? String)?.lowercased()
            let message = (payload["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let code = (payload["code"] as? String)?.uppercased()

            self.isAwaitingSearchStart = false
            self.unlockFindPartnerEmit(reason: "find_partner_ack")

            guard isOK else {
                self.isSearching = false
                self.handleFindPartnerFailure(code: code, message: message)
                return
            }

            switch status {
            case "searching":
                self.isSearching = true
                print("DEBUG: find_partner ack confirmed queued searching state.")
            case "matched":
                self.isSearching = false
                print("DEBUG: find_partner ack reported immediate match. Waiting for partner_found.")
            default:
                print("DEBUG: find_partner ack returned unknown success status: \(status ?? "nil")")
            }
        }
    }

    private func extractAckDictionary(from data: [Any]) -> [String: Any]? {
        if let dictionary = data.first as? [String: Any] {
            return dictionary
        }

        if let first = data.first as? String,
           first.lowercased().contains("no ack") {
            return nil
        }

        return nil
    }

    private func handleFindPartnerFailure(code: String?, message: String?) {
        let resolvedMessage = message ?? "Eslesme baslatilamadi."
        print("DEBUG: find_partner failed with code=\(code ?? "nil"), message=\(resolvedMessage)")

        switch code {
        case "INSUFFICIENT_GEMS":
            storePresentationMessage = resolvedMessage
            storePresentationRequestID = UUID()
        case "AUTH_REQUIRED":
            appUserStore.handleUnauthorized()
        default:
            appState.showTimedToast(resolvedMessage)
        }
    }

    private func cleanupCurrentPeer(reason: String) {
        print("🧹 Cleaning up current peer. reason=\(reason)")
        webRTCManager.endSession()
        sessionStage = .idle
        activeCallMode = nil
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        matchedAt = nil
        messages.removeAll()
        isPartnerTyping = false
        isPartnerViewingProfile = false
        localProfileViewStateIsActive = false
        partnerName = nil
        partnerAvatarURL = nil
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
        outgoingCallMode = nil
        incomingPrivateCall = nil
        privateCallNotice = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
    }

    private func scheduleAutoRematchIfNeeded(trigger: String, delay: TimeInterval = 0.8) {
        autoRematchWorkItem?.cancel()
        guard currentSearchPayload != nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.activePartnerId == nil else { return }
            guard self.isAwaitingSearchStart else {
                print("DEBUG: Auto rematch skipped after \(trigger) because search state is already confirmed.")
                return
            }
            guard !self.isFindPartnerLocked else {
                print("DEBUG: Auto rematch skipped after \(trigger) because find_partner is still locked.")
                return
            }

            print("📤 Emitting auto find_partner after \(trigger)")
            self.findPartner()
        }

        autoRematchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func applyGemBalanceUpdateOnce(_ gems: Int, source: String) {
        let now = Date()
        if let lastGemBalanceValue,
           let lastGemBalanceUpdateAt,
           lastGemBalanceValue == gems,
           now.timeIntervalSince(lastGemBalanceUpdateAt) < 0.5 {
            print("🟡 Ignored duplicate gem update (\(source)): \(gems)")
            return
        }

        lastGemBalanceValue = gems
        lastGemBalanceUpdateAt = now
        appUserStore.updateGemBalance(gems)
        print("💎 Gem balance updated (\(source)): \(gems)")
    }

    #if canImport(SocketIO)
    private func registerHandlers(for socket: SocketIOClient) {
        socket.onAny { event in
            print("DEBUG: Incoming Socket Event: \(event.event) with items: \(String(describing: event.items))")
        }

        socket.on(clientEvent: .connect) { _, _ in
            print("✅ Socket connected. status=\(socket.status)")
            self.myStatus = .online
            if !self.observedStatusUserIds.isEmpty {
                self.requestUserStatus(for: Array(self.observedStatusUserIds))
            }
        }

        socket.on(clientEvent: .disconnect) { data, _ in
            print("❌ Socket disconnected: \(data)")
            self.myStatus = .offline
            self.markObservedUsersOffline()
        }

        socket.on(clientEvent: .error) { data, _ in
            print("🛑 Socket error event: \(data)")
            self.handleSocketAuthenticationFailureIfNeeded(from: data)
        }

        socket.on("error") { data, _ in
            print("🚨 Server Error: \(data)")
            self.handleSocketAuthenticationFailureIfNeeded(from: data)
        }

        socket.on("connection_refused") { data, _ in
            print("🚫 Connection Refused: \(data)")
            self.handleSocketAuthenticationFailureIfNeeded(from: data)
        }

        socket.on("connect_error") { data, _ in
            print("🚫 Connect Error: \(data)")
            self.handleSocketAuthenticationFailureIfNeeded(from: data)
        }

        socket.on("partner_online") { data, _ in
            guard let dictionary = data.first as? [String: Any] else { return }
            let userId = (dictionary["userId"] as? String) ?? ""
            let name = (dictionary["name"] as? String) ?? "Biri"
            guard !userId.isEmpty else { return }
            Task { @MainActor in
                OnlineNotificationCenter.shared.showOnlineBanner(userId: userId, name: name)
            }
        }

        socket.on("user_statuses") { [weak self] data, _ in
            print("DEBUG: Received status response: \(data)")
            self?.applyUserStatusSnapshot(from: data)
        }

        socket.on("user_status_response") { [weak self] data, _ in
            print("DEBUG: Received status response: \(data)")
            self?.applyUserStatusSnapshot(from: data)
        }

        socket.on("user_status_changed") { [weak self] data, _ in
            self?.applyUserStatusChange(from: data)
        }

        socket.on("search_started") { [weak self] data, _ in
            guard let self else { return }
            print("DEBUG: search_started received: \(data)")
            DispatchQueue.main.async {
                let payload = data.first as? [String: Any]
                let status = (payload?["status"] as? String)?.lowercased()
                let autoResumed = (payload?["autoResumed"] as? Bool) ?? false
                guard status == nil || status == "searching" else { return }
                self.autoRematchWorkItem?.cancel()
                self.autoRematchWorkItem = nil
                self.isAwaitingSearchStart = false
                self.isSearching = true
                print("DEBUG: search_started applied. autoResumed=\(autoResumed)")
                self.unlockFindPartnerEmit(reason: autoResumed ? "search_started_auto_resumed" : "search_started")
            }
        }

        socket.on("error_message") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            print("DEBUG: error_message received: \(dictionary)")
            self.isAwaitingSearchStart = false
            self.isSearching = false
            self.unlockFindPartnerEmit(reason: "error_message")
            let type = (dictionary["type"] as? String) ?? ""
            if type == "INSUFFICIENT_GEMS" {
                let message = (dictionary["message"] as? String)
                    ?? "Filtre kullanmak için yeterli taşın yok! Mağazadan hemen yükleyebilirsin."
                self.storePresentationMessage = message
                self.storePresentationRequestID = UUID()
                self.stopSearch()
            } else if let message = dictionary["message"] as? String, !message.isEmpty {
                self.appState.showTimedToast(message)
            }
        }

        socket.on("update_my_likes") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let gems =
                (dictionary["gems"] as? Int)
                ?? (dictionary["balance"] as? Int)
                ?? (dictionary["tickets"] as? Int)
            if let gems {
                self.applyGemBalanceUpdateOnce(gems, source: "update_my_likes")
            }
        }

        socket.on("update_my_gems") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let gems =
                (dictionary["gems"] as? Int)
                ?? (dictionary["balance"] as? Int)
                ?? (dictionary["tickets"] as? Int)
            if let gems {
                self.applyGemBalanceUpdateOnce(gems, source: "update_my_gems")
            }
        }

        socket.on("gems_updated") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let gems =
                (dictionary["gems"] as? Int)
                ?? (dictionary["newBalance"] as? Int)
                ?? (dictionary["balance"] as? Int)
                ?? (dictionary["tickets"] as? Int)
            if let gems {
                self.applyGemBalanceUpdateOnce(gems, source: "gems_updated")
            }
        }

        socket.on("partner_found") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any],
                  let payload = self.makePartnerPayload(from: dictionary) else { return }
            print("🎉 partner_found received: \(dictionary)")
            if payload.privateCall {
                print("📞 partner_found flagged as private call")
            }
            self.saveCurrentPartnerToRecentHistory()
            self.partner = payload
            self.activePartnerId = payload.partnerId
            self.activeMatch = payload
            self.matchedAt = Date()
            self.activeCallMode = nil
            self.isPartnerViewingProfile = false
            self.localProfileViewStateIsActive = false
            self.partnerName = (dictionary["partnerName"] as? String)
                ?? payload.partnerName
            self.partnerAvatarURL = (dictionary["partnerAvatar"] as? String)
                ?? (dictionary["partnerAvatarURL"] as? String)
                ?? payload.partnerAvatarURL
                ?? payload.partnerProfilePic
                ?? payload.partnerAvatar
            self.autoRematchWorkItem?.cancel()
            self.autoRematchWorkItem = nil
            self.isSearching = false
            self.isAwaitingSearchStart = false
            self.unlockFindPartnerEmit(reason: "partner_found")
            self.messages.removeAll()
            self.incomingPrivateCall = nil
            self.privateCallNotice = nil
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil

            if !self.appUserStore.isLoggedIn {
                self.guestMatchCount += 1
            }

            if payload.privateCall {
                let resolvedMode = payload.callMode ?? .video
                self.activeCallMode = resolvedMode
                switch resolvedMode {
                case .video:
                    self.sessionStage = .videoCall
                    self.webRTCManager.startSession(
                        partnerId: payload.partnerId,
                        isInitiator: payload.initiator,
                        audioOnly: false
                    )
                case .voice:
                    self.sessionStage = .voiceCall
                    self.webRTCManager.startSession(
                        partnerId: payload.partnerId,
                        isInitiator: payload.initiator,
                        audioOnly: true
                    )
                }
            } else {
                self.sessionStage = .textChat
                self.webRTCManager.endSession()
            }

            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
        }

        socket.on("signal") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let senderId = (dictionary["from"] as? String) ?? "unknown"
            guard let signalPayload = dictionary["signal"] as? [String: Any] else { return }
            let signalType = (signalPayload["type"] as? String) ?? "unknown"
            print("📨 signal received from \(senderId), type: \(signalType)")

            switch signalType {
            case "offer":
                if let sdp = signalPayload["sdp"] as? String {
                    self.webRTCManager.handleRemoteOffer(sdp: sdp)
                }
            case "answer":
                if let sdp = signalPayload["sdp"] as? String {
                    self.webRTCManager.handleRemoteAnswer(sdp: sdp)
                }
            case "candidate":
                if let candidateData = signalPayload["candidate"] as? [String: Any] {
                    self.webRTCManager.addIceCandidate(candidateData: candidateData)
                } else {
                    self.webRTCManager.addIceCandidate(candidateData: signalPayload)
                }
            default:
                self.webRTCManager.handleIncomingSignal(signalPayload, from: senderId)
            }

            if senderId != "unknown" {
                self.activePartnerId = senderId
            }
        }

        socket.on("chat_message") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let senderId = (dictionary["senderId"] as? String) ?? "unknown"
            let text = (dictionary["text"] as? String) ?? ""
            let senderName = dictionary["senderName"] as? String
            let profilePic = dictionary["profilePic"] as? String
            let timestamp = self.parseMessageTimestamp(dictionary["timestamp"])
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            print("📥 Received message: \(text)")
            self.appendMessage(
                ChatMessage(
                    senderId: senderId,
                    senderName: senderName,
                    senderProfilePic: profilePic,
                    text: text,
                    isFromMe: false,
                    timestamp: timestamp
                )
            )
            if senderId != (socket.sid ?? "") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        socket.on("partner_typing") { [weak self] _, _ in
            self?.isPartnerTyping = true
        }

        socket.on("partner_stopped_typing") { [weak self] _, _ in
            self?.isPartnerTyping = false
        }

        socket.on("partner_profile_view_state") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let senderId = (dictionary["from"] as? String) ?? ""
            let state = ((dictionary["state"] as? String) ?? "").lowercased()
            guard senderId == self.activePartnerId else { return }
            self.isPartnerViewingProfile = state == "active"
        }

        socket.on("candidate") { data, _ in
            print("🧊 candidate received: \(data)")
            if let dictionary = data.first as? [String: Any] {
                WebRTCManager.shared.addIceCandidate(candidateData: dictionary)
            }
        }

        socket.on("receive_like") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            if let newLikes = dictionary["newLikes"] as? Int {
                self.totalReceivedLikes = newLikes
            }
            self.incomingLikeBurstID = UUID()
        }

        socket.on("partner_left_auto_next") { [weak self] _, _ in
            guard let self else { return }
            print("↪️ partner_left_auto_next received. Re-entering queue...")
            self.saveCurrentPartnerToRecentHistory()
            self.cleanupCurrentPeer(reason: "partner_left_auto_next")
            self.isSearching = false
            self.isSearching = true
            self.isAwaitingSearchStart = true
            self.unlockFindPartnerEmit(reason: "partner_left_auto_next_cleanup")
            self.scheduleAutoRematchIfNeeded(trigger: "partner_left_auto_next")
        }

        socket.on("partner_left") { [weak self] data, _ in
            print("👋 partner_left received: \(data)")
            self?.saveCurrentPartnerToRecentHistory()
            self?.cleanupCurrentPeer(reason: "partner_left")
            self?.isSearching = false
            self?.isAwaitingSearchStart = false
            self?.unlockFindPartnerEmit(reason: "partner_left")
        }

        socket.on("end_call") { [weak self] data, _ in
            print("📴 end_call received: \(data)")
            self?.saveCurrentPartnerToRecentHistory()
            self?.cleanupCurrentPeer(reason: "end_call")
            self?.isSearching = false
            self?.isAwaitingSearchStart = false
            self?.unlockFindPartnerEmit(reason: "end_call")
        }

        socket.on("incoming_private_call") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            guard self.myStatus != .offline else {
                print("DEBUG: Ignoring incoming_private_call because local status is offline.")
                return
            }
            let callerId = (dictionary["callerId"] as? String) ?? ""
            guard !callerId.isEmpty else { return }
            let callerName = (dictionary["callerName"] as? String) ?? "Biri"
            let avatar = (dictionary["callerAvatar"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let mode = CallRequestMode(rawValue: (dictionary["mode"] as? String) ?? "") ?? .video
            self.incomingPrivateCall = IncomingPrivateCall(
                callerId: callerId,
                callerName: callerName,
                callerAvatarURL: avatar?.isEmpty == true ? nil : avatar,
                mode: mode
            )
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
        }

        socket.on("incoming_voice_call") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            guard self.myStatus != .offline else { return }
            let callerId = (dictionary["callerId"] as? String) ?? ""
            guard !callerId.isEmpty else { return }
            let callerName = (dictionary["callerName"] as? String) ?? "Biri"
            let avatar = (dictionary["callerAvatar"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.incomingPrivateCall = IncomingPrivateCall(
                callerId: callerId,
                callerName: callerName,
                callerAvatarURL: avatar?.isEmpty == true ? nil : avatar,
                mode: .voice
            )
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
        }

        socket.on("incoming_video_call") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            guard self.myStatus != .offline else { return }
            let callerId = (dictionary["callerId"] as? String) ?? ""
            guard !callerId.isEmpty else { return }
            let callerName = (dictionary["callerName"] as? String) ?? "Biri"
            let avatar = (dictionary["callerAvatar"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.incomingPrivateCall = IncomingPrivateCall(
                callerId: callerId,
                callerName: callerName,
                callerAvatarURL: avatar?.isEmpty == true ? nil : avatar,
                mode: .video
            )
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
        }

        socket.on("private_call_cancelled") { [weak self] data, _ in
            self?.handleIncomingPrivateCallCancelled(
                eventName: "private_call_cancelled",
                items: data
            )
        }

        socket.on("call_cancelled") { [weak self] data, _ in
            self?.handleIncomingPrivateCallCancelled(
                eventName: "call_cancelled",
                items: data
            )
        }

        socket.on("cancel_private_call") { [weak self] data, _ in
            self?.handleIncomingPrivateCallCancelled(
                eventName: "cancel_private_call",
                items: data
            )
        }

        socket.on("voice_call_cancelled") { [weak self] data, _ in
            self?.handleIncomingPrivateCallCancelled(
                eventName: "voice_call_cancelled",
                items: data
            )
        }

        socket.on("video_call_cancelled") { [weak self] data, _ in
            self?.handleIncomingPrivateCallCancelled(
                eventName: "video_call_cancelled",
                items: data
            )
        }

        socket.on("call_rejected") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.outgoingCallMode = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Arama reddedildi")
            }
        }

        socket.on("voice_rejected") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.outgoingCallMode = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Sesli arama reddedildi")
            }
        }

        socket.on("video_rejected") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.outgoingCallMode = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Video daveti reddedildi")
            }
        }

        socket.on("target_unavailable") { [weak self] _, _ in
            self?.outgoingPrivateCallTargetId = nil
            self?.outgoingPrivateCallPhase = nil
            self?.outgoingCallMode = nil
            self?.privateCallPhaseWorkItem?.cancel()
            self?.privateCallPhaseWorkItem = nil
            print("DEBUG: Server says target is unavailable. Check if the ID is correct and if the user is online.")
            self?.schedulePrivateCallNotice("User is busy or offline.")
        }

        socket.on("target_is_busy") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.outgoingCallMode = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Kullanici su an mesgul. Lutfen daha sonra tekrar deneyin.")
            }
        }

        socket.on("insufficient_gems") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.outgoingCallMode = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Yetersiz Gem. Ozel arama icin 50 Gem gerekli.")
            }
        }

        socket.on("voice_call_started") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let partnerId = (dictionary["partnerId"] as? String) ?? self.activePartnerId ?? ""
            guard !partnerId.isEmpty else { return }
            let initiator = (dictionary["initiator"] as? Bool) ?? false
            self.activePartnerId = partnerId
            self.activeCallMode = .voice
            self.sessionStage = .voiceCall
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
            self.webRTCManager.startSession(partnerId: partnerId, isInitiator: initiator, audioOnly: true)
            self.showPrivateCallToast("Sesli gorusme basladi")
        }

        socket.on("video_call_started") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let partnerId = (dictionary["partnerId"] as? String) ?? self.activePartnerId ?? ""
            guard !partnerId.isEmpty else { return }
            let initiator = (dictionary["initiator"] as? Bool) ?? false
            self.activePartnerId = partnerId
            self.activeCallMode = .video
            self.sessionStage = .videoCall
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.outgoingCallMode = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
            self.webRTCManager.startSession(partnerId: partnerId, isInitiator: initiator, audioOnly: false)
            self.showPrivateCallToast("Video gorusme basladi")
        }

        socket.on("voice_call_ended") { [weak self] _, _ in
            guard let self else { return }
            self.webRTCManager.endSession()
            self.activeCallMode = nil
            if self.activePartnerId != nil {
                self.sessionStage = .textChat
                self.showPrivateCallToast("Sesli gorusme bitti")
            } else {
                self.sessionStage = .idle
            }
        }

        socket.on("video_call_ended") { [weak self] _, _ in
            guard let self else { return }
            self.webRTCManager.endSession()
            self.activeCallMode = nil
            if self.activePartnerId != nil {
                self.sessionStage = .textChat
                self.showPrivateCallToast("Video gorusme bitti")
            } else {
                self.sessionStage = .idle
            }
        }

        socket.on("account_banned") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let reason = (dictionary["reason"] as? String) ?? "Topluluk kurallari ihlal edildi."
            let expireAt = Self.parseISODate(dictionary["expireAt"])
            self.banEvent = BanEvent(reason: reason, expireAt: expireAt)
            self.isSearching = false
            self.activePartnerId = nil
            self.webRTCManager.endSession()
            self.disconnect()
        }
    }

    private func emitSignal(_ signal: [String: Any]) {
        guard let partnerId = activePartnerId else {
            print("⚠️ Cannot emit signal: activePartnerId is nil")
            return
        }
        let payload: [String: Any] = [
            "to": partnerId,
            "signal": signal
        ]
        print("📡 Emitting WebRTC signal to \(partnerId): \(signal)")
        socket?.emit("signal", payload)
    }
    #endif

    private func decodePayload<T: Decodable>(from dictionary: [String: Any]) -> T? {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func parseISODate(_ rawValue: Any?) -> Date? {
        guard let rawString = rawValue as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: rawString)
    }

    private func makePartnerPayload(from dictionary: [String: Any]) -> PartnerFoundPayload? {
        guard let partnerId = dictionary["partnerId"] as? String else { return nil }

        let nestedPartner = (dictionary["partner"] as? [String: Any])
            ?? (dictionary["partnerUser"] as? [String: Any])
            ?? (dictionary["user"] as? [String: Any])
            ?? (dictionary["partnerInfo"] as? [String: Any])

        let partnerName = (dictionary["partnerName"] as? String)
            ?? (dictionary["partner_name"] as? String)
            ?? (dictionary["name"] as? String)
            ?? (nestedPartner?["partnerName"] as? String)
            ?? (nestedPartner?["name"] as? String)

        let avatarCandidates: [String?] = [
            dictionary["partnerAvatarURL"] as? String,
            dictionary["partnerAvatarUrl"] as? String,
            dictionary["partner_avatar_url"] as? String,
            dictionary["avatarUrl"] as? String,
            nestedPartner?["partnerAvatarURL"] as? String,
            nestedPartner?["partnerAvatarUrl"] as? String,
            nestedPartner?["avatarUrl"] as? String,
            dictionary["partnerProfilePic"] as? String,
            dictionary["profilePic"] as? String,
            dictionary["avatar"] as? String,
            dictionary["partnerAvatar"] as? String,
            nestedPartner?["profilePic"] as? String,
            nestedPartner?["avatar"] as? String,
            nestedPartner?["photo"] as? String,
            nestedPartner?["picture"] as? String
        ]
        let partnerAvatarURL = avatarCandidates.compactMap { value -> String? in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }.first

        let trustScore = (dictionary["partnerTrustScore"] as? Int)
            ?? (nestedPartner?["trustScore"] as? Int)

        let partnerInterests =
            (dictionary["partnerInterests"] as? [String])
            ?? (nestedPartner?["interests"] as? [String])
            ?? []

        let partnerLookingFor =
            (dictionary["partnerLookingFor"] as? [String])
            ?? (nestedPartner?["lookingFor"] as? [String])
            ?? []

        let partnerPhotos =
            (dictionary["partnerPhotos"] as? [String])
            ?? (nestedPartner?["photos"] as? [String])
            ?? []

        let partnerLanguages =
            (dictionary["partnerLanguages"] as? [String])
            ?? (nestedPartner?["languages"] as? [String])
            ?? []

        return PartnerFoundPayload(
            partnerId: partnerId,
            initiator: (dictionary["initiator"] as? Bool) ?? false,
            country: (dictionary["country"] as? String) ?? "UN",
            partnerGender: (dictionary["partnerGender"] as? String) ?? "all",
            partnerLikes: (dictionary["partnerLikes"] as? Int) ?? 0,
            partnerTrustScore: trustScore,
            privateCall: (dictionary["privateCall"] as? Bool) ?? false,
            partnerName: partnerName,
            partnerAvatarURL: partnerAvatarURL,
            partnerProfilePic: partnerAvatarURL,
            partnerAvatar: (dictionary["partnerAvatar"] as? String) ?? (nestedPartner?["avatar"] as? String),
            partnerAge: (dictionary["partnerAge"] as? Int) ?? (nestedPartner?["age"] as? Int),
            partnerWork: (dictionary["partnerWork"] as? String) ?? (nestedPartner?["work"] as? String),
            partnerEducation: (dictionary["partnerEducation"] as? String) ?? (nestedPartner?["education"] as? String),
            partnerBio: (dictionary["partnerBio"] as? String) ?? (nestedPartner?["bio"] as? String),
            partnerPhotos: partnerPhotos,
            partnerInterests: partnerInterests,
            partnerLookingFor: partnerLookingFor,
            partnerLanguages: partnerLanguages,
            callMode: CallRequestMode(rawValue: (dictionary["callMode"] as? String) ?? "")
        )
    }

    private func appendMessage(_ message: ChatMessage) {
        DispatchQueue.main.async {
            self.messages.append(message)
        }
    }

    private func parseMessageTimestamp(_ rawValue: Any?) -> Date {
        if let unix = rawValue as? TimeInterval {
            return Date(timeIntervalSince1970: unix > 10_000_000_000 ? unix / 1_000 : unix)
        }

        if let text = rawValue as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let unix = TimeInterval(trimmed) {
                return Date(timeIntervalSince1970: unix > 10_000_000_000 ? unix / 1_000 : unix)
            }

            let iso8601WithFractionalSeconds = ISO8601DateFormatter()
            iso8601WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = iso8601WithFractionalSeconds.date(from: trimmed) {
                return parsed
            }

            let iso8601 = ISO8601DateFormatter()
            if let parsed = iso8601.date(from: trimmed) {
                return parsed
            }
        }

        return Date()
    }

    private func saveCurrentPartnerToRecentHistory() {
        guard let activeMatch, let activePartnerId else { return }
        let screenshot = captureEvidenceScreenshot(partnerId: activePartnerId)
        let displayName = partnerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (displayName?.isEmpty == false ? displayName! : (activeMatch.partnerName ?? "Unknown"))
        let resolvedAvatar = partnerAvatarURL ?? activeMatch.partnerAvatarURL ?? activeMatch.partnerAvatar
        let entry = MatchedPartner(
            id: activePartnerId,
            name: resolvedName,
            avatarURL: resolvedAvatar,
            country: activeMatch.country,
            screenshot: screenshot
        )

        DispatchQueue.main.async {
            self.recentPartners.removeAll { $0.id == entry.id }
            self.recentPartners.insert(entry, at: 0)
            if self.recentPartners.count > 3 {
                self.recentPartners = Array(self.recentPartners.prefix(3))
            }
        }
    }

    private func captureEvidenceScreenshot(partnerId: String) -> UIImage {
        if let rendererSnapshot = RemoteVideoCaptureRegistry.shared.captureSnapshot(for: "remote-\(partnerId)") {
            return rendererSnapshot
        }

        guard
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first(where: { $0.isKeyWindow })
        else {
            return placeholderScreenshot()
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
    }

    private func imageToBase64JPEG(_ image: UIImage, compressionQuality: CGFloat = 0.5) -> String? {
        let maxDimension: CGFloat = 640
        let source = image.size.width > 0 && image.size.height > 0 ? image : placeholderScreenshot()
        let scaledImage = source.scaledTo(maxDimension: maxDimension)
        guard let jpegData = scaledImage.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    private func placeholderScreenshot() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func handleSocketAuthenticationFailureIfNeeded(from data: [Any]) {
        let message = data.compactMap { item -> String? in
            if let text = item as? String {
                return text
            }
            if let dictionary = item as? [String: Any] {
                return (dictionary["message"] as? String) ?? (dictionary["error"] as? String)
            }
            return nil
        }
        .joined(separator: " ")
        .lowercased()

        guard message.contains("unauthorized")
            || message.contains("auth")
            || message.contains("jwt")
            || message.contains("token")
        else {
            return
        }

        DispatchQueue.main.async {
            self.myStatus = .offline
            self.appUserStore.handleUnauthorized()
        }
    }
}

extension UIImage {
    func scaledTo(maxDimension: CGFloat) -> UIImage {
        let currentMax = max(size.width, size.height)
        guard currentMax > 0, currentMax > maxDimension else { return self }

        let scale = maxDimension / currentMax
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
