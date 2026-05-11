import Foundation
import StoreKit

@MainActor
public final class SKAdNetworkManager {
    public static let shared = SKAdNetworkManager()

    @available(iOS 14.5, *)
    var skImpression: SKAdImpression? {
        get { skImpressionBox as? SKAdImpression }
        set { skImpressionBox = newValue }
    }
    // SKAdImpression is iOS 14.5+; storing as `Any?` sidesteps the
    // deploying-target-vs-stored-property-availability rule (a stored
    // `SKAdImpression?` would force the whole class to require iOS 14.5,
    // but the class needs to remain accessible on iOS 14.0 — methods
    // gracefully return false on iOS < 14.5 instead of crashing).
    var skImpressionBox: Any?
    var isStarted: Bool = false

    private init() {}

    // MARK: - Public API

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
        guard #available(iOS 14.5, *) else {
            completion(false, nil)
            return
        }

        // Required top-level fields.
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
            completion(false, Errors.make(
                domain: "MISSING_ARGUMENTS",
                message: "Missing required arguments: \(missing.joined(separator: ", "))"
            ))
            return
        }

        // Optional with defaults.
        let sourceApp = ValueCoercion.int(params["sourceApp"]) ?? 0
        let campaign = ValueCoercion.int(params["campaign"]) ?? 0

        // Property-based init covers iOS 14.5+; the iOS 16.0 memberwise
        // init is just sugar — using one path keeps the code uniform.
        let imp = SKAdImpression()
        imp.version = version
        imp.adNetworkIdentifier = networkId
        imp.advertisedAppStoreItemIdentifier = NSNumber(value: itunesItem)
        imp.sourceAppStoreItemIdentifier = NSNumber(value: sourceApp)
        imp.adCampaignIdentifier = NSNumber(value: campaign)
        imp.adImpressionIdentifier = nonce
        imp.timestamp = NSNumber(value: timestampInt)
        imp.signature = signature

        if #available(iOS 16.1, *) {
            if let sourceIdentifier = SKAdNetworkParsing.sourceIdentifier(from: params) {
                imp.sourceIdentifier = NSNumber(value: sourceIdentifier)
            }
        }

        let previousImpression = isStarted ? skImpression : nil
        isStarted = false
        skImpression = imp

        // End any previous impression after the new one is safely
        // stored. We await the system's completion so the caller knows
        // the previous impression is fully ended before they proceed.
        // Best-effort: a failure here doesn't propagate (the new init
        // genuinely succeeded). The OS retries SKAN postbacks
        // internally, so the missed end-signal isn't catastrophic.
        if let old = previousImpression {
            SKAdNetwork.endImpression(old) { _ in
                Task { @MainActor in completion(true, nil) }
            }
        } else {
            completion(true, nil)
        }
    }

    public func startImpression(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard #available(iOS 14.5, *) else {
            completion(false, nil)
            return
        }
        guard let impression = skImpression else {
            completion(false, Errors.make(
                domain: "NO_IMPRESSION",
                message: "SKAdImpression not initialized. Call initImpression first."
            ))
            return
        }
        guard !isStarted else {
            // Already started — ignore duplicate call.
            completion(true, nil)
            return
        }

        isStarted = true
        SKAdNetwork.startImpression(impression) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // Only roll back if our state still references THIS
                    // impression. If init replaced it between the call
                    // and this callback, the new impression has its own
                    // lifecycle and shouldn't inherit the failed start's
                    // rollback.
                    if self.skImpression === impression {
                        self.isStarted = false
                    }
                    completion(false, Errors.make(
                        domain: "SKAN_START_IMPRESSION_FAILED",
                        message: "Failed to start SKAdImpression: \(error)"
                    ))
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    public func endImpression(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard #available(iOS 14.5, *) else {
            completion(false, nil)
            return
        }
        guard let impression = skImpression else {
            completion(false, Errors.make(
                domain: "NO_IMPRESSION",
                message: "SKAdImpression not initialized. Call initImpression first."
            ))
            return
        }
        guard isStarted else {
            // Not started — ignore unmatched endImpression.
            completion(true, nil)
            return
        }

        isStarted = false
        SKAdNetwork.endImpression(impression) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    // Only roll back if our state still references THIS
                    // impression. If init replaced it between the call
                    // and this callback, the new impression has its own
                    // lifecycle and shouldn't inherit the failed end's
                    // rollback (which would falsely mark NEW as started).
                    if self.skImpression === impression {
                        self.isStarted = true
                    }
                    completion(false, Errors.make(
                        domain: "SKAN_END_IMPRESSION_FAILED",
                        message: "Failed to end SKAdImpression: \(error)"
                    ))
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    public func dispose(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        if #available(iOS 14.5, *), isStarted, let impression = skImpression {
            isStarted = false
            skImpressionBox = nil
            SKAdNetwork.endImpression(impression) { error in
                Task { @MainActor in
                    if let error {
                        completion(false, Errors.make(
                            domain: "SKAN_DISPOSE_END_IMPRESSION_FAILED",
                            message: "Failed to end SKAdImpression during dispose: \(error)"
                        ))
                    } else {
                        completion(true, nil)
                    }
                }
            }
        } else {
            isStarted = false
            skImpressionBox = nil
            completion(true, nil)
        }
    }

    /// Initializes the SKAdImpression. Throws on validation failure or
    /// system error. Returns normally on success or when running on iOS
    /// older than 14.5 (where the API isn't available).
    public func initImpression(params: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            initImpression(params: params) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else if success {
                    cont.resume()
                } else {
                    cont.resume(throwing: Errors.make(
                        domain: "SKAN_INIT_UNAVAILABLE",
                        message: "SKAdImpression is unavailable on this iOS version"
                    ))
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
}
