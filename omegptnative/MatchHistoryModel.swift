import Foundation

enum UserStatus: String, Codable, Equatable {
    case online
    case busy
    case offline

    init(rawServerValue: String?) {
        switch rawServerValue?.lowercased() {
        case "online":
            self = .online
        case "busy":
            self = .busy
        default:
            self = .offline
        }
    }

    init(isOnline: Bool) {
        self = isOnline ? .online : .offline
    }

    var isOnline: Bool {
        self == .online
    }
}

struct MatchHistory: Decodable, Identifiable {
    let serverId: String
    let duration: Int
    let createdAt: Date
    let partner: Partner
    var isFollowing: Bool
    var status: UserStatus

    var id: String { serverId }

    enum CodingKeys: String, CodingKey {
        case serverId = "id"
        case duration
        case createdAt
        case partner
        case isFollowing
        case following
        case isFollowed
        case isOnline
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try container.decode(String.self, forKey: .serverId)
        duration = try container.decode(Int.self, forKey: .duration)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        partner = try container.decode(Partner.self, forKey: .partner)
        if let isFollowingValue = try container.decodeIfPresent(Bool.self, forKey: .isFollowing) {
            isFollowing = isFollowingValue
        } else if let followingValue = try container.decodeIfPresent(Bool.self, forKey: .following) {
            isFollowing = followingValue
        } else if let isFollowedValue = try container.decodeIfPresent(Bool.self, forKey: .isFollowed) {
            isFollowing = isFollowedValue
        } else {
            isFollowing = false
        }
        if let statusValue = try container.decodeIfPresent(String.self, forKey: .status) {
            status = UserStatus(rawServerValue: statusValue)
        } else {
            let isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
            status = UserStatus(isOnline: isOnline)
        }
    }
}

struct Partner: Decodable {
    let id: String?
    let name: String?
    let avatar: String?
    let country: String?
    let countryFlag: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatar
        case country
        case countryFlag
    }
}

struct FollowingUser: Decodable, Identifiable {
    let id: String
    let name: String?
    let avatar: String?
    let country: String?
    let countryFlag: String?
    var status: UserStatus
    var isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatar
        case country
        case countryFlag
        case isOnline
        case status
        case isFollowing
        case following
        case isFollowed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        countryFlag = try container.decodeIfPresent(String.self, forKey: .countryFlag)
        if let statusValue = try container.decodeIfPresent(String.self, forKey: .status) {
            status = UserStatus(rawServerValue: statusValue)
        } else {
            let isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
            status = UserStatus(isOnline: isOnline)
        }
        if let isFollowingValue = try container.decodeIfPresent(Bool.self, forKey: .isFollowing) {
            isFollowing = isFollowingValue
        } else if let followingValue = try container.decodeIfPresent(Bool.self, forKey: .following) {
            isFollowing = followingValue
        } else if let isFollowedValue = try container.decodeIfPresent(Bool.self, forKey: .isFollowed) {
            isFollowing = isFollowedValue
        } else {
            isFollowing = true
        }
    }
}
