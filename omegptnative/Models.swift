import Foundation
import SwiftUI
import UIKit
import Combine

struct AuthSession {
    let user: User
    let accessToken: String
}

struct User: Codable, Identifiable {
    var id: String
    var googleId: String?
    var email: String?
    var name: String
    var avatar: String?
    var gender: String?
    var age: Int?
    var country: String?
    var bio: String?
    var photos: [String]
    var interests: [String]
    var badges: [String]
    var followersCount: Int
    var followingCount: Int
    var likes: Int
    var trustScore: Int
    var isRegistered: Bool
    var gems: Int
    var birthDate: String?
    var work: String?
    var education: String?
    var location: String?
    var hometown: String?
    var height: Int?
    var exercise: String?
    var lookingFor: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case mongoId = "_id"
        case googleId
        case email
        case name
        case avatar
        case gender
        case age
        case country
        case bio
        case photos
        case interests
        case badges
        case followersCount
        case followingCount
        case likes
        case trustScore
        case isRegistered
        case gems
        case birthDate
        case work
        case education
        case location
        case hometown
        case height
        case exercise
        case lookingFor
        case balance
        case tickets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .mongoId)
        self.googleId = try container.decodeIfPresent(String.self, forKey: .googleId)
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        self.gender = try container.decodeIfPresent(String.self, forKey: .gender)
        self.age = try container.decodeIfPresent(Int.self, forKey: .age)
        self.country = try container.decodeIfPresent(String.self, forKey: .country)
        self.bio = try container.decodeIfPresent(String.self, forKey: .bio)
        self.photos = try container.decodeIfPresent([String].self, forKey: .photos) ?? []
        self.interests = try container.decodeIfPresent([String].self, forKey: .interests) ?? []
        self.badges = try container.decodeIfPresent([String].self, forKey: .badges) ?? []
        self.followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        self.followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        self.likes = try container.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        self.trustScore = try container.decodeIfPresent(Int.self, forKey: .trustScore) ?? 100
        self.isRegistered = try container.decodeIfPresent(Bool.self, forKey: .isRegistered) ?? false
        self.birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
        self.work = try container.decodeIfPresent(String.self, forKey: .work)
        self.education = try container.decodeIfPresent(String.self, forKey: .education)
        self.location = try container.decodeIfPresent(String.self, forKey: .location)
        self.hometown = try container.decodeIfPresent(String.self, forKey: .hometown)
        self.height = try container.decodeIfPresent(Int.self, forKey: .height)
        self.exercise = try container.decodeIfPresent(String.self, forKey: .exercise)
        self.lookingFor = try container.decodeIfPresent([String].self, forKey: .lookingFor) ?? []
        let gemsValue = try container.decodeIfPresent(Int.self, forKey: .gems)
        let balanceValue = try container.decodeIfPresent(Int.self, forKey: .balance)
        let ticketsValue = try container.decodeIfPresent(Int.self, forKey: .tickets)
        self.gems = gemsValue ?? balanceValue ?? ticketsValue ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(googleId, forKey: .googleId)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(avatar, forKey: .avatar)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(bio, forKey: .bio)
        try container.encode(photos, forKey: .photos)
        try container.encode(interests, forKey: .interests)
        try container.encode(badges, forKey: .badges)
        try container.encode(followersCount, forKey: .followersCount)
        try container.encode(followingCount, forKey: .followingCount)
        try container.encode(likes, forKey: .likes)
        try container.encode(trustScore, forKey: .trustScore)
        try container.encode(isRegistered, forKey: .isRegistered)
        try container.encode(gems, forKey: .gems)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(work, forKey: .work)
        try container.encodeIfPresent(education, forKey: .education)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(hometown, forKey: .hometown)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(exercise, forKey: .exercise)
        try container.encode(lookingFor, forKey: .lookingFor)
    }
}

struct PartnerFoundPayload: Codable {
    let partnerId: String
    let initiator: Bool
    let country: String
    let partnerGender: String
    let partnerLikes: Int
    let partnerTrustScore: Int?
    let privateCall: Bool
    let partnerName: String?
    let partnerAvatarURL: String?
    let partnerProfilePic: String?
    let partnerAvatar: String?
}

struct BanEvent: Identifiable {
    let id = UUID()
    let reason: String
    let expireAt: Date?
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let senderId: String
    let senderName: String?
    let senderProfilePic: String?
    let text: String
    let isFromMe: Bool
}

struct IncomingPrivateCall: Identifiable, Equatable {
    let id = UUID()
    let callerId: String
    let callerName: String
    let callerAvatarURL: String?
}

struct PrivateCallNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct HeartParticle: Identifiable, Equatable {
    let id = UUID()
    let startXRatio: CGFloat
    let drift: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let color: Color
}

struct MatchedPartner: Identifiable, Equatable {
    let id: String
    let name: String
    let avatarURL: String?
    let country: String
    let screenshot: UIImage

    static func == (lhs: MatchedPartner, rhs: MatchedPartner) -> Bool {
        lhs.id == rhs.id
    }
}

struct MatchSearchPayload {
    let myGender: String
    let searchGender: String
    let selectedCountry: String
}

struct EmptyAckPayload: Codable {}

struct CountryOption: Identifiable, Hashable {
    let regionCode: String
    let name: String
    let flag: String

    var id: String { regionCode }
}
