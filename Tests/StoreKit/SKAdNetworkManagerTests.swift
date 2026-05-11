import Foundation
import Testing
@testable import KontextKit

@MainActor
struct SKAdNetworkManagerTests {

    @Test func skAdNetworkManagerSingletonExists() {
        _ = SKAdNetworkManager.shared
    }

    @Test func skAdNetworkManagerStartImpressionWithoutInitFails() async {
        // On iOS 14.5+ this should fail with NO_IMPRESSION;
        // on older simulators it returns false with nil error.
        do {
            _ = try await SKAdNetworkManager.shared.startImpression()
            if #available(iOS 14.5, *) {
                Issue.record("Expected startImpression to throw without prior init")
            }
        } catch {
            // Expected on iOS 14.5+
        }
    }

    @Test func skAdNetworkManagerEndImpressionWithoutInitFails() async {
        do {
            _ = try await SKAdNetworkManager.shared.endImpression()
            if #available(iOS 14.5, *) {
                Issue.record("Expected endImpression to throw without prior init")
            }
        } catch {
            // Expected on iOS 14.5+
        }
    }

    @Test func skAdNetworkManagerDisposeWithoutInit() async throws {
        // dispose without prior init should succeed (idempotent cleanup)
        try await SKAdNetworkManager.shared.dispose()
    }

    @Test func skAdNetworkManagerInitImpressionMissingArgs() async {
        guard #available(iOS 14.5, *) else { return }

        do {
            try await SKAdNetworkManager.shared.initImpression(params: [:])
            Issue.record("Expected initImpression to throw with empty params")
        } catch let error as NSError {
            #expect(error.domain == "MISSING_ARGUMENTS")
        }
    }

    // MARK: - initImpression happy paths
    //
    // These tests inspect skImpressionBox after initImpression to verify
    // attribution fields were stored correctly. Cleanup: each test calls
    // dispose first to ensure a clean starting state.

    private static func validParams() -> [String: Any] {
        [
            "version": "2.2",
            "network": "abc.skadnetwork",
            "itunesItem": "987654321",
            "sourceApp": "111222",
            "campaign": "42",
            "nonce": "00000000-0000-0000-0000-000000000001",
            "timestamp": "1704067200000",
            "signature": "sig=="
        ]
    }

    @Test func initImpressionHappyPathTopLevel() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await SKAdNetworkManager.shared.dispose()

        try await SKAdNetworkManager.shared.initImpression(params: Self.validParams())

        let imp = SKAdNetworkManager.shared.skImpression
        #expect(imp != nil)
        #expect(imp?.version == "2.2")
        #expect(imp?.adNetworkIdentifier == "abc.skadnetwork")
        #expect(imp?.advertisedAppStoreItemIdentifier == NSNumber(value: 987654321))
        #expect(imp?.sourceAppStoreItemIdentifier == NSNumber(value: 111222))
        #expect(imp?.adCampaignIdentifier == NSNumber(value: 42))
        #expect(imp?.adImpressionIdentifier == "00000000-0000-0000-0000-000000000001")
        #expect(imp?.timestamp == NSNumber(value: 1704067200000))
        #expect(imp?.signature == "sig==")

        try await SKAdNetworkManager.shared.dispose()
    }

    @Test func initImpressionFidelity0FallsBackForNonceTimestampSignature() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await SKAdNetworkManager.shared.dispose()

        // Top-level lacks nonce/timestamp/signature; fidelity-0 supplies them.
        let params: [String: Any] = [
            "version": "2.2",
            "network": "abc.skadnetwork",
            "itunesItem": "987654321",
            "sourceApp": "0",
            "fidelities": [
                ["fidelity": 0, "nonce": "from-f0", "timestamp": "555", "signature": "f0sig"]
            ]
        ]
        try await SKAdNetworkManager.shared.initImpression(params: params)

        let imp = SKAdNetworkManager.shared.skImpression
        #expect(imp?.adImpressionIdentifier == "from-f0")
        #expect(imp?.timestamp == NSNumber(value: 555))
        #expect(imp?.signature == "f0sig")

        try await SKAdNetworkManager.shared.dispose()
    }

    @Test func initImpressionTopLevelTakesPrecedenceOverFidelity0() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await SKAdNetworkManager.shared.dispose()

        var params = Self.validParams()
        // Add a fidelity-0 with conflicting values; top-level should win.
        params["fidelities"] = [
            ["fidelity": 0, "nonce": "wrong", "timestamp": "1", "signature": "wrong-sig"]
        ]
        try await SKAdNetworkManager.shared.initImpression(params: params)

        let imp = SKAdNetworkManager.shared.skImpression
        #expect(imp?.adImpressionIdentifier == "00000000-0000-0000-0000-000000000001")
        #expect(imp?.signature == "sig==")

        try await SKAdNetworkManager.shared.dispose()
    }

    @Test func initImpressionMissingSourceAppDefaultsToZero() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await SKAdNetworkManager.shared.dispose()

        var params = Self.validParams()
        params.removeValue(forKey: "sourceApp")
        try await SKAdNetworkManager.shared.initImpression(params: params)

        #expect(SKAdNetworkManager.shared.skImpression?.sourceAppStoreItemIdentifier == NSNumber(value: 0))

        try await SKAdNetworkManager.shared.dispose()
    }

    @Test func initImpressionIncludesSourceIdentifierWhenPresent() async throws {
        guard #available(iOS 16.1, *) else { return }
        try await SKAdNetworkManager.shared.dispose()

        var params = Self.validParams()
        params["sourceIdentifier"] = "1234"
        try await SKAdNetworkManager.shared.initImpression(params: params)

        #expect(SKAdNetworkManager.shared.skImpression?.sourceIdentifier == NSNumber(value: 1234))

        try await SKAdNetworkManager.shared.dispose()
    }
}
