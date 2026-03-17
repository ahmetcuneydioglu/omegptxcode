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

    init() {
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

            let user = try await networkManager.socialLogin(idToken: token)
            currentUser = user
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
        isLoggedIn = false
        clearPersistedSession()
    }

    func logout() {
        signOut()
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
        photos: [String]? = nil
    ) async -> Bool {
        guard var user = currentUser else { return false }

        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                authErrorMessage = "Kullanici adi bos olamaz."
                return false
            }
        }

        guard let url = URL(string: "https://videochat-1qxi.onrender.com/api/users/update-profile") else {
            authErrorMessage = "Profil guncelleme adresi gecersiz."
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = ["dbUserId": user.id]

        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { payload["name"] = trimmed }
        }
        if let avatarBase64, !avatarBase64.isEmpty {
            payload["avatarBase64"] = avatarBase64
        }
        if let bio {
            payload["bio"] = bio
        }
        if let interests {
            payload["interests"] = interests
        }
        if let photos {
            payload["photos"] = photos
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
                authErrorMessage = "Profil guncellenemedi."
                print("⚠️ updateProfile failed: \(raw)")
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let v = json["name"] as? String        { user.name = v }
                if let v = json["bio"] as? String         { user.bio = v }
                if let v = json["interests"] as? [String] { user.interests = v }
                if let v = json["photos"] as? [String]    { user.photos = v }
                if let v = (json["avatar"] as? String) ?? (json["avatarUrl"] as? String) {
                    user.avatar = v
                } else if let avatarBase64, !avatarBase64.isEmpty {
                    user.avatar = avatarBase64.hasPrefix("data:image")
                        ? avatarBase64
                        : "data:image/jpeg;base64,\(avatarBase64)"
                }
            }

            currentUser = user
            authErrorMessage = nil
            persistSession()
            return true
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
            let user = try JSONDecoder().decode(User.self, from: data)
            currentUser = user
            isLoggedIn = true
            authErrorMessage = nil
            print("🔐 Restored persisted session for userId=\(user.id)")
        } catch {
            print("🚨 Session restore failed: \(error)")
            clearPersistedSession()
        }
    }

    private func persistSession() {
        guard isLoggedIn, let currentUser else { return }

        do {
            let data = try JSONEncoder().encode(currentUser)
            userDefaults.set(data, forKey: persistedUserKey)
            userDefaults.set(currentUser.id, forKey: persistedUserIdKey)
            userDefaults.set(true, forKey: persistedLoggedInKey)
        } catch {
            print("🚨 Failed to persist session: \(error)")
        }
    }

    private func clearPersistedSession() {
        userDefaults.removeObject(forKey: persistedUserKey)
        userDefaults.removeObject(forKey: persistedUserIdKey)
        userDefaults.removeObject(forKey: persistedLoggedInKey)
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
