import Foundation
import Testing
@testable import KontextKit

struct SKAdNetworkParsingTests {

    @Test func fidelity1HappyPath() {
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 1, "nonce": "abc", "timestamp": "1234567890", "signature": "sig"]
            ]
        ]
        let result = SKAdNetworkParsing.fidelity1Values(from: skan)
        #expect(result?.nonce == "abc")
        #expect(result?.timestamp == "1234567890")
        #expect(result?.signature == "sig")
    }

    @Test func fidelity1NoFidelitiesKey() {
        #expect(SKAdNetworkParsing.fidelity1Values(from: [:]) == nil)
    }

    @Test func fidelity1FidelitiesWrongType() {
        // `fidelities` not an array of dicts → nil.
        #expect(SKAdNetworkParsing.fidelity1Values(from: ["fidelities": "not an array"]) == nil)
    }

    @Test func fidelity1NoMatchingFidelity() {
        // Only fidelity 0 present.
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 0, "nonce": "abc", "timestamp": "123", "signature": "sig"]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity1Values(from: skan) == nil)
    }

    @Test func fidelity1PicksRightEntryAmongMany() {
        // Mixed array; helper must pick the fidelity == 1 entry.
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 0, "nonce": "wrong", "timestamp": "0", "signature": "wrong-sig"],
                ["fidelity": 1, "nonce": "right", "timestamp": "111", "signature": "right-sig"]
            ]
        ]
        let result = SKAdNetworkParsing.fidelity1Values(from: skan)
        #expect(result?.nonce == "right")
        #expect(result?.signature == "right-sig")
    }

    @Test func fidelity1AcceptsStringFidelityValue() {
        // Server may send `fidelity: "1"` rather than `1` — ValueCoercion.int
        // should still match this entry.
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": "1", "nonce": "abc", "timestamp": "123", "signature": "sig"]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity1Values(from: skan) != nil)
    }

    @Test func fidelity1MissingNonceReturnsNil() {
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 1, "timestamp": "123", "signature": "sig"]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity1Values(from: skan) == nil)
    }

    @Test func fidelity1EmptyStringFieldReturnsNil() {
        // ValueCoercion.string returns nil for empty/whitespace, so an
        // empty signature should propagate as a parse failure.
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 1, "nonce": "abc", "timestamp": "123", "signature": ""]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity1Values(from: skan) == nil)
    }

    // MARK: - SKAdNetworkParsing.fields

    private static func makeValidSkanDict() -> [String: Any] {
        [
            "version": "2.2",
            "network": "abc123.skadnetwork",
            "sourceApp": "987654321",
            "campaign": "42",
            "fidelities": [
                ["fidelity": 1, "nonce": "n", "timestamp": "1704067200000", "signature": "s"]
            ]
        ]
    }

    @Test func fieldsHappyPath() {
        let result = SKAdNetworkParsing.fields(from: Self.makeValidSkanDict())
        #expect(result?.version == "2.2")
        #expect(result?.network == "abc123.skadnetwork")
        #expect(result?.sourceAppInt == 987654321)
        #expect(result?.campaignInt == 42)
        #expect(result?.nonce == "n")
        #expect(result?.timestampInt == 1704067200000)
        #expect(result?.signature == "s")
    }

    @Test func fieldsMissingVersionReturnsNil() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "version")
        #expect(SKAdNetworkParsing.fields(from: skan) == nil)
    }

    @Test func fieldsMissingNetworkReturnsNil() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "network")
        #expect(SKAdNetworkParsing.fields(from: skan) == nil)
    }

    @Test func fieldsMissingSourceAppReturnsNil() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "sourceApp")
        #expect(SKAdNetworkParsing.fields(from: skan) == nil)
    }

    @Test func fieldsMissingFidelity1ReturnsNil() {
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [["fidelity": 0, "nonce": "x", "timestamp": "1", "signature": "s"]]
        #expect(SKAdNetworkParsing.fields(from: skan) == nil)
    }

    @Test func fieldsNonNumericTimestampReturnsNil() {
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [
            ["fidelity": 1, "nonce": "n", "timestamp": "not-a-number", "signature": "s"]
        ]
        #expect(SKAdNetworkParsing.fields(from: skan) == nil)
    }

    @Test func fieldsMissingCampaignDefaultsToZero() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "campaign")
        #expect(SKAdNetworkParsing.fields(from: skan)?.campaignInt == 0)
    }

    @Test func fieldsNonNumericSourceAppDefaultsToZero() {
        // Apple allows sourceApp = 0 for "no App Store ID known".
        var skan = Self.makeValidSkanDict()
        skan["sourceApp"] = "not-a-number"
        #expect(SKAdNetworkParsing.fields(from: skan)?.sourceAppInt == 0)
    }

    // MARK: - SKAdNetworkParsing.sourceIdentifier

    @Test func sourceIdentifierReturnsValueWhenNumeric() {
        #expect(SKAdNetworkParsing.sourceIdentifier(from: ["sourceIdentifier": "1234"]) == 1234)
    }

    @Test func sourceIdentifierReturnsNilWhenMissing() {
        #expect(SKAdNetworkParsing.sourceIdentifier(from: [:]) == nil)
    }

    @Test func sourceIdentifierReturnsNilWhenNonNumeric() {
        #expect(SKAdNetworkParsing.sourceIdentifier(from: ["sourceIdentifier": "abc"]) == nil)
    }

    // MARK: - SKAdNetworkParsing.fidelity0Values

    @Test func fidelity0HappyPath() {
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 0, "nonce": "n0", "timestamp": "111", "signature": "s0"]
            ]
        ]
        let result = SKAdNetworkParsing.fidelity0Values(from: skan)
        #expect(result?.nonce == "n0")
        #expect(result?.timestamp == "111")
        #expect(result?.signature == "s0")
    }

    @Test func fidelity0PicksRightEntryAmongMixedFidelities() {
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 1, "nonce": "n1", "timestamp": "1", "signature": "s1"],
                ["fidelity": 0, "nonce": "n0", "timestamp": "0", "signature": "s0"]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity0Values(from: skan)?.nonce == "n0")
    }

    @Test func fidelity0NoMatchingFidelityReturnsNil() {
        let skan: [String: Any] = [
            "fidelities": [
                ["fidelity": 1, "nonce": "n", "timestamp": "1", "signature": "s"]
            ]
        ]
        #expect(SKAdNetworkParsing.fidelity0Values(from: skan) == nil)
    }
}
