import AppKit
import Foundation
import ServiceManagement
import WebKit

@MainActor
public final class CompanionModel: ObservableObject {
    @Published public var config = AppConfig.default
    @Published public var username = ""
    @Published public var password = ""
    @Published public var status = "未执行"
    @Published public var loginState = "未检测登录态"
    @Published public var firewallState = "未检测防火墙"
    @Published public var lastPublicIP = "未知"
    @Published public var activityLog: [String] = []
    @Published public var isFeiniuWebLoginPresented = false
    @Published public var isWorking = false
    @Published public var launchAtLoginEnabled = false
    public let feiniuWebSession = FeiniuWebSession()

    private let configStore = ConfigStore()
    private let keychain = KeychainStore(service: "MacCompanion.Feiniu")
    private var sessionToken: String?
    private var shouldAutoVerifyAfterWebSession = false
    private var lastAutoVerifiedToken: String?

    public init() {}

    public func load() {
        do {
            config = try configStore.load()
            configureFeiniuWebSession()
            refreshStoredTokenState()
            refreshLaunchAtLoginState()
            Task { @MainActor in
                await syncFeiniuTokenFromEmbeddedWebIfAvailable()
            }
        } catch {
            setStatus("读取配置失败：\(error.localizedDescription)")
        }
    }

    public func save() {
        do {
            try configStore.save(config)
            configureFeiniuWebSession()
            setStatus("已保存配置")
        } catch {
            setStatus("保存失败：\(error.localizedDescription)")
        }
    }

    public func openFeiniuWeb() {
        save()
        guard let url = feiniuWebURL else {
            setStatus("飞牛 Web URL 无效")
            return
        }
        NSWorkspace.shared.open(url)
        setStatus("已打开飞牛 Web 界面")
    }

    public var feiniuWebURL: URL? {
        URL(string: config.feiniu.webURL)
    }

    public var hasFeiniuSession: Bool {
        guard let sessionToken else { return false }
        return !sessionToken.isEmpty
    }

    public func presentFeiniuWebLogin(autoVerify: Bool = true) {
        guard feiniuWebURL != nil else {
            setStatus("飞牛 Web URL 无效")
            return
        }
        shouldAutoVerifyAfterWebSession = autoVerify
        configureFeiniuWebSession()
        feiniuWebSession.loadIfNeeded()
        isFeiniuWebLoginPresented = true
        setStatus("正在打开飞牛内置网页并读取登录态")
        Task { @MainActor in
            await syncFeiniuTokenFromEmbeddedWebIfAvailable(autoVerify: autoVerify)
        }
    }

    public func dismissFeiniuWebLogin() {
        isFeiniuWebLoginPresented = false
        setStatus(hasFeiniuSession ? "飞牛网页登录态已就绪" : "已关闭飞牛网页登录面板")
    }

    public func syncFeiniuTokenFromEmbeddedWeb() async {
        await run("同步飞牛网页登录态") {
            guard let token = await self.feiniuWebSession.syncTokenFromCookieStore() else {
                throw FeiniuWebLoginError.tokenCookieNotFound
            }
            self.storeFeiniuSessionToken(token)
            return "已同步 \(self.config.feiniu.tokenCookieName)，可以添加白名单"
        }
    }

    public func syncFeiniuTokenFromEmbeddedWebIfAvailable(autoVerify: Bool = false) async {
        guard let token = await feiniuWebSession.syncTokenFromCookieStore() else {
            loginState = "等待内置网页登录态"
            postStatusChange()
            return
        }
        storeFeiniuSessionToken(token)
        setStatus("已自动同步飞牛登录态")
        if autoVerify {
            autoVerifyFeiniuConnectionIfNeeded(token: token)
        }
    }

    public func handleEmbeddedWebToken(_ token: String) {
        let isNewToken = sessionToken != token
        storeFeiniuSessionToken(token)
        if isNewToken {
            setStatus("已检测到飞牛网页登录态")
        } else {
            postStatusChange()
        }
        if shouldAutoVerifyAfterWebSession {
            autoVerifyFeiniuConnectionIfNeeded(token: token)
        }
    }

    public func login() async {
        await run("登录飞牛") {
            self.save()
            let client = FeiniuLoginClient(config: self.config.feiniu, keychain: self.keychain)
            try await client.login(username: self.username, password: self.password)
            return "登录成功，token 已保存到钥匙串"
        }
    }

    public func addCurrentIPToFeiniuFirewall() async {
        await run("添加白名单") {
            self.save()
            try await self.ensureFeiniuSession()
            let ip = try await PublicIPService().fetchIPv4()
            self.lastPublicIP = ip
            let result = try await self.feiniuWebSession.addAllowAllRule(for: ip)
            let summary = try? await self.feiniuWebSession.fetchFirewallSummary()
            if let summary {
                self.firewallState = "已连接：\(summary.profile)，规则 \(summary.ruleCount) 条"
            }
            switch result {
            case .alreadyExists:
                return "当前公网 IP 已在白名单：\(ip)"
            case .added:
                return "已添加当前公网 IP：\(ip)"
            }
        }
    }

    public func verifyFeiniuFirewallConnection() async {
        await run("验证飞牛连接") {
            try await self.ensureFeiniuSession()
            let summary = try await self.feiniuWebSession.fetchFirewallSummary()
            self.firewallState = "已连接：\(summary.profile)，规则 \(summary.ruleCount) 条"
            return "飞牛防火墙连接正常，规则 \(summary.ruleCount) 条"
        }
    }

    public func note(_ value: String) {
        setStatus(value)
    }

    public func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginState()
            setStatus(enabled ? "已开启开机启动" : "已关闭开机启动")
        } catch {
            refreshLaunchAtLoginState()
            setStatus("更新开机启动失败：\(error.localizedDescription)")
        }
    }

    public func ensureFeiniuSession() async throws {
        await syncFeiniuTokenFromEmbeddedWebIfAvailable()
        if hasFeiniuSession {
            return
        }
        presentFeiniuWebLogin(autoVerify: false)
        setStatus("正在等待飞牛网页登录态")
        let token = try await feiniuWebSession.waitForToken(timeout: 30)
        storeFeiniuSessionToken(token)
        setStatus("已取得飞牛网页登录态")
    }

    private func refreshStoredTokenState() {
        if let sessionToken, !sessionToken.isEmpty {
            loginState = "已登录：当前会话可用"
        } else {
            loginState = "未登录"
        }
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    private func configureFeiniuWebSession() {
        feiniuWebSession.configure(
            config: config.feiniu,
            onToken: { [weak self] token in
                self?.handleEmbeddedWebToken(token)
            },
            onNavigation: { [weak self] location in
                self?.note("飞牛网页已加载：\(location)")
            }
        )
    }

    private func extractFeiniuToken(from cookies: [HTTPCookie]) throws -> String {
        guard let cookie = cookies.first(where: { $0.name == config.feiniu.tokenCookieName }), !cookie.value.isEmpty else {
            throw FeiniuWebLoginError.tokenCookieNotFound
        }
        return cookie.value
    }

    private func storeFeiniuSessionToken(_ token: String) {
        sessionToken = token
        loginState = "已登录：当前会话可用"
    }

    private func autoVerifyFeiniuConnectionIfNeeded(token: String) {
        guard lastAutoVerifiedToken != token else { return }
        guard !isWorking else { return }
        shouldAutoVerifyAfterWebSession = false
        lastAutoVerifiedToken = token
        Task { @MainActor in
            await verifyFeiniuFirewallConnection()
        }
    }

    private func currentFeiniuToken() throws -> String {
        if let sessionToken, !sessionToken.isEmpty {
            return sessionToken
        }
        throw FeiniuWebLoginError.tokenCookieNotFound
    }

    private func run(_ name: String, operation: @escaping () async throws -> String) async {
        isWorking = true
        setStatus("\(name)中...")
        do {
            setStatus(try await operation())
        } catch {
            setStatus("\(name)失败：\(error.localizedDescription)")
        }
        isWorking = false
        postStatusChange()
    }

    private func setStatus(_ value: String) {
        status = value
        appendLog(value)
        postStatusChange()
    }

    private func appendLog(_ value: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        activityLog.insert("[\(formatter.string(from: Date()))] \(value)", at: 0)
        if activityLog.count > 80 {
            activityLog.removeLast(activityLog.count - 80)
        }
    }

    private func postStatusChange() {
        NotificationCenter.default.post(name: .companionStatusDidChange, object: self)
    }
}

public extension Notification.Name {
    static let companionStatusDidChange = Notification.Name("MacCompanion.statusDidChange")
}
