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
        /// reported at the next `present` or `dismiss()`. Also a browser that
        /// was waiting for the previous one to leave the screen and could then
        /// not be shown.
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

    /// A browser is open: presented, not closed since, and still on screen (UIKit
    /// presents it and is not dismissing it), or about to be shown once the
    /// previous browser has left the screen.
    public var isPresented: Bool {
        guard isOpen, let vc = presentedController else { return false }
        return vc === pending || isOnScreen(vc)
    }

    private var isOpen = false
    private var onClose: (@MainActor (CloseReason) -> Void)?
    private var leftApp = false
    private var sceneObservers: [NSObjectProtocol] = []
    /// Bumped by every `present` that passes its checks, so one that ran the old
    /// browser's handler can tell whether that handler presented a browser itself.
    private var session = 0
    /// The scene of the view controller the browser was presented over, until the
    /// browser is in a window of its own.
    private weak var ownerScene: AnyObject?
    /// The browser waiting for the previous one to leave the screen; held here
    /// because UIKit does not hold it yet.
    private var pending: UIViewController?

    private let notificationCenter: NotificationCenter
    private let topViewController: @MainActor () -> UIViewController?
    private let presentController: @MainActor (_ browser: UIViewController, _ presenter: UIViewController) -> Void
    private let dismissController: @MainActor (_ browser: UIViewController, _ animated: Bool) -> Void
    private let presentingController: @MainActor (_ controller: UIViewController) -> UIViewController?
    private let afterTransition: @MainActor (_ leaving: UIViewController, _ then: @escaping @MainActor @Sendable () -> Void) -> Void
    private let sceneOf: @MainActor (_ controller: UIViewController) -> AnyObject?

    /// How many transitions (or 50 ms ticks) a present waits for the previous
    /// browser to leave the screen before it gives up.
    private static let exitWaitLimit = 40

    init(
        notificationCenter: NotificationCenter = .default,
        topViewController: @escaping @MainActor () -> UIViewController? = { Scenes.topViewController() },
        presentController: @escaping @MainActor (UIViewController, UIViewController) -> Void = { $1.present($0, animated: true) },
        dismissController: @escaping @MainActor (UIViewController, Bool) -> Void = { $0.dismiss(animated: $1) },
        presentingController: @escaping @MainActor (UIViewController) -> UIViewController? = { $0.presentingViewController },
        afterTransition: @escaping @MainActor (UIViewController, @escaping @MainActor @Sendable () -> Void) -> Void
            = InAppBrowserManager.waitForTransition,
        sceneOf: @escaping @MainActor (UIViewController) -> AnyObject? = { $0.viewIfLoaded?.window?.windowScene }
    ) {
        self.notificationCenter = notificationCenter
        self.topViewController = topViewController
        self.presentController = presentController
        self.dismissController = dismissController
        self.presentingController = presentingController
        self.afterTransition = afterTransition
        self.sceneOf = sceneOf
        super.init()
    }

    // MARK: - Public API

    @discardableResult
    public func present(url: URL) -> Bool {
        present(url: url, from: nil, onClose: nil)
    }

    /// Presents `url` over `presenter`, or over the top-most view controller when nil.
    /// A controller that is being dismissed, or the browser going away, is skipped
    /// for the one that presents it. `onClose` runs once, when this browser goes
    /// away for any reason.
    ///
    /// `false`, and no `onClose`, when the URL is not http(s), nothing can present
    /// it (no presenter, one not in a window, being dismissed, or already presenting
    /// something else), or UIKit refuses it; in the first cases an open browser is
    /// left as it was. Also `false` when the replaced browser's `onClose` presents a
    /// browser of its own: that newer request wins and this one is dropped.
    ///
    /// When the previous browser is still leaving the screen (a present from its
    /// `onClose`, or right after "Done"), the new one is shown once it has gone.
    /// `true` then means it is on its way: `isPresented` is true and
    /// `presentedController` is the new browser meanwhile, and if it can no longer
    /// be shown its `onClose` gets `.dismissed`.
    @discardableResult
    public func present(
        url: URL,
        from presenter: UIViewController? = nil,
        onClose: (@MainActor (CloseReason) -> Void)?
    ) -> Bool {
        guard Self.isSupportedScheme(url) else { return false }
        let outgoing = presentedController
        guard let top = resolvePresenter(presenter ?? topViewController(), outgoing: outgoing) else { return false }

        session += 1
        let current = session
        let replaced = isPresented
        if replaced, let outgoing {
            dismissController(outgoing, false)
        }
        close(replaced ? .replaced : .dismissed)
        // The old browser's handler presented a browser of its own: it is the newer
        // request and now the managed one, so this one stands down.
        guard session == current else { return false }

        let vc = SFSafariViewController(url: url)
        vc.delegate = self
        vc.modalPresentationStyle = .overFullScreen

        presentedController = vc
        ownerScene = sceneOf(top)
        isOpen = true
        self.onClose = onClose
        startSceneObservers()

        // The browser closed before (Done, `dismiss()`, the auto-dismiss) is still on
        // screen over the presenter, animating away: UIKit would refuse a second
        // presentation, so wait until it has gone.
        if !replaced, let outgoing, presentingController(outgoing) === top {
            pending = vc
            waitForExit(of: outgoing, then: vc, over: top, session: current, attempts: Self.exitWaitLimit)
            return true
        }
        guard show(vc, over: top) else {
            abandon(vc)
            return false
        }
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

    // MARK: - Presenting

    /// The view controller to present over: `candidate`, or, while it is the
    /// browser going away or being dismissed, the one presenting it. Nil when that
    /// one cannot present: not in a window, being dismissed, or presenting
    /// something other than the browser going away.
    private func resolvePresenter(_ candidate: UIViewController?, outgoing: UIViewController?) -> UIViewController? {
        var top = candidate
        while let vc = top, vc === outgoing || vc.isBeingDismissed {
            top = presentingController(vc)
        }
        guard let top, top.viewIfLoaded?.window != nil, !top.isBeingDismissed else { return nil }
        if let shown = top.presentedViewController, shown !== outgoing { return nil }
        return top
    }

    /// Presents `vc` over `top`; false when UIKit refused it (it attaches a
    /// presentation it accepts at once).
    private func show(_ vc: UIViewController, over top: UIViewController) -> Bool {
        presentController(vc, top)
        return presentingController(vc) != nil
    }

    private func waitForExit(
        of outgoing: UIViewController,
        then vc: UIViewController,
        over top: UIViewController,
        session: Int,
        attempts: Int
    ) {
        afterTransition(outgoing) { [weak self, weak outgoing, weak top] in
            guard let self, self.session == session, self.pending === vc else { return }
            guard let top else {
                self.close(.dismissed)
                return
            }
            if let outgoing, attempts > 1, self.presentingController(outgoing) != nil {
                self.waitForExit(of: outgoing, then: vc, over: top, session: session, attempts: attempts - 1)
                return
            }
            self.pending = nil
            guard self.resolvePresenter(top, outgoing: outgoing) === top, self.show(vc, over: top) else {
                self.close(.dismissed)
                return
            }
        }
    }

    /// Calls `then` when `leaving`'s transition ends, or after a short tick when
    /// none is running.
    static func waitForTransition(_ leaving: UIViewController, _ then: @escaping @MainActor @Sendable () -> Void) {
        if let coordinator = leaving.transitionCoordinator ?? leaving.presentingViewController?.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                MainActor.assumeIsolated { then() }
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                then()
            }
        }
    }

    /// Forgets a browser UIKit refused, without running its handler.
    private func abandon(_ vc: UIViewController) {
        guard presentedController === vc else { return }
        presentedController = nil
        onClose = nil
        close(.dismissed)
    }

    // MARK: - Closing

    private func dismiss(reason: CloseReason) -> Bool {
        let wasPresented = isPresented
        if wasPresented, pending == nil, let vc = presentedController {
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
        pending = nil
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

    private func isOnScreen(_ vc: UIViewController) -> Bool {
        presentingController(vc) != nil && !vc.isBeingDismissed
    }

    // MARK: - Helpers

    /// SFSafariViewController only supports http/https — see Apple's docs.
    private static func isSupportedScheme(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}
