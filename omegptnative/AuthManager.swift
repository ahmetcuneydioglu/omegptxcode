import Foundation
import Observation
import UIKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

typealias AppUserStore = AuthManager

@Observable
final class AuthManager {
    static let shared = AuthManager()

    private(set) var currentUser: User?
    private(set) var accessToken: String?
    private(set) var isLoggedIn = false
    private(set) var isLoading = false
    var authErrorMessage: String?
    var preferredGender = "all"
    var preferredCountry = "all"

    private let networkManager = NetworkManager()
    private let googleClientID = "18397104529-ped0jv9ovoj8mq6c1e3vogl3u6dv27eb.apps.googleusercontent.com"
    private let userDefaults = UserDefaults.standard
    private let persistedUserKey = "persisted.auth.user"
    private let persistedUserIdKey = "persisted.auth.userId"
    private let persistedLoggedInKey = "persisted.auth.isLoggedIn"
    private let persistedAccessTokenKey = "persisted.auth.accessToken"

    private let avatarSentinel = "local://avatar_cache"
    private var avatarCacheURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("profile_avatar_cache.jpg")
    }
    private var photosCacheURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("profile_photos_cache.json")
    }

    func cachedAvatarImage() -> UIImage? {
        guard let data = try? Data(contentsOf: avatarCacheURL) else { return nil }
        return UIImage(data: data)
    }

    func saveAvatarToCache(_ data: Data) {
        try? data.write(to: avatarCacheURL, options: .atomic)
    }

    func savePhotosToCache(_ images: [UIImage]) {
        let datas = images.compactMap { $0.jpegData(compressionQuality: 0.6) }
        let b64s = datas.map { $0.base64EncodedString() }
        if let encoded = try? JSONEncoder().encode(b64s) {
            try? encoded.write(to: photosCacheURL, options: .atomic)
        }
    }

    func cachedPhotos() -> [UIImage] {
        guard let data = try? Data(contentsOf: photosCacheURL),
              let b64s = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return b64s.compactMap { Data(base64Encoded: $0).flatMap { UIImage(data: $0) } }
    }

    private func migrateOversizedUserDefaults() {
        guard let data = userDefaults.data(forKey: persistedUserKey),
              data.count > 512_000 else { return }
        userDefaults.removeObject(forKey: persistedUserKey)
        userDefaults.removeObject(forKey: persistedLoggedInKey)
        print("⚠️ Oversized UserDefaults entry cleared — user must re-login")
    }

    init() {
        migrateOversizedUserDefaults()
        configureGoogleSignIn()
        checkSession()
    }

    func configureGoogleSignIn() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
        #endif
    }

    func signInWithGoogle() async {
        isLoading = true
        defer { isLoading = false }

        #if canImport(GoogleSignIn)
        do {
            configureGoogleSignIn()

            guard let rootViewController = Self.topViewController() else {
                authErrorMessage = "Giriş ekranı açılamadı."
                return
            }

            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            guard let token = signInResult.user.idToken?.tokenString else {
                authErrorMessage = "Kimlik doğrulama tokenı alınamadı."
                return
            }

            let session = try await networkManager.socialLogin(idToken: token)
            currentUser = session.user
            accessToken = session.accessToken
            isLoggedIn = true
            authErrorMessage = nil
            persistSession()
        } catch {
            authErrorMessage = "Google ile giriş başarısız."
            isLoggedIn = false
            print("🚨 GERÇEK HATA BURADA: \(error.localizedDescription)")
            print("🚨 HATA DETAYI: \(String(describing: error))")
        }
        #else
        authErrorMessage = "GoogleSignIn SDK projede bulunmuyor."
        #endif
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        currentUser = nil
        accessToken = nil
        isLoggedIn = false
        clearPersistedSession()
    }

    func logout() {
        signOut()
    }

    func handleUnauthorized() {
        authErrorMessage = "Oturumun sona erdi. Lutfen tekrar giris yap."
        signOut()
    }

    func refreshFollowCounts(followingCount: Int, followersCount: Int) {
        guard currentUser != nil else { return }
        currentUser?.followingCount = followingCount
        currentUser?.followersCount = followersCount
        persistSession()
    }

    func updateGemBalance(_ newValue: Int) {
        guard newValue >= 0 else { return }
        guard var user = currentUser else { return }
        user.gems = newValue
        currentUser = user
        persistSession()
    }

    func updateProfile(
        name: String? = nil,
        avatarBase64: String? = nil,
        bio: String? = nil,
        interests: [String]? = nil,
        photos: [String]? = nil,
        gender: String? = nil,
        birthDate: String? = nil
    ) async -> Bool {
        guard currentUser != nil else { return false }
        var payload: [String: Any] = [:]
        if let name { payload["name"] = name }
        if let avatarBase64 { payload["avatarBase64"] = avatarBase64 }
        if let bio { payload["bio"] = bio }
        if let interests { payload["interests"] = interests }
        if let photos { payload["photos"] = photos }
        if let gender { payload["gender"] = gender }
        if let birthDate { payload["birthDate"] = birthDate }

        do {
            _ = try await networkManager.postJSON(
                path: "/api/users/update-profile",
                body: payload
            )
            return await refreshCurrentUserFromServer()
        } catch NetworkError.unauthorized {
            handleUnauthorized()
            return false
        } catch {
            authErrorMessage = "Profil guncellenemedi."
            print("⚠️ updateProfile error: \(error)")
            return false
        }
    }

    func checkSession() {
        guard userDefaults.bool(forKey: persistedLoggedInKey) else {
            currentUser = nil
            isLoggedIn = false
            return
        }

        guard let data = userDefaults.data(forKey: persistedUserKey) else {
            clearPersistedSession()
            return
        }

        do {
            var user = try JSONDecoder().decode(User.self, from: data)
            guard let persistedToken = userDefaults.string(forKey: persistedAccessTokenKey), !persistedToken.isEmpty else {
                clearPersistedSession()
                return
            }
            if user.avatar == avatarSentinel {
                user.avatar = avatarSentinel
            }
            currentUser = user
            accessToken = persistedToken
            isLoggedIn = true
            authErrorMessage = nil
            print("🔐 Restored persisted session for userId=\(user.id)")
            Task {
                await refreshCurrentUserFromServer()
            }
        } catch {
            print("🚨 Session restore failed: \(error)")
            clearPersistedSession()
        }
    }

    @discardableResult
    func refreshCurrentUserFromServer() async -> Bool {
        guard isLoggedIn else { return false }

        do {
            let json = try await networkManager.getJSON(path: "/api/auth/me")
            let userPayload = (json["user"] as? [String: Any]) ?? json
            guard JSONSerialization.isValidJSONObject(userPayload) else {
                throw NetworkError.invalidResponse
            }

            let userData = try JSONSerialization.data(withJSONObject: userPayload)
            let refreshedUser = try JSONDecoder().decode(User.self, from: userData)
            currentUser = refreshedUser
            authErrorMessage = nil
            persistSession()
            return true
        } catch NetworkError.unauthorized {
            handleUnauthorized()
            return false
        } catch {
            print("⚠️ refreshCurrentUserFromServer error: \(error)")
            return false
        }
    }

    private func persistSession() {
        guard isLoggedIn, let currentUser, let accessToken, !accessToken.isEmpty else { return }

        do {
            let slimUser = makePersistableUser(from: currentUser)
            let data = try JSONEncoder().encode(slimUser)
            guard data.count < 512_000 else {
                // Never leave a stale session snapshot behind if we cannot persist the latest user.
                userDefaults.removeObject(forKey: persistedUserKey)
                print("🚨 Slim user still too large (\(data.count) bytes), cleared stale persisted user snapshot")
                return
            }
            userDefaults.set(data, forKey: persistedUserKey)
            userDefaults.set(currentUser.id, forKey: persistedUserIdKey)
            userDefaults.set(true, forKey: persistedLoggedInKey)
            userDefaults.set(accessToken, forKey: persistedAccessTokenKey)
        } catch {
            print("🚨 Failed to persist session: \(error)")
        }
    }

    private func makePersistableUser(from user: User) -> User {
        var slimUser = user

        if let avatar = user.avatar {
            if avatar.hasPrefix("data:") {
                let base64Part = avatar.components(separatedBy: ",").last ?? avatar
                if let imageData = Data(base64Encoded: base64Part) {
                    saveAvatarToCache(imageData)
                }
                slimUser.avatar = avatarSentinel
            }
        }

        // Keep only remotely resolvable photo identifiers in UserDefaults.
        slimUser.photos = user.photos.filter { !$0.hasPrefix("data:") && !$0.isEmpty }

        if persistedPayloadSize(for: slimUser) < 512_000 {
            return slimUser
        }

        // Trim non-essential fields before giving up so the latest interests/name still persist.
        slimUser.photos = []
        slimUser.badges = []
        slimUser.bio = nil
        slimUser.country = nil
        slimUser.gender = nil
        slimUser.birthDate = nil

        if persistedPayloadSize(for: slimUser) < 512_000 {
            return slimUser
        }

        slimUser.avatar = slimUser.avatar == avatarSentinel ? avatarSentinel : nil
        slimUser.googleId = nil
        slimUser.email = nil
        return slimUser
    }

    private func persistedPayloadSize(for user: User) -> Int {
        (try? JSONEncoder().encode(user).count) ?? .max
    }

    private func clearPersistedSession() {
        userDefaults.removeObject(forKey: persistedUserKey)
        userDefaults.removeObject(forKey: persistedUserIdKey)
        userDefaults.removeObject(forKey: persistedLoggedInKey)
        userDefaults.removeObject(forKey: persistedAccessTokenKey)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }

        if let navigation = current as? UINavigationController {
            return navigation.visibleViewController
        }
        if let tab = current as? UITabBarController {
            return tab.selectedViewController
        }
        return current
    }
}
