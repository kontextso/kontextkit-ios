import Foundation
import SafariServices
import UIKit

/// Hosts a single SFSafariViewController at a time for the in-app
/// browser flow. Presented from the top-most view controller (or the one
/// the caller passes); closed by the user tapping "Done", explicitly by
/// `dismiss()`, by a new `present`, or automatically when the user comes
/// back to the app after having left it (the deep-link case where the
/// browser sent them to another app via an `amazon://` or App Store
/// redirect, and they return to find the browser still stuck on top).
/// A mere inactive → active bounce, such as Notification Center or
/// Control Center pulled down over the browser, leaves it open.
@MainActor
public final class InAppBrowserManager: NSObject, @preconcurrency SFSafariViewControllerDelegate {
    public static let shared = InAppBrowserManager()

    /// Why the browser went away, passed to the `onClose` handler of `present(url:from:onClose:)`.
    public enum CloseReason: Sendable, Equatable {
        /// The user tapped "Done".
        case done
        /// `dismiss()` was called, or UIKit had already taken the browser away
        /// without telling (the app dismissing its whole stack); the latter is
        /// reported at the next `present` or `dismiss()`.
        case dismissed
        /// A new `present` replaced it.
        case replaced
        /// The user came back to the app after having left it.
        case returnedToApp
    }

    /// The browser presented last, until UIKit releases it. Weak, and still set
    /// while its dismissal animates after it closed, so a caller can recognise it
    /// on screen; `isPresented` says whether it is open.
    public private(set) weak var presentedController: UIViewController?

    /// A browser is open: presented, not closed since, and still held by UIKit.
    public var isPresented: Bool { isOpen && presentedController != nil }

    private var isOpen = false
    private var onClose: (@MainActor (CloseReason) -> Void)?
    private var leftApp = false
    private var sceneObservers: [NSObjectProtocol] = []

    private let notificationCenter: NotificationCenter
    private let topViewController: @MainActor () -> UIViewController?
    private let presentController: @MainActor (_ browser: UIViewController, _ presenter: UIViewController) -> Void
    private let dismissController: @MainActor (_ browser: UIViewController, _ animated: Bool) -> Void

    init(
        notificationCenter: NotificationCenter = .default,
        topViewController: @escaping @MainActor () -> UIViewController? = { Scenes.topViewController() },
        presentController: @escaping @MainActor (UIViewController, UIViewController) -> Void = { $1.present($0, animated: true) },
        dismissController: @escaping @MainActor (UIViewController, Bool) -> Void = { $0.dismiss(animated: $1) }
    ) {
        self.notificationCenter = notificationCenter
        self.topViewController = topViewController
        self.presentController = presentController
        self.dismissController = dismissController
        super.init()
    }

    // MARK: - Public API

    @discardableResult
    public func present(url: URL) -> Bool {
        present(url: url, from: nil, onClose: nil)
    }

    /// Presents `url` over `presenter`, or over the top-most view controller when nil.
    /// `onClose` runs once, when this browser goes away for any reason. `false`, and
    /// no `onClose`, when the URL is not http(s) or nothing can present it; an open
    /// browser is then left as it was.
    @discardableResult
    public func present(
        url: URL,
        from presenter: UIViewController? = nil,
        onClose: (@MainActor (CloseReason) -> Void)?
    ) -> Bool {
        guard Self.isSupportedScheme(url) else { return false }
        guard let top = presenter ?? topViewController() else { return false }

        let replaced = isPresented
        if replaced, let existing = presentedController {
            dismissController(existing, false)
        }
        close(replaced ? .replaced : .dismissed)

        let vc = SFSafariViewController(url: url)
        vc.delegate = self
        vc.modalPresentationStyle = .overFullScreen
        presentController(vc, top)

        presentedController = vc
        isOpen = true
        self.onClose = onClose
        startSceneObservers()
        return true
    }

    @discardableResult
    public func dismiss() -> Bool {
        dismiss(reason: .dismissed)
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
        guard controller === presentedController, isOpen else { return }
        close(.done)
    }

    // MARK: - Closing

    private func dismiss(reason: CloseReason) -> Bool {
        let wasPresented = isPresented
        if wasPresented, let vc = presentedController {
            dismissController(vc, true)
        }
        close(reason)
        return wasPresented
    }

    /// Marks the browser closed and runs its handler, at most once. The handler is
    /// cleared before it runs, so one that presents again starts a fresh browser.
    private func close(_ reason: CloseReason) {
        isOpen = false
        leftApp = false
        stopSceneObservers()
        guard let handler = onClose else { return }
        onClose = nil
        handler(reason)
    }

    // MARK: - Auto-dismiss on return to the app

    /// SFSafariViewController is presented modally, so the app stays in front while it
    /// is up. The scene only enters the background when the browser hands the user to
    /// another app (a deep link, an App Store redirect) or the user leaves; the next
    /// activation is then their return, and the browser is closed. An activation with
    /// no background before it (Notification Center, Control Center, a system alert)
    /// leaves it open.
    private func startSceneObservers() {
        guard sceneObservers.isEmpty else { return }
        sceneObservers = [
            observe(UIScene.didEnterBackgroundNotification) { manager, scene in
                if manager.isBrowserScene(scene) { manager.leftApp = true }
            },
            observe(UIScene.didActivateNotification) { manager, scene in
                guard manager.leftApp, manager.isBrowserScene(scene) else { return }
                _ = manager.dismiss(reason: manager.isPresented ? .returnedToApp : .dismissed)
            },
        ]
    }

    private func stopSceneObservers() {
        sceneObservers.forEach(notificationCenter.removeObserver)
        sceneObservers = []
    }

    private func observe(
        _ name: Notification.Name,
        _ handle: @escaping @MainActor @Sendable (InAppBrowserManager, UIScene?) -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
            // UIKit posts scene notifications on the main thread; handle them in place so
            // a background and the activation after it keep their order.
            let scene = UncheckedSendable(note.object as? UIScene)
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handle(self, scene.value)
                }
            } else {
                Task { @MainActor in
                    guard let self else { return }
                    handle(self, scene.value)
                }
            }
        }
    }

    /// Another window scene of a multi-window app does not count; a notification
    /// without a scene, or a browser not in a window yet, does.
    private func isBrowserScene(_ scene: UIScene?) -> Bool {
        guard let scene, let own = presentedController?.viewIfLoaded?.window?.windowScene else { return true }
        return scene === own
    }

    // MARK: - Helpers

    /// SFSafariViewController only supports http/https — see Apple's docs.
    private static func isSupportedScheme(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
