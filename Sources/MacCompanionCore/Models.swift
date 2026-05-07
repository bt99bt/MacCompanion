import Foundation

public struct AppConfig: Codable, Sendable {
    public var feiniu: FeiniuConfig

    public static let `default` = AppConfig(
        feiniu: FeiniuConfig(
            webURL: "https://your-feiniu.example.com:16666",
            websocketURL: "wss://your-feiniu.example.com:16666/websocket?type=main",
            origin: "https://your-feiniu.example.com:16666",
            loginURL: "https://your-feiniu.example.com:16666",
            loginMethod: "POST",
            loginContentType: "application/json",
            loginBodyTemplate: #"{"username":"{username}","password":"{password}"}"#,
            tokenCookieName: "fnos-token",
            language: "zh-CN",
            memo: "Mac伴侣",
            portRange: PortRange(from: 1, to: 65535)
        )
    )
}

public struct FeiniuConfig: Codable, Sendable {
    public var webURL: String
    public var websocketURL: String
    public var origin: String
    public var loginURL: String
    public var loginMethod: String
    public var loginContentType: String
    public var loginBodyTemplate: String
    public var tokenCookieName: String
    public var language: String
    public var memo: String
    public var portRange: PortRange

    enum CodingKeys: String, CodingKey {
        case webURL
        case websocketURL
        case origin
        case loginURL
        case loginMethod
        case loginContentType
        case loginBodyTemplate
        case tokenCookieName
        case language
        case memo
        case portRange
    }

    public init(
        webURL: String,
        websocketURL: String,
        origin: String,
        loginURL: String,
        loginMethod: String,
        loginContentType: String,
        loginBodyTemplate: String,
        tokenCookieName: String,
        language: String,
        memo: String,
        portRange: PortRange
    ) {
        self.webURL = webURL
        self.websocketURL = websocketURL
        self.origin = origin
        self.loginURL = loginURL
        self.loginMethod = loginMethod
        self.loginContentType = loginContentType
        self.loginBodyTemplate = loginBodyTemplate
        self.tokenCookieName = tokenCookieName
        self.language = language
        self.memo = memo
        self.portRange = portRange
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppConfig.default.feiniu
        let container = try decoder.container(keyedBy: CodingKeys.self)
        webURL = try container.decodeIfPresent(String.self, forKey: .webURL) ?? defaults.webURL
        websocketURL = try container.decodeIfPresent(String.self, forKey: .websocketURL) ?? defaults.websocketURL
        origin = try container.decodeIfPresent(String.self, forKey: .origin) ?? defaults.origin
        loginURL = try container.decodeIfPresent(String.self, forKey: .loginURL) ?? defaults.loginURL
        loginMethod = try container.decodeIfPresent(String.self, forKey: .loginMethod) ?? defaults.loginMethod
        loginContentType = try container.decodeIfPresent(String.self, forKey: .loginContentType) ?? defaults.loginContentType
        loginBodyTemplate = try container.decodeIfPresent(String.self, forKey: .loginBodyTemplate) ?? defaults.loginBodyTemplate
        tokenCookieName = try container.decodeIfPresent(String.self, forKey: .tokenCookieName) ?? defaults.tokenCookieName
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        memo = try container.decodeIfPresent(String.self, forKey: .memo) ?? defaults.memo
        portRange = try container.decodeIfPresent(PortRange.self, forKey: .portRange) ?? defaults.portRange
    }
}

public struct PortRange: Codable, Sendable {
    public var from: Int
    public var to: Int

    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }
}

public struct FirewallPayload: Codable, Sendable {
    public var profile: String
    public var enable: Bool
    public var workmode: String
    public var txfallback: Bool?
    public var rxfallback: Bool?
    public var allowlan: Bool?
    public var rules: [FirewallRule]
}

public struct FirewallRule: Codable, Sendable {
    public var ifname: String
    public var flowdir: Int
    public var pro: Int
    public var ports: FirewallPorts
    public var ips: FirewallIPs
    public var priority: Int
    public var allow: Bool
    public var enable: Bool
    public var memo: String?
}

public struct FirewallPorts: Codable, Sendable {
    public var type: Int
    public var ranges: FirewallPortRanges
}

public struct FirewallPortRanges: Codable, Sendable {
    public var process: [String]?
    public var ports: [Int]?
    public var range: FirewallRange?
}

public struct FirewallRange: Codable, Sendable {
    public var from: Int
    public var to: Int
}

public struct FirewallIPs: Codable, Sendable {
    public var type: Int
    public var ip: String?
    public var country: String?
    public var cidr: FirewallCIDR?
}

public struct FirewallCIDR: Codable, Sendable {
    public var net: String
    public var len: Int
}

public struct FirewallEnvelope: Codable, Sendable {
    public var reqid: String
    public var data: [FirewallPayload]?
    public var req: String
}

public struct FirewallAckEnvelope: Codable, Sendable {
    public var reqid: String
    public var req: String?
    public var code: Int?
    public var msg: String?
    public var data: [FirewallPayload]?
}

public struct FirewallSummary: Sendable {
    public var profile: String
    public var ruleCount: Int
    public var enabled: Bool
}

public enum AddFirewallRuleResult: Sendable {
    case alreadyExists
    case added
}
