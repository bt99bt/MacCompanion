import Darwin
import Foundation

final class RestrictedWiFiLoginClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let config: RestrictedWiFiConfig
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(config: RestrictedWiFiConfig) {
        self.config = config
    }

    func checkInternetConnection() async throws -> Bool {
        guard let url = URL(string: config.connectivityCheckURL) else {
            throw RestrictedWiFiError.invalidURL("联网检测 URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RestrictedWiFiError.invalidResponse
        }
        return http.statusCode == config.expectedConnectivityStatusCode
    }

    func requestSMS() async throws {
        let phone = normalizedPhoneNumber()
        guard !phone.isEmpty else {
            throw RestrictedWiFiError.missingPhoneNumber
        }
        guard let url = smsURL() else {
            throw RestrictedWiFiError.invalidURL("短信接口 URL 无效")
        }

        let userIP = try localIPv4()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(origin(from: config.portalPageURL), forHTTPHeaderField: "Origin")
        request.setValue(referer(userIP: userIP), forHTTPHeaderField: "Referer")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "mobile": "\(config.countryCode)\(phone)",
            "reason": config.smsReason
        ])

        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response, context: "短信请求")
    }

    func login(code: String) async throws {
        let phone = normalizedPhoneNumber()
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phone.isEmpty else {
            throw RestrictedWiFiError.missingPhoneNumber
        }
        guard !cleanCode.isEmpty else {
            throw RestrictedWiFiError.missingVerificationCode
        }

        let userIP = try localIPv4()
        guard let url = portalURL(base: config.portalLoginURL, userIP: userIP) else {
            throw RestrictedWiFiError.invalidURL("登录 URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(origin(from: config.portalPageURL), forHTTPHeaderField: "Origin")
        request.setValue(referer(userIP: userIP), forHTTPHeaderField: "Referer")
        request.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = formBody([
            "username": "\(config.countryCode)\(phone)",
            "password": cleanCode,
            "cmd": "login"
        ])

        let (_, response) = try await session.data(for: request)
        try validateHTTPResponse(response, context: "登录")
    }

    func fetchVerificationCodeFromServer() async throws -> String? {
        try fetchVerificationCodeFromDNS()
    }

    func checkDNSServerHealth() throws -> DNSHealthCheckResult {
        let expected = config.dnsHealthExpectedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else {
            throw RestrictedWiFiError.invalidDNSConfig("DNS 健康检查期望地址为空")
        }
        let addresses = try resolveIPv4Addresses(for: config.dnsHealthLookupDomain)
        return DNSHealthCheckResult(
            expectedAddress: expected,
            resolvedAddresses: addresses,
            isHealthy: addresses.contains(expected)
        )
    }

    func fetchVerificationCodeFromDNS() throws -> String? {
        let addresses = try resolveIPv4Addresses(for: config.dnsCodeLookupDomain)
        for address in addresses {
            guard let code = Self.decodeVerificationCode(from: address) else {
                continue
            }
            return code
        }
        return nil
    }

    func fetchVerificationCodeFromHTTPServer() async throws -> String? {
        guard config.serverCodeEnabled, !config.serverCodeURL.isEmpty else {
            return nil
        }
        guard let url = URL(string: config.serverCodeURL) else {
            throw RestrictedWiFiError.invalidURL("服务器验证码 URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = config.serverCodeMethod.uppercased()
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, context: "服务器验证码")

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil {
                return trimmed
            }
        }

        let object = try JSONSerialization.jsonObject(with: data)
        return Self.value(in: object, path: config.serverCodeJSONPath) as? String
    }

    private func resolveIPv4Addresses(for hostname: String) throws -> [String] {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RestrictedWiFiError.invalidDNSConfig("DNS 查询域名为空")
        }

        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(trimmed, nil, &hints, &result)
        guard status == 0, let result else {
            throw RestrictedWiFiError.dnsLookupFailed(trimmed, String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let current = pointer {
            if let socketAddress = current.pointee.ai_addr {
                let address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipv4 in
                    var addr = ipv4.pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                    return Self.nullTerminatedString(from: buffer)
                }
                addresses.append(address)
            }
            pointer = current.pointee.ai_next
        }
        return addresses
    }

    func localIPv4() throws -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            throw RestrictedWiFiError.localIPNotFound(config.targetIPPrefix)
        }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = Self.nullTerminatedString(from: hostname)
            if ip.hasPrefix(config.targetIPPrefix), !ip.hasPrefix("127.") {
                return ip
            }
        }

        throw RestrictedWiFiError.localIPNotFound(config.targetIPPrefix)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func normalizedPhoneNumber() -> String {
        config.phoneNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private func smsURL() -> URL? {
        guard var components = URLComponents(string: config.smsAPIURL) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "language", value: config.language))
        items.append(URLQueryItem(name: "os", value: config.os))
        items.append(URLQueryItem(name: "t", value: String(Int64(Date().timeIntervalSince1970 * 1000))))
        components.queryItems = items
        return components.url
    }

    private func portalURL(base: String, userIP: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = portalQueryItems(userIP: userIP)
        return components.url
    }

    private func referer(userIP: String) -> String {
        portalURL(base: config.portalPageURL, userIP: userIP)?.absoluteString ?? config.portalPageURL
    }

    private func portalQueryItems(userIP: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "a", value: "1"),
            URLQueryItem(name: "apmac", value: config.apMAC),
            URLQueryItem(name: "default_auth_type", value: config.defaultAuthType),
            URLQueryItem(name: "nasip", value: config.nasIP),
            URLQueryItem(name: "userip", value: userIP)
        ]
    }

    private func origin(from urlString: String) -> String {
        guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host else {
            return ""
        }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(Self.formEncode(key))=\(Self.formEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func validateHTTPResponse(_ response: URLResponse, context: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RestrictedWiFiError.invalidResponse
        }
        guard (200..<400).contains(http.statusCode) else {
            throw RestrictedWiFiError.httpStatus(context, http.statusCode)
        }
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func nullTerminatedString(from buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<end].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func value(in object: Any, path: String) -> Any? {
        let keys = path.split(separator: ".").map(String.init)
        return keys.reduce(object as Any?) { current, key in
            guard let dictionary = current as? [String: Any] else { return nil }
            return dictionary[key]
        }
    }

    private static func decodeVerificationCode(from address: String) -> String? {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 1 else { return nil }
        guard parts[1...3].allSatisfy({ (0...255).contains($0) }) else { return nil }
        let value = parts[1] * 10000 + parts[2] * 100 + parts[3]
        guard value > 0, value <= 999_999 else { return nil }
        return String(format: "%06d", value)
    }
}

struct DNSHealthCheckResult: Sendable {
    let expectedAddress: String
    let resolvedAddresses: [String]
    let isHealthy: Bool

    var summary: String {
        if isHealthy {
            return "验证码 DNS 服务正常"
        }
        if resolvedAddresses.contains(where: Self.isFakeIPAddress) {
            return "验证码 DNS 被本机代理改写：\(resolvedAddresses.joined(separator: ", "))"
        }
        if resolvedAddresses.isEmpty {
            return "验证码 DNS 没有返回 A 记录，期望 \(expectedAddress)"
        }
        return "验证码 DNS 返回 \(resolvedAddresses.joined(separator: ", "))，期望 \(expectedAddress)"
    }

    private static func isFakeIPAddress(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 198 && (18...19).contains(parts[1])
    }
}

enum RestrictedWiFiError: LocalizedError {
    case missingPhoneNumber
    case missingVerificationCode
    case invalidURL(String)
    case invalidResponse
    case httpStatus(String, Int)
    case localIPNotFound(String)
    case invalidDNSConfig(String)
    case dnsLookupFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .missingPhoneNumber:
            return "请先填写接收验证码的手机号"
        case .missingVerificationCode:
            return "请填写短信验证码"
        case .invalidURL(let message):
            return message
        case .invalidResponse:
            return "网络响应异常"
        case .httpStatus(let context, let code):
            return "\(context)返回 HTTP \(code)"
        case .localIPNotFound(let prefix):
            return "没有找到前缀为 \(prefix) 的本机 IPv4 地址"
        case .invalidDNSConfig(let message):
            return message
        case .dnsLookupFailed(let hostname, let reason):
            return "DNS 查询失败：\(hostname)，\(reason)"
        }
    }
}
