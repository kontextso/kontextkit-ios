import Testing
@testable import KontextKit

// `@MainActor` because AdvertisingIdProvider.getVendorId() /
// resolveIds() are main-actor-isolated (they read UIDevice.current).
@MainActor
struct AdvertisingIdProviderTests {

    /// IDFA is gated on ATT authorization. In the simulator without ATT
    /// granted, the call returns nil. We can't authorize from a test, so
    /// the test only asserts the call doesn't crash and returns one of
    /// `nil` or a non-empty, non-zero UUID.
    @Test func getAdvertisingIdReturnsNilOrValidUUID() {
        let id = AdvertisingIdProvider.getAdvertisingId()
        if let id {
            #expect(!id.isEmpty)
            #expect(id.lowercased() != "00000000-0000-0000-0000-000000000000")
        }
    }

    /// IDFV doesn't require ATT, so simulators usually return a real UUID.
    /// Asserting non-emptiness rather than non-nil because some test
    /// environments still return nil.
    @Test func getVendorIdReturnsNilOrValidUUID() {
        let id = AdvertisingIdProvider.getVendorId()
        if let id {
            #expect(!id.isEmpty)
            #expect(id.lowercased() != "00000000-0000-0000-0000-000000000000")
        }
    }

    // MARK: - resolveIds + manual overrides

    @Test func resolveIdsManualOverrideWins() {
        let manualAd = "manual-advertising-id"
        let manualV = "manual-vendor-id"
        let result = AdvertisingIdProvider.resolveIds(
            manualAdvertisingId: manualAd,
            manualVendorId: manualV
        )
        #expect(result.advertisingId == manualAd)
        #expect(result.vendorId == manualV)
    }

    @Test func resolveIdsEmptyManualFallsBackToSystem() {
        // Empty manual overrides should normalize to nil and trigger fallback.
        let systemVendor = AdvertisingIdProvider.getVendorId()
        let result = AdvertisingIdProvider.resolveIds(
            manualAdvertisingId: "",
            manualVendorId: ""
        )
        #expect(result.vendorId == systemVendor)
    }

    @Test func resolveIdsZeroUUIDManualFallsBackToSystem() {
        let zeroUUID = "00000000-0000-0000-0000-000000000000"
        let systemVendor = AdvertisingIdProvider.getVendorId()
        let result = AdvertisingIdProvider.resolveIds(
            manualAdvertisingId: zeroUUID,
            manualVendorId: zeroUUID
        )
        #expect(result.vendorId == systemVendor)
    }

    @Test func resolveIdsWhitespaceManualFallsBackToSystem() {
        let systemVendor = AdvertisingIdProvider.getVendorId()
        let result = AdvertisingIdProvider.resolveIds(
            manualAdvertisingId: "   ",
            manualVendorId: "  \t  "
        )
        #expect(result.vendorId == systemVendor)
    }

    @Test func resolveIdsNilManualUsesSystem() {
        let result = AdvertisingIdProvider.resolveIds()
        // Both should match what the bare getters return.
        #expect(result.advertisingId == AdvertisingIdProvider.getAdvertisingId())
        #expect(result.vendorId == AdvertisingIdProvider.getVendorId())
    }
}
