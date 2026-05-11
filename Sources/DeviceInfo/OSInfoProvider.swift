import Foundation
import UIKit

/// Provides OS-level metadata (name, version, locale, timezone) for ad
/// targeting. Centralised here so every iOS-using SDK (sdk-swift,
/// sdk-react-native, sdk-flutter) reports values that match the server's
/// `osSchema` — in particular a **BCP-47** locale tag and a lowercase
/// platform name.
public enum OSInfoProvider {

    public struct OSInfo: Sendable {
        public let name: String       // Always "ios" on iOS — matches server's `osSchema` example
        public let version: String    // e.g. "17.4"
        public let locale: String     // BCP-47, e.g. "en-US" (NOT POSIX "en_US")
        public let timezone: String   // IANA, e.g. "Europe/Prague"
    }

    @MainActor
    public static func collect() -> OSInfo {
        OSInfo(
            name: "ios",
            version: UIDevice.current.systemVersion,
            locale: bcp47Locale(),
            timezone: TimeZone.current.identifier
        )
    }

    /// Returns the current locale as a BCP-47 language tag (`en-US`).
    ///
    /// `Locale.current.identifier` returns POSIX form (`en_US`), which the
    /// server stores but doesn't match the documented `osSchema.locale`
    /// shape ("BCP-47, e.g. cs-CZ"). iOS 16+ exposes `.identifier(.bcp47)`;
    /// for iOS 14/15 we compose the tag from `languageCode` +
    /// `regionCode`, which is what the old sdk-swift's PR #71 settled on.
    static func bcp47Locale() -> String {
        if #available(iOS 16, *) {
            return Locale.current.identifier(.bcp47)
        }
        let language = Locale.current.languageCode ?? "en"
        if let region = Locale.current.regionCode, !region.isEmpty {
            return "\(language)-\(region)"
        }
        return language
    }

    /// Dictionary representation for bridge layers (RN, Flutter).
    @MainActor
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        return [
            "name": info.name,
            "version": info.version,
            "locale": info.locale,
            "timezone": info.timezone,
        ]
    }
}
