import Foundation
import WebKit

@MainActor
public final class FeiniuWebSession: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
    public let webView: WKWebView

    private var config = AppConfig.default.feiniu
    private var hasStartedLoading = false
    private var isLoaded = false
    private var loadContinuations: [CheckedContinuation<Void, Error>] = []
    private var currentToken: String?
    private var tokenContinuation: CheckedContinuation<String, Error>?
    private var onToken: ((String) -> Void)?
    private var onNavigation: ((String) -> Void)?
    private var onDiagnostic: ((String) -> Void)?

    public override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
    }

    public func configure(
        config: FeiniuConfig,
        onToken: @escaping (String) -> Void,
        onNavigation: @escaping (String) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        self.config = config
        self.onToken = onToken
        self.onNavigation = onNavigation
        self.onDiagnostic = onDiagnostic
    }

    public func loadIfNeeded() {
        guard !hasStartedLoading else {
            inspectCookies()
            return
        }
        load()
    }

    public func load() {
        guard let url = URL(string: config.webURL) else {
            onNavigation?("飞牛 Web URL 无效")
            return
        }
        hasStartedLoading = true
        isLoaded = false
        webView.load(URLRequest(url: url))
    }

    public func ensureLoaded() async throws {
        if isLoaded {
            inspectCookies()
            return
        }
        if !hasStartedLoading {
            load()
        }
        try await withCheckedThrowingContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    public func waitForToken(timeout: TimeInterval) async throws -> String {
        if let currentToken, !currentToken.isEmpty {
            return currentToken
        }
        if let token = await syncTokenFromCookieStore() {
            return token
        }
        loadIfNeeded()

        return try await withCheckedThrowingContinuation { continuation in
            if let currentToken, !currentToken.isEmpty {
                continuation.resume(returning: currentToken)
                return
            }
            tokenContinuation = continuation
            inspectCookies()

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    guard let self, let continuation = self.tokenContinuation else { return }
                    self.tokenContinuation = nil
                    continuation.resume(throwing: FeiniuWebLoginError.tokenCookieNotFound)
                }
            }
        }
    }

    public func syncTokenFromCookieStore() async -> String? {
        let tokenCookieName = config.tokenCookieName
        return await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let token = cookies.first(where: { $0.name == tokenCookieName })?.value
                DispatchQueue.main.async {
                    guard let token, !token.isEmpty else {
                        continuation.resume(returning: nil)
                        return
                    }
                    self.acceptToken(token)
                    continuation.resume(returning: token)
                }
            }
        }
    }

    public func fetchFirewallSummary() async throws -> FirewallSummary {
        let result = try await runFirewallScript(mode: "summary", ip: nil)
        guard let profile = result["profile"] as? String,
              let ruleCount = result["ruleCount"] as? Int,
              let enabled = result["enabled"] as? Bool
        else {
            throw FeiniuBrowserFirewallError.invalidResult(String(describing: result))
        }
        return FirewallSummary(profile: profile, ruleCount: ruleCount, enabled: enabled)
    }

    public func addAllowAllRule(for ip: String) async throws -> AddFirewallRuleResult {
        let result = try await runFirewallScript(mode: "add", ip: ip)
        guard let action = result["action"] as? String else {
            throw FeiniuBrowserFirewallError.invalidResult(String(describing: result))
        }
        switch action {
        case "alreadyExists":
            return .alreadyExists
        case "added":
            return .added
        default:
            throw FeiniuBrowserFirewallError.invalidResult(String(describing: result))
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        onNavigation?(webView.url?.absoluteString ?? "页面已加载")
        inspectCookies()
        resumeLoadContinuations()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoaded = false
        resumeLoadContinuations(throwing: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoaded = false
        resumeLoadContinuations(throwing: error)
    }

    public func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        inspectCookies()
    }

    private func inspectCookies() {
        let tokenCookieName = config.tokenCookieName
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            guard let token = cookies.first(where: { $0.name == tokenCookieName })?.value, !token.isEmpty else {
                return
            }
            DispatchQueue.main.async {
                self.acceptToken(token)
            }
        }
    }

    private func acceptToken(_ token: String) {
        currentToken = token
        onToken?(token)
        resumeTokenContinuation(with: token)
    }

    private func runFirewallScript(mode: String, ip: String?) async throws -> [String: Any] {
        try await ensureLoaded()

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(
                FeiniuBrowserFirewallClient.script,
                arguments: [
                    "websocketURL": config.websocketURL,
                    "tokenCookieName": config.tokenCookieName,
                    "mode": mode,
                    "ip": ip ?? "",
                    "memo": config.memo,
                    "portFrom": config.portRange.from,
                    "portTo": config.portRange.to
                ],
                in: nil,
                contentWorld: .page
            )
        } catch {
            throw FeiniuBrowserFirewallError.javascriptException(FeiniuBrowserFirewallClient.describe(error))
        }

        guard let json = raw as? String, let data = json.data(using: .utf8) else {
            throw FeiniuBrowserFirewallError.invalidResult(String(describing: raw))
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FeiniuBrowserFirewallError.invalidResult(json)
        }

        if let error = object["error"] as? String {
            throw FeiniuBrowserFirewallError.javascript(error)
        }

        if let warning = object["warning"] as? String, !warning.isEmpty {
            onDiagnostic?(warning)
        }
        if let transport = object["transport"] as? String, !transport.isEmpty {
            onDiagnostic?("飞牛防火墙调用通道：\(transport)")
        }

        return object
    }

    private func resumeLoadContinuations(throwing error: Error? = nil) {
        let continuations = loadContinuations
        loadContinuations.removeAll()
        for continuation in continuations {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func resumeTokenContinuation(with token: String) {
        guard let continuation = tokenContinuation else { return }
        tokenContinuation = nil
        continuation.resume(returning: token)
    }
}
