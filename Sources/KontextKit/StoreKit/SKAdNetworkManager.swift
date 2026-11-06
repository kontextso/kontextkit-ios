import Foundation
// SKAdImpression isn't annotated Sendable in the StoreKit headers, even
// though it's an immutable value-carrying class. We only ever touch it
// from MainActor — `@preconcurrency` tells the compiler to trust that.
@preconcurrency import StoreKit

/// SKAdNetwork view-through impressions.
///
/// `createImpression(params:)` returns one `SKAdImpressionSession` per ad, each with its own
/// `SKAdImpression`, so several ads (from one SDK or several) can be measured at once.
///
/// `initImpression` / `startImpression` / `endImpression` / `dispose` drive a single impression held by
/// the shared manager: every caller of them shares that one slot, and a second ad's `initImpression`
/// ends the first one's. They are kept for existing callers and run on an `SKAdImpressionSession`.
@MainActor
public final class SKAdNetworkManager {
    public static let shared = SKAdNetworkManager()

    /// The impression the single-slot methods drive.
    var current: SKAdImpressionSession?

    @available(iOS 14.5, *)
    var skImpression: SKAdImpression? { current?.skImpression }

    // Apple's calls, replaceable so tests can see what reaches StoreKit. Typed on `AnyObject` because a
    // stored property cannot carry the iOS 14.5 availability of `SKAdImpression`.
    static var appleStartImpression: @MainActor (AnyObject, @escaping @Sendable (Error?) -> Void) -> Void = { impression, done in
        if #available(iOS 14.5, *), let impression = impression as? SKAdImpression {
            SKAdNetwork.startImpression(impression, completionHandler: done)
        } else {
            done(nil)
        }
    }

    static var appleEndImpression: @MainActor (AnyObject, @escaping @Sendable (Error?) -> Void) -> Void = { impression, done in
        if #available(iOS 14.5, *), let impression = impression as? SKAdImpression {
            SKAdNetwork.endImpression(impression, completionHandler: done)
        } else {
            done(nil)
        }
    }

    private init() {}

    // MARK: - Public API

    /// A new impression for one ad, independent of every other. Throws `MISSING_ARGUMENTS` when a
    /// required key is missing, `SKAN_INIT_UNAVAILABLE` below iOS 14.5. Keys: see `initImpression`.
    public func createImpression(params: [String: Any]) throws -> SKAdImpressionSession {
        guard let impression = try SKAdImpressionSession.makeImpression(params: params) else {
            throw Self.unavailableError()
        }
        return SKAdImpressionSession(impression: impression)
    }

    /// Replaces the shared manager's one impression; the previous one is ended (if it was started) before
    /// the completion runs. Prefer `createImpression(params:)`, which gives each ad its own.
    ///
    /// Required keys:
    ///  - version: String
    ///  - network: String              (adNetworkIdentifier)
    ///  - itunesItem: String/Int       (advertisedAppStoreItemIdentifier)
    ///
    /// Required (either at top-level OR inside `fidelities[]` as a
    /// fidelity-0 entry):
    ///  - nonce: String                (adImpressionIdentifier)
    ///  - timestamp: String/Int
    ///  - signature: String
    ///
    /// Optional keys:
    ///  - sourceApp: String/Int        (sourceAppStoreItemIdentifier; defaults to 0 — "no App Store ID known")
    ///  - campaign: String/Int         (adCampaignIdentifier; defaults to 0)
    ///  - sourceIdentifier: String/Int (SKAdNetwork 4.0, iOS 16.1+)
    ///  - fidelities: Array            (fidelity-0 entry fills missing top-level nonce/timestamp/signature)
    public func initImpression(params: [String: Any], completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        let impression: AnyObject?
        do {
            impression = try SKAdImpressionSession.makeImpression(params: params)
        } catch {
            completion(false, error as NSError)
            return
        }
        guard let impression else {
            completion(false, nil)
            return
        }

        let previous = current
        current = SKAdImpressionSession(impression: impression)

        // Best-effort: a failed end of the previous one doesn't fail this init. The OS retries SKAN
        // postbacks internally, so the missed end-signal isn't catastrophic.
        if let previous {
            previous.end { _, _ in completion(true, nil) }
        } else {
            completion(true, nil)
        }
    }

    public func startImpression(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard #available(iOS 14.5, *) else {
            completion(false, nil)
            return
        }
        guard let current else {
            completion(false, Self.noImpressionError())
            return
        }
        current.start(completion: completion)
    }

    public func endImpression(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard #available(iOS 14.5, *) else {
            completion(false, nil)
            return
        }
        guard let current else {
            completion(false, Self.noImpressionError())
            return
        }
        current.end(completion: completion)
    }

    public func dispose(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard let disposed = current else {
            completion(true, nil)
            return
        }
        current = nil
        disposed.end(
            failureDomain: "SKAN_DISPOSE_END_IMPRESSION_FAILED",
            failureMessage: "Failed to end SKAdImpression during dispose",
            completion: completion
        )
    }

    /// Initializes the SKAdImpression. Throws on validation failure, and
    /// with `SKAN_INIT_UNAVAILABLE` on iOS older than 14.5 (where the API
    /// isn't available).
    public func initImpression(params: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            initImpression(params: params) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: Self.unavailableError())
                }
            }
        }
    }

    /// Starts the impression tracking window. Returns `true` if started
    /// (or already started), `false` if iOS < 14.5. Throws if init wasn't
    /// called or the system rejected the start.
    public func startImpression() async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            startImpression { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: success)
                }
            }
        }
    }

    /// Ends the impression. Same return semantics as `startImpression`.
    public func endImpression() async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            endImpression { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: success)
                }
            }
        }
    }

    /// Disposes of the impression. Throws if `SKAdNetwork.endImpression`
    /// reports an error during teardown — surfaces what would otherwise
    /// be silent failures so consumers can route them to telemetry.
    public func dispose() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            dispose { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Helpers

    private nonisolated static func unavailableError() -> NSError {
        Errors.make(domain: "SKAN_INIT_UNAVAILABLE", message: "SKAdImpression is unavailable on this iOS version")
    }

    private static func noImpressionError() -> NSError {
        Errors.make(domain: "NO_IMPRESSION", message: "SKAdImpression not initialized. Call initImpression first.")
    }
}
