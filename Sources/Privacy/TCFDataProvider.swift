import Foundation

/// Reads IAB Transparency and Consent Framework (TCF) data from UserDefaults.
///
/// CMPs (Consent Management Platforms) store TCF consent signals in UserDefaults
/// using standardized keys prefixed with `IABTCF_`.
///
/// Strict validation at the boundary:
/// - `gdprConsent` must be non-empty (whitespace-only treated as empty).
/// - `gdpr` must be exactly 0 or 1 (per IAB TCF v2.2 spec).
///   Out-of-range values from misbehaving CMPs decay to nil rather
///   than being forwarded to the ad server as junk.
///
/// Field names match openRTB / kontext ad-server's `regulatorySchema`
/// (`gdpr`, `gdprConsent`) rather than the IAB TCF storage spec's wire
/// names (`gdprApplies`, `tcString`) — keeps consumer code aligned with
/// the request shape Preload.swift sends to the server.
public enum TCFDataProvider {

    /// TCF consent data needed for RTB bid requests.
    public struct TCFData: Sendable {
        /// The TC (Transparency & Consent) string, or `nil` if not set
        /// or set to an empty/whitespace-only value.
        public let gdprConsent: String?

        /// Whether GDPR applies: `1` = yes, `0` = no, `nil` = unknown
        /// (key absent OR a non-{0,1} integer was written by a buggy CMP).
        public let gdpr: Int?
    }

    /// Reads TCF data from the standard UserDefaults.
    public static func getTCFData(from defaults: UserDefaults = .standard) -> TCFData {
        return TCFData(
            gdprConsent: normalizedTcString(from: defaults.string(forKey: "IABTCF_TCString")),
            gdpr: normalizedGdprApplies(from: defaults.object(forKey: "IABTCF_gdprApplies"))
        )
    }

    /// Returns TCF data as `NSDictionary` for bridge layers (RN, Flutter).
    public static func getTCFDataAsDict(from defaults: UserDefaults = .standard) -> NSDictionary {
        let tcf = getTCFData(from: defaults)
        return [
            "gdprConsent": tcf.gdprConsent ?? NSNull(),
            "gdpr": tcf.gdpr ?? NSNull(),
        ]
    }

    // MARK: - Private

    /// Returns the TC string only if it's non-empty after trimming
    /// whitespace. Empty/whitespace-only is invalid per IAB spec.
    private static func normalizedTcString(from raw: String?) -> String? {
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return raw
    }

    /// Normalizes the raw `IABTCF_gdprApplies` value to exactly 0 or 1.
    /// Accepts NSNumber, Bool, and String wire shapes (different CMPs
    /// store different types). Anything outside {0, 1} → nil.
    private static func normalizedGdprApplies(from raw: Any?) -> Int? {
        let intValue: Int?
        if let n = raw as? NSNumber {
            intValue = Int(exactly: n.doubleValue)
        } else if let b = raw as? Bool {
            intValue = b ? 1 : 0
        } else if let s = raw as? String, let parsed = Int(s) {
            intValue = parsed
        } else {
            intValue = nil
        }
        guard let intValue, intValue == 0 || intValue == 1 else { return nil }
        return intValue
    }
}
