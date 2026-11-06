import Foundation
import SafariServices
import UIKit

/// Hosts a single SFSafariViewController at a time for the in-app
/// browser flow. Presented from the top-most view controller (or the one
/// the caller passes); closed by the user tapping "Done", explicitly by
/// `dismiss()`, or automatically when the user comes
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
        /// The user came back to the app after having left it.
        case returnedToApp
    }

    /// The browser presented last, until UIKit releases it. Weak, and still set
    /// while its dismissal animates after it closed, so a caller can recognise it
    /// on screen; `isPresented` says whether it is open.
    public private(set) weak var presentedController: UIViewController?

    /// A browser is open: presented, not closed since, and still on screen (UIKit
    /// presents it and is not dismissing it).
    public var isPresented: Bool {
        guard isOpen, let vc = presentedController else { return false }
        return isOnScreen(vc)
    }

    private var isOpen = false
    private var onClose: (@MainActor (CloseReason) -> Void)?
    private var leftApp = false
    private var sceneObservers: [NSObjectProtocol] = []
    /// The scene of the view controller the browser was presented over, until the
    /// browser is in a window of its own.
    private weak var ownerScene: AnyObject?

    private let notificationCenter: NotificationCenter
    private let topViewController: @MainActor () -> UIViewController?
    private let presentController: @MainActor (_ browser: UIViewController, _ presenter: UIViewController) -> Void
    private let dismissController: @MainActor (
        _ browser: UIViewController, _ animated: Bool, _ completion: @escaping @MainActor @Sendable () -> Void
    ) -> Void
    private let presentingController: @MainActor (_ controller: UIViewController) -> UIViewController?
    private let afterSelfDismissal: @MainActor (_ browser: UIViewController, _ then: @escaping @MainActor @Sendable () -> Void) -> Void
    private let after: @MainActor (_ seconds: Double, _ work: @escaping @MainActor @Sendable () -> Void) -> Void
    private let sceneOf: @MainActor (_ controller: UIViewController) -> AnyObject?

    /// When UIKit never reports the end of a dismissal, `onClose` runs anyway after this.
    static let closeDeadline: Double = 2

    init(
        notificationCenter: NotificationCenter = .default,
        topViewController: @escaping @MainActor () -> UIViewController? = { Scenes.topViewController() },
        presentController: @escaping @MainActor (UIViewController, UIViewController) -> Void = { $1.present($0, animated: true) },
        dismissController: @escaping @MainActor (UIViewController, Bool, @escaping @MainActor @Sendable () -> Void) -> Void
            = { browser, animated, completion in browser.dismiss(animated: animated, completion: completion) },
        presentingController: @escaping @MainActor (UIViewController) -> UIViewController? = { $0.presentingViewController },
        afterSelfDismissal: @escaping @MainActor (UIViewController, @escaping @MainActor @Sendable () -> Void) -> Void
            = InAppBrowserManager.afterSafariDismissal,
        after: @escaping @MainActor (Double, @escaping @MainActor @Sendable () -> Void) -> Void = { seconds, work in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                work()
            }
        },
        sceneOf: @escaping @MainActor (UIViewController) -> AnyObject? = { $0.viewIfLoaded?.window?.windowScene }
    ) {
        self.notificationCenter = notificationCenter
        self.topViewController = topViewController
        self.presentController = presentController
        self.dismissController = dismissController
        self.presentingController = presentingController
        self.afterSelfDismissal = afterSelfDismissal
        self.after = after
        self.sceneOf = sceneOf
        super.init()
    }

    // MARK: - Public API

    @discardableResult
    public func present(url: URL) -> Bool {
        present(url: url, from: nil, onClose: nil)
    }

    /// Presents `url` over `presenter`, or over the top-most view controller when nil.
    /// The presenter should be a full-screen context, such as the top-most view
    /// controller; a contained child is not looked through.
    ///
    /// `onClose` runs once, after this browser is off screen, whatever the reason.
    /// A `present` from it therefore just works.
    ///
    /// One browser at a time: while a browser is open, or closed but still leaving
    /// the screen (right after "Done" or `dismiss()`), `present` returns `false` and
    /// leaves it alone. Present again from `onClose`.
    ///
    /// `false`, and no `onClose`, also when the URL is not http(s), nothing can
    /// present it (no presenter, one not in a window, being dismissed, or already
    /// presenting something), or UIKit refuses it.
    @discardableResult
    public func present(
        url: URL,
        from presenter: UIViewController? = nil,
        onClose: (@MainActor (CloseReason) -> Void)?
    ) -> Bool {
        guard Self.isSupportedScheme(url) else { return false }
        if let shown = presentedController, presentingController(shown) != nil { return false }
        // Gone without notice: the app dismissed the stack holding it.
        if isOpen { close(.dismissed) { done in done() } }
        // !isOpen: that browser's onClose presented one of its own.
        guard !isOpen, let top = presenter ?? topViewController(), canPresent(over: top) else { return false }

        let vc = SFSafariViewController(url: url)
        vc.delegate = self
        vc.modalPresentationStyle = .overFullScreen
        presentController(vc, top)
        // UIKit attaches a presentation it accepts at once.
        guard presentingController(vc) != nil else { return false }

        presentedController = vc
        ownerScene = sceneOf(top)
        isOpen = true
        leftApp = false
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
        guard isOpen, controller === presentedController else { return }
        close(.done) { [afterSelfDismissal] done in afterSelfDismissal(controller, done) }
    }

    // MARK: - Closing

    private func dismiss(reason: CloseReason) -> Bool {
        guard isOpen else { return false }
        guard isPresented, let vc = presentedController else {
            close(.dismissed) { done in done() }
            return false
        }
        close(reason) { [dismissController] done in dismissController(vc, true, done) }
        return true
    }

    /// Marks the browser closed at once, and runs its handler once `leave` reports
    /// it off screen, or after `closeDeadline` if UIKit never does.
    private func close(_ reason: CloseReason, leave: (_ done: @escaping @MainActor @Sendable () -> Void) -> Void) {
        isOpen = false
        leftApp = false
        stopSceneObservers()
        let pending = PendingClose(reason: reason, handler: onClose)
        onClose = nil
        guard pending.handler != nil else {
            leave { }
            return
        }
        after(Self.closeDeadline) { pending.run() }
        leave { pending.run() }
    }

    /// Safari dismisses itself after `safariViewControllerDidFinish` returns: wait for
    /// that transition to end, or, with none running, check that it has gone. Anything
    /// else is left to the deadline.
    static func afterSafariDismissal(_ browser: UIViewController, _ then: @escaping @MainActor @Sendable () -> Void) {
        let presenter = browser.presentingViewController
        Task { @MainActor [weak browser, weak presenter] in
            if let coordinator = presenter?.transitionCoordinator ?? browser?.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    Task { @MainActor in then() }
                }
            } else if browser?.presentingViewController == nil {
                then()
            }
        }
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
                _ = manager.dismiss(reason: .returnedToApp)
            },
        ]
    }

    private func stopSceneObservers() {
        sceneObservers.forEach(notificationCenter.removeObserver)
        sceneObservers = []
    }

    private func observe(
        _ name: Notification.Name,
        _ handle: @escaping @MainActor @Sendable (InAppBrowserManager, AnyObject?) -> Void
    ) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
            // UIKit posts scene notifications on the main thread; handle them in place so
            // a background and the activation after it keep their order.
            let scene = UncheckedSendable(note.object as AnyObject?)
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

    /// The browser's scene: its own window's once it has one, before that the scene
    /// of the view controller it was presented over. Another window scene of a
    /// multi-window app does not count; a notification without a scene, or a
    /// browser whose scene is not known, does.
    private func isBrowserScene(_ scene: AnyObject?) -> Bool {
        guard let scene else { return true }
        guard let own = presentedController.flatMap(sceneOf) ?? ownerScene else { return true }
        return scene === own
    }

    /// `top` is in a window, not being dismissed, and presents nothing.
    private func canPresent(over top: UIViewController) -> Bool {
        top.viewIfLoaded?.window != nil && !top.isBeingDismissed && top.presentedViewController == nil
    }

    private func isOnScreen(_ vc: UIViewController) -> Bool {
        presentingController(vc) != nil && !vc.isBeingDismissed
    }

    // MARK: - Helpers

    /// SFSafariViewController only supports http/https — see Apple's docs.
    private static func isSupportedScheme(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}

/// A closed browser's handler, run once: by the end of its dismissal or by the deadline.
@MainActor
private final class PendingClose {
    let reason: InAppBrowserManager.CloseReason
    private(set) var handler: (@MainActor (InAppBrowserManager.CloseReason) -> Void)?

    init(reason: InAppBrowserManager.CloseReason, handler: (@MainActor (InAppBrowserManager.CloseReason) -> Void)?) {
        self.reason = reason
        self.handler = handler
    }

    func run() {
        guard let handler else { return }
        self.handler = nil
        handler(reason)
    }
}
