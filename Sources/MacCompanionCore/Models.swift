import Foundation

public struct AppConfig: Codable, Sendable {
    public var feiniu: FeiniuConfig
    public var restrictedWiFi: RestrictedWiFiConfig
    public var wifiCodeServerDeploy: WiFiCodeServerDeployConfig
    public var clipboardHistory: ClipboardHistoryConfig
    public var cachedPublicIPv4: String?

    public static let `default` = AppConfig(
        cachedPublicIPv4: nil,
        feiniu: FeiniuConfig(
            webURL: "https://your-feiniu.example.com",
            websocketURL: "wss://your-feiniu.example.com/websocket?type=main",
            origin: "https://your-feiniu.example.com",
            loginURL: "https://your-feiniu.example.com",
            loginMethod: "POST",
            loginContentType: "application/json",
            loginBodyTemplate: #"{"username":"{username}","password":"{password}"}"#,
            tokenCookieName: "fnos-token",
            language: "zh-CN",
            memo: "Mac伴侣",
            portRange: PortRange(from: 1, to: 65535)
        ),
        restrictedWiFi: RestrictedWiFiConfig(
            phoneNumber: "",
            countryCode: "+86",
            targetIPPrefix: "10.50.",
            connectivityCheckURL: "http://connect.rom.miui.com/generate_204",
            expectedConnectivityStatusCode: 204,
            portalLoginURL: "https://cloud-guest.botanee.com.cn:9100/login",
            portalPageURL: "https://terminalsmex.botanee.com.cn:10443/multiple-pages/guest-wifi-login.html",
            smsAPIURL: "https://terminalsmex.botanee.com.cn:10443/api/v1/wifi/guest/portal/apply/sms_self_service",
            apMAC: "00:00:00:00:00:71",
            nasIP: "10.55.1.253",
            defaultAuthType: "sms",
            language: "zh-CN",
            os: "web",
            smsReason: 1,
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36",
            pollIntervalSeconds: 5,
            pollAttempts: 12,
            dnsCodeLookupDomain: "code.code.example.com",
            dnsHealthLookupDomain: "health.code.example.com",
            dnsHealthExpectedAddress: "1.255.255.255",
            serverCodeURL: "",
            serverCodeMethod: "GET",
            serverCodeJSONPath: "code",
            serverCodeEnabled: false
        ),
        wifiCodeServerDeploy: WiFiCodeServerDeployConfig(
            sshHost: "",
            sshPort: 22,
            sshUsername: "",
            remoteWorkDirectory: "~/wifi-code-server",
            baseDomain: "",
            containerName: "wifi-code-server",
            imageName: "wifi-code-server:latest",
            httpPort: 8080,
            dnsPort: 53,
            allowDockerInstall: true,
            stopConflictingKnownContainers: false
        ),
        clipboardHistory: ClipboardHistoryConfig(
            isEnabled: true,
            persistHistory: true,
            maxItems: 100,
            maxTextLength: 20_000,
            pollIntervalSeconds: 0.5,
            ignoresSensitiveText: false,
            trigger: ClipboardTriggerConfig(
                mode: .middleMouse,
                keyboardShortcut: "cmd+option+v",
                swallowMiddleMouseClick: true
            )
        )
    )

    enum CodingKeys: String, CodingKey {
        case feiniu
        case restrictedWiFi
        case wifiCodeServerDeploy
        case clipboardHistory
        case cachedPublicIPv4
    }

    public init(
        cachedPublicIPv4: String?,
        feiniu: FeiniuConfig,
        restrictedWiFi: RestrictedWiFiConfig,
        wifiCodeServerDeploy: WiFiCodeServerDeployConfig,
        clipboardHistory: ClipboardHistoryConfig
    ) {
        self.cachedPublicIPv4 = cachedPublicIPv4
        self.feiniu = feiniu
        self.restrictedWiFi = restrictedWiFi
        self.wifiCodeServerDeploy = wifiCodeServerDeploy
        self.clipboardHistory = clipboardHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feiniu = try container.decodeIfPresent(FeiniuConfig.self, forKey: .feiniu) ?? AppConfig.default.feiniu
        restrictedWiFi = try container.decodeIfPresent(RestrictedWiFiConfig.self, forKey: .restrictedWiFi) ?? AppConfig.default.restrictedWiFi
        wifiCodeServerDeploy = try container.decodeIfPresent(WiFiCodeServerDeployConfig.self, forKey: .wifiCodeServerDeploy) ?? AppConfig.default.wifiCodeServerDeploy
        clipboardHistory = try container.decodeIfPresent(ClipboardHistoryConfig.self, forKey: .clipboardHistory) ?? AppConfig.default.clipboardHistory
        cachedPublicIPv4 = try container.decodeIfPresent(String.self, forKey: .cachedPublicIPv4)
    }
}

public struct ClipboardHistoryConfig: Codable, Sendable {
    public var isEnabled: Bool
    public var persistHistory: Bool
    public var maxItems: Int
    public var maxTextLength: Int
    public var pollIntervalSeconds: Double
    public var ignoresSensitiveText: Bool
    public var trigger: ClipboardTriggerConfig

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case persistHistory
        case maxItems
        case maxTextLength
        case pollIntervalSeconds
        case ignoresSensitiveText
        case trigger
    }

    public init(
        isEnabled: Bool,
        persistHistory: Bool,
        maxItems: Int,
        maxTextLength: Int,
        pollIntervalSeconds: Double,
        ignoresSensitiveText: Bool,
        trigger: ClipboardTriggerConfig
    ) {
        self.isEnabled = isEnabled
        self.persistHistory = persistHistory
        self.maxItems = maxItems
        self.maxTextLength = maxTextLength
        self.pollIntervalSeconds = pollIntervalSeconds
        self.ignoresSensitiveText = ignoresSensitiveText
        self.trigger = trigger
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppConfig.default.clipboardHistory
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        persistHistory = try container.decodeIfPresent(Bool.self, forKey: .persistHistory) ?? defaults.persistHistory
        maxItems = try container.decodeIfPresent(Int.self, forKey: .maxItems) ?? defaults.maxItems
        maxTextLength = try container.decodeIfPresent(Int.self, forKey: .maxTextLength) ?? defaults.maxTextLength
        pollIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? defaults.pollIntervalSeconds
        ignoresSensitiveText = try container.decodeIfPresent(Bool.self, forKey: .ignoresSensitiveText) ?? defaults.ignoresSensitiveText
        trigger = try container.decodeIfPresent(ClipboardTriggerConfig.self, forKey: .trigger) ?? defaults.trigger
    }
}

public struct ClipboardTriggerConfig: Codable, Sendable {
    public var mode: ClipboardTriggerMode
    public var keyboardShortcut: String
    public var swallowMiddleMouseClick: Bool

    public init(mode: ClipboardTriggerMode, keyboardShortcut: String, swallowMiddleMouseClick: Bool) {
        self.mode = mode
        self.keyboardShortcut = keyboardShortcut
        self.swallowMiddleMouseClick = swallowMiddleMouseClick
    }
}

public enum ClipboardTriggerMode: String, Codable, CaseIterable, Sendable {
    case middleMouse
    case keyboard

    public var title: String {
        switch self {
        case .middleMouse: "鼠标中键"
        case .keyboard: "键盘快捷键"
        }
    }
}

public struct ClipboardHistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), lastUsedAt: Date? = nil, useCount: Int = 0) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}

public enum CompanionLogScope: String, CaseIterable, Sendable {
    case feiniu
    case network
    case clipboard
    case settings
    case automation
    case general
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

public struct RestrictedWiFiConfig: Codable, Sendable {
    public var phoneNumber: String
    public var countryCode: String
    public var targetIPPrefix: String
    public var connectivityCheckURL: String
    public var expectedConnectivityStatusCode: Int
    public var portalLoginURL: String
    public var portalPageURL: String
    public var smsAPIURL: String
    public var apMAC: String
    public var nasIP: String
    public var defaultAuthType: String
    public var language: String
    public var os: String
    public var smsReason: Int
    public var userAgent: String
    public var pollIntervalSeconds: Int
    public var pollAttempts: Int
    public var dnsCodeLookupDomain: String
    public var dnsHealthLookupDomain: String
    public var dnsHealthExpectedAddress: String
    public var serverCodeURL: String
    public var serverCodeMethod: String
    public var serverCodeJSONPath: String
    public var serverCodeEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case phoneNumber
        case countryCode
        case targetIPPrefix
        case connectivityCheckURL
        case expectedConnectivityStatusCode
        case portalLoginURL
        case portalPageURL
        case smsAPIURL
        case apMAC
        case nasIP
        case defaultAuthType
        case language
        case os
        case smsReason
        case userAgent
        case pollIntervalSeconds
        case pollAttempts
        case dnsCodeLookupDomain
        case dnsHealthLookupDomain
        case dnsHealthExpectedAddress
        case serverCodeURL
        case serverCodeMethod
        case serverCodeJSONPath
        case serverCodeEnabled
    }

    public init(
        phoneNumber: String,
        countryCode: String,
        targetIPPrefix: String,
        connectivityCheckURL: String,
        expectedConnectivityStatusCode: Int,
        portalLoginURL: String,
        portalPageURL: String,
        smsAPIURL: String,
        apMAC: String,
        nasIP: String,
        defaultAuthType: String,
        language: String,
        os: String,
        smsReason: Int,
        userAgent: String,
        pollIntervalSeconds: Int,
        pollAttempts: Int,
        dnsCodeLookupDomain: String,
        dnsHealthLookupDomain: String,
        dnsHealthExpectedAddress: String,
        serverCodeURL: String,
        serverCodeMethod: String,
        serverCodeJSONPath: String,
        serverCodeEnabled: Bool
    ) {
        self.phoneNumber = phoneNumber
        self.countryCode = countryCode
        self.targetIPPrefix = targetIPPrefix
        self.connectivityCheckURL = connectivityCheckURL
        self.expectedConnectivityStatusCode = expectedConnectivityStatusCode
        self.portalLoginURL = portalLoginURL
        self.portalPageURL = portalPageURL
        self.smsAPIURL = smsAPIURL
        self.apMAC = apMAC
        self.nasIP = nasIP
        self.defaultAuthType = defaultAuthType
        self.language = language
        self.os = os
        self.smsReason = smsReason
        self.userAgent = userAgent
        self.pollIntervalSeconds = pollIntervalSeconds
        self.pollAttempts = pollAttempts
        self.dnsCodeLookupDomain = dnsCodeLookupDomain
        self.dnsHealthLookupDomain = dnsHealthLookupDomain
        self.dnsHealthExpectedAddress = dnsHealthExpectedAddress
        self.serverCodeURL = serverCodeURL
        self.serverCodeMethod = serverCodeMethod
        self.serverCodeJSONPath = serverCodeJSONPath
        self.serverCodeEnabled = serverCodeEnabled
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppConfig.default.restrictedWiFi
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? defaults.phoneNumber
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? defaults.countryCode
        targetIPPrefix = try container.decodeIfPresent(String.self, forKey: .targetIPPrefix) ?? defaults.targetIPPrefix
        connectivityCheckURL = try container.decodeIfPresent(String.self, forKey: .connectivityCheckURL) ?? defaults.connectivityCheckURL
        expectedConnectivityStatusCode = try container.decodeIfPresent(Int.self, forKey: .expectedConnectivityStatusCode) ?? defaults.expectedConnectivityStatusCode
        portalLoginURL = try container.decodeIfPresent(String.self, forKey: .portalLoginURL) ?? defaults.portalLoginURL
        portalPageURL = try container.decodeIfPresent(String.self, forKey: .portalPageURL) ?? defaults.portalPageURL
        smsAPIURL = try container.decodeIfPresent(String.self, forKey: .smsAPIURL) ?? defaults.smsAPIURL
        apMAC = try container.decodeIfPresent(String.self, forKey: .apMAC) ?? defaults.apMAC
        nasIP = try container.decodeIfPresent(String.self, forKey: .nasIP) ?? defaults.nasIP
        defaultAuthType = try container.decodeIfPresent(String.self, forKey: .defaultAuthType) ?? defaults.defaultAuthType
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? defaults.language
        os = try container.decodeIfPresent(String.self, forKey: .os) ?? defaults.os
        smsReason = try container.decodeIfPresent(Int.self, forKey: .smsReason) ?? defaults.smsReason
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent) ?? defaults.userAgent
        pollIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? defaults.pollIntervalSeconds
        pollAttempts = try container.decodeIfPresent(Int.self, forKey: .pollAttempts) ?? defaults.pollAttempts
        dnsCodeLookupDomain = try container.decodeIfPresent(String.self, forKey: .dnsCodeLookupDomain) ?? defaults.dnsCodeLookupDomain
        dnsHealthLookupDomain = try container.decodeIfPresent(String.self, forKey: .dnsHealthLookupDomain) ?? defaults.dnsHealthLookupDomain
        dnsHealthExpectedAddress = try container.decodeIfPresent(String.self, forKey: .dnsHealthExpectedAddress) ?? defaults.dnsHealthExpectedAddress
        serverCodeURL = try container.decodeIfPresent(String.self, forKey: .serverCodeURL) ?? defaults.serverCodeURL
        serverCodeMethod = try container.decodeIfPresent(String.self, forKey: .serverCodeMethod) ?? defaults.serverCodeMethod
        serverCodeJSONPath = try container.decodeIfPresent(String.self, forKey: .serverCodeJSONPath) ?? defaults.serverCodeJSONPath
        serverCodeEnabled = try container.decodeIfPresent(Bool.self, forKey: .serverCodeEnabled) ?? defaults.serverCodeEnabled
    }
}

public struct WiFiCodeServerDeployConfig: Codable, Sendable {
    public var sshHost: String
    public var sshPort: Int
    public var sshUsername: String
    public var remoteWorkDirectory: String
    public var baseDomain: String
    public var containerName: String
    public var imageName: String
    public var httpPort: Int
    public var dnsPort: Int
    public var allowDockerInstall: Bool
    public var stopConflictingKnownContainers: Bool

    enum CodingKeys: String, CodingKey {
        case sshHost
        case sshPort
        case sshUsername
        case remoteWorkDirectory
        case baseDomain
        case containerName
        case imageName
        case httpPort
        case dnsPort
        case allowDockerInstall
        case stopConflictingKnownContainers
    }

    public init(
        sshHost: String,
        sshPort: Int,
        sshUsername: String,
        remoteWorkDirectory: String,
        baseDomain: String,
        containerName: String,
        imageName: String,
        httpPort: Int,
        dnsPort: Int,
        allowDockerInstall: Bool,
        stopConflictingKnownContainers: Bool
    ) {
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.remoteWorkDirectory = remoteWorkDirectory
        self.baseDomain = baseDomain
        self.containerName = containerName
        self.imageName = imageName
        self.httpPort = httpPort
        self.dnsPort = dnsPort
        self.allowDockerInstall = allowDockerInstall
        self.stopConflictingKnownContainers = stopConflictingKnownContainers
    }

    public init(from decoder: Decoder) throws {
        let defaults = AppConfig.default.wifiCodeServerDeploy
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? defaults.sshHost
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? defaults.sshPort
        sshUsername = try container.decodeIfPresent(String.self, forKey: .sshUsername) ?? defaults.sshUsername
        remoteWorkDirectory = try container.decodeIfPresent(String.self, forKey: .remoteWorkDirectory) ?? defaults.remoteWorkDirectory
        baseDomain = try container.decodeIfPresent(String.self, forKey: .baseDomain) ?? defaults.baseDomain
        containerName = try container.decodeIfPresent(String.self, forKey: .containerName) ?? defaults.containerName
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName) ?? defaults.imageName
        httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? defaults.httpPort
        dnsPort = try container.decodeIfPresent(Int.self, forKey: .dnsPort) ?? defaults.dnsPort
        allowDockerInstall = try container.decodeIfPresent(Bool.self, forKey: .allowDockerInstall) ?? defaults.allowDockerInstall
        stopConflictingKnownContainers = try container.decodeIfPresent(Bool.self, forKey: .stopConflictingKnownContainers) ?? defaults.stopConflictingKnownContainers
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
