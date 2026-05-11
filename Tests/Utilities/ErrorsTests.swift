import Foundation
import Testing
@testable import KontextKit

struct ErrorsTests {

    @Test func errorsMakeSetsDomainAndMessage() {
        let error = Errors.make(domain: "TEST_DOMAIN", message: "test message")
        #expect(error.domain == "TEST_DOMAIN")
        #expect(error.code == 1)
        #expect(error.localizedDescription == "test message")
    }

    @Test func errorsMakeOmitsDetailsByDefault() {
        let error = Errors.make(domain: "X", message: "y")
        #expect(error.userInfo["details"] == nil)
    }

    @Test func errorsMakeIncludesDetailsWhenProvided() {
        let error = Errors.make(domain: "X", message: "y", details: "underlying")
        #expect(error.userInfo["details"] as? String == "underlying")
    }
}
