import Foundation
import Testing
@testable import KontextKit

struct ValueCoercionTests {

    @Test func valueCoercionStringFromString() {
        #expect(ValueCoercion.string("hello") == "hello")
    }

    @Test func valueCoercionStringFromEmptyStringReturnsNil() {
        #expect(ValueCoercion.string("") == nil)
    }

    @Test func valueCoercionStringFromNSNumber() {
        #expect(ValueCoercion.string(NSNumber(value: 42)) == "42")
    }

    @Test func valueCoercionStringFromNilReturnsNil() {
        #expect(ValueCoercion.string(nil) == nil)
    }

    @Test func valueCoercionStringFromWhitespaceReturnsNil() {
        // Whitespace-only strings are treated as empty — a SKAN field
        // like `itunesItem: "   "` is a server bug, not a valid value.
        #expect(ValueCoercion.string("   ") == nil)
        #expect(ValueCoercion.string("\t\n  ") == nil)
    }

    @Test func valueCoercionIntFromInt() {
        #expect(ValueCoercion.int(42) == 42)
    }

    @Test func valueCoercionIntFromString() {
        #expect(ValueCoercion.int("123") == 123)
    }

    @Test func valueCoercionIntFromInvalidStringReturnsNil() {
        #expect(ValueCoercion.int("abc") == nil)
    }

    @Test func valueCoercionIntFromNSNumber() {
        #expect(ValueCoercion.int(NSNumber(value: 99)) == 99)
    }

    @Test func valueCoercionIntFromNilReturnsNil() {
        #expect(ValueCoercion.int(nil) == nil)
    }

    @Test func valueCoercionIntFromExactDoubleReturnsValue() {
        // Integer-valued Doubles round-trip cleanly via Swift's
        // NSNumber-Int bridging (`as? Int` check).
        #expect(ValueCoercion.int(NSNumber(value: 42.0)) == 42)
        #expect(ValueCoercion.int(42.0 as Double) == 42)
    }

    @Test func valueCoercionIntRejectsFractionalNSNumber() {
        // Fractional values (e.g. server bug sending `campaign: 12.5`)
        // return nil rather than silently truncating to 12.
        #expect(ValueCoercion.int(NSNumber(value: 42.5)) == nil)
        #expect(ValueCoercion.int(0.1) == nil)
    }

    @Test func valueCoercionIntRejectsRoundedValueAboveIntMax() {
        #expect(ValueCoercion.int(Double(Int.max) as Double) == nil)
    }

    @Test func valueCoercionIntRejectsPaddedString() {
        // Strict `Int(_:)` parsing — no leading/trailing whitespace allowed.
        #expect(ValueCoercion.int(" 123") == nil)
        #expect(ValueCoercion.int("123 ") == nil)
    }

    @Test func valueCoercionIntRejectsDecimalString() {
        // "123.0" isn't a valid Int literal even though it represents
        // an exact integer — strict parsing.
        #expect(ValueCoercion.int("123.0") == nil)
        #expect(ValueCoercion.int("123.5") == nil)
    }
}
