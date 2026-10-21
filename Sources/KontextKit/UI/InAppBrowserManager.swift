import Foundation
import SafariServices
import UIKit

/// Hosts a single SFSafariViewController at a time for the in-app
/// browser flow. Presented from the top-most view controller; dismissed
/// explicitly, automatically on app foreground (to cover the deep-link
/// interaction case where the user leaves via an `amazon://` or App Store
/// redirect and returns to find the browser still stuck on top), or by
/// the user tapping "Done".
@MainActor
public final class InAppBrowserManager: NSObject, @preconcurrency SFSafariViewControllerDelegate {
    public static let shared = InAppBrowserManager()

    private weak var current: SFSafariViewController?
    private var foregroundObserver: NSObjectProtocol?

    private override init() {}

    // MARK: - Public API

    @discardableResult
    public func present(url: URL) -> Bool {
        guard Self.isSupportedScheme(url) else { return false }
        guard let top = Scenes.topViewController() else { return false }

        // Close any existing instance first (shouldn't happen in practice but
        // safer than leaking).
        if let existing = current {
            existing.dismiss(animated: false, completion: nil)
            current = nil
        }

        let vc = SFSafariViewController(url: url)
        vc.delegate = self
        vc.modalPresentationStyle = .overFullScreen
        top.present(vc, animated: true, completion: nil)

        current = vc
        startForegroundObserverIfNeeded()
        return true
    }

    @discardableResult
    public func dismiss() -> Bool {
        guard let vc = current else {
            stopForegroundObserver()
            return false
        }
        vc.dismiss(animated: true, completion: nil)
        current = nil
        stopForegroundObserver()
        return true
    }

    /// Open URL in in-app browser with http(s) validation. For bridge layers (RN, Flutter).
    @discardableResult
    public func openFromURLString(_ urlString: String) -> Result<Bool, NSError> {
        guard let url = URL(string: urlString), Self.isSupportedScheme(url) else {
            return .failure(Errors.make(
                domain: "IN_APP_BROWSER_ERROR",
                message: "Invalid or unsupported URL: \(urlString)"
            ))
        }
        if present(url: url) {
            return .success(true)
        } else {
            return .failure(Errors.make(
                domain: "IN_APP_BROWSER_ERROR",
                message: "Failed to present in-app browser"
            ))
        }
    }

    // MARK: - SFSafariViewControllerDelegate

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        if controller === current {
            current = nil
            stopForegroundObserver()
        }
    }

    // MARK: - Auto-dismiss on app foreground

    /// Registers a listener so we dismiss the browser when the user returns
    /// to the app (e.g. after the browser triggered a deep link and the OS
    /// switched to another app). Without this, the SFSafariViewController
    /// stays presented on top of the UI with stale content.
    private func startForegroundObserverIfNeeded() {
        guard foregroundObserver == nil else { return }
        let center = NotificationCenter.default
        foregroundObserver = center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
            // SFSafariViewController is presented modally — the app stays active
            // throughout, so this notification only fires when the user returns from
            // a deep-link hand-off (e.g. amazon:// or App Store redirect). No
            // first-activation skip needed (unlike the Android CustomTabs path).
            // The notification block is nonisolated; hop to MainActor.
            Task { @MainActor in self?.handleForeground() }
        }
    }

    private func stopForegroundObserver() {
        if let token = foregroundObserver {
            NotificationCenter.default.removeObserver(token)
            foregroundObserver = nil
        }
    }

    private func handleForeground() {
        // Only dismiss if we actually have a presented browser. Covers the case
        // where the user manually tapped Done — current is already nil and
        // this becomes a no-op.
        guard current != nil else { return }
        dismiss()
    }

    // MARK: - Helpers

    /// SFSafariViewController only supports http/https — see Apple's docs.
    private static func isSupportedScheme(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
