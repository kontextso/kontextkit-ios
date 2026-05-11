import Foundation
import StoreKit
import Testing
@testable import KontextKit

@MainActor
struct SKOverlayManagerTests {

    @Test func skOverlayManagerSingletonExists() {
        _ = SKOverlayManager.shared
    }

    // MARK: - applyImpression

    /// Reusable valid SKAN dict for tests.
    private static func makeValidSkanDict() -> [String: Any] {
        [
            "version": "2.2",
            "network": "abc123.skadnetwork",
            "itunesItem": "987654321",
            "sourceApp": "111222333",
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

    @Test func applyImpressionHappyPath() {
        guard #available(iOS 16.0, *) else { return }
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(SKOverlayManager.applyImpression(Self.makeValidSkanDict(), to: config))
    }

    @Test func applyImpressionMissingVersionReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "version")
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionMissingNetworkReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "network")
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionMissingItunesItemReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "itunesItem")
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionNonNumericItunesItemReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan["itunesItem"] = "not-a-number"
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionMissingSourceAppReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan.removeValue(forKey: "sourceApp")
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionMissingFidelity1ReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [["fidelity": 0, "nonce": "x", "timestamp": "1", "signature": "s"]]
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionNonNumericTimestampReturnsFalse() {
        guard #available(iOS 16.0, *) else { return }
        var skan = Self.makeValidSkanDict()
        skan["fidelities"] = [
            ["fidelity": 1, "nonce": "n", "timestamp": "abc", "signature": "s"]
        ]
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(!SKOverlayManager.applyImpression(skan, to: config))
    }

    @Test func applyImpressionNoFidelitiesReturnsTrue() {
        // Caller didn't intend SKAN attribution — overlay still presents
        // (no install credit, but the click works).
        guard #available(iOS 16.0, *) else { return }
        let skan: [String: Any] = ["itunesItem": "987654321"]
        let config = SKOverlay.AppConfiguration(appIdentifier: "987654321", position: .bottom)
        #expect(SKOverlayManager.applyImpression(skan, to: config))
    }

    // MARK: - SKOverlayDelegate
    //
    // SKOverlay.TransitionContext has no public initializer, so the
    // didFinishPresentation/didFinishDismissal delegate methods aren't
    // directly callable from tests. The state-transition pattern (read
    // pending completion → nil it → invoke) is identical across all
    // three delegate methods, so testing didFailToLoad is enough to
    // cover the shared logic.

    @Test func storeOverlayDidFailToLoadFiresPendingCompletionWithError() async {
        guard #available(iOS 16.0, *) else { return }
        let manager = SKOverlayManager.shared
        let config = SKOverlay.AppConfiguration(appIdentifier: "1", position: .bottom)
        let overlay = SKOverlay(configuration: config)

        let captured: (Bool, NSError?) = await withCheckedContinuation { (cont: CheckedContinuation<(Bool, NSError?), Never>) in
            manager.pendingPresentCompletion = { success, error in cont.resume(returning: (success, error)) }
            let loadError = NSError(domain: "test", code: 0)
            manager.storeOverlayDidFailToLoad(overlay, error: loadError)
        }
        #expect(!captured.0)
        #expect(captured.1?.domain == "LOAD_FAILED")
        #expect(manager.pendingPresentCompletion == nil)
    }
}
