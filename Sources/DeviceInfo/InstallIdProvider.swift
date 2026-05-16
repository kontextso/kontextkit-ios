import Foundation

/// Per-app-install identifier. Generated as a UUID v7 on first SDK use,
/// persisted to `UserDefaults`, and attached to every ad-server request
/// (`/init`, `/preload`, `/error`, `/debug`) so the server can key pacing,
/// frequency caps, and per-install diagnostics to a stable client identity
/// independent of `conversationId` or `userId`.
///
/// Survives app launches; resets only when the user uninstalls the app
/// (or clears app data). Matches the `kontextso:installId` localStorage
/// key used by `@kontextso/sdk-js` so web and native installs share the
/// same shape on the wire.
public enum InstallIdProvider {

    /// UserDefaults key under which the install ID is persisted.
    private static let storageKey = "kontextso.installId"

    /// Returns the persisted install ID, generating + storing one on
    /// first call. The stored value is validated against the canonical
    /// UUID shape (8-4-4-4-12 hex) and overwritten if corrupted — guards
    /// against accidental tampering, partial UserDefaults migration, or
    /// a future change to the generator.
    public static func getOrCreate(
        defaults: UserDefaults = .standard
    ) -> String {
        if let existing = defaults.string(forKey: storageKey),
           isCanonicalUUID(existing) {
            return existing
        }
        let fresh = uuidv7()
        defaults.set(fresh, forKey: storageKey)
        return fresh
    }

    /// Generates a UUID v7 string per RFC 9562:
    ///
    ///   48-bit big-endian Unix-epoch milliseconds | version (0111) | 12 random bits |
    ///   variant (10) | 62 random bits
    ///
    /// Time-ordered, so server-side sorts and B-tree indexes stay friendly.
    static func uuidv7() -> String {
        let ts = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        // 48-bit timestamp, big-endian
        bytes[0] = UInt8((ts >> 40) & 0xff)
        bytes[1] = UInt8((ts >> 32) & 0xff)
        bytes[2] = UInt8((ts >> 24) & 0xff)
        bytes[3] = UInt8((ts >> 16) & 0xff)
        bytes[4] = UInt8((ts >> 8) & 0xff)
        bytes[5] = UInt8(ts & 0xff)
        // Random bytes for the remaining 10 octets.
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, 10, &bytes[6])
        if randomStatus != errSecSuccess {
            // SecRandomCopyBytes is documented to never fail in practice;
            // fall back to arc4random_buf so we still produce a well-formed
            // UUID rather than ship zero bytes.
            arc4random_buf(&bytes[6], 10)
        }
        // Version 7 in the high nibble of byte 6.
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        // Variant 10 in the high two bits of byte 8.
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let i0 = hex.startIndex
        let i8 = hex.index(i0, offsetBy: 8)
        let i12 = hex.index(i8, offsetBy: 4)
        let i16 = hex.index(i12, offsetBy: 4)
        let i20 = hex.index(i16, offsetBy: 4)
        return "\(hex[i0..<i8])-\(hex[i8..<i12])-\(hex[i12..<i16])-\(hex[i16..<i20])-\(hex[i20...])"
    }

    /// Validates any canonical UUID shape (8-4-4-4-12 hex). Intentionally
    /// not version- or variant-locked so a future change to the generator
    /// (e.g. v8) doesn't invalidate the IDs already in users' UserDefaults.
    static func isCanonicalUUID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        return UUID(uuidString: value) != nil
    }
}
