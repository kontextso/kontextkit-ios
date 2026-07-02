import WebKit

/// Provides network information for ad targeting and analytics.
///
/// Only `userAgent` is collected on-device. `type` detection was removed
/// (it relied on an `NWPathMonitor` whose non-one-shot `pathUpdateHandler`
/// resumed a `CheckedContinuation` twice and crashed the app —
/// EXC_BREAKPOINT — on flapping / constrained networks), and `carrier` /
/// `detail` are no longer collected. The ad server does not use these
/// fields for ad selection, so dropping them is behaviourally safe.
public enum NetworkInfoProvider {

    /// Cached user agent string (collected once via WKWebView). Marked
    /// `@MainActor` because every reader is on the main actor — silences
    /// Swift 6 strict-concurrency warnings without a separate actor.
    @MainActor
    private static var cachedUserAgent: String?

    /// Network information result. `type` and `carrier` are kept in the
    /// shape (always nil) so the wire format stays stable and a value can be
    /// reintroduced later without a breaking change; only `userAgent` is
    /// populated today.
    public struct NetworkInfo: Sendable {
        public let type: String?       // "wifi", "cellular", "ethernet", "other" — always nil
        public let carrier: String?    // always nil
        public let userAgent: String?  // Browser user agent string
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly. Nil fields are dropped so
    /// consumers see "field absent" rather than `NSNull`.
    @MainActor
    public static func collectAsDict() async -> [String: Any] {
        let info = await collect()
        var dict: [String: Any] = [:]
        if let type = info.type { dict["type"] = type }
        if let carrier = info.carrier { dict["carrier"] = carrier }
        if let userAgent = info.userAgent { dict["userAgent"] = userAgent }
        return dict
    }

    /// Collects network information asynchronously. Only `userAgent` is
    /// resolved (via WKWebView); `type` and `carrier` are always nil.
    @MainActor
    public static func collect() async -> NetworkInfo {
        NetworkInfo(
            type: nil,
            carrier: nil,
            userAgent: await currentUserAgent()
        )
    }

    // MARK: - Private

    @MainActor
    private static func currentUserAgent() async -> String? {
        if let cached = cachedUserAgent {
            return cached
        }
        let webView = WKWebView(frame: .zero)
        let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String
        cachedUserAgent = ua
        return ua
    }
}
