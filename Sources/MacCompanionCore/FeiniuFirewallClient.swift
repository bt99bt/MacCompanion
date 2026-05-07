import Foundation

public final class FeiniuFirewallClient: @unchecked Sendable {
    private let config: FeiniuConfig
    private let token: String?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(config: FeiniuConfig, token: String?) {
        self.config = config
        self.token = token
    }

    public func addAllowAllRule(for ip: String) async throws -> AddFirewallRuleResult {
        let connection = try await makeConnection()
        let webSocket = connection.webSocket
        let session = connection.session
        defer {
            webSocket.cancel(with: .goingAway, reason: nil)
            session.finishTasksAndInvalidate()
        }

        var payloads = try await fetchFirewallPayloads(webSocket: webSocket)
        guard var payload = payloads.first else {
            throw FeiniuFirewallError.emptyFirewallData
        }

        if payload.rules.contains(where: { Self.isExistingAllowAllRule($0, ip: ip, range: config.portRange) }) {
            return .alreadyExists
        }

        let nextPriority = (payload.rules.map(\.priority).max() ?? -1) + 1
        payload.rules.append(Self.makeAllowAllRule(ip: ip, priority: nextPriority, config: config))
        payloads[0] = payload

        let reqid = Self.makeReqID()
        let setEnvelope = FirewallEnvelope(reqid: reqid, data: payloads, req: "appcgi.security.firewall.setting")
        try await send(setEnvelope, webSocket: webSocket)
        let ack = try await receiveAck(reqid: reqid, webSocket: webSocket)
        if let code = ack.code, code != 0 {
            throw FeiniuFirewallError.serverRejected(code: code, message: ack.msg)
        }

        return .added
    }

    public func fetchFirewallSummary() async throws -> FirewallSummary {
        let connection = try await makeConnection()
        let webSocket = connection.webSocket
        let session = connection.session
        defer {
            webSocket.cancel(with: .goingAway, reason: nil)
            session.finishTasksAndInvalidate()
        }

        let payloads = try await fetchFirewallPayloads(webSocket: webSocket)
        guard let payload = payloads.first else {
            throw FeiniuFirewallError.emptyFirewallData
        }
        return FirewallSummary(profile: payload.profile, ruleCount: payload.rules.count, enabled: payload.enable)
    }

    private func makeConnection() async throws -> (session: URLSession, webSocket: URLSessionWebSocketTask) {
        guard let url = URL(string: config.websocketURL) else {
            throw FeiniuFirewallError.invalidURL
        }
        guard let token, !token.isEmpty else {
            throw FeiniuFirewallError.missingToken
        }

        var request = URLRequest(url: url)
        request.setValue(config.origin, forHTTPHeaderField: "Origin")
        request.setValue("language=\(config.language); \(config.tokenCookieName)=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) MacCompanion/1.0", forHTTPHeaderField: "User-Agent")

        let delegate = WebSocketOpenDelegate()
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let webSocket = session.webSocketTask(with: request)
        webSocket.maximumMessageSize = 4 * 1024 * 1024
        webSocket.resume()
        try await delegate.waitUntilOpen(timeout: 8)
        return (session, webSocket)
    }

    private func fetchFirewallPayloads(webSocket: URLSessionWebSocketTask) async throws -> [FirewallPayload] {
        let reqid = Self.makeReqID()
        let getEnvelope = FirewallEnvelope(reqid: reqid, data: nil, req: "appcgi.security.firewall.getting")
        try await send(getEnvelope, webSocket: webSocket)
        return try await receiveFirewallPayloads(reqid: reqid, webSocket: webSocket)
    }

    private func send(_ envelope: FirewallEnvelope, webSocket: URLSessionWebSocketTask) async throws {
        let data = try encoder.encode(envelope)
        let json = String(decoding: data, as: UTF8.self)
        let message = "\(Self.makeMessagePrefix())=\(json)"
        do {
            try await webSocket.send(.string(message))
        } catch {
            throw FeiniuFirewallError.sendFailed(message: error.localizedDescription)
        }
    }

    private func receiveFirewallPayloads(reqid: String, webSocket: URLSessionWebSocketTask) async throws -> [FirewallPayload] {
        let data = try await receiveRawJSON(reqid: reqid, webSocket: webSocket)
        let envelope = try decoder.decode(FirewallEnvelope.self, from: data)
        guard let payloads = envelope.data else {
            throw FeiniuFirewallError.emptyFirewallData
        }
        return payloads
    }

    private func receiveAck(reqid: String, webSocket: URLSessionWebSocketTask) async throws -> FirewallAckEnvelope {
        let data = try await receiveRawJSON(reqid: reqid, webSocket: webSocket)
        return try decoder.decode(FirewallAckEnvelope.self, from: data)
    }

    private func receiveRawJSON(reqid: String, webSocket: URLSessionWebSocketTask) async throws -> Data {
        var lastJSON = ""
        for _ in 0..<30 {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await webSocket.receive()
            } catch {
                throw FeiniuFirewallError.receiveFailed(message: error.localizedDescription)
            }
            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let data):
                text = String(decoding: data, as: UTF8.self)
            @unknown default:
                continue
            }

            guard let separator = text.firstIndex(of: "=") else {
                continue
            }
            let json = String(text[text.index(after: separator)...])
            lastJSON = json
            if json.contains(#""reqid":"\#(reqid)""#) {
                return Data(json.utf8)
            }
        }
        throw FeiniuFirewallError.timeout(lastMessage: lastJSON)
    }

    public static func isExistingAllowAllRule(_ rule: FirewallRule, ip: String, range: PortRange) -> Bool {
        rule.allow &&
        rule.enable &&
        rule.flowdir == 1 &&
        rule.pro == 1 &&
        rule.ips.type == 0 &&
        rule.ips.ip == ip &&
        rule.ports.type == 1 &&
        rule.ports.ranges.range?.from == range.from &&
        rule.ports.ranges.range?.to == range.to
    }

    public static func makeAllowAllRule(ip: String, priority: Int, config: FeiniuConfig) -> FirewallRule {
        FirewallRule(
            ifname: "ALL",
            flowdir: 1,
            pro: 1,
            ports: FirewallPorts(
                type: 1,
                ranges: FirewallPortRanges(
                    process: nil,
                    ports: nil,
                    range: FirewallRange(from: config.portRange.from, to: config.portRange.to)
                )
            ),
            ips: FirewallIPs(type: 0, ip: ip, country: nil, cidr: nil),
            priority: priority,
            allow: true,
            enable: true,
            memo: config.memo
        )
    }

    private static func makeReqID() -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970), radix: 16)
        return timestamp + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
    }

    private static func makeMessagePrefix() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        return String((0..<43).map { _ in alphabet.randomElement()! })
    }
}

enum FeiniuFirewallError: LocalizedError {
    case invalidURL
    case missingToken
    case emptyFirewallData
    case timeout(lastMessage: String)
    case serverRejected(code: Int, message: String?)
    case connectionTimeout
    case connectionClosed(code: String, reason: String)
    case sendFailed(message: String)
    case receiveFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "WebSocket URL 无效"
        case .missingToken:
            return "缺少 fnos-token，请先登录"
        case .emptyFirewallData:
            return "没有读取到防火墙配置"
        case .timeout(let lastMessage):
            if lastMessage.isEmpty {
                return "等待飞牛 WebSocket 响应超时"
            }
            return "等待飞牛 WebSocket 响应超时，最后响应：\(lastMessage)"
        case .serverRejected(let code, let message):
            return "飞牛拒绝保存规则：\(code) \(message ?? "")"
        case .connectionTimeout:
            return "连接飞牛 WebSocket 超时，请确认已在内置网页登录且 WebSocket URL 可访问"
        case .connectionClosed(let code, let reason):
            if reason.isEmpty {
                return "飞牛 WebSocket 握手后被关闭：\(code)"
            }
            return "飞牛 WebSocket 握手后被关闭：\(code)，\(reason)"
        case .sendFailed(let message):
            return "发送飞牛 WebSocket 消息失败：\(message)"
        case .receiveFailed(let message):
            return "读取飞牛 WebSocket 响应失败：\(message)"
        }
    }
}

private final class WebSocketOpenDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var didOpen = false
    private var closeError: Error?

    func waitUntilOpen(timeout: TimeInterval) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    self.lock.lock()
                    if self.didOpen {
                        self.lock.unlock()
                        continuation.resume()
                        return
                    }
                    if let closeError = self.closeError {
                        self.lock.unlock()
                        continuation.resume(throwing: closeError)
                        return
                    }
                    self.continuation = continuation
                    self.lock.unlock()
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw FeiniuFirewallError.connectionTimeout
            }

            try await group.next()
            group.cancelAll()
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        lock.lock()
        didOpen = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let error = FeiniuFirewallError.connectionClosed(code: String(describing: closeCode), reason: reasonText)

        lock.lock()
        closeError = error
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
