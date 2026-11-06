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

    @MainActor
    private final class Harness {
        let center = NotificationCenter()
        let presenter = UIViewController()
        var presented: [UIViewController] = []
        var dismissed: [(UIViewController, Bool)] = []
        var reasons: [InAppBrowserManager.CloseReason] = []
        lazy var manager = InAppBrowserManager(
            notificationCenter: center,
            topViewController: { [unowned self] in presenter },
            presentController: { [unowned self] browser, _ in presented.append(browser) },
            dismissController: { [unowned self] browser, animated in dismissed.append((browser, animated)) }
        )

        func present() -> Bool {
            manager.present(url: URL(string: "https://example.com")!) { [unowned self] in reasons.append($0) }
        }

        func tapDone() {
            manager.safariViewControllerDidFinish(presented.last as! SFSafariViewController)
        }

        func post(_ name: Notification.Name) {
            center.post(name: name, object: nil)
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
            dismissController: { _, _ in }
        )
        #expect(!manager.present(url: url, onClose: nil), "no top view controller")
        let own = UIViewController()
        #expect(manager.present(url: url, from: own, onClose: nil))
        #expect(presenters.count == 1 && presenters.first === own)
        #expect(held.count == 1)
    }
}
