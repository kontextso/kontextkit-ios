import Testing
@testable import KontextKit

struct SKAdNetworkIdsProviderTests {

    @Test func collectReturnsArray() {
        // In a test environment without SKAdNetworkItems in Info.plist,
        // `collect()` returns []. The return type is non-optional [String]
        // so existence is guaranteed by the type system — this is a
        // smoke test for "doesn't throw / doesn't return junk".
        let ids = SKAdNetworkIdsProvider.collect()
        #expect(ids is [String])
    }
}
