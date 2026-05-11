import Testing
@testable import KontextKit

struct OMSDKTests {

    // MARK: - OMCreativeType

    @Test func omCreativeTypeDisplayRawValue() {
        #expect(OMCreativeType.display.rawValue == "display")
    }

    @Test func omCreativeTypeVideoRawValue() {
        #expect(OMCreativeType.video.rawValue == "video")
    }

    @Test func omCreativeTypeFromRawValue() {
        #expect(OMCreativeType(rawValue: "display") == .display)
        #expect(OMCreativeType(rawValue: "video") == .video)
        #expect(OMCreativeType(rawValue: "unknown") == nil)
    }

    @Test func omCreativeTypeHashable() {
        let set: Set<OMCreativeType> = [.display, .video, .display]
        #expect(set.count == 2)
    }

    // MARK: - OMManager.omsdkScript

    /// The bundled `omsdk-v1.js` is the load-bearing piece of the
    /// integration — without it, the WebView has no OMID JS layer and
    /// every session would fail. This test guards against the resource
    /// being dropped from `Package.swift`'s `.copy` declarations or
    /// `KontextKit.podspec`'s `s.resources`.
    @Test func omsdkScriptIsBundled() {
        let script = OMManager.omsdkScript()
        #expect(script != nil)
        #expect((script?.count ?? 0) > 0)
    }
}
