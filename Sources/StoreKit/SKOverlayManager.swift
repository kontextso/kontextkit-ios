import Foundation
import StoreKit
import UIKit

@MainActor
public final class SKOverlayManager: NSObject {
    public static let shared = SKOverlayManager()

    @available(iOS 16.0, *)
    private var overlay: SKOverlay? {
        get { _overlay as? SKOverlay }
        set { _overlay = newValue }
    }
    // SKOverlay is iOS 16+; an `SKOverlay?` stored property would force
    // the whole class to require iOS 16, but our deployment target is
    // iOS 14. Storing as `AnyObject?` sidesteps that constraint.
    private var _overlay: AnyObject?

    // `internal` (default) so test target can observe state transitions
    // via `@testable import`; not part of the public surface.
    var pendingPresentCompletion: ((Bool, NSError?) -> Void)?
    var pendingDismissCompletion: ((Bool, NSError?) -> Void)?

    private override init() {}

    // MARK: - Public API

    /// Anchor position for an SKOverlay. Mirrors `SKOverlay.Position`.
    /// `String` raw value lets bridges send `Position(rawValue:)` from
    /// JS/Dart strings, while internal callers stay on the enum.
    public enum Position: String, Sendable {
        case bottom
        case bottomRaised

        @available(iOS 16.0, *)
        fileprivate var skOverlayPosition: SKOverlay.Position {
            switch self {
            case .bottom: return .bottom
            case .bottomRaised: return .bottomRaised
            }
        }
    }

    public func present(skan: [String: Any], position: Position, dismissible: Bool, completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        // Class is @MainActor — no dispatch wrapper needed.
        guard #available(iOS 16.0, *) else {
            completion(false, Errors.make(domain: "UNSUPPORTED_IOS", message: "SKOverlay requires iOS 16.0 or later"))
            return
        }
        guard pendingPresentCompletion == nil,
              pendingDismissCompletion == nil else {
            completion(false, Errors.make(domain: "OPERATION_IN_PROGRESS", message: "SKOverlay operation already in progress"))
            return
        }
        guard Scenes.activeScene() != nil else {
            completion(false, Errors.make(domain: "NO_ACTIVE_SCENE", message: "No active UIWindowScene found"))
            return
        }

        // Capture skan + position + dismissible by value into the
        // `dismiss` continuation closure (which crosses a `@Sendable`
        // boundary). Wrap in a struct-of-Sendable values rather than
        // capturing the raw `[String: Any]`, which isn't Sendable.
        let payload = PresentPayload(skan: skan, position: position, dismissible: dismissible)
        dismiss { [weak self] _, _ in
            // dismiss completion runs as @Sendable; hop back to MainActor
            // before touching @MainActor-isolated state. iOS 16 check
            // already passed at the top of `present`; repeated only
            // because the Task closure body needs its own availability
            // gate to call iOS-16-only `continuePresent`.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.continuePresent(payload: payload, completion: completion)
            }
        }
    }

    public func dismiss(completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        // Class is @MainActor — no dispatch wrapper needed.
        guard #available(iOS 16.0, *) else {
            completion(false, Errors.make(domain: "UNSUPPORTED_IOS", message: "SKOverlay requires iOS 16.0 or later"))
            return
        }
        guard pendingDismissCompletion == nil else {
            completion(false, Errors.make(domain: "OPERATION_IN_PROGRESS", message: "SKOverlay dismiss already in progress"))
            return
        }
        guard pendingPresentCompletion == nil else {
            completion(false, Errors.make(domain: "OPERATION_IN_PROGRESS", message: "Cannot dismiss while present is in progress"))
            return
        }
        guard overlay != nil else {
            completion(false, Errors.make(domain: "NO_OVERLAY", message: "No overlay to dismiss"))
            return
        }
        guard let scene = Scenes.activeScene() else {
            completion(false, Errors.make(domain: "NO_ACTIVE_SCENE", message: "No active UIWindowScene found"))
            return
        }

        pendingDismissCompletion = completion
        SKOverlay.dismiss(in: scene)
    }

    /// Presents the SKOverlay anchored at the given position. Returns
    /// `true` if it actually displayed. Throws on validation errors
    /// (missing `itunesItem`, no active scene, unsupported iOS, invalid
    /// SKAN attribution data, etc.) or when an overlay operation is
    /// already in progress.
    public func present(
        skan: [String: Any],
        position: Position,
        dismissible: Bool
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            present(skan: skan, position: position, dismissible: dismissible) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: success)
                }
            }
        }
    }

    /// Dismisses any currently-presented overlay. Returns `true` if one
    /// was dismissed. Throws on validation errors (no overlay, no
    /// active scene, dismiss-during-present, etc.).
    public func dismiss() async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            dismiss { dismissed, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: dismissed)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Carrier for the `present(...)` arguments through the
    /// `@Sendable`-typed `dismiss` continuation. Marked
    /// `@unchecked Sendable` because `[String: Any]` isn't natively
    /// Sendable but it's only ever read on the main actor (the
    /// continuation hops back to MainActor before unpacking).
    private struct PresentPayload: @unchecked Sendable {
        let skan: [String: Any]
        let position: Position
        let dismissible: Bool
    }

    @available(iOS 16.0, *)
    private func continuePresent(payload: PresentPayload, completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard let scene = Scenes.activeScene() else {
            completion(false, Errors.make(domain: "NO_ACTIVE_SCENE", message: "No active UIWindowScene found"))
            return
        }

        guard let itunesItem = ValueCoercion.string(payload.skan["itunesItem"]) else {
            completion(false, Errors.make(domain: "INVALID_ARGUMENTS", message: "itunesItem is required"))
            return
        }

        let config = SKOverlay.AppConfiguration(appIdentifier: itunesItem, position: payload.position.skOverlayPosition)
        config.userDismissible = payload.dismissible

        // Strict attribution: refuse to present if SKAN data can't be
        // applied. Shipping an un-attributed overlay would silently
        // drop install credit for the network — better to fail loud
        // than silently miss attribution.
        guard Self.applyImpression(payload.skan, to: config) else {
            completion(false, Errors.make(
                domain: "INVALID_SKAN",
                message: "Failed to apply SKAN impression — missing or invalid fidelity-1 attribution data"
            ))
            return
        }

        let overlay = SKOverlay(configuration: config)
        overlay.delegate = self

        self.overlay = overlay
        self.pendingPresentCompletion = completion
        overlay.present(in: scene)
    }

    @available(iOS 16.0, *)
    static func applyImpression(_ skan: [String: Any], to config: SKOverlay.AppConfiguration) -> Bool {
        // No `fidelities` key → caller didn't intend SKAN attribution;
        // overlay still presents, just without install-credit tracking.
        // If `fidelities` is present, attribution must be fully valid.
        guard skan["fidelities"] != nil else { return true }

        // SKOverlay reads itunesItem from the SKAN dict (SKStoreProduct
        // gets it from a separate parameter). SKAdImpression accepts the
        // nonce as a raw String, so no UUID conversion is needed here.
        guard
            let itunesItem = ValueCoercion.string(skan["itunesItem"]),
            let itemId = ValueCoercion.int(itunesItem),
            let f = SKAdNetworkParsing.fields(from: skan)
        else { return false }

        let imp = SKAdImpression()
        imp.version = f.version
        imp.adNetworkIdentifier = f.network
        imp.advertisedAppStoreItemIdentifier = NSNumber(value: itemId)
        imp.sourceAppStoreItemIdentifier = NSNumber(value: f.sourceAppInt)
        imp.adCampaignIdentifier = NSNumber(value: f.campaignInt)
        imp.adImpressionIdentifier = f.nonce
        imp.timestamp = NSNumber(value: f.timestampInt)
        imp.signature = f.signature

        if #available(iOS 16.1, *) {
            if let sourceIdentifierInt = SKAdNetworkParsing.sourceIdentifier(from: skan) {
                imp.sourceIdentifier = NSNumber(value: sourceIdentifierInt)
            }
        }

        config.setAdImpression(imp)
        return true
    }
}

@available(iOS 16.0, *)
extension SKOverlayManager: @preconcurrency SKOverlayDelegate {
    // Apple delivers SKOverlayDelegate callbacks on the main thread;
    // `@preconcurrency` lets the @MainActor-isolated method bodies
    // satisfy the nonisolated protocol requirement.
    public func storeOverlayDidFailToLoad(_ overlay: SKOverlay, error: Error) {
        if let tracked = self.overlay, tracked === overlay {
            self.overlay = nil
        }
        let completion = pendingPresentCompletion
        pendingPresentCompletion = nil
        completion?(false, Errors.make(
            domain: "LOAD_FAILED",
            message: "Failed to load SKOverlay",
            details: error.localizedDescription
        ))
    }

    public func storeOverlayDidFinishPresentation(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        let completion = pendingPresentCompletion
        pendingPresentCompletion = nil
        completion?(true, nil)
    }

    public func storeOverlayDidFinishDismissal(_ overlay: SKOverlay, transitionContext: SKOverlay.TransitionContext) {
        if let tracked = self.overlay, tracked === overlay {
            self.overlay = nil
        }
        let completion = pendingDismissCompletion
        pendingDismissCompletion = nil
        completion?(true, nil)
    }
}
