import Foundation
import Testing
@testable import KontextKit

private let uuidV7Pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
private let storageKey = "kontextso.installId"

/// Pattern-match helper that doesn't require iOS 16+ (`Regex` /
/// `#/.../#` literal). `String.range(of:options:)` with
/// `.regularExpression` has been around since iOS 4 — keeps the test
/// file buildable against KontextKit's iOS 14 deployment target.
private func matchesV7Shape(_ id: String) -> Bool {
    id.range(of: uuidV7Pattern, options: .regularExpression) != nil
}

/// Builds a fresh UserDefaults backed by a unique suite name so each
/// test gets isolated storage — avoids cross-test contamination on the
/// shared `.standard` defaults and lets us assert against a known-empty
/// starting state.
private func freshDefaults(_ suite: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

struct UUIDv7Tests {
    @Test func producesCanonicalV7Shape() {
        let id = InstallIdProvider.uuidv7()
        #expect(matchesV7Shape(id))
    }

    @Test func encodesCurrentTimestampInPrefix() {
        let before = UInt64(Date().timeIntervalSince1970 * 1000)
        let id = InstallIdProvider.uuidv7()
        let after = UInt64(Date().timeIntervalSince1970 * 1000)
        // First 12 hex chars (without the hyphen) are the 48-bit timestamp.
        let tsHex = String(id.prefix(8)) + String(id.dropFirst(9).prefix(4))
        let ts = UInt64(tsHex, radix: 16) ?? 0
        #expect(ts >= before)
        #expect(ts <= after)
    }

    @Test func emitsTimeOrderedIDsAcrossDistinctMilliseconds() {
        let a = InstallIdProvider.uuidv7()
        // Spin until the millisecond changes so the timestamp prefix differs.
        let baseline = UInt64(Date().timeIntervalSince1970 * 1000)
        while UInt64(Date().timeIntervalSince1970 * 1000) == baseline { /* spin */ }
        let b = InstallIdProvider.uuidv7()
        #expect(a < b)
    }
}

struct InstallIdProviderTests {

    @Test func generatesAndPersistsOnFirstCall() {
        let defaults = freshDefaults()
        let id = InstallIdProvider.getOrCreate(defaults: defaults)
        #expect(matchesV7Shape(id))
        #expect(defaults.string(forKey: storageKey) == id)
    }

    @Test func returnsSameValueOnSubsequentCalls() {
        let defaults = freshDefaults()
        let first = InstallIdProvider.getOrCreate(defaults: defaults)
        let second = InstallIdProvider.getOrCreate(defaults: defaults)
        #expect(first == second)
    }

    @Test func reusesValueAlreadyInStorage() {
        let defaults = freshDefaults()
        let seeded = "01890000-0000-7000-8000-000000000000"
        defaults.set(seeded, forKey: storageKey)
        #expect(InstallIdProvider.getOrCreate(defaults: defaults) == seeded)
    }

    @Test func acceptsNonV7UUIDForForwardCompat() {
        // v4 UUID — the validator is intentionally version-agnostic so a
        // future generator change doesn't invalidate IDs already on disk.
        let defaults = freshDefaults()
        let v4 = "550e8400-e29b-41d4-a716-446655440000"
        defaults.set(v4, forKey: storageKey)
        #expect(InstallIdProvider.getOrCreate(defaults: defaults) == v4)
    }

    @Test(arguments: [
        "",
        "lol-not-a-uuid",
        "01890000-0000-7000-8000-00000000", // truncated
        "01890000-0000-7000-8000-000000000000-extra",
        "{\"foo\":\"bar\"}",
        "0189zzzz-0000-7000-8000-000000000000", // non-hex chars
    ])
    func overwritesMalformedStoredValue(_ malformed: String) {
        let defaults = freshDefaults()
        defaults.set(malformed, forKey: storageKey)
        let id = InstallIdProvider.getOrCreate(defaults: defaults)
        #expect(matchesV7Shape(id))
        #expect(id != malformed)
        // Replacement is persisted so subsequent calls see the same value.
        #expect(defaults.string(forKey: storageKey) == id)
    }
}
