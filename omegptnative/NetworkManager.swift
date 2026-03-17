import Foundation

final class NetworkManager {
    private let baseURL = "https://videochat-1qxi.onrender.com"

    func socialLogin(idToken: String) async throws -> User {
        guard let url = URL(string: "\(baseURL)/api/auth/social-login") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": idToken])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        if let rawResponse = String(data: data, encoding: .utf8) {
            print("📦 SUNUCUDAN GELEN RAW CEVAP: \(rawResponse)")
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let user = try JSONDecoder().decode(User.self, from: data)
                return user
            } catch {
                print("🚨 JSON DECODE HATASI: \(error)")
                throw error
            }
        case 401:
            throw NetworkError.unauthorized
        default:
            let fallback = "Server returned status \(httpResponse.statusCode)"
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NetworkError.serverError(message ?? fallback)
        }
    }
}
