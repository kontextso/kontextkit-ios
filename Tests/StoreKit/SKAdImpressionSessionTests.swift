import Foundation
@testable import KontextKit
@preconcurrency import StoreKit
import Testing

// Part of the serialized `SKAdNetworkManagerTests` suite: both replace StoreKit's start and end.
extension SKAdNetworkManagerTests {

    /// What reaches StoreKit, as `start:<nonce>` / `end:<nonce>`. `holdStart` keeps each start's
    /// completion for the test to release; `startFails` makes StoreKit reject the start.
    @MainActor
    final class StoreKitSpy {
        var calls: [String] = []
        var holdStart = false
        var startFails = false
        var heldStarts: [@Sendable (Error?) -> Void] = []
    }

    private func withStoreKitSpy(_ body: (StoreKitSpy) async throws -> Void) async throws {
        let savedStart = SKAdNetworkManager.appleStartImpression
        let savedEnd = SKAdNetworkManager.appleEndImpression
        defer {
            SKAdNetworkManager.appleStartImpression = savedStart
            SKAdNetworkManager.appleEndImpression = savedEnd
        }
        let spy = StoreKitSpy()
        SKAdNetworkManager.appleStartImpression = { impression, done in
            spy.calls.append("start:\(Self.nonce(of: impression))")
            if spy.holdStart {
                spy.heldStarts.append(done)
            } else {
                done(spy.startFails ? AppleError() : nil)
            }
        }
        SKAdNetworkManager.appleEndImpression = { impression, done in
            spy.calls.append("end:\(Self.nonce(of: impression))")
            done(nil)
        }
        try await SKAdNetworkManager.shared.dispose()
        try await body(spy)
    }

    private static func nonce(of impression: AnyObject) -> String {
        guard #available(iOS 14.5, *) else { return "" }
        return (impression as? SKAdImpression)?.adImpressionIdentifier ?? ""
    }

    private static func params(nonce: String) -> [String: Any] {
        var params = validParams()
        params["nonce"] = nonce
        return params
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - SKAdImpressionSession

    @Test func createImpressionBuildsItsOwnImpression() throws {
        guard #available(iOS 14.5, *) else { return }
        let session = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
        #expect(session.skImpression?.adImpressionIdentifier == "a")
        #expect(session.skImpression?.advertisedAppStoreItemIdentifier == NSNumber(value: 987654321))
    }

    @Test func createImpressionRejectsMissingArguments() {
        guard #available(iOS 14.5, *) else { return }
        do {
            _ = try SKAdNetworkManager.shared.createImpression(params: [:])
            Issue.record("Expected createImpression to throw with empty params")
        } catch let error as NSError {
            #expect(error.domain == "MISSING_ARGUMENTS")
        }
    }

    @Test func twoImpressionsAliveAtOnceDoNotAffectEachOther() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await withStoreKitSpy { spy in
            let a = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
            let b = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "b"))

            #expect(try await a.start())
            #expect(try await b.start())
            #expect(try await a.end())
            #expect(spy.calls == ["start:a", "start:b", "end:a"], "ending a leaves b running")

            // The shared slot is a third impression: replacing it ends neither session.
            try await SKAdNetworkManager.shared.initImpression(params: Self.params(nonce: "c"))
            _ = try await SKAdNetworkManager.shared.startImpression()
            try await SKAdNetworkManager.shared.initImpression(params: Self.params(nonce: "d"))
            #expect(spy.calls == ["start:a", "start:b", "end:a", "start:c", "end:c"])

            #expect(try await b.end())
            #expect(spy.calls.last == "end:b")
            try await SKAdNetworkManager.shared.dispose()
        }
    }

    @Test func startAndEndReachStoreKitOnceInOrder() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await withStoreKitSpy { spy in
            let session = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
            #expect(try await session.start())
            #expect(try await session.start(), "a second start is answered without StoreKit")
            #expect(try await session.end())
            #expect(try await session.end(), "a second end is answered without StoreKit")
            #expect(try await session.start() == false, "ending is final")
            #expect(spy.calls == ["start:a", "end:a"])
        }
    }

    @Test func anEndMadeWhileTheStartIsInFlightWaitsForIt() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await withStoreKitSpy { spy in
            spy.holdStart = true
            var session: SKAdImpressionSession? = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
            let ended = TestFlag()
            session?.start { _, _ in }
            session?.end { ok, error in ended.set(ok && error == nil) }
            // The caller lets go right after end: the queued calls keep the impression alive.
            session = nil

            await Self.waitUntil { spy.heldStarts.count == 1 }
            try? await Task.sleep(nanoseconds: 20_000_000)
            #expect(spy.calls == ["start:a"], "the end must not overtake the start")

            spy.heldStarts[0](nil)
            await Self.waitUntil { ended.value }
            #expect(ended.value)
            #expect(spy.calls == ["start:a", "end:a"])
        }
    }

    @Test func anEndBeforeAnyStartMeansNoStart() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await withStoreKitSpy { spy in
            let session = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
            #expect(try await session.end())
            #expect(try await session.start() == false)
            #expect(spy.calls.isEmpty, "an ad that left before it started is never started")
        }
    }

    @Test func aSessionWhoseStartFailedStillReachesApplesEnd() async throws {
        guard #available(iOS 14.5, *) else { return }
        try await withStoreKitSpy { spy in
            spy.startFails = true
            let session = try SKAdNetworkManager.shared.createImpression(params: Self.params(nonce: "a"))
            await #expect(throws: (any Error).self) { _ = try await session.start() }
            #expect(try await session.end())
            #expect(spy.calls == ["start:a", "end:a"])
        }
    }
}

/// A flag set from a `@Sendable` completion and read on the main actor.
private final class TestFlag: @unchecked Sendable {
    private(set) var value = false
    func set(_ value: Bool) { self.value = value }
}
