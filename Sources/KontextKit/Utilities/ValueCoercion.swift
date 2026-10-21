import Foundation

// Shared loose-typed coercion helpers used when parsing the `[String: Any]`
// dicts produced by JSONSerialization from JS-side payloads. Both
// `string` and `int` accept the usual Objective-C JSON bridging
// types (String, NSNumber, Int) so the managers can stay agnostic to
// whether the ad server sent, for example, `itunesItem: "123"` or
// `itunesItem: 123`.
//
// Strict by design:
// - `string` rejects empty AND whitespace-only strings.
// - `int` rejects fractional values (a fractional `itunesItem` /
//   `campaign` / `timestamp` indicates a server bug; silently
//   truncating would hide it).

enum ValueCoercion {
    /// Returns a non-empty trimmed-non-empty String. Accepts:
    /// - String (rejected if empty after trimming whitespace)
    /// - NSNumber (converted via `.stringValue` — e.g. NSNumber(42) → "42")
    /// Returns nil for everything else.
    static func string(_ value: Any?) -> String? {
        if let string = value as? String,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    /// Returns an Int. Accepts:
    /// - Int directly
    /// - NSNumber whose value is an exact integer (`42`, `42.0` → 42;
    ///   `42.5` → nil). JSONSerialization can return Double-typed
    ///   NSNumbers for any JSON number — Swift's `as? Int` would
    ///   reject those even when they hold exact integers, so this
    ///   branch checks `doubleValue == rounded` instead.
    /// - String parseable as Int via the strict `Int(_:)` initialiser
    ///   (no leading/trailing whitespace, no decimal point).
    /// Returns nil for fractional NSNumbers, out-of-range values, and
    /// everything else.
    static func int(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return Int(exactly: number.doubleValue)
        }
        if let string = value as? String, let intValue = Int(string) {
            return intValue
        }
        return nil
    }
}
