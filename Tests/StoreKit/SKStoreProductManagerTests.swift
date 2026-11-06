import Foundation
import Testing
import StoreKit
@testable import KontextKit

// Serialized: tests drive the one shared manager's pending state, and some replace its StoreKit load.
@Suite(.serialized)
@MainActor
struct SKStoreProductManagerTests {

    @Test func skStoreProductManagerSingletonExists() {
        _ = SKStoreProductManager.shared
    }

    @Test func presentReturnsOperationInProgressWhenPresentAlreadyPending() async {
        let manager = SKStoreProductManager.shared
        manager.pendingPresentCompletion = { _, _ in }
        defer { manager.pendingPresentCompletion = nil }

        let result: (Bool, NSError?) = await withCheckedContinuation { continuation in
            manager.present(skan: ["itunesItem": "987654321"]) { success, error in
                continuation.resume(returning: (success, error))
            }
        }

        #expect(!result.0)
        #expect(result.1?.domain == "OPERATION_IN_PROGRESS")
    }

    @Test func dismissReturnsFalseWhenPresentAlreadyPending() {
        let manager = SKStoreProductManager.shared
        manager.pendingPresentCompletion = { _, _ in }
        defer { manager.pendingPresentCompletion = nil }

        let dismissed = TestBox<Bool>()
        manager.dismiss { dismissed.value = $0 }

        #expect(dismissed.value == false)
    }

    // MARK: - Load timeout

    private struct LoadError: Error {}

    @Test func aLoadThatNeverCallsBackTimesOutAndNothingIsPresentedLater() async {
        let manager = SKStoreProductManager.shared
        let savedTimeout = SKStoreProductManager.loadTimeout
        let savedLoad = SKStoreProductManager.loadProduct
        defer {
            SKStoreProductManager.loadTimeout = savedTimeout
            SKStoreProductManager.loadProduct = savedLoad
        }
        var loads: [@Sendable (Bool, Error?) -> Void] = []
        SKStoreProductManager.loadProduct = { _, _, done in loads.append(done) }
        SKStoreProductManager.loadTimeout = 0.05

        let first: (Bool, NSError?) = await withCheckedContinuation { continuation in
            manager.present(skan: ["itunesItem": "987654321"]) { continuation.resume(returning: ($0, $1)) }
        }
        #expect(!first.0)
        #expect(first.1?.domain == "LOAD_TIMEOUT")
        #expect(manager.pendingPresentCompletion == nil)

        // The next present is accepted, and the first one's late load neither presents nor resolves it.
        SKStoreProductManager.loadTimeout = 30
        let second = TestBox<(Bool, NSError?)>()
        manager.present(skan: ["itunesItem": "987654321"]) { second.value = ($0, $1) }
        #expect(loads.count == 2)
        loads[0](true, nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(second.value == nil, "a timed-out load must not act on the next present")
        #expect(manager.pendingPresentCompletion != nil)

        loads[1](false, LoadError())
        for _ in 0..<100 where second.value == nil {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(second.value?.0 == false)
        #expect(second.value?.1?.domain == "LOAD_FAILED")
        #expect(manager.pendingPresentCompletion == nil)
    }

    // MARK: - applySkanParams

    /// Reusable valid SKAN dict for tests. Each test mutates one field
    /// to exercise a specific failure or optional path.
    private static func makeValidSkanDict() -> [String: Any] {
        [
            "version": "2.2",
            "network": "abc123.skadnetwork",
            "sourceApp": "987654321",
            "campaign": "42",
            "fidelities": [
                [
                    "fidelity": 1,
                    "nonce": "00000000-0000-0000-0000-000000000001",
                    "timestamp": "1704067200000",
                    "signature": "sig-base64=="
                ]
            ]
        ]
    }

    @Test func applySkanParamsHappyPath() {
        var params: [String: Any] = [:]
        #expect(SKStoreProductManager.applySkanParams(Self.makeValidSkanDict(), into: &params))

        #expect(params[SKStoreProductParameterAdNetworkVersion] as? String == "2.2")
        #expect(params[SKStoreProductParameterAdNetworkIdentifier] as? String == "abc123.skadnetwork")
        #expect(params[SKStoreProductParameterAdNetworkSourceAppStoreIdentifier] as? NSNumber == NSNumber(value: 987654321))
        #expect(params[SKStoreProductParameterAdNetworkCampaignIdentifier] as? NSNumber == NSNumber(value: 42))
        #expect(params[SKStoreProductParameterAdNetworkTimestamp] as? NSNumber == NSNumber(value: 1704067200000))
        #expect(params[SKStoreProductParameterAdNetworkAttributionSignature] as? String == "sig-base64==")
        #expect(params[SKStoreProductParameterAdNetworkNonce] as? UUID == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    @Test func applySkanParamsMissingVersionReturnsFalse() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "version")
        var params: [String: Any] = [:]
        #expect(!SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params.isEmpty)
    }

    @Test func applySkanParamsMissingFidelity1ReturnsFalse() {
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [["fidelity": 0, "nonce": "abc", "timestamp": "1", "signature": "s"]]
        var params: [String: Any] = [:]
        #expect(!SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params.isEmpty)
    }

    @Test func applySkanParamsInvalidNonceUUIDReturnsFalse() {
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [
            ["fidelity": 1, "nonce": "not-a-uuid", "timestamp": "1", "signature": "s"]
        ]
        var params: [String: Any] = [:]
        #expect(!SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params.isEmpty)
    }

    @Test func applySkanParamsNonNumericTimestampReturnsFalse() {
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [
            ["fidelity": 1, "nonce": "00000000-0000-0000-0000-000000000001", "timestamp": "abc", "signature": "s"]
        ]
        var params: [String: Any] = [:]
        #expect(!SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params.isEmpty)
    }

    @Test func applySkanParamsNoFidelitiesReturnsTrue() {
        // Caller didn't intend SKAN attribution — page still loads
        // without the AdNetwork* params.
        var params: [String: Any] = [:]
        #expect(SKStoreProductManager.applySkanParams(["itunesItem": "987654321"], into: &params))
        #expect(params.isEmpty)
    }

    @Test func applySkanParamsMissingCampaignDefaultsToZero() {
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "campaign")
        var params: [String: Any] = [:]
        #expect(SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params[SKStoreProductParameterAdNetworkCampaignIdentifier] as? NSNumber == NSNumber(value: 0))
    }

    @Test func applySkanParamsNonNumericSourceAppDefaultsToZero() {
        // Apple allows sourceApp = 0 for "no App Store ID known".
        var skan = Self.makeValidSkanDict()
        skan["sourceApp"] = "not-a-number"
        var params: [String: Any] = [:]
        #expect(SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params[SKStoreProductParameterAdNetworkSourceAppStoreIdentifier] as? NSNumber == NSNumber(value: 0))
    }

    @Test func applySkanParamsIncludesSourceIdentifierWhenPresent() {
        guard #available(iOS 16.1, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan["sourceIdentifier"] = "1234"
        var params: [String: Any] = [:]
        #expect(SKStoreProductManager.applySkanParams(skan, into: &params))
        #expect(params[SKStoreProductParameterAdNetworkSourceIdentifier] as? NSNumber == NSNumber(value: 1234))
    }

    @Test func applySkanParamsOmitsSourceIdentifierWhenMissing() {
        guard #available(iOS 16.1, *) else { return }
        var params: [String: Any] = [:]
        _ = SKStoreProductManager.applySkanParams(Self.makeValidSkanDict(), into: &params)
        #expect(params[SKStoreProductParameterAdNetworkSourceIdentifier] == nil)
    }
}

/// Mutable reference-typed box for capturing in @Sendable test closures.
/// The completion runs on the same MainActor that reads it back, so
/// @unchecked Sendable is sound for test use.
private final class TestBox<T>: @unchecked Sendable {
    var value: T?
}
