import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    var followingUsers: [FollowingUser] = []
    var followerUsers: [FollowingUser] = []
    var isLoading = false
    var errorMessage: String?

    private let networkManager = NetworkManager()

    func fetchAll(userId: String) async {
        guard !userId.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        async let following: () = loadFollowing(userId: userId)
        async let followers: () = loadFollowers(userId: userId)
        await (following, followers)
        AppUserStore.shared.refreshFollowCounts(
            followingCount: followingUsers.count,
            followersCount: followerUsers.count
        )
    }

    private func loadFollowing(userId: String) async {
        do {
            let data = try await networkManager.getData(path: "/api/users/\(userId)/following")
            followingUsers = (try? decode(data)) ?? []
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
        } catch {
            print("ProfileVM following error: \(error)")
        }
    }

    private func loadFollowers(userId: String) async {
        do {
            let data = try await networkManager.getData(path: "/api/users/\(userId)/followers")
            followerUsers = (try? decode(data)) ?? []
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
        } catch {
            print("ProfileVM followers error: \(error)")
        }
    }

    func toggleFollow(targetId: String, currentUserId: String) async {
        guard !targetId.isEmpty, !currentUserId.isEmpty else { return }
        do {
            _ = try await networkManager.postJSON(path: "/api/users/follow", body: ["followingId": targetId])
            for i in followingUsers.indices where followingUsers[i].id == targetId {
                followingUsers[i].isFollowing.toggle()
            }
            followingUsers.removeAll { $0.id == targetId && !$0.isFollowing }
            for i in followerUsers.indices where followerUsers[i].id == targetId {
                followerUsers[i].isFollowing.toggle()
            }
        } catch NetworkError.unauthorized {
            AppUserStore.shared.handleUnauthorized()
        } catch {
            print("ProfileVM toggleFollow error: \(error)")
        }
    }

    private func decode(_ data: Data) throws -> [FollowingUser] {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode([FollowingUser].self, from: data) {
            return direct
        }
        struct Envelope: Decodable {
            let items: [FollowingUser]
            enum CodingKeys: String, CodingKey { case following, followers, users, items, data }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                items = (try? c.decode([FollowingUser].self, forKey: .following))
                    ?? (try? c.decode([FollowingUser].self, forKey: .followers))
                    ?? (try? c.decode([FollowingUser].self, forKey: .users))
                    ?? (try? c.decode([FollowingUser].self, forKey: .items))
                    ?? (try? c.decode([FollowingUser].self, forKey: .data))
                    ?? []
            }
        }
        return (try? decoder.decode(Envelope.self, from: data).items) ?? []
    }
}
