import Foundation

final class PublicIPService: @unchecked Sendable {
    func fetchIPv4() async throws -> String {
        let url = URL(string: "https://api.ipify.org")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PublicIPError.requestFailed
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
    case requestFailed
    case invalidIP(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "公网 IP 请求失败"
        case .invalidIP(let value):
            return "公网 IP 格式异常：\(value)"
        }
    }
}
