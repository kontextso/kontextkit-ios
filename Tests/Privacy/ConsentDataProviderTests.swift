import Foundation
import Testing
@testable import KontextKit

/// Each test gets a fresh `UserDefaults` suite via the struct's `init`.
/// Swift Testing constructs a new struct instance per test, so the
/// `defaults` property is naturally test-isolated. There's no `deinit`
/// on structs; the suite lives for the test process lifetime, but
/// each test uses a unique UUID-suffixed name so they can't collide.
struct TCFDataProviderTests {

    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        self.suiteName = "TCFDataProviderTests-\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Empty defaults

    @Test func returnsNilFieldsWhenDefaultsEmpty() {
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdprConsent == nil)
        #expect(tcf.gdpr == nil)
    }

    // MARK: - tcString

    @Test func readsTcStringWhenPresent() {
        defaults.set("CO9-VxxO9-VxxAQAAA==", forKey: "IABTCF_TCString")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdprConsent == "CO9-VxxO9-VxxAQAAA==")
    }

    @Test func rejectsEmptyTcString() {
        // CMP wrote an empty string — invalid per IAB spec, treat as absent.
        defaults.set("", forKey: "IABTCF_TCString")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdprConsent == nil)
    }

    @Test func rejectsWhitespaceOnlyTcString() {
        // Whitespace-only is also invalid — same defensive normalization.
        defaults.set("   ", forKey: "IABTCF_TCString")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdprConsent == nil)
    }

    // MARK: - gdprApplies — multiple wire shapes

    /// Stored as `NSNumber` (CMP wrote `1` directly).
    @Test func gdprAppliesAsNSNumberOne() {
        defaults.set(NSNumber(value: 1), forKey: "IABTCF_gdprApplies")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdpr == 1)
    }

    @Test func gdprAppliesAsNSNumberZero() {
        defaults.set(NSNumber(value: 0), forKey: "IABTCF_gdprApplies")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdpr == 0)
    }

    /// Stored as `Bool` — coerced to 1/0.
    @Test func gdprAppliesAsBoolTrue() {
        defaults.set(true, forKey: "IABTCF_gdprApplies")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        // UserDefaults stores Bool as NSNumber under the hood, so this
        // hits the NSNumber branch — still 1.
        #expect(tcf.gdpr == 1)
    }

    /// Stored as `String` (some misbehaving CMPs write strings).
    @Test func gdprAppliesAsString() {
        defaults.set("1", forKey: "IABTCF_gdprApplies")
        let tcf = TCFDataProvider.getTCFData(from: defaults)
        #expect(tcf.gdpr == 1)
    }

    /// Per IAB TCF v2.2 spec, gdprApplies must be 0 or 1.
    /// Anything else (e.g. a buggy CMP writes 5) decays to nil.
    @Test func gdprAppliesRejectsOutOfRangeInts() {
        defaults.set(5, forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)

        defaults.set(-1, forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)

        defaults.set(2, forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)
    }

    @Test func gdprAppliesRejectsFractionalNumbers() {
        defaults.set(NSNumber(value: 1.5), forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)

        defaults.set(NSNumber(value: 0.9), forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)
    }

    @Test func gdprAppliesRejectsOutOfRangeStrings() {
        defaults.set("5", forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)

        defaults.set("abc", forKey: "IABTCF_gdprApplies")
        #expect(TCFDataProvider.getTCFData(from: defaults).gdpr == nil)
    }

    // MARK: - Bridge dict

    @Test func asDictReturnsNSNullForMissingFields() {
        let dict = TCFDataProvider.getTCFDataAsDict(from: defaults)
        #expect(dict["gdprConsent"] is NSNull)
        #expect(dict["gdpr"] is NSNull)
    }

    @Test func asDictReturnsValuesWhenPresent() {
        defaults.set("CO9-test", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let dict = TCFDataProvider.getTCFDataAsDict(from: defaults)
        #expect(dict["gdprConsent"] as? String == "CO9-test")
        #expect(dict["gdpr"] as? Int == 1)
    }
}
