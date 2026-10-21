import Testing
@testable import KontextKit

struct SKAdNetworkIdsProviderTests {

    @Test func collectReturnsEmptyWithoutInfoPlistEntries() {
        // Test bundle's Info.plist has no `SKAdNetworkItems`, so the
        // provider should return an empty array (not nil, not junk).
        let ids = SKAdNetworkIdsProvider.collect()
        #expect(ids.isEmpty)
    }

    @Test func adAttributionKitIdsAreEmptyWithoutInfoPlistEntries() {
        // No `AdNetworkIdentifiers` in the test bundle either.
        #expect(AdAttributionKitIdsProvider.collect().isEmpty)
    }
}
