import Foundation

final class NetworkManager {
    private let baseURL = "https://videochat-1qxi.onrender.com"
    private var accessToken: String? { AuthManager.shared.accessToken }

    func socialLogin(idToken: String) async throws -> AuthSession {
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
            return try decodeAuthSession(from: data)
        case 401:
            throw NetworkError.unauthorized
        default:
            let fallback = "Server returned status \(httpResponse.statusCode)"
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NetworkError.serverError(message ?? fallback)
        }
    }

    func getData(path: String, requiresAuth: Bool = true) async throws -> Data {
        let request = try makeRequest(path: path, method: "GET", body: nil, requiresAuth: requiresAuth)
        let (data, response) = try await URLSession.shared.data(for: request)
        _ = try validate(response: response, data: data)
        return data
    }

    func getJSON(path: String, requiresAuth: Bool = true) async throws -> [String: Any] {
        let request = try makeRequest(path: path, method: "GET", body: nil, requiresAuth: requiresAuth)
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try validate(response: response, data: data)

        if httpResponse.statusCode == 204 || data.isEmpty {
            return [:]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse
        }
        return json
    }

    func postJSON(path: String, body: [String: Any]? = nil, requiresAuth: Bool = true) async throws -> [String: Any] {
        try await requestJSON(path: path, method: "POST", body: body, requiresAuth: requiresAuth)
    }

    func postWithoutDecoding(path: String, body: [String: Any]? = nil, requiresAuth: Bool = true) async throws {
        let request = try makeRequest(path: path, method: "POST", body: body, requiresAuth: requiresAuth)
        let (data, response) = try await URLSession.shared.data(for: request)
        _ = try validate(response: response, data: data)
    }

    func requestJSON(
        path: String,
        method: String,
        body: [String: Any]?,
        requiresAuth: Bool = true
    ) async throws -> [String: Any] {
        let request = try makeRequest(path: path, method: method, body: body, requiresAuth: requiresAuth)
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try validate(response: response, data: data)

        if httpResponse.statusCode == 204 || data.isEmpty {
            return [:]
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse
        }
        return json
    }

    private func makeRequest(
        path: String,
        method: String,
        body: [String: Any]?,
        requiresAuth: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            guard let accessToken, !accessToken.isEmpty else {
                throw NetworkError.unauthorized
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            guard JSONSerialization.isValidJSONObject(body) else {
                print("⚠️ Invalid JSON body for \(method) \(path): \(body)")
                throw NetworkError.serverError("Gecersiz istek verisi.")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }

        return request
    }

    @discardableResult
    private func validate(response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return httpResponse
        case 401:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.serverError(extractServerMessage(from: data) ?? "Server returned status \(httpResponse.statusCode)")
        }
    }

    private func decodeAuthSession(from data: Data) throws -> AuthSession {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse
        }

        let accessToken = (json["accessToken"] as? String)
            ?? (json["token"] as? String)
            ?? (json["jwt"] as? String)

        guard let accessToken, !accessToken.isEmpty else {
            throw NetworkError.serverError("Access token missing in auth response.")
        }

        let userPayload = (json["user"] as? [String: Any])
            ?? (json["data"] as? [String: Any])
            ?? json

        guard JSONSerialization.isValidJSONObject(userPayload) else {
            throw NetworkError.invalidResponse
        }

        let userData = try JSONSerialization.data(withJSONObject: userPayload)
        let user = try JSONDecoder().decode(User.self, from: userData)
        return AuthSession(user: user, accessToken: accessToken)
    }

    private func extractServerMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let error = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (json["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let error, !error.isEmpty, let detail, !detail.isEmpty, error != detail {
                return "\(error) | detail: \(detail)"
            }
            if let message, !message.isEmpty, let detail, !detail.isEmpty, message != detail {
                return "\(message) | detail: \(detail)"
            }

            return message
                ?? error
                ?? detail
        }
        return String(data: data, encoding: .utf8)
    }
}
