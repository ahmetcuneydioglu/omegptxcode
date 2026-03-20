import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [MatchHistory] = []
    @Published private(set) var followingUsers: [FollowingUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let networkManager = NetworkManager()
    private var currentUserId: String?

    func fetchHistory(currentUserId: String?) async {
        guard let currentUserId, !currentUserId.isEmpty else {
            items = []
            errorMessage = nil
            print("HistoryViewModel: currentUserId is missing. Skipping history fetch.")
            return
        }

        self.currentUserId = currentUserId

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await networkManager.getData(path: "/api/users/\(currentUserId)/history")

            if data.isEmpty {
                items = []
                errorMessage = nil
                print("HistoryViewModel: empty response body")
                return
            }

            items = try decodeHistory(from: data)
            errorMessage = nil
            print("HistoryViewModel: loaded \(items.count) history items")
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
            errorMessage = "Oturum suresi doldu."
        } catch {
            print("History Fetch Error: \(error)")
            if let decodingError = error as? DecodingError {
                print("History Decoding Error: \(decodingError)")
            }
            errorMessage = "History could not be loaded."
        }
    }

    func fetchFollowing(currentUserId: String?) async {
        guard let currentUserId, !currentUserId.isEmpty else {
            followingUsers = []
            errorMessage = nil
            print("HistoryViewModel: currentUserId is missing. Skipping following fetch.")
            return
        }

        self.currentUserId = currentUserId

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await networkManager.getData(path: "/api/users/\(currentUserId)/following")
            if data.isEmpty {
                followingUsers = []
                errorMessage = nil
                return
            }

            followingUsers = try decodeFollowing(from: data)
            errorMessage = nil
            print("HistoryViewModel: loaded \(followingUsers.count) following users")
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
            errorMessage = "Oturum suresi doldu."
        } catch {
            print("Following Fetch Error: \(error)")
            errorMessage = "Following list could not be loaded."
        }
    }

    func toggleFollow(partnerId: String?) async {
        guard let currentUserId, !currentUserId.isEmpty else {
            print("HistoryViewModel: toggleFollow aborted. currentUserId missing.")
            return
        }
        guard let partnerId, !partnerId.isEmpty else {
            print("HistoryViewModel: toggleFollow aborted. partnerId missing.")
            return
        }
        let payload: [String: Any] = [
            "followingId": partnerId
        ]
        print("HistoryViewModel: toggleFollow payload=\(payload)")

        do {
            _ = try await networkManager.postJSON(path: "/api/users/follow", body: payload)

            for index in items.indices where items[index].partner.id == partnerId {
                items[index].isFollowing.toggle()
            }
            for index in followingUsers.indices where followingUsers[index].id == partnerId {
                followingUsers[index].isFollowing.toggle()
            }
            followingUsers.removeAll { $0.id == partnerId && !$0.isFollowing }
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
        } catch {
            print("HistoryViewModel: toggleFollow error: \(error)")
        }
    }

    func allTrackedUserIds(includeFollowing: Bool) -> [String] {
        if includeFollowing {
            return followingUsers.map(\.id).filter { !$0.isEmpty }
        } else {
            return items.compactMap(\.partner.id).filter { !$0.isEmpty }
        }
    }

    func applyOnlineStates(_ states: [String: UserStatus]) {
        guard !states.isEmpty || !items.isEmpty || !followingUsers.isEmpty else { return }

        for index in items.indices {
            if let partnerId = items[index].partner.id {
                items[index].status = states[partnerId] ?? .offline
            } else {
                items[index].status = .offline
            }
        }

        for index in followingUsers.indices {
            followingUsers[index].status = states[followingUsers[index].id] ?? .offline
        }
    }

    private func decodeHistory(from data: Data) throws -> [MatchHistory] {
        let rawJSON = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
        let decoder = makeHistoryDecoder()

        do {
            let direct = try decoder.decode([MatchHistory].self, from: data)
            return direct
        } catch {
            logDecodingError(error, rawJSON: rawJSON, context: "direct array")
        }

        do {
            let wrapped = try decoder.decode(MatchHistoryEnvelope.self, from: data)
            return wrapped.items
        } catch {
            logDecodingError(error, rawJSON: rawJSON, context: "wrapped object")
        }

        print("History Decode Raw JSON: \(rawJSON)")
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Unsupported history payload")
        )
    }

    private func decodeFollowing(from data: Data) throws -> [FollowingUser] {
        let rawJSON = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
        let decoder = makeHistoryDecoder()

        do {
            return try decoder.decode([FollowingUser].self, from: data)
        } catch {
            logDecodingError(error, rawJSON: rawJSON, context: "following direct array")
        }

        do {
            let wrapped = try decoder.decode(FollowingEnvelope.self, from: data)
            return wrapped.items
        } catch {
            logDecodingError(error, rawJSON: rawJSON, context: "following wrapped object")
        }

        print("Following Decode Raw JSON: \(rawJSON)")
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Unsupported following payload")
        )
    }

    private func makeHistoryDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date"
            )
        }
        return decoder
    }

    private func logDecodingError(_ error: Error, rawJSON: String, context: String) {
        switch error {
        case let DecodingError.keyNotFound(key, decodingContext):
            print("History Decoding Error [\(context)] keyNotFound: \(key.stringValue) path=\(codingPathString(decodingContext.codingPath))")
        case let DecodingError.typeMismatch(type, decodingContext):
            print("History Decoding Error [\(context)] typeMismatch: \(type) path=\(codingPathString(decodingContext.codingPath)) desc=\(decodingContext.debugDescription)")
        case let DecodingError.valueNotFound(type, decodingContext):
            print("History Decoding Error [\(context)] valueNotFound: \(type) path=\(codingPathString(decodingContext.codingPath)) desc=\(decodingContext.debugDescription)")
        case let DecodingError.dataCorrupted(decodingContext):
            print("History Decoding Error [\(context)] dataCorrupted: path=\(codingPathString(decodingContext.codingPath)) desc=\(decodingContext.debugDescription)")
        default:
            print("History Decoding Error [\(context)]: \(error)")
        }
        print("History Decode Raw JSON: \(rawJSON)")
    }

    private func codingPathString(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "<root>" }
        return path.map(\.stringValue).joined(separator: ".")
    }
}

private struct MatchHistoryEnvelope: Decodable {
    let items: [MatchHistory]

    enum CodingKeys: String, CodingKey {
        case history
        case matches
        case items
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items =
            (try? container.decode([MatchHistory].self, forKey: .history))
            ?? (try? container.decode([MatchHistory].self, forKey: .matches))
            ?? (try? container.decode([MatchHistory].self, forKey: .items))
            ?? (try? container.decode([MatchHistory].self, forKey: .data))
            ?? []
    }
}

private struct FollowingEnvelope: Decodable {
    let items: [FollowingUser]

    enum CodingKeys: String, CodingKey {
        case following
        case users
        case items
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items =
            (try? container.decode([FollowingUser].self, forKey: .following))
            ?? (try? container.decode([FollowingUser].self, forKey: .users))
            ?? (try? container.decode([FollowingUser].self, forKey: .items))
            ?? (try? container.decode([FollowingUser].self, forKey: .data))
            ?? []
    }
}
