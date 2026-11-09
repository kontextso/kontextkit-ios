import Foundation
import Testing
@testable import KontextKit

private let uuidV7Pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

/// `String.range(of:options:)` keeps the file buildable against the iOS 14 deployment target (`Regex` is iOS 16+).
private func matchesV7Shape(_ id: String) -> Bool {
    id.range(of: uuidV7Pattern, options: .regularExpression) != nil
}

struct UUIDv7Tests {
    @Test func producesCanonicalV7Shape() {
        let id = UUIDv7.generate()
        #expect(matchesV7Shape(id))
    }

    @Test func encodesCurrentTimestampInPrefix() {
        let before = UInt64(Date().timeIntervalSince1970 * 1000)
        let id = UUIDv7.generate()
        let after = UInt64(Date().timeIntervalSince1970 * 1000)
        // First 12 hex chars (without the hyphen) are the 48-bit timestamp.
        let tsHex = String(id.prefix(8)) + String(id.dropFirst(9).prefix(4))
        let ts = UInt64(tsHex, radix: 16) ?? 0
        #expect(ts >= before)
        #expect(ts <= after)
    }

    @Test func emitsTimeOrderedIDsAcrossDistinctMilliseconds() {
        let a = UUIDv7.generate()
        // Spin until the millisecond changes so the timestamp prefix differs.
        let baseline = UInt64(Date().timeIntervalSince1970 * 1000)
        while UInt64(Date().timeIntervalSince1970 * 1000) == baseline { /* spin */ }
        let b = UUIDv7.generate()
        #expect(a < b)
    }
}
