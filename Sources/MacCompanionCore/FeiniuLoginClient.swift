import Foundation

final class FeiniuLoginClient: @unchecked Sendable {
    private let config: FeiniuConfig
    private let keychain: KeychainStore

    init(config: FeiniuConfig, keychain: KeychainStore) {
        self.config = config
        self.keychain = keychain
    }

    func login(username: String, password: String) async throws {
        guard !username.isEmpty, !password.isEmpty else {
            throw FeiniuLoginError.missingCredential
        }
        guard let url = URL(string: config.loginURL) else {
            throw FeiniuLoginError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.loginMethod
        request.setValue(config.loginContentType, forHTTPHeaderField: "Content-Type")
        request.setValue(config.origin, forHTTPHeaderField: "Origin")
        request.setValue("language=\(config.language)", forHTTPHeaderField: "Cookie")

        let body = config.loginBodyTemplate
            .replacingOccurrences(of: "{username}", with: username.jsonEscaped)
            .replacingOccurrences(of: "{password}", with: password.jsonEscaped)
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeiniuLoginError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FeiniuLoginError.httpStatus(http.statusCode)
        }

        if let token = Self.extractCookieToken(from: http, cookieName: config.tokenCookieName) {
            try keychain.save(token, account: config.tokenCookieName)
            return
        }

        if let token = Self.extractJSONToken(from: data, tokenName: config.tokenCookieName) {
            try keychain.save(token, account: config.tokenCookieName)
            return
        }

        throw FeiniuLoginError.tokenNotFound
    }

    private static func extractCookieToken(from response: HTTPURLResponse, cookieName: String) -> String? {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let key = item.key as? String, let value = item.value as? String {
                result[key] = value
            }
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: response.url ?? URL(string: "https://localhost")!)
        return cookies.first(where: { $0.name == cookieName })?.value
    }

    private static func extractJSONToken(from data: Data, tokenName: String) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let value = findToken(in: object, names: [tokenName, "token", "accessToken", "access_token"])
        else {
            return nil
        }
        return value
    }

    private static func findToken(in object: Any, names: Set<String>) -> String? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if names.contains(key), let token = value as? String {
                    return token
                }
                if let nested = findToken(in: value, names: names) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let nested = findToken(in: value, names: names) {
                    return nested
                }
            }
        }
        return nil
    }
}

enum FeiniuLoginError: LocalizedError {
    case missingCredential
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case tokenNotFound

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "请输入飞牛用户名和密码"
        case .invalidURL:
            return "登录 URL 无效"
        case .invalidResponse:
            return "登录响应异常"
        case .httpStatus(let code):
            return "登录接口返回 HTTP \(code)"
        case .tokenNotFound:
            return "登录成功但没有找到 fnos-token，请检查登录接口配置"
        }
    }
}

enum FeiniuWebLoginError: LocalizedError {
    case tokenCookieNotFound

    var errorDescription: String? {
        switch self {
        case .tokenCookieNotFound:
            return "请先在内置网页登录飞牛"
        }
    }
}

private extension String {
    var jsonEscaped: String {
        let data = try? JSONEncoder().encode(self)
        let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(self)\""
        return String(encoded.dropFirst().dropLast())
    }
}
