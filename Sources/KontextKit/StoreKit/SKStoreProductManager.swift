import Foundation
import StoreKit
import UIKit

@MainActor
public final class SKStoreProductManager: NSObject, @preconcurrency SKStoreProductViewControllerDelegate {
    public static let shared = SKStoreProductManager()

    private weak var presentedViewController: SKStoreProductViewController?
    var pendingPresentCompletion: ((Bool, NSError?) -> Void)?
    var pendingDismissCompletion: ((Bool) -> Void)?

    private override init() {}

    // MARK: - Public API

    public func present(skan: [String: Any], completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard let itunesItem = ValueCoercion.string(skan["itunesItem"]),
              let itemId = Int(itunesItem) else {
            completion(false, Errors.make(domain: "INVALID_ARGUMENTS", message: "itunesItem must be a valid integer string"))
            return
        }

        var params: [String: Any] = [
            SKStoreProductParameterITunesItemIdentifier: NSNumber(value: itemId)
        ]
        // Strict attribution: if SKAN data is provided, it must apply
        // cleanly. Shipping a product page with malformed attribution
        // would silently drop install credit. If no `fidelities` key
        // is present, applySkanParams returns true (no attribution
        // intended — the product page still loads).
        guard Self.applySkanParams(skan, into: &params) else {
            completion(false, Errors.make(
                domain: "INVALID_SKAN",
                message: "Failed to apply SKAN attribution — missing or invalid fidelity-1 data"
            ))
            return
        }

        guard pendingPresentCompletion == nil,
              pendingDismissCompletion == nil else {
            completion(false, Errors.make(domain: "OPERATION_IN_PROGRESS", message: "SKStoreProduct operation already in progress"))
            return
        }

        if presentedViewController != nil || Scenes.topViewController() is SKStoreProductViewController {
            // `params` is `[String: Any]` (StoreKit's required shape), which
            // isn't Sendable. Capturing it directly into the @Sendable Task
            // closure trips Swift 6 strict-concurrency. Building it on
            // MainActor and consuming it on MainActor is actually safe — the
            // wrapper expresses that with @unchecked Sendable.
            let sendableParams = UncheckedSendable(params)
            dismiss { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        completion(false, Errors.make(domain: "MANAGER_DEALLOCATED", message: "Manager was deallocated"))
                        return
                    }
                    guard self.presentedViewController == nil else {
                        completion(false, Errors.make(domain: "DISMISS_FAILED", message: "Failed to dismiss existing product view before presenting a new one"))
                        return
                    }
                    self.loadAndPresent(params: sendableParams.value, completion: completion)
                }
            }
            return
        }

        loadAndPresent(params: params, completion: completion)
    }

    private func loadAndPresent(params: [String: Any], completion: @escaping @Sendable (Bool, NSError?) -> Void) {
        guard pendingPresentCompletion == nil,
              pendingDismissCompletion == nil else {
            completion(false, Errors.make(domain: "OPERATION_IN_PROGRESS", message: "SKStoreProduct operation already in progress"))
            return
        }

        pendingPresentCompletion = completion
        let viewController = SKStoreProductViewController()
        viewController.delegate = self
        viewController.loadProduct(withParameters: params) { [weak self] loaded, error in
            // loadProduct's completion runs on an unspecified queue.
            // Hop to MainActor explicitly before touching VC presentation
            // and our @MainActor state.
            Task { @MainActor [weak self] in
                guard let self else {
                    completion(false, Errors.make(domain: "MANAGER_DEALLOCATED", message: "Manager was deallocated"))
                    return
                }
                guard loaded else {
                    let errorMessage = error?.localizedDescription ?? "Failed to load product"
                    self.completePresent(false, Errors.make(domain: "LOAD_FAILED", message: errorMessage))
                    return
                }

                guard let top = Scenes.topViewController() else {
                    self.completePresent(false, Errors.make(domain: "NO_TOP_VIEW_CONTROLLER", message: "No top view controller found"))
                    return
                }

                top.present(viewController, animated: true) { [weak self] in
                    self?.presentedViewController = viewController
                    self?.completePresent(true, nil)
                }
            }
        }
    }

    public func dismiss(completion: @escaping @Sendable (Bool) -> Void) {
        // Class is @MainActor — already on main, no dispatch needed.
        guard pendingDismissCompletion == nil else {
            completion(false)
            return
        }
        guard pendingPresentCompletion == nil else {
            completion(false)
            return
        }

        if let viewController = self.presentedViewController {
            pendingDismissCompletion = completion
            viewController.dismiss(animated: true) { [weak self] in
                self?.presentedViewController = nil
                self?.completeDismiss(true)
            }
            return
        }

        if let top = Scenes.topViewController() as? SKStoreProductViewController {
            pendingDismissCompletion = completion
            top.dismiss(animated: true) { [weak self] in
                self?.presentedViewController = nil
                self?.completeDismiss(true)
            }
            return
        }

        completion(false)
    }

    /// Presents the App Store product page. Returns `true` when a
    /// view controller was actually presented. Throws on validation or
    /// load errors (missing/invalid `itunesItem`, network failure, etc).
    public func present(skan: [String: Any]) async throws -> Bool {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            present(skan: skan) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: success)
                }
            }
        }
    }

    /// Dismisses the currently-presented product page. Returns `true` if
    /// something was actually dismissed.
    public func dismiss() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            dismiss { dismissed in cont.resume(returning: dismissed) }
        }
    }

    // MARK: - SKStoreProductViewControllerDelegate

    public func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        viewController.dismiss(animated: true) { [weak self] in
            self?.presentedViewController = nil
        }
    }

    // MARK: - Helpers

    /// Writes SKAN attribution params if `fidelities` key is present
    /// and parses cleanly. Returns:
    /// - `true` if attribution was applied OR the dict has no
    ///   `fidelities` key (caller didn't intend attribution).
    /// - `false` if `fidelities` was provided but parsing failed.
    static func applySkanParams(_ skan: [String: Any], into params: inout [String: Any]) -> Bool {
        // No fidelities key → caller didn't intend SKAN attribution;
        // signal success so the caller can still present the product page.
        guard skan["fidelities"] != nil else { return true }

        // SKStoreProduct requires the nonce as UUID (Apple's
        // SKStoreProductParameterAdNetworkNonce is typed UUID, unlike
        // SKAdImpression.adImpressionIdentifier which is String).
        // Validate at the call site since Fields stores it as raw string.
        guard
            let f = SKAdNetworkParsing.fields(from: skan),
            let nonce = UUID(uuidString: f.nonce)
        else { return false }

        params[SKStoreProductParameterAdNetworkVersion] = f.version
        params[SKStoreProductParameterAdNetworkIdentifier] = f.network
        params[SKStoreProductParameterAdNetworkSourceAppStoreIdentifier] = NSNumber(value: f.sourceAppInt)
        params[SKStoreProductParameterAdNetworkCampaignIdentifier] = NSNumber(value: f.campaignInt)
        params[SKStoreProductParameterAdNetworkTimestamp] = NSNumber(value: f.timestampInt)
        params[SKStoreProductParameterAdNetworkAttributionSignature] = f.signature
        params[SKStoreProductParameterAdNetworkNonce] = nonce

        if #available(iOS 16.1, *) {
            if let sourceIdentifierInt = SKAdNetworkParsing.sourceIdentifier(from: skan) {
                params[SKStoreProductParameterAdNetworkSourceIdentifier] = NSNumber(value: sourceIdentifierInt)
            }
        }

        return true
    }

    private func completePresent(_ success: Bool, _ error: NSError?) {
        let completion = pendingPresentCompletion
        pendingPresentCompletion = nil
        completion?(success, error)
    }

    private func completeDismiss(_ success: Bool) {
        let completion = pendingDismissCompletion
        pendingDismissCompletion = nil
        completion?(success)
    }
}
