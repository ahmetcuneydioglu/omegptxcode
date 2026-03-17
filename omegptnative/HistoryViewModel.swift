import Combine
import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [MatchHistory] = []
    @Published private(set) var followingUsers: [FollowingUser] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let baseURL = "https://videochat-1qxi.onrender.com"
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
            guard let url = URL(string: "\(baseURL)/api/users/\(currentUserId)/history") else {
                errorMessage = "History URL is invalid."
                return
            }

            print("HistoryViewModel: fetching history for userId=\(currentUserId)")
            print("HistoryViewModel: GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "History request failed."
                print("History Fetch Error: response is not HTTPURLResponse")
                return
            }

            print("HistoryViewModel: statusCode=\(httpResponse.statusCode)")

            if httpResponse.statusCode == 204 {
                items = []
                errorMessage = nil
                print("HistoryViewModel: empty history response (204 No Content)")
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let rawJSON = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                errorMessage = "History request failed."
                print("History Fetch Error: statusCode=\(httpResponse.statusCode)")
                print("History Fetch Response: \(rawJSON)")
                return
            }

            if data.isEmpty {
                items = []
                errorMessage = nil
                print("HistoryViewModel: empty response body")
                return
            }

            items = try decodeHistory(from: data)
            errorMessage = nil
            print("HistoryViewModel: loaded \(items.count) history items")
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
            guard let url = URL(string: "\(baseURL)/api/users/\(currentUserId)/following") else {
                errorMessage = "Following URL is invalid."
                return
            }

            print("HistoryViewModel: fetching following for userId=\(currentUserId)")
            print("HistoryViewModel: GET \(url.absoluteString)")
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Following request failed."
                print("Following Fetch Error: response is not HTTPURLResponse")
                return
            }

            print("HistoryViewModel: following statusCode=\(httpResponse.statusCode)")

            if httpResponse.statusCode == 204 || data.isEmpty {
                followingUsers = []
                errorMessage = nil
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let rawJSON = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                errorMessage = "Following request failed."
                print("Following Fetch Error: statusCode=\(httpResponse.statusCode)")
                print("Following Fetch Response: \(rawJSON)")
                return
            }

            followingUsers = try decodeFollowing(from: data)
            errorMessage = nil
            print("HistoryViewModel: loaded \(followingUsers.count) following users")
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
        guard let url = URL(string: "\(baseURL)/api/users/follow") else {
            print("HistoryViewModel: follow URL invalid.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "userId": currentUserId,
            "followingId": partnerId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        print("HistoryViewModel: toggleFollow payload=\(payload)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                print("HistoryViewModel: follow request failed. response=\(raw)")
                return
            }

            for index in items.indices where items[index].partner.id == partnerId {
                items[index].isFollowing.toggle()
            }
            for index in followingUsers.indices where followingUsers[index].id == partnerId {
                followingUsers[index].isFollowing.toggle()
            }
            followingUsers.removeAll { $0.id == partnerId && !$0.isFollowing }
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
