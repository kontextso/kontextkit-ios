import Foundation
import Testing
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
