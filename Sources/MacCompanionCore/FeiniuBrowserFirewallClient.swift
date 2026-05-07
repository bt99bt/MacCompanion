import Foundation
import WebKit

@MainActor
public final class FeiniuBrowserFirewallClient {
    private let config: FeiniuConfig

    public init(config: FeiniuConfig) {
        self.config = config
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

    private func runFirewallScript(mode: String, ip: String?) async throws -> [String: Any] {
        guard let url = URL(string: config.origin.isEmpty ? config.webURL : config.origin) else {
            throw FeiniuBrowserFirewallError.invalidURL
        }

        let webView = WKWebView(frame: .zero, configuration: makeConfiguration())
        let loader = WebViewLoader()
        webView.navigationDelegate = loader
        try await loader.loadBridgePage(baseURL: url, in: webView)

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(
                Self.script,
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
            throw FeiniuBrowserFirewallError.javascriptException(Self.describe(error))
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

        return object
    }

    private func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return configuration
    }

    static let script = """
    let requestCounter = 0;
    let socketBackID = "0000000000000000";
    let socketSI = "";

    function makeReqID() {
      requestCounter = (requestCounter + 1) & 0xffff;
      const timestamp = Math.floor(Date.now() / 1000).toString(16).padStart(8, "0");
      const counter = requestCounter.toString(16).padStart(4, "0");
      return timestamp + socketBackID + counter;
    }

    function getCookie(name) {
      return document.cookie
        .split(";")
        .map((item) => item.trim())
        .filter(Boolean)
        .map((item) => {
          const separator = item.indexOf("=");
          return separator < 0 ? [item, ""] : [item.slice(0, separator), item.slice(separator + 1)];
        })
        .find(([key]) => key === name)?.[1] || "";
    }

    function bytesToBase64(bytes) {
      let binary = "";
      for (const byte of bytes) {
        binary += String.fromCharCode(byte);
      }
      return btoa(binary);
    }

    function base64Bytes(value) {
      try {
        let normalized = value.trim().replace(/-/g, "+").replace(/_/g, "/");
        while (normalized.length % 4 !== 0) {
          normalized += "=";
        }
        const binary = atob(normalized);
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) {
          bytes[index] = binary.charCodeAt(index);
        }
        return bytes.length > 0 ? bytes : null;
      } catch (_) {
        return null;
      }
    }

    function secretBytes(secret) {
      const base64 = base64Bytes(secret);
      if (base64) {
        return base64;
      }
      if (/^[0-9a-fA-F]+$/.test(secret) && secret.length % 2 === 0) {
        const bytes = new Uint8Array(secret.length / 2);
        for (let index = 0; index < secret.length; index += 2) {
          bytes[index / 2] = Number.parseInt(secret.slice(index, index + 2), 16);
        }
        return bytes;
      }
      return new TextEncoder().encode(secret);
    }

    async function signaturePrefix(text) {
      const secret = localStorage.getItem("fnos-Secret") || "";
      if (!secret) {
        return "";
      }
      const key = await crypto.subtle.importKey(
        "raw",
        secretBytes(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
      );
      const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(text));
      return bytesToBase64(new Uint8Array(signature));
    }

    async function encodeMessage(payload, options = {}) {
      const text = JSON.stringify(payload);
      if (options.plain) {
        return text;
      }
      return (await signaturePrefix(text)) + text;
    }

    function parseMessage(raw) {
      const text = String(raw);
      const start = text.indexOf("{");
      try {
        return JSON.parse(start < 0 ? text : text.slice(start));
      } catch (error) {
        return null;
      }
    }

    function openSocket() {
      return new Promise((resolve, reject) => {
        const socket = new WebSocket(websocketURL);
        const messages = [];
        socket.addEventListener("message", (event) => {
          messages.push(String(event.data).slice(0, 500));
          if (messages.length > 12) {
            messages.shift();
          }
        });
        const timer = setTimeout(() => {
          try { socket.close(); } catch (_) {}
          reject(new Error("飞牛 WebSocket 连接超时"));
        }, 10000);

        socket.onopen = () => {
          clearTimeout(timer);
          resolve({ socket, messages });
        };
        socket.onerror = () => {
          clearTimeout(timer);
          reject(new Error("飞牛 WebSocket 连接错误"));
        };
        socket.onclose = (event) => {
          clearTimeout(timer);
          reject(new Error(`飞牛 WebSocket 已关闭：${event.code} ${event.reason || ""}`));
        };
      });
    }

    function request(socket, messages, payload, options = {}) {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          socket.removeEventListener("message", onMessage);
          reject(new Error(`等待飞牛响应超时：${payload.req}；最近消息：${messages.join(" || ")}`));
        }, 12000);

        const onMessage = (event) => {
          const parsed = parseMessage(event.data);
          if (!parsed || parsed.reqid !== payload.reqid) {
            return;
          }
          clearTimeout(timer);
          socket.removeEventListener("message", onMessage);
          if (parsed.result === "fail") {
            if (parsed.errno === 65534) {
              const message = payload.req === "user.authToken"
                ? "飞牛 WebSocket 认证失败，请重新打开内置网页确认登录态"
                : "飞牛会话无效，请先在内置网页登录后重试";
              reject(new Error(message));
            } else {
              reject(new Error(`飞牛返回失败：errno=${parsed.errno ?? "unknown"} req=${payload.req}`));
            }
            return;
          }
          resolve(parsed);
        };

        socket.addEventListener("message", onMessage);
        encodeMessage(payload, options).then(
          (message) => socket.send(message),
          (error) => {
            clearTimeout(timer);
            socket.removeEventListener("message", onMessage);
            reject(error);
          }
        );
      });
    }

    function describeRemoteError(error) {
      if (!error) {
        return "未知错误";
      }
      if (error.message) {
        return error.message;
      }
      if (typeof error === "object") {
        const parts = [];
        for (const key of ["result", "errno", "code", "type", "errmsg", "req"]) {
          if (error[key] !== undefined && error[key] !== null) {
            parts.push(`${key}=${error[key]}`);
          }
        }
        if (parts.length > 0) {
          return parts.join(" ");
        }
      }
      return String(error);
    }

    async function findOfficialSocket() {
      const scripts = Array.from(document.scripts)
        .map((script) => script.src)
        .filter((src) => src && src.startsWith(location.origin));
      const diagnostics = [];

      for (const src of scripts) {
        try {
          const module = await import(src);
          for (const [name, value] of Object.entries(module)) {
            if (
              value &&
              typeof value === "object" &&
              typeof value.send === "function" &&
              typeof value.useReq === "function" &&
              typeof value.useRes === "function" &&
              value.websocket &&
              String(value.url || "").includes("type=main")
            ) {
              return { socket: value, name };
            }
          }
          diagnostics.push(`${new URL(src).pathname}:no-socket`);
        } catch (error) {
          diagnostics.push(`${new URL(src).pathname}:${describeRemoteError(error)}`);
        }
      }

      throw new Error(`未找到飞牛页面官方 WebSocket 客户端：${diagnostics.slice(0, 4).join("；")}`);
    }

    async function requestWithOfficialPageSession(payload, options = {}) {
      const { socket, name } = await findOfficialSocket();
      if (socket.status !== 1 && typeof socket.init === "function") {
        await socket.init();
      }
      try {
        const response = await socket.send(payload, {
          timeout: options.timeout ?? 12000,
          autoFailTips: false
        });
        response.__macCompanionTransport = `embedded-page:${name}`;
        return response;
      } catch (error) {
        throw new Error(`飞牛内置网页登录态调用失败：${describeRemoteError(error)}`);
      }
    }

    async function prepareSocket(socket, messages) {
      const cryptoInfo = await request(socket, messages, {
        reqid: makeReqID(),
        req: "util.crypto.getRSAPub"
      }, { plain: true });
      if (cryptoInfo.si) {
        socketSI = cryptoInfo.si;
      }
    }

    async function authenticate(socket, messages) {
      const rawToken = getCookie(tokenCookieName);
      const token = rawToken ? decodeURIComponent(rawToken) : "";
      if (!token) {
        throw new Error(`当前飞牛页面没有 ${tokenCookieName} cookie`);
      }
      const auth = await request(socket, messages, {
        reqid: makeReqID(),
        req: "user.authToken",
        token,
        si: socketSI,
        main: true
      });
      if (auth.backId) {
        socketBackID = auth.backId;
      }
      return auth;
    }

    try {
      let socket = null;
      let messages = [];
      let usesOfficialPageSession = false;
      let current;

      let officialPageSessionMiss = "";
      try {
        current = await requestWithOfficialPageSession({
          req: "appcgi.security.firewall.getting"
        });
        usesOfficialPageSession = true;
      } catch (officialError) {
        officialPageSessionMiss = describeRemoteError(officialError);
        if (!String(officialPageSessionMiss).includes("未找到飞牛页面官方 WebSocket 客户端")) {
          throw officialError;
        }
        try {
          const opened = await openSocket();
          socket = opened.socket;
          messages = opened.messages;
          socket.onclose = null;
          socket.onerror = null;
          await prepareSocket(socket, messages);
          await authenticate(socket, messages);

          const getReqID = makeReqID();
          current = await request(socket, messages, {
            reqid: getReqID,
            req: "appcgi.security.firewall.getting"
          });
        } catch (fallbackError) {
          throw new Error(`${officialPageSessionMiss}；备用连接失败：${describeRemoteError(fallbackError)}`);
        }
      }

      const payloads = current.data || [];
      const payload = payloads[0];
      if (!payload || !Array.isArray(payload.rules)) {
        throw new Error("飞牛返回的防火墙配置为空");
      }

      if (mode === "summary") {
        if (socket) {
          socket.close();
        }
        return JSON.stringify({
          profile: payload.profile || "",
          ruleCount: payload.rules.length,
          enabled: Boolean(payload.enable),
          transport: usesOfficialPageSession ? current.__macCompanionTransport : "manual-websocket"
        });
      }

      const exists = payload.rules.some((rule) => {
        return rule &&
          rule.allow === true &&
          rule.enable === true &&
          rule.flowdir === 1 &&
          rule.pro === 1 &&
          rule.ips &&
          rule.ips.type === 0 &&
          rule.ips.ip === ip &&
          rule.ports &&
          rule.ports.type === 1 &&
          rule.ports.ranges &&
          rule.ports.ranges.range &&
          rule.ports.ranges.range.from === portFrom &&
          rule.ports.ranges.range.to === portTo;
      });

      if (exists) {
        if (socket) {
          socket.close();
        }
        return JSON.stringify({
          action: "alreadyExists",
          ip,
          ruleCount: payload.rules.length,
          transport: usesOfficialPageSession ? current.__macCompanionTransport : "manual-websocket"
        });
      }

      const nextPriority = payload.rules.reduce((max, rule) => {
        return Math.max(max, Number(rule.priority ?? -1));
      }, -1) + 1;

      payload.rules.push({
        ifname: "ALL",
        flowdir: 1,
        pro: 1,
        ports: {
          type: 1,
          ranges: {
            range: {
              from: portFrom,
              to: portTo
            }
          }
        },
        ips: {
          type: 0,
          ip
        },
        priority: nextPriority,
        allow: true,
        enable: true,
        memo
      });

      const ack = usesOfficialPageSession
        ? await requestWithOfficialPageSession({
            data: payloads,
            req: "appcgi.security.firewall.setting"
          }, { timeout: 20000 })
        : await request(socket, messages, {
            reqid: makeReqID(),
            data: payloads,
            req: "appcgi.security.firewall.setting"
          });
      if (socket) {
        socket.close();
      }

      if (typeof ack.code === "number" && ack.code !== 0) {
        throw new Error(`飞牛拒绝保存规则：${ack.code} ${ack.msg || ""}`);
      }

      return JSON.stringify({
        action: "added",
        ip,
        ruleCount: payload.rules.length,
        transport: usesOfficialPageSession ? ack.__macCompanionTransport : "manual-websocket"
      });
    } catch (error) {
      return JSON.stringify({
        error: error && error.message ? error.message : String(error)
      });
    }
    """
}

private final class WebViewLoader: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func loadBridgePage(baseURL: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(
                """
                <!doctype html>
                <html>
                  <head><meta charset="utf-8"><title>Mac Companion Bridge</title></head>
                  <body></body>
                </html>
                """,
                baseURL: baseURL
            )
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

enum FeiniuBrowserFirewallError: LocalizedError {
    case invalidURL
    case invalidResult(String)
    case javascript(String)
    case javascriptException(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "飞牛 Web URL 无效"
        case .invalidResult(let value):
            return "飞牛浏览器调用返回异常：\(value)"
        case .javascript(let message):
            return message
        case .javascriptException(let message):
            return "飞牛浏览器脚本执行失败：\(message)"
        }
    }
}

extension FeiniuBrowserFirewallClient {
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfo = nsError.userInfo
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: "; ")
        if userInfo.isEmpty {
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription); \(userInfo)"
    }
}
