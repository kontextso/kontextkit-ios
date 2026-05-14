import CoreTelephony
import Network
import WebKit

/// Provides network information for ad targeting and analytics.
public enum NetworkInfoProvider {

    /// Cached user agent string (collected once via WKWebView). Marked
    /// `@MainActor` because every reader is on the main actor — silences
    /// Swift 6 strict-concurrency warnings without a separate actor.
    @MainActor
    private static var cachedUserAgent: String?

    /// Network information result.
    public struct NetworkInfo: Sendable {
        public let type: String        // "wifi", "cellular", "ethernet", "other"
        /// Always `nil` on iOS 16+: Apple removed access to carrier
        /// metadata (`CTCarrier.carrierName` returns "—" / nil and the
        /// underlying `serviceSubscriberCellularProviders` is deprecated).
        /// Kept in the schema so the wire shape stays stable across
        /// iOS versions and other platforms (Android still reports
        /// carrier where possible).
        public let carrier: String?
        public let detail: String?     // "5g", "lte", "3g", "2g", "hspa", "edge", "gprs"
        public let userAgent: String?  // Browser user agent string
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly.
    @MainActor
    public static func collectAsDict() async -> [String: Any] {
        let info = await collect()
        var dict: [String: Any] = ["type": info.type]
        if let carrier = info.carrier { dict["carrier"] = carrier }
        if let detail = info.detail { dict["detail"] = detail }
        if let userAgent = info.userAgent { dict["userAgent"] = userAgent }
        return dict
    }

    /// Collects network information asynchronously.
    ///
    /// `type` is resolved by spinning up a one-shot `NWPathMonitor` and
    /// awaiting its first `pathUpdateHandler` callback (mirrors v3
    /// sdk-swift's pattern; an unstarted monitor's `currentPath` returns
    /// stale/`.unsatisfied` data). The monitor is cancelled inside the
    /// handler so it doesn't outlive the call.
    ///
    /// `carrier` is intentionally always nil on iOS 16+ — see field doc.
    /// `detail` (radio access technology) still works on modern iOS
    /// because `serviceCurrentRadioAccessTechnology` was kept; only
    /// `CTCarrier.carrierName` was removed.
    @MainActor
    public static func collect() async -> NetworkInfo {
        // `async let` runs both async sub-tasks concurrently (Swift's
        // equivalent of JS `Promise.all`). `currentNetworkType()` waits
        // up to 100ms on `NWPathMonitor`; `currentUserAgent()` blocks on
        // WKWebView's `evaluateJavaScript`. Sequential awaits would add
        // their latencies; concurrent awaits cap at the slower of the two.
        async let type = currentNetworkType()
        async let userAgent = currentUserAgent()

        let resolvedType = await type
        // CoreTelephony reports the cellular radio's access tech even
        // when Wi-Fi is the active path (the radio stays up on 5G/LTE
        // for calls and fallback). Gating on `type == "cellular"`
        // keeps `detail` describing the connection that's actually
        // carrying data. Mirrors sdk-react-native's
        // AdsProvider.tsx behaviour.
        let detail = resolvedType == "cellular" ? currentRadioDetail() : nil

        return NetworkInfo(
            type: resolvedType,
            carrier: nil,
            detail: detail,
            userAgent: await userAgent
        )
    }

    // MARK: - Private

    /// Resolves the current network type, with a 100ms safety-net timeout
    /// that returns `"other"` if `NWPathMonitor.pathUpdateHandler` never
    /// fires (rare — the OS normally has a path cached and the handler
    /// fires within a few milliseconds, but the simulator and freshly
    /// restored devices have been observed to stall indefinitely).
    private static func currentNetworkType() async -> String {
        await withTaskGroup(of: String.self) { group in
            group.addTask { await observeNetworkType() }
            group.addTask {
                try? await Task.sleep(nanoseconds: 100_000_000)
                return "other"
            }
            let first = await group.next() ?? "other"
            group.cancelAll()
            return first
        }
    }

    /// One-shot `NWPathMonitor` read: `pathUpdateHandler` fires once with
    /// the current state, we cancel the monitor, resume the continuation.
    /// Mirrors v3 sdk-swift's pattern.
    private static func observeNetworkType() async -> String {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let type: String
                if path.usesInterfaceType(.wifi) {
                    type = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    type = "cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    type = "ethernet"
                } else {
                    type = "other"
                }
                monitor.cancel()
                continuation.resume(returning: type)
            }
            monitor.start(queue: DispatchQueue.global(qos: .background))
        }
    }

    /// Reads the current radio access technology synchronously.
    /// Multi-SIM aware via `dataServiceIdentifier` (iOS 13+), with
    /// fallback to the first available provider for older devices.
    private static func currentRadioDetail() -> String? {
        let info = CTTelephonyNetworkInfo()
        let radioAccess: String?
        if #available(iOS 13.0, *),
           let dataId = info.dataServiceIdentifier,
           let dict = info.serviceCurrentRadioAccessTechnology {
            radioAccess = dict[dataId] ?? dict.values.first
        } else {
            radioAccess = info.serviceCurrentRadioAccessTechnology?.values.first
        }
        guard let radioAccess else { return nil }
        return mapRadioAccess(radioAccess)
    }

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

    /// Maps a raw `CTRadioAccessTechnology*` constant to a wire-friendly
    /// detail string. Internal (not private) so unit tests can exercise
    /// the table without needing `CTTelephonyNetworkInfo`.
    static func mapRadioAccess(_ radioAccess: String) -> String? {
        switch radioAccess {
        case CTRadioAccessTechnologyGPRS: return "gprs"
        case CTRadioAccessTechnologyEdge: return "edge"
        case CTRadioAccessTechnologyWCDMA: return "3g"
        case CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA: return "hspa"
        case CTRadioAccessTechnologyCDMA1x: return "2g"
        case CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD: return "3g"
        case CTRadioAccessTechnologyLTE: return "lte"
        default:
            if #available(iOS 14.1, *) {
                if radioAccess == CTRadioAccessTechnologyNRNSA || radioAccess == CTRadioAccessTechnologyNR {
                    return "5g"
                }
            }
            return nil
        }
    }
}
