import SwiftUI
import WebKit

public struct FeiniuWebView: NSViewRepresentable {
    public let session: FeiniuWebSession

    public init(session: FeiniuWebSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> WKWebView {
        session.loadIfNeeded()
        return session.webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        session.loadIfNeeded()
    }
}
