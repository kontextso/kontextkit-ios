import Testing
@testable import KontextKit

struct NetworkInfoProviderTests {

    // MARK: - collect / collectAsDict

    /// On-device network-type detection was removed (the `NWPathMonitor`
    /// read could double-resume its continuation and crash the app), so
    /// `type` is always nil and the ad server sends no `network.type`.
    @Test @MainActor func typeIsAlwaysNil() async {
        let info = await NetworkInfoProvider.collect()
        #expect(info.type == nil)
    }

    /// `carrier` is no longer collected (and CTCarrier is unavailable on
    /// iOS 16+ anyway), so it is always nil.
    @Test @MainActor func carrierIsAlwaysNil() async {
        let info = await NetworkInfoProvider.collect()
        #expect(info.carrier == nil)
    }

    /// `type` and `carrier` are always nil, and the bridge dict drops nil
    /// fields, so those keys (and the removed `detail`) must be absent —
    /// RN/Flutter consumers see "field absent", not `NSNull`.
    @Test @MainActor func dictOmitsNilFields() async {
        let dict = await NetworkInfoProvider.collectAsDict()
        #expect(dict["type"] == nil)
        #expect(dict["carrier"] == nil)
        #expect(dict["detail"] == nil)
    }

    /// `userAgent` is the only field still collected; when present it must
    /// be surfaced verbatim in the bridge dict.
    @Test @MainActor func dictUserAgentMatchesInfo() async {
        let info = await NetworkInfoProvider.collect()
        let dict = await NetworkInfoProvider.collectAsDict()
        if let userAgent = info.userAgent {
            #expect(dict["userAgent"] as? String == userAgent)
        } else {
            #expect(dict["userAgent"] == nil)
        }
    }
}
