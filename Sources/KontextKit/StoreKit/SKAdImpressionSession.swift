import Foundation
// SKAdImpression isn't annotated Sendable in the StoreKit headers; it is only touched from MainActor.
@preconcurrency import StoreKit

/// One ad's SKAdNetwork view-through impression: its own `SKAdImpression`, started when the ad is
/// displayed and ended when it is gone.
///
/// Created by `SKAdNetworkManager.createImpression(params:)`, one per ad. Any number can be alive at
/// once: Apple's `startImpression` / `endImpression` take the impression itself, so two ads on screen
/// (from one SDK or two) never touch each other's.
///
/// Calls are applied one at a time, in the order they are made on the main actor: an `end()` made while
/// `start()` is still waiting for StoreKit reaches Apple after the start has finished. Ending is final;
/// a `start()` after `end()` does nothing. A queued call keeps the session alive, so the caller can drop
/// its reference right after `end()`.
@MainActor
public final class SKAdImpressionSession {
    // `SKAdImpression` is iOS 14.5+; a stored `SKAdImpression` would force the class to require it.
    private let impressionBox: AnyObject
    private var isStarted = false
    // A start was asked of Apple and no end yet: Apple wants the end even when the start failed, so this,
    // not `isStarted`, decides whether `end()` reaches Apple.
    private var needsEnd = false
    private var isEnded = false
    private var tail: Task<Void, Never>?

    // Read by tests only; analyze doesn't see the test target.
    @available(iOS 14.5, *)
    // swiftlint:disable:next unused_declaration
    var skImpression: SKAdImpression? { impressionBox as? SKAdImpression }

    init(impression: AnyObject) {
        impressionBox = impression
    }

    // MARK: - Public API

    /// Starts the impression. `true` once started (or already started); `false` after `end()`, with
    /// nothing sent to Apple. An error when StoreKit rejected the start; `end()` still reaches Apple then.
    public func start(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        enqueue { [self] in
            let (started, error) = await performStart()
            completion(started, error)
        }
    }

    /// Ends the impression, after any `start()` made before it. `true` when ended, or when there was
    /// nothing to end (never started). An error when StoreKit rejected the end; another `end()` retries it.
    public func end(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        end(failureDomain: "SKAN_END_IMPRESSION_FAILED", failureMessage: "Failed to end SKAdImpression", completion: completion)
    }

    /// Async form of `start(completion:)`. Throws when StoreKit rejected the start.
    public func start() async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            start { started, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: started)
                }
            }
        }
    }

    /// Async form of `end(completion:)`. Throws when StoreKit rejected the end.
    public func end() async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            end { ended, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ended)
                }
            }
        }
    }

    // MARK: - Internal

    func end(failureDomain: String, failureMessage: String, completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        enqueue { [self] in
            let (ended, error) = await performEnd(failureDomain: failureDomain, failureMessage: failureMessage)
            completion(ended, error)
        }
    }

    /// Builds the `SKAdImpression` from the ad's SKAN dictionary. `nil` below iOS 14.5; throws
    /// `MISSING_ARGUMENTS` when a required field is missing. Keys: see `SKAdNetworkManager.initImpression`.
    static func makeImpression(params: [String: Any]) throws -> AnyObject? {
        guard #available(iOS 14.5, *) else { return nil }

        let version = ValueCoercion.string(params["version"])
        let networkId = ValueCoercion.string(params["network"])
        let itunesItem = ValueCoercion.int(params["itunesItem"])

        // Resolve attribution: prefer top-level, fall back to fidelity-0.
        let f0 = SKAdNetworkParsing.fidelity0Values(from: params)
        let nonce = ValueCoercion.string(params["nonce"]) ?? f0?.nonce
        let timestampInt = ValueCoercion.int(params["timestamp"]) ?? f0.flatMap { Int($0.timestamp) }
        let signature = ValueCoercion.string(params["signature"]) ?? f0?.signature

        var missing: [String] = []
        if version == nil { missing.append("version") }
        if networkId == nil { missing.append("network") }
        if itunesItem == nil { missing.append("itunesItem") }
        if nonce == nil { missing.append("nonce") }
        if timestampInt == nil { missing.append("timestamp") }
        if signature == nil { missing.append("signature") }

        guard
            missing.isEmpty,
            let version, let networkId, let itunesItem,
            let nonce, let timestampInt, let signature
        else {
            throw Errors.make(
                domain: "MISSING_ARGUMENTS",
                message: "Missing required arguments: \(missing.joined(separator: ", "))"
            )
        }

        // Property-based init covers iOS 14.5+; the iOS 16.0 memberwise init is just sugar.
        let imp = SKAdImpression()
        imp.version = version
        imp.adNetworkIdentifier = networkId
        imp.advertisedAppStoreItemIdentifier = NSNumber(value: itunesItem)
        imp.sourceAppStoreItemIdentifier = NSNumber(value: ValueCoercion.int(params["sourceApp"]) ?? 0)
        imp.adCampaignIdentifier = NSNumber(value: ValueCoercion.int(params["campaign"]) ?? 0)
        imp.adImpressionIdentifier = nonce
        imp.timestamp = NSNumber(value: timestampInt)
        imp.signature = signature

        if #available(iOS 16.1, *) {
            if let sourceIdentifier = SKAdNetworkParsing.sourceIdentifier(from: params) {
                imp.sourceIdentifier = NSNumber(value: sourceIdentifier)
            }
        }
        return imp
    }

    // MARK: - Helpers

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    private func performStart() async -> (Bool, NSError?) {
        if isEnded { return (false, nil) }
        if isStarted { return (true, nil) }

        isStarted = true
        needsEnd = true
        if let error = await callApple(SKAdNetworkManager.appleStartImpression) {
            isStarted = false
            return (false, Errors.make(
                domain: "SKAN_START_IMPRESSION_FAILED",
                message: "Failed to start SKAdImpression: \(error)"
            ))
        }
        return (true, nil)
    }

    private func performEnd(failureDomain: String, failureMessage: String) async -> (Bool, NSError?) {
        isEnded = true
        guard needsEnd else { return (true, nil) }

        if let error = await callApple(SKAdNetworkManager.appleEndImpression) {
            return (false, Errors.make(domain: failureDomain, message: "\(failureMessage): \(error)"))
        }
        isStarted = false
        needsEnd = false
        return (true, nil)
    }

    private func callApple(_ call: @MainActor (AnyObject, @escaping @Sendable (Error?) -> Void) -> Void) async -> Error? {
        await withCheckedContinuation { (cont: CheckedContinuation<Error?, Never>) in
            call(impressionBox) { error in cont.resume(returning: error) }
        }
    }
}
