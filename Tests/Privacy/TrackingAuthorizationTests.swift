import Foundation
import Testing
@testable import KontextKit

// `@MainActor` because TrackingAuthorizationManager is main-actor-isolated.
@MainActor
struct TrackingAuthorizationTests {

    @Test func currentStatusReturnsInteger() {
        // On a simulator without ATT entitlements, this should return
        // a valid status value (0 = notDetermined, typically).
        if #available(iOS 14, *) {
            let status = TrackingAuthorizationManager.currentStatus
            #expect((0...4).contains(status), "Status should be 0-4, got \(status)")
        }
    }

    /// `runStartupFlow` is documented to be idempotent — calling it
    /// repeatedly must not re-trigger the ATT prompt and must return
    /// the same `(advertisingId, vendorId)` tuple. The xctest host has
    /// no ATT entitlements, so the prompt path is a no-op here; what
    /// we're really verifying is that the second call returns matching
    /// IDs without hanging or throwing.
    @Test func runStartupFlowIsIdempotent() async {
        let first = await TrackingAuthorizationManager.shared.runStartupFlow()
        let second = await TrackingAuthorizationManager.shared.runStartupFlow()
        #expect(first.advertisingId == second.advertisingId)
        #expect(first.vendorId == second.vendorId)
    }

    /// Manual overrides take precedence over auto-resolved values.
    @Test func runStartupFlowRespectsManualOverrides() async {
        let manualAd = "11111111-2222-3333-4444-555555555555"
        let manualVendor = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let result = await TrackingAuthorizationManager.shared.runStartupFlow(
            manualAdvertisingId: manualAd,
            manualVendorId: manualVendor
        )
        #expect(result.advertisingId == manualAd)
        #expect(result.vendorId == manualVendor)
    }

    @Test func tcfDataReturnsNilWhenNotSet() {
        // Use a separate UserDefaults suite so we don't pollute the standard one
        let defaults = UserDefaults(suiteName: "com.kontext.test.tcf")!
        defaults.removePersistentDomain(forName: "com.kontext.test.tcf")

        let data = TCFDataProvider.getTCFData(from: defaults)
        #expect(data.gdprConsent == nil)
        #expect(data.gdpr == nil)
    }

    @Test func tcfDataReadsValues() {
        let defaults = UserDefaults(suiteName: "com.kontext.test.tcf2")!
        defaults.removePersistentDomain(forName: "com.kontext.test.tcf2")

        defaults.set("CONSENT_STRING_123", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")

        let data = TCFDataProvider.getTCFData(from: defaults)
        #expect(data.gdprConsent == "CONSENT_STRING_123")
        #expect(data.gdpr == 1)
    }
}
