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
    private(set) var isSearching = false
    private(set) var totalReceivedLikes = 0
    var banEvent: BanEvent?
    var messages: [ChatMessage] = []
    var isPartnerTyping = false
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
    private(set) var userOnlineStates: [String: UserStatus] = [:]
    private(set) var myStatus: UserStatus = .offline
    private var currentSearchPayload: MatchSearchPayload?
    private var findPartnerUnlockWorkItem: DispatchWorkItem?
    private var privateCallPhaseWorkItem: DispatchWorkItem?
    private var lastGemBalanceValue: Int?
    private var lastGemBalanceUpdateAt: Date?
    private var observedStatusUserIds: Set<String> = []
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

    func connect(dbUserId: String?) {
        #if canImport(SocketIO)
        print("🔌 Socket connect requested. dbUserId: \(dbUserId ?? "guest")")
        disconnect()

        guard let url = URL(string: "https://videochat-1qxi.onrender.com") else { return }

        var config: SocketIOClientConfiguration = [
            .compress,
            .forceWebsockets(true),
            .reconnects(true),
            .log(true)
        ]

        if let dbUserId = dbUserId, !dbUserId.isEmpty {
            config.insert(.connectParams(["dbUserId": dbUserId]))
        }

        let manager = SocketManager(socketURL: url, config: config)
        let socket = manager.defaultSocket

        socketManager = manager
        self.socket = socket

        registerHandlers(for: socket)
        socket.connect()
        #endif
    }

    func disconnect() {
        #if canImport(SocketIO)
        if let dbUserId = appUserStore.currentUser?.id, !dbUserId.isEmpty {
            socket?.emit("manual_offline", ["dbUserId": dbUserId])
        }
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        socketManager = nil
        #endif
        myStatus = .offline
        webRTCManager.endSession()
        isSearching = false
        activePartnerId = nil
        activeMatch = nil
        partner = nil
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        recentPartners.removeAll()
        incomingPrivateCall = nil
        privateCallNotice = nil
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
        markObservedUsersOffline()
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
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

        guard !isFindPartnerLocked else {
            print("⏳ find_partner locked. Ignoring duplicate emit.")
            return
        }

        if socket.status != .connected {
            print("⚠️ Socket is not connected. Reconnecting before find_partner...")
            socket.connect()
            return
        }

        lockFindPartnerEmit(for: 2.0)

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
        socket.emit("find_partner", emitPayload)
        isSearching = true
        activePartnerId = nil
        activeMatch = nil
        partner = nil
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
        isSearching = true

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
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        isSearching = true

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

        let senderName = appUserStore.currentUser?.name ?? "Guest"
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
                isFromMe: true
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
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        outgoingPrivateCallTargetId = nil
        outgoingPrivateCallPhase = nil
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
        isSearching = false
        messages.removeAll()
        isPartnerTyping = false
        partnerName = nil
        partnerAvatarURL = nil
        outgoingPrivateCallTargetId = nil
        incomingPrivateCall = nil
        outgoingPrivateCallPhase = nil
        privateCallPhaseWorkItem?.cancel()
        privateCallPhaseWorkItem = nil
    }

    func consumeStorePresentationRequest() {
        storePresentationRequestID = nil
    }

    func requestPrivateCall(targetUserId: String) {
        #if canImport(SocketIO)
        guard !targetUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let myId = appUserStore.currentUser?.id, !myId.isEmpty else {
            print("DEBUG: private_call_request aborted because caller dbUserId is missing.")
            return
        }
        let payload: [String: Any] = [
            "targetUserId": targetUserId,
            "callerId": myId
        ]
        print("DEBUG: Calling target with DB ID: \(targetUserId)")
        print("DEBUG: Sending private_call_request - Caller: \(myId), Target: \(targetUserId)")
        print("Socket: Emitting private_call_request for \(targetUserId)")
        print("📞 Emitting private_call_request: \(payload)")
        outgoingPrivateCallTargetId = targetUserId
        outgoingPrivateCallPhase = .checking
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

        var payload: [String: Any] = ["targetId": trimmedTargetId]
        if let callerId = appUserStore.currentUser?.id, !callerId.isEmpty {
            payload["callerId"] = callerId
        }
        print("DEBUG: ATTEMPTING EMIT cancel_private_call to \(trimmedTargetId)")
        print("DEBUG: Sending cancel for \(trimmedTargetId)")
        print("📴 Emitting cancel_private_call: \(payload)")
        socket.emitWithAck("cancel_private_call", payload).timingOut(after: 3) { data in
            print("DEBUG: Server acknowledged the cancel event with items: \(data)")
        }
        #endif

        DispatchQueue.main.async {
            self.clearOutgoingPrivateCallState()
        }
    }

    func acceptPrivateCall(callerId: String) {
        #if canImport(SocketIO)
        let payload: [String: Any] = ["callerId": callerId]
        print("✅ Emitting private_call_accepted: \(payload)")
        socket?.emit("private_call_accepted", payload)
        #endif
        incomingPrivateCall = nil
    }

    func rejectPrivateCall(callerId: String) {
        #if canImport(SocketIO)
        let payload: [String: Any] = ["callerId": callerId]
        print("❌ Emitting private_call_rejected: \(payload)")
        socket?.emit("private_call_rejected", payload)
        #endif
        incomingPrivateCall = nil
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
            if let dbUserId = self.appUserStore.currentUser?.id, !dbUserId.isEmpty {
                let payload: [String: Any] = ["dbUserId": dbUserId]
                print("DEBUG: Emitting register_user with dbUserId: \(dbUserId)")
                socket.emit("register_user", payload)
            }
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
        }

        socket.on("error") { data, _ in
            print("🚨 Server Error: \(data)")
        }

        socket.on("connection_refused") { data, _ in
            print("🚫 Connection Refused: \(data)")
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

        socket.on("error_message") { [weak self] data, _ in
            guard let self, let dictionary = data.first as? [String: Any] else { return }
            let type = (dictionary["type"] as? String) ?? ""
            if type == "INSUFFICIENT_GEMS" {
                let message = (dictionary["message"] as? String)
                    ?? "Filtre kullanmak için yeterli taşın yok! Mağazadan hemen yükleyebilirsin."
                self.storePresentationMessage = message
                self.storePresentationRequestID = UUID()
                self.stopSearch()
                self.unlockFindPartnerEmit(reason: "insufficient_gems")
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
            self.partnerName = (dictionary["partnerName"] as? String)
                ?? payload.partnerName
            self.partnerAvatarURL = (dictionary["partnerAvatar"] as? String)
                ?? (dictionary["partnerAvatarURL"] as? String)
                ?? payload.partnerAvatarURL
                ?? payload.partnerProfilePic
                ?? payload.partnerAvatar
            self.isSearching = false
            self.unlockFindPartnerEmit(reason: "partner_found")
            self.messages.removeAll()
            self.incomingPrivateCall = nil
            self.privateCallNotice = nil
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil
            self.webRTCManager.startSession(
                partnerId: payload.partnerId,
                isInitiator: payload.initiator
            )

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
            let _ = dictionary["timestamp"] as? String
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            print("📥 Received message: \(text)")
            self.appendMessage(
                ChatMessage(
                    senderId: senderId,
                    senderName: senderName,
                    senderProfilePic: profilePic,
                    text: text,
                    isFromMe: false
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
            self.webRTCManager.endSession()
            self.activePartnerId = nil
            self.activeMatch = nil
            self.partner = nil
            self.isSearching = true
            self.messages.removeAll()
            self.isPartnerTyping = false
            self.partnerName = nil
            self.partnerAvatarURL = nil
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
            self.privateCallPhaseWorkItem?.cancel()
            self.privateCallPhaseWorkItem = nil

            self.unlockFindPartnerEmit(reason: "partner_left_auto_next")
            if self.currentSearchPayload != nil {
                self.findPartner()
            }
        }

        socket.on("partner_left") { [weak self] data, _ in
            print("👋 partner_left received: \(data)")
            self?.saveCurrentPartnerToRecentHistory()
            self?.webRTCManager.endSession()
            self?.activePartnerId = nil
            self?.activeMatch = nil
            self?.messages.removeAll()
            self?.isPartnerTyping = false
            self?.partnerName = nil
            self?.partnerAvatarURL = nil
            self?.outgoingPrivateCallTargetId = nil
            self?.outgoingPrivateCallPhase = nil
            self?.privateCallPhaseWorkItem?.cancel()
            self?.privateCallPhaseWorkItem = nil
            self?.unlockFindPartnerEmit(reason: "partner_left")
        }

        socket.on("end_call") { [weak self] data, _ in
            print("📴 end_call received: \(data)")
            self?.saveCurrentPartnerToRecentHistory()
            self?.webRTCManager.endSession()
            self?.activePartnerId = nil
            self?.activeMatch = nil
            self?.messages.removeAll()
            self?.isPartnerTyping = false
            self?.partnerName = nil
            self?.partnerAvatarURL = nil
            self?.outgoingPrivateCallTargetId = nil
            self?.outgoingPrivateCallPhase = nil
            self?.privateCallPhaseWorkItem?.cancel()
            self?.privateCallPhaseWorkItem = nil
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
            self.incomingPrivateCall = IncomingPrivateCall(
                callerId: callerId,
                callerName: callerName,
                callerAvatarURL: avatar?.isEmpty == true ? nil : avatar
            )
            self.outgoingPrivateCallTargetId = nil
            self.outgoingPrivateCallPhase = nil
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

        socket.on("call_rejected") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Arama reddedildi")
            }
        }

        socket.on("target_unavailable") { [weak self] _, _ in
            self?.outgoingPrivateCallTargetId = nil
            self?.outgoingPrivateCallPhase = nil
            self?.privateCallPhaseWorkItem?.cancel()
            self?.privateCallPhaseWorkItem = nil
            print("DEBUG: Server says target is unavailable. Check if the ID is correct and if the user is online.")
            self?.schedulePrivateCallNotice("User is busy or offline.")
        }

        socket.on("target_is_busy") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Kullanici su an mesgul. Lutfen daha sonra tekrar deneyin.")
            }
        }

        socket.on("insufficient_gems") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.outgoingPrivateCallTargetId = nil
                self?.outgoingPrivateCallPhase = nil
                self?.privateCallPhaseWorkItem?.cancel()
                self?.privateCallPhaseWorkItem = nil
                self?.showPrivateCallToast("Yetersiz Gem. Ozel arama icin 50 Gem gerekli.")
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
            partnerAvatar: (dictionary["partnerAvatar"] as? String) ?? (nestedPartner?["avatar"] as? String)
        )
    }

    private func appendMessage(_ message: ChatMessage) {
        DispatchQueue.main.async {
            self.messages.append(message)
        }
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
