import Foundation

final class PublicIPService: @unchecked Sendable {
    struct Provider: Sendable {
        let name: String
        let url: URL
    }

    struct FetchResult: Sendable {
        let ip: String
        let providerName: String
    }

    struct AttemptFailure: Sendable {
        let providerName: String
        let reason: String
    }

    private let providers: [Provider]
    private let timeout: TimeInterval

    init(
        providers: [Provider] = [
            Provider(name: "ipify", url: URL(string: "https://api.ipify.org?format=text")!),
            Provider(name: "icanhazip", url: URL(string: "https://ipv4.icanhazip.com")!),
            Provider(name: "ifconfig.me", url: URL(string: "https://ifconfig.me/ip")!),
            Provider(name: "checkip.amazonaws.com", url: URL(string: "https://checkip.amazonaws.com")!)
        ],
        timeout: TimeInterval = 5
    ) {
        self.providers = providers
        self.timeout = timeout
    }

    func fetchIPv4() async throws -> String {
        try await fetchIPv4Result().ip
    }

    func fetchIPv4Result() async throws -> FetchResult {
        var failures: [AttemptFailure] = []

        for provider in providers {
            do {
                let ip = try await fetchIPv4(from: provider)
                return FetchResult(ip: ip, providerName: provider.name)
            } catch {
                failures.append(AttemptFailure(providerName: provider.name, reason: error.localizedDescription))
            }
        }

        throw PublicIPError.allProvidersFailed(failures)
    }

    private func fetchIPv4(from provider: Provider) async throws -> String {
        var request = URLRequest(url: provider.url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PublicIPError.requestFailed("响应不是 HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw PublicIPError.requestFailed("HTTP \(http.statusCode)")
        }

        let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isIPv4(ip) else {
            throw PublicIPError.invalidIP(ip)
        }
        return ip
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let int = Int(part), int >= 0, int <= 255 else { return false }
            return String(int) == part
        }
    }
}

enum PublicIPError: LocalizedError {
    case requestFailed(String)
    case invalidIP(String)
    case allProvidersFailed([PublicIPService.AttemptFailure])

    var errorDescription: String? {
        switch self {
        case .requestFailed(let reason):
            return "公网 IP 请求失败：\(reason)"
        case .invalidIP(let value):
            return "公网 IP 格式异常：\(value)"
        case .allProvidersFailed(let failures):
            let providers = failures.map(\.providerName).joined(separator: "、")
            return "公网 IP 获取失败，已尝试 \(failures.count) 个服务：\(providers)"
        }
    }

    var attemptFailures: [PublicIPService.AttemptFailure] {
        switch self {
        case .allProvidersFailed(let failures):
            return failures
        case .requestFailed, .invalidIP:
            return []
        }
    }
}
