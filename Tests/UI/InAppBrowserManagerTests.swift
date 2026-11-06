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
    typealias Reason = InAppBrowserManager.CloseReason

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
        var reasons: [Reason] = []
        /// A dismissal ends at once; false holds it until `finishDismissals()`.
        var dismissCompletes = true
        var pendingDismissals: [@MainActor @Sendable () -> Void] = []
        var selfDismissals: [@MainActor @Sendable () -> Void] = []
        var deadlines: [(Double, @MainActor @Sendable () -> Void)] = []
        lazy var manager = InAppBrowserManager(
            notificationCenter: center,
            topViewController: { [unowned self] in presenter },
            presentController: { [unowned self] browser, _ in
                presented.append(browser)
                onScreen.insert(ObjectIdentifier(browser))
            },
            dismissController: { [unowned self] browser, animated, completion in
                dismissed.append((browser, animated))
                let end: @MainActor @Sendable () -> Void = { [unowned self] in
                    leave(browser)
                    completion()
                }
                if dismissCompletes { end() } else { pendingDismissals.append(end) }
            },
            presentingController: { [unowned self] vc in isShown(vc) ? presenter : nil },
            afterSelfDismissal: { [unowned self] _, then in selfDismissals.append(then) },
            after: { [unowned self] seconds, work in deadlines.append((seconds, work)) },
            sceneOf: { [unowned self] vc in vc === presenter ? presenterScene : nil }
        )

        init() {
            window.rootViewController = presenter
            window.isHidden = false
        }

        func present() -> Bool {
            manager.present(url: URL(string: "https://example.com")!) { [unowned self] in reasons.append($0) }
        }

        var browser: SFSafariViewController { presented.last as! SFSafariViewController }

        /// Safari calls its delegate, then dismisses itself; `leaves: false` stops
        /// before that dismissal has ended.
        func tapDone(leaves: Bool = true) {
            let browser = browser
            manager.safariViewControllerDidFinish(browser)
            if leaves { finishSelfDismissal(of: browser) }
        }

        func finishSelfDismissal(of browser: UIViewController) {
            leave(browser)
            let pending = selfDismissals
            selfDismissals = []
            pending.forEach { $0() }
        }

        func finishDismissals() {
            let pending = pendingDismissals
            pendingDismissals = []
            pending.forEach { $0() }
        }

        func fireDeadlines() {
            let pending = deadlines
            deadlines = []
            pending.forEach { $0.1() }
        }

        func isShown(_ vc: UIViewController) -> Bool {
            onScreen.contains(ObjectIdentifier(vc)) && presented.contains { $0 === vc }
        }

        func leave(_ vc: UIViewController) {
            onScreen.remove(ObjectIdentifier(vc))
        }

        func post(_ name: Notification.Name, scene: AnyObject? = nil) {
            center.post(name: name, object: scene)
        }
    }

    // MARK: - onClose runs once the browser is off screen

    @Test func doneRunsTheHandlerOnceSafariHasGone() {
        let h = Harness()
        #expect(h.present())
        let a = h.browser
        h.tapDone(leaves: false)
        #expect(h.reasons.isEmpty, "Safari is still leaving")
        #expect(!h.manager.isPresented)
        #expect(h.manager.presentedController === a, "still recognisable while it leaves")
        h.finishSelfDismissal(of: a)
        #expect(h.reasons == [.done])
        #expect(h.dismissed.isEmpty, "Safari dismisses itself on Done")
    }

    @Test func dismissRunsTheHandlerWhenTheDismissalEnds() {
        let h = Harness()
        h.dismissCompletes = false
        #expect(h.present())
        #expect(h.manager.dismiss())
        #expect(h.reasons.isEmpty)
        #expect(!h.manager.isPresented)
        h.finishDismissals()
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.count == 1 && h.dismissed.first?.1 == true)
    }

    @Test func returnAfterBackgroundRunsReturnedToAppWhenTheDismissalEnds() {
        let h = Harness()
        h.dismissCompletes = false
        #expect(h.present())
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons.isEmpty)
        #expect(!h.manager.isPresented)
        h.finishDismissals()
        #expect(h.reasons == [.returnedToApp])
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons == [.returnedToApp])
    }

    @Test func presentFromTheDoneHandlerJustWorks() {
        let h = Harness()
        var next: Bool?
        var nextReasons: [Reason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            next = h.manager.present(url: url, onClose: { nextReasons.append($0) })
        }))
        h.tapDone()
        #expect(next == true)
        #expect(h.presented.count == 2)
        #expect(h.manager.isPresented)
        #expect(h.manager.dismiss())
        #expect(nextReasons == [.dismissed])
    }

    // MARK: - The deadline

    @Test func deadlineRunsTheHandlerOnceWhenUIKitNeverReports() {
        let h = Harness()
        h.dismissCompletes = false
        #expect(h.present())
        #expect(h.manager.dismiss())
        #expect(h.deadlines.map(\.0) == [InAppBrowserManager.closeDeadline])
        h.fireDeadlines()
        #expect(h.reasons == [.dismissed])
        h.finishDismissals()
        #expect(h.reasons == [.dismissed], "a late completion does nothing")
    }

    @Test func deadlineAfterTheDismissalEndedDoesNothing() {
        let h = Harness()
        #expect(h.present())
        h.tapDone()
        #expect(h.reasons == [.done])
        h.fireDeadlines()
        #expect(h.reasons == [.done])
    }

    @Test func doneDeadlineKeepsTheReason() {
        let h = Harness()
        #expect(h.present())
        let a = h.browser
        h.tapDone(leaves: false)
        h.fireDeadlines()
        #expect(h.reasons == [.done])
        h.finishSelfDismissal(of: a)
        #expect(h.reasons == [.done])
    }

    @Test func noHandlerNoDeadline() {
        let h = Harness()
        #expect(h.manager.present(url: url))
        #expect(h.manager.dismiss())
        #expect(h.deadlines.isEmpty)
    }

    // MARK: - Unsupported cases: false or nothing, never a crash

    @Test func unsupportedCasesReturnFalseOrDoNothing() {
        let h = Harness()
        // dismiss() with nothing open, twice.
        #expect(!h.manager.dismiss())
        #expect(!h.manager.dismiss())

        // A detached presenter; a present while a browser is open.
        #expect(!h.manager.present(url: url, from: UIViewController(), onClose: { _ in }))
        #expect(h.present())
        #expect(!h.manager.present(url: url, from: UIViewController(), onClose: { _ in }))
        #expect(!h.manager.present(url: url, onClose: { _ in }))
        #expect(!h.manager.present(url: url))
        #expect(h.presented.count == 1)
        #expect(h.manager.isPresented)
        #expect(h.reasons.isEmpty)
        #expect(h.dismissed.isEmpty)

        // dismiss() twice: the second does nothing.
        #expect(h.manager.dismiss())
        #expect(!h.manager.dismiss())
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.count == 1)

        // dismiss() after Done does nothing.
        #expect(h.present())
        let b = h.browser
        h.tapDone(leaves: false)
        #expect(!h.manager.dismiss())
        h.tapDone(leaves: false)

        // A present while the closed browser is still leaving.
        #expect(!h.manager.present(url: url, onClose: { _ in }))
        #expect(h.presented.count == 2)
        h.finishSelfDismissal(of: b)
        #expect(h.reasons == [.dismissed, .done])
        #expect(h.dismissed.count == 1, "UIKit is never asked to dismiss a browser that is gone")

        // A handler that calls present and dismiss.
        var inner: [Reason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            _ = h.manager.present(url: self.url, onClose: { inner.append($0) })
            _ = h.manager.dismiss()
            _ = h.manager.dismiss()
        }))
        h.tapDone()
        #expect(inner == [.dismissed])
        #expect(!h.manager.isPresented)
        h.fireDeadlines()
        #expect(inner == [.dismissed])
        #expect(h.reasons == [.dismissed, .done])
    }

    @Test func goneBrowsersHandlerPresentingItsOwnWins() {
        let h = Harness()
        var own: [Reason] = []
        #expect(h.manager.present(url: url, onClose: { _ in
            _ = h.manager.present(url: self.url, onClose: { own.append($0) })
        }))
        h.leave(h.browser)  // the app dismissed its stack without telling
        #expect(!h.manager.present(url: url, onClose: { _ in Issue.record("never installed") }))
        #expect(h.presented.count == 2, "the first browser and the handler's")
        #expect(h.manager.presentedController === h.presented.last)
        #expect(h.manager.dismiss())
        #expect(own == [.dismissed])
    }

    // MARK: - State and the auto-dismiss

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

    @Test func retainedBrowserDismissedWithoutNoticeIsNotPresented() {
        let h = Harness()
        #expect(h.present())
        let kept = h.manager.presentedController
        h.leave(kept!)  // the app dismissed its whole stack; the controller lives on
        #expect(h.manager.presentedController === kept)
        #expect(!h.manager.isPresented)
        #expect(!h.manager.dismiss())
        #expect(h.reasons == [.dismissed])
        #expect(h.dismissed.isEmpty)
    }

    @Test func inactiveActiveBounceKeepsTheBrowserOpen() {
        let h = Harness()
        #expect(h.present())
        h.post(UIScene.willDeactivateNotification)
        h.post(UIScene.didActivateNotification)
        #expect(h.reasons.isEmpty)
        #expect(h.manager.isPresented)
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

    @Test func anotherScenesBackgroundDoesNotArmTheAutoDismiss() {
        let h = Harness()
        let other = NSObject()
        #expect(h.present())
        h.post(UIScene.didEnterBackgroundNotification, scene: other)
        h.post(UIScene.didActivateNotification, scene: h.presenterScene)
        #expect(h.manager.isPresented)
        h.post(UIScene.didEnterBackgroundNotification, scene: h.presenterScene)
        h.post(UIScene.didActivateNotification, scene: other)
        #expect(h.manager.isPresented, "another scene's activation is not the return")
        h.post(UIScene.didActivateNotification, scene: h.presenterScene)
        #expect(h.reasons == [.returnedToApp])
    }

    // MARK: - The old API

    @Test func presentWithoutHandlerStillWorks() {
        let h = Harness()
        #expect(h.manager.present(url: url))
        #expect(h.manager.isPresented)
        #expect(!h.manager.present(url: url), "one browser at a time")
        #expect(h.presented.count == 1)
        h.post(UIScene.didEnterBackgroundNotification)
        h.post(UIScene.didActivateNotification)
        #expect(!h.manager.isPresented)
        #expect(h.manager.present(url: url))
        #expect(h.manager.dismiss())
        #expect(!h.manager.present(url: URL(string: "ftp://example.com")!))
    }

    @Test func rejectedURLLeavesTheOpenBrowserAlone() {
        let h = Harness()
        #expect(h.present())
        #expect(!h.manager.present(url: URL(string: "ftp://example.com")!, onClose: { _ in }))
        #expect(h.manager.isPresented)
        #expect(h.reasons.isEmpty)
    }
}

/// The manager on real UIKit presentations in a test window, with UIKit's own
/// present and dismiss.
@MainActor
struct InAppBrowserManagerUIKitTests {
    private let url = URL(string: "https://example.com")!

    @MainActor
    private final class Stage {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        lazy var manager = InAppBrowserManager(
            notificationCenter: NotificationCenter(),
            topViewController: { [unowned self] in Scenes.topViewController(base: root) }
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

    @Test func presentsOverTheGivenPresenter() {
        let s = Stage()
        let other = Stage()
        #expect(s.manager.present(url: url, from: other.root, onClose: nil))
        #expect(s.manager.presentedController?.presentingViewController === other.root)
        #expect(s.root.presentedViewController == nil)
    }

    @Test func detachedPresenterFailsAndLeavesTheOpenBrowserAlone() {
        let s = Stage()
        var reasons: [InAppBrowserManager.CloseReason] = []
        #expect(!s.manager.present(url: url, from: UIViewController(), onClose: { _ in }))
        #expect(s.manager.present(url: url, onClose: { reasons.append($0) }))
        let open = s.manager.presentedController
        #expect(!s.manager.present(url: url, from: UIViewController(), onClose: { _ in }))
        #expect(s.manager.presentedController === open)
        #expect(open?.presentingViewController === s.root)
        #expect(s.manager.isPresented)
        #expect(reasons.isEmpty)
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

    @Test func presentWhileABrowserIsOpenFailsAndLeavesItAlone() {
        let s = Stage()
        var reasons: [InAppBrowserManager.CloseReason] = []
        #expect(s.manager.present(url: url, onClose: { reasons.append($0) }))
        let open = s.manager.presentedController
        #expect(!s.manager.present(url: URL(string: "https://example.org")!, onClose: { _ in }))
        #expect(!s.manager.present(url: url, from: s.root, onClose: { _ in }))
        #expect(s.manager.presentedController === open)
        #expect(s.root.presentedViewController === open)
        #expect(reasons.isEmpty)
    }
}
