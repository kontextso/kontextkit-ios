import Foundation

/// Provides app metadata for ad targeting and analytics. Mirrors Android
/// `AppInfoProvider`; both platforms must report the same shape on the wire.
public enum AppInfoProvider {

    /// App information result.
    public struct AppInfo: Sendable {
        /// Empty string only in pathological hosts with no `CFBundleIdentifier`
        /// (e.g. some command-line tools); real iOS apps always have one.
        public let bundleId: String
        public let version: String
        /// First-install time as Unix epoch milliseconds.
        /// Source: Documents directory creation date (proxy for install time).
        public let firstInstallTime: Int64?
        /// Last app-update time. **Always nil on iOS** — Apple exposes no
        /// public API for "when was this app last updated." The field
        /// exists for cross-platform shape parity with Android, where
        /// `PackageInfo.lastUpdateTime` populates the same slot.
        public let lastUpdateTime: Int64?
    }

    /// Epoch ms when `AppInfoProvider` was first referenced — proxy for
    /// "when the SDK loaded into the host process." Captured at static
    /// init, shared across all Kontext consumer SDKs (sdk-swift,
    /// sdk-react-native iOS, sdk-flutter iOS) so the cross-platform
    /// definition can't drift between collectors.
    public static let processStartMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    /// Collects app metadata.
    public static func collect() -> AppInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppInfo(
            bundleId: Bundle.main.bundleIdentifier ?? "",
            version: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            firstInstallTime: getFirstInstallTime(),
            lastUpdateTime: nil
        )
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly.
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        var dict: [String: Any] = [
            "bundleId": info.bundleId,
            "version": info.version,
            "processStartMs": processStartMs,
        ]
        if let firstInstallTime = info.firstInstallTime {
            dict["firstInstallTime"] = firstInstallTime
        }
        // lastUpdateTime is always nil on iOS — omitted from the dict
        // (matches the "absent over null sentinel" convention).
        return dict
    }

    /// Returns the first-install time as Unix epoch ms, derived from the
    /// Documents directory creation date (Apple's recommended proxy).
    private static func getFirstInstallTime() -> Int64? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attrs = try? FileManager.default.attributesOfItem(atPath: documentsURL.path),
              let creationDate = attrs[.creationDate] as? Date else {
            return nil
        }
        return Int64(creationDate.timeIntervalSince1970 * 1000)
    }
}
