import Foundation
import Security

/// UUID version 7 (RFC 9562): 48 bits of Unix-epoch milliseconds, then random bits, so ids sort by the
/// millisecond they were made in; within one millisecond, or after the clock was set back, their order is
/// random. `InstallIdProvider` makes the install id with it; an SDK makes its own time-ordered ids (a session
/// id) the same way. Mirrors kontextkit-android `UuidV7`.
public enum UUIDv7 {
    /// A new UUID v7 as a lowercase canonical string (8-4-4-4-12 hex):
    ///
    ///   48-bit big-endian Unix-epoch milliseconds | version (0111) | 12 random bits |
    ///   variant (10) | 62 random bits
    public static func generate() -> String {
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
}
