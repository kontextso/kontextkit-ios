import Foundation

/// Reads the consent signals a CMP (Consent Management Platform) writes to
/// `UserDefaults` under the IAB's shared keys: TCF v2 (`IABTCF_`), GPP
/// (`IABGPP_`) and the legacy US Privacy string (`IABUSPrivacy_String`).
///
/// Strict validation at the boundary:
/// - Strings must be non-empty (whitespace-only treated as empty).
/// - `gdpr` must be exactly 0 or 1 (per IAB TCF v2.2 spec), whatever type
///   the CMP stored it as. Out-of-range values decay to nil rather than
///   being forwarded to the ad server as junk.
/// - `gppSid` is the section-id list as the GPP in-app spec writes it,
///   `2_7`; a CMP writing `2,7` or a single number is read too.
///
/// Field names match openRTB / the ad servers' `regulatorySchema`
/// (`gdpr`, `gdprConsent`, `gpp`, `gppSid`, `usPrivacy`) rather than the IAB
/// storage keys, so consumer code reads as the request it sends. What the
/// publisher set by hand, and `coppa`, are the consumer's to merge.
public enum ConsentDataProvider {

    public struct ConsentData: Sendable, Equatable {
        /// Whether GDPR applies: `1` = yes, `0` = no, `nil` = unknown
        /// (key absent OR a non-{0,1} value was written by a buggy CMP).
        public let gdpr: Int?
        /// The TC (Transparency & Consent) string.
        public let gdprConsent: String?
        /// The GPP header string.
        public let gpp: String?
        /// The GPP section ids in `gpp`.
        public let gppSid: [Int]?
        /// The US Privacy (CCPA) string.
        public let usPrivacy: String?
    }

    /// Reads the consent keys from the given defaults (the app's standard
    /// defaults, where CMPs write).
    public static func collect(from defaults: UserDefaults = .standard) -> ConsentData {
        ConsentData(
            gdpr: gdprApplies(defaults.object(forKey: "IABTCF_gdprApplies")),
            gdprConsent: nonEmpty(defaults.string(forKey: "IABTCF_TCString")),
            gpp: nonEmpty(defaults.string(forKey: "IABGPP_HDR_GppString")),
            gppSid: gppSections(defaults.object(forKey: "IABGPP_GppSID")),
            usPrivacy: nonEmpty(defaults.string(forKey: "IABUSPrivacy_String"))
        )
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter).
    /// Absent values are `NSNull`.
    public static func collectAsDict(from defaults: UserDefaults = .standard) -> NSDictionary {
        let consent = collect(from: defaults)
        return [
            "gdpr": consent.gdpr ?? NSNull(),
            "gdprConsent": consent.gdprConsent ?? NSNull(),
            "gpp": consent.gpp ?? NSNull(),
            "gppSid": consent.gppSid ?? NSNull(),
            "usPrivacy": consent.usPrivacy ?? NSNull(),
        ]
    }

    // MARK: - Private

    /// The string only if it is non-empty after trimming whitespace.
    private static func nonEmpty(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }

    /// `IABTCF_gdprApplies` as CMPs actually write it: NSNumber, Bool or
    /// String. Exactly 0 or 1; anything else is unknown.
    private static func gdprApplies(_ raw: Any?) -> Int? {
        let value: Int?
        if let number = raw as? NSNumber {
            value = Int(exactly: number.doubleValue)
        } else if let bool = raw as? Bool {
            value = bool ? 1 : 0
        } else if let string = raw as? String {
            value = Int(string.trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
        guard let value, value == 0 || value == 1 else { return nil }
        return value
    }

    /// `IABGPP_GppSID`: `2_7` or `2,7`, or a single number.
    private static func gppSections(_ raw: Any?) -> [Int]? {
        if let number = raw as? NSNumber, let section = Int(exactly: number.doubleValue) {
            return [section]
        }
        guard let string = raw as? String else { return nil }
        let sections = string.split(whereSeparator: { $0 == "_" || $0 == "," }).compactMap { Int($0) }
        return sections.isEmpty ? nil : sections
    }
}
