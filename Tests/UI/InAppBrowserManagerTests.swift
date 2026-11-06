import Foundation
import SafariServices
import Testing
import UIKit
@testable import KontextKit

@MainActor
struct InAppBrowserManagerTests {

    @Test func inAppBrowserManagerSingletonExists() {
        _ = InAppBrowserManager.shared
    }

    @Test func inAppBrowserDismissWhenNothingPresented() {
        let result = InAppBrowserManager.shared.dismiss()
        #expect(!result, "dismiss() should return false when no browser is presented")
    }

    // openFromURLString validation — present(url:) itself needs a key window
    // and a top view controller (absent in the test bundle), so these tests
    // assert the validation gate, not the actual present.

    @Test func inAppBrowserRejectsEmptyString() {
        let result = InAppBrowserManager.shared.openFromURLString("")
        if case .failure(let error) = result {
            #expect(error.domain == "IN_APP_BROWSER_ERROR")
            #expect(error.localizedDescription.contains("Invalid"))
        } else {
            Issue.record("Expected .failure for empty URL string")
        }
    }

    @Test func inAppBrowserRejectsNonHttpScheme() {
        let result = InAppBrowserManager.shared.openFromURLString("ftp://example.com")
        if case .failure(let error) = result {
            #expect(error.localizedDescription.contains("Invalid"))
        } else {
            Issue.record("Expected .failure for ftp:// URL")
        }
    }

    @Test func inAppBrowserRejectsJavascriptScheme() {
        let result = InAppBrowserManager.shared.openFromURLString("javascript:alert(1)")
        if case .failure(let error) = result {
            #expect(error.localizedDescription.contains("Invalid"))
        } else {
            Issue.record("Expected .failure for javascript: URL")
        }
    }

    @Test func inAppBrowserAcceptsHttpsThenFailsOnPresent() {
        // Validation passes; present fails because the test bundle has no key
        // window. Distinguishes "scheme rejected" from "present failed".
        let result = InAppBrowserManager.shared.openFromURLString("https://example.com")
        if case .failure(let error) = result {
            #expect(error.localizedDescription.contains("Failed to present"))
        } else {
            Issue.record("Expected present to fail without a key window")
        }
    }
}

/// The browser's life on a manager whose UIKit presentation is faked: a private
/// notification center, a stand-in presenter, and fakes that only record.
@MainActor
struct InAppBrowserManagerLifecycleTests {
    private let url = URL(string: "https://example.com")!

    /// A fake UIKit: `presented` is what UIKit holds, `onScreen` what it shows.
    /// The presenter sits in a real window, so the manager's presenter checks pass.
    @MainActor
    private final class Harness {
        let center = NotificationCenter()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let presenter = UIViewController()
        let presenterScene = NSObject()
        var presented: [UIViewController] = []
        var onScreen: Set<ObjectIdentifier> = []
        var dismissed: [(UIViewController, Bool)] = []
        var reasons: [InAppBrowserManager.CloseReason] = []
        /// A dismissal takes the browser off screen at once; false leaves it animating.
        var dismissCompletes = true
        /// The top-most view controller; the presenter when nil.
        var top: UIViewController?
        var transitions: [@MainActor @Sendable () -> Void] = []
        lazy var manager = InAppBrowserManager(
            notificationCenter: center,
            topViewController: { [unowned self] in top ?? presenter },
            presentController: { [unowned self] browser, _ in
                presented.append(browser)
                onScreen.insert(ObjectIdentifier(browser))
            },
            dismissController: { [unowned self] browser, animated in
                dismissed.append((browser, animated))
                if dismissCompletes { leave(browser) }
            },
            presentingController: { [unowned self] vc in isShown(vc) ? presenter : nil },
            afterTransition: { [unowned self] _, then in transitions.append(then) },
            sceneOf: { [unowned self] vc in vc === presenter ? presenterScene : nil }
        )

        init() {
            window.rootViewController = presenter
            window.isHidden = false
        }

        func present() -> Bool {
            manager.present(url: URL(string: "https://example.com")!) { [unowned self] in reasons.append($0) }
        }

        /// Safari calls its delegate, then dismisses itself; `leaves: false` stops
        /// before the dismissal has finished.
        func tapDone(leaves: Bool = true) {
            let browser = presented.last as! SFSafariViewController
            manager.safariViewControllerDidFinish(browser)
            if leaves { leave(browser) }
        }

        func isShown(_ vc: UIViewController) -> Bool {
            onScreen.contains(ObjectIdentifier(vc)) && presented.contains { $0 === vc }
        }

        func leave(_ vc: UIViewController) {
            onScreen.remove(ObjectIdentifier(vc))
        }

        func finishTransitions() {
            let pending = transitions
            transitions = []
            pending.forEach { $0() }
        }

        func post(_ name: Notification.Name, scene: AnyObject? = nil) {
            center.post(name: name, object: scene)
        }
    }

    @Test func doneFiresOnceWithDone() {
        let h = Harness()
        #expect(h.present())
        h.tapDone()
        h.tapDone()
        #expect(h.reasons == [.done])
        #expect(h.dismissed.isEmpty, "Safari dismisses itself on Done")
    }

    @Test func dismissFiresOnceWithDismissed() {
        let h = Harness()
        #expect(h.present())
        #expect(h.manager.dismiss())
        #expect(!h.manager.dismiss())
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.count == 1)
        #expect(h.dismissed.first?.0 === h.presented.first)
        #expect(h.dismissed.first?.1 == true)
    }

    @Test func dismissAfterDoneDoesNothing() {
        let h = Harness()
        #expect(h.present())
        h.tapDone()
        #expect(!h.manager.dismiss())
        #expect(h.reasons == [.done])
        #expect(h.dismissed.isEmpty)
    }

    @Test func newPresentReplacesAndFiresReplaced() {
        let h = Harness()
        var second: [InAppBrowserManager.CloseReason] = []
        #expect(h.present())
        #expect(h.manager.present(url: url, onClose: { second.append($0) }))
        #expect(h.reasons == [.replaced])
        #expect(second.isEmpty)
        #expect(h.dismissed.count == 1)
        #expect(h.dismissed.first?.0 === h.presented.first)
        #expect(h.dismissed.first?.1 == false)
        #expect(h.manager.presentedController === h.presented.last)
        #expect(h.manager.isPresented)
        h.tapDone()
        #expect(second == [.done])
        #expect(h.reasons == [.replaced])
    }

    @Test func returnAfterBackgroundFiresReturnedToApp() {
        let h = Harness()
        #expect(h.present())
        h.post(UIScene.willDeactivateNotification)
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.willEnterForegroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons == [.returnedToApp])
        #expect(!h.manager.isPresented)
        #expect(h.dismissed.count == 1)
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons == [.returnedToApp])
    }

    @Test func inactiveActiveBounceKeepsBrowserOpen() {
        let h = Harness()
        #expect(h.present())
        h.post(UIScene.willDeactivateNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons.isEmpty)
        #expect(h.manager.isPresented)
        #expect(h.dismissed.isEmpty)
    }

    @Test func backgroundBeforePresentDoesNotCount() {
        let h = Harness()
        #expect(h.present())
        h.tapDone()
        h.post(UIScene.didEnterBackgroundNotification)
        #expect(h.present())
        h.post(UIScene.didActivateNotification)
        #expect(h.manager.isPresented)
        #expect(h.reasons == [.done])
    }

    @Test func stateTracksThePresentedBrowser() {
        let h = Harness()
        #expect(!h.manager.isPresented)
        #expect(h.manager.presentedController == nil)
        #expect(h.present())
        #expect(h.manager.isPresented)
        #expect(h.manager.presentedController === h.presented.first)
        #expect(h.presented.first is SFSafariViewController)
        h.tapDone()
        #expect(!h.manager.isPresented)
        #expect(h.manager.presentedController === h.presented.first, "kept while UIKit still holds it")
        h.presented.removeAll()
        #expect(h.manager.presentedController == nil, "weak: gone once UIKit releases it")
    }

    @Test func browserReleasedWithoutNoticeReportsDismissedAtNextPresent() {
        let h = Harness()
        #expect(h.present())
        h.presented.removeAll()
        #expect(!h.manager.isPresented)
        #expect(h.present())
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.isEmpty)
    }

    @Test func presentWithoutCallbackStillWorks() {
        let h = Harness()
        #expect(h.manager.present(url: url))
        #expect(h.manager.isPresented)
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(!h.manager.isPresented)
        #expect(h.manager.present(url: url))
        #expect(h.manager.dismiss())
    }

    @Test func rejectedURLLeavesTheOpenBrowserAlone() {
        let h = Harness()
        #expect(h.present())
        #expect(!h.manager.present(url: URL(string: "ftp://example.com")!, onClose: { _ in }))
        #expect(h.manager.isPresented)
        #expect(h.reasons.isEmpty)
    }

    @Test func presentsOverTheGivenPresenter() {
        var presenters: [UIViewController] = []
        var held: [UIViewController] = []
        let manager = InAppBrowserManager(
            notificationCenter: NotificationCenter(),
            topViewController: { nil },
            presentController: { browser, presenter in presenters.append(presenter); held.append(browser) },
            dismissController: { _, _ in },
            presentingController: { vc in held.contains { $0 === vc } ? presenters.last : nil }
        )
        #expect(!manager.present(url: url, onClose: nil), "no top view controller")
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let own = UIViewController()
        window.rootViewController = own
        window.isHidden = false
        #expect(manager.present(url: url, from: own, onClose: nil))
        #expect(presenters.count == 1 && presenters.first === own)
        #expect(held.count == 1)
    }

    // MARK: - Re-entrant handlers

    @Test func replacedHandlerPresentingAgainWinsOverTheOuterPresent() {
        let h = Harness()
        var aReasons: [InAppBrowserManager.CloseReason] = []
        var bReasons: [InAppBrowserManager.CloseReason] = []
        var cReasons: [InAppBrowserManager.CloseReason] = []
        var cPresented = false
        #expect(h.manager.present(url: url, onClose: { reason in
            aReasons.append(reason)
            cPresented = h.manager.present(url: url, onClose: { cReasons.append($0) })
        }))
        let a = h.presented.first
        #expect(!h.manager.present(url: url, onClose: { bReasons.append($0) }), "superseded by the handler's present")
        #expect(cPresented)
        #expect(aReasons == [.replaced])
        #expect(h.presented.count == 2, "A and C; B never reaches UIKit")
        #expect(h.presented.first === a)
        let c = h.presented.last
        #expect(h.manager.presentedController === c)
        #expect(h.manager.isPresented)
        h.tapDone()
        #expect(cReasons == [.done])
        #expect(aReasons == [.replaced])
        #expect(bReasons.isEmpty)
        #expect(!h.manager.dismiss())
        #expect(cReasons == [.done])
    }

    @Test func handlerCallingDismissDoesNotStopTheNewBrowser() {
        let h = Harness()
        var aReasons: [InAppBrowserManager.CloseReason] = []
        var dismissedInHandler: Bool?
        #expect(h.manager.present(url: url, onClose: { reason in
            aReasons.append(reason)
            dismissedInHandler = h.manager.dismiss()
        }))
        #expect(h.present())
        #expect(aReasons == [.replaced])
        #expect(dismissedInHandler == false, "nothing is open while the old handler runs")
        #expect(h.manager.isPresented)
        #expect(h.manager.presentedController === h.presented.last)
        #expect(h.manager.dismiss())
        #expect(h.reasons == [.dismissed])
        #expect(aReasons == [.replaced])
    }

    @Test func handlerPresentingThenDismissingLeavesNothingOpen() {
        let h = Harness()
        var cReasons: [InAppBrowserManager.CloseReason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            _ = h.manager.present(url: url, onClose: { cReasons.append($0) })
            _ = h.manager.dismiss()
        }))
        #expect(!h.present())
        #expect(cReasons == [.dismissed])
        #expect(h.reasons.isEmpty, "the outer browser was never installed")
        #expect(!h.manager.isPresented)
    }

    // MARK: - Presenting while the previous browser leaves

    @Test func presentFromDoneHandlerWaitsForTheBrowserToLeave() {
        let h = Harness()
        var cReasons: [InAppBrowserManager.CloseReason] = []
        var cPresented = false
        #expect(h.manager.present(url: url, onClose: { _ in
            cPresented = h.manager.present(url: url, onClose: { cReasons.append($0) })
        }))
        let a = h.presented.first!
        h.top = a  // the closing browser is still the top-most controller
        h.tapDone(leaves: false)
        #expect(cPresented)
        #expect(h.presented.count == 1, "not presented over, or next to, the closing browser")
        #expect(h.manager.isPresented)
        #expect(h.manager.presentedController !== a)
        h.finishTransitions()
        #expect(h.presented.count == 1, "still leaving: waits for the next transition")
        #expect(h.transitions.count == 1)
        h.leave(a)
        h.top = nil
        h.finishTransitions()
        #expect(h.presented.count == 2)
        #expect(h.manager.presentedController === h.presented.last)
        #expect(h.manager.isPresented)
        #expect(h.manager.dismiss())
        #expect(cReasons == [.dismissed])
    }

    @Test func presentFromDismissHandlerWaitsForTheDismissalAnimation() {
        let h = Harness()
        h.dismissCompletes = false
        var cReasons: [InAppBrowserManager.CloseReason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            _ = h.manager.present(url: url, onClose: { cReasons.append($0) })
        }))
        let a = h.presented.first!
        #expect(h.manager.dismiss())
        #expect(h.presented.count == 1)
        #expect(h.manager.isPresented)
        #expect(h.manager.presentedController !== a)
        h.leave(a)
        h.finishTransitions()
        #expect(h.presented.count == 2)
        h.tapDone()
        #expect(cReasons == [.done])
    }

    @Test func dismissWhileWaitingCancelsTheWaitingBrowser() {
        let h = Harness()
        var cReasons: [InAppBrowserManager.CloseReason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            _ = h.manager.present(url: url, onClose: { cReasons.append($0) })
        }))
        let a = h.presented.first!
        h.tapDone(leaves: false)
        #expect(h.manager.dismiss())
        #expect(cReasons == [.dismissed])
        h.leave(a)
        h.finishTransitions()
        #expect(h.presented.count == 1, "never shown")
        #expect(h.dismissed.isEmpty, "nothing on screen to dismiss")
    }

    // MARK: - Presented state

    @Test func retainedBrowserDismissedWithoutNoticeIsNotPresented() {
        let h = Harness()
        #expect(h.present())
        let kept = h.manager.presentedController
        h.leave(kept!)  // the app dismissed its whole stack; the controller lives on
        #expect(h.manager.presentedController === kept)
        #expect(!h.manager.isPresented)
        #expect(h.present())
        #expect(h.reasons == [.dismissed], "not .replaced")
        #expect(h.dismissed.isEmpty)
    }

    @Test func dismissOfARetainedSilentlyDismissedBrowserReturnsFalse() {
        let h = Harness()
        #expect(h.present())
        let kept = h.manager.presentedController
        h.leave(kept!)
        #expect(!h.manager.dismiss())
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.isEmpty)
    }

    // MARK: - Scenes

    @Test func anotherScenesBackgroundDoesNotArmTheAutoDismiss() {
        let h = Harness()
        let other = NSObject()
        #expect(h.present())
        h.post(UIScene.didEnterBackgroundNotification, scene: other)
        h.post(UIScene.didActivateNotification, scene: h.presenterScene)
        #expect(h.manager.isPresented)
        #expect(h.reasons.isEmpty)
        h.post(UIScene.didEnterBackgroundNotification, scene: h.presenterScene)
        h.post(UIScene.didActivateNotification, scene: other)
        #expect(h.manager.isPresented, "another scene's activation is not the return")
        h.post(UIScene.didActivateNotification, scene: h.presenterScene)
        #expect(h.reasons == [.returnedToApp])
    }
}

/// The manager on real UIKit presentations in a test window. The test bundle has
/// no app, so UIKit attaches (or refuses) a presentation at once but never
/// finishes a transition: a presented controller stays on screen for the test.
@MainActor
struct InAppBrowserManagerUIKitTests {
    private let url = URL(string: "https://example.com")!

    @MainActor
    private final class Stage {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        var transitions: [@MainActor @Sendable () -> Void] = []
        lazy var manager = InAppBrowserManager(
            notificationCenter: NotificationCenter(),
            topViewController: { [unowned self] in Scenes.topViewController(base: root) },
            afterTransition: { [unowned self] _, then in transitions.append(then) }
        )

        init() {
            window.rootViewController = root
            window.isHidden = false
        }
    }

    @Test func presentsOverTheTopController() {
        let s = Stage()
        #expect(s.manager.present(url: url, onClose: nil))
        let browser = s.manager.presentedController
        #expect(browser is SFSafariViewController)
        #expect(browser?.presentingViewController === s.root)
        #expect(s.manager.isPresented)
    }

    @Test func detachedPresenterFailsAndLeavesTheOpenBrowserAlone() {
        let s = Stage()
        var reasons: [InAppBrowserManager.CloseReason] = []
        var rejected: [InAppBrowserManager.CloseReason] = []
        #expect(s.manager.present(url: url, onClose: { reasons.append($0) }))
        let open = s.manager.presentedController
        #expect(!s.manager.present(url: url, from: UIViewController(), onClose: { rejected.append($0) }))
        #expect(s.manager.presentedController === open)
        #expect(open?.presentingViewController === s.root)
        #expect(s.manager.isPresented)
        #expect(reasons.isEmpty)
        #expect(s.manager.dismiss())
        #expect(reasons == [.dismissed])
        #expect(rejected.isEmpty)
    }

    @Test func busyPresenterFailsAndLeavesTheOpenBrowserAlone() {
        let s = Stage()
        let other = Stage()
        let sheet = UIViewController()
        other.root.present(sheet, animated: false)
        #expect(sheet.presentingViewController === other.root)
        var reasons: [InAppBrowserManager.CloseReason] = []
        #expect(s.manager.present(url: url, onClose: { reasons.append($0) }))
        let open = s.manager.presentedController
        #expect(!s.manager.present(url: url, from: other.root, onClose: { _ in }), "already presenting something else")
        #expect(s.manager.presentedController === open)
        #expect(s.manager.isPresented)
        #expect(reasons.isEmpty)
        #expect(other.root.presentedViewController === sheet)
    }

    @Test func presentFromDoneHandlerSkipsTheClosingBrowser() {
        let s = Stage()
        var next: Bool?
        #expect(s.manager.present(url: url, onClose: { _ in
            next = s.manager.present(url: URL(string: "https://example.org")!, onClose: nil)
        }))
        let closing = s.manager.presentedController as! SFSafariViewController
        #expect(Scenes.topViewController(base: s.root) === closing)
        s.manager.safariViewControllerDidFinish(closing)
        #expect(next == true)
        #expect(closing.presentedViewController == nil, "not presented over the closing browser")
        #expect(s.root.presentedViewController === closing, "nor pushed at its busy presenter")
        #expect(s.manager.presentedController !== closing)
        #expect(s.manager.isPresented)
        #expect(s.transitions.count == 1, "waits for the closing browser to leave")
    }

    @Test func explicitPresenterThatIsTheClosingBrowserIsSkipped() {
        let s = Stage()
        var next: Bool?
        var closing: UIViewController?
        #expect(s.manager.present(url: url, onClose: { _ in
            next = s.manager.present(url: URL(string: "https://example.org")!, from: closing, onClose: nil)
        }))
        closing = s.manager.presentedController
        #expect(s.manager.dismiss())
        #expect(next == true)
        #expect(closing?.presentedViewController == nil)
        #expect(s.manager.presentedController !== closing)
        #expect(s.transitions.count == 1)
    }
}
