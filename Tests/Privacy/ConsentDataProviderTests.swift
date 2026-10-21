import Foundation
import Testing
@testable import KontextKit

/// Each test gets a fresh `UserDefaults` suite via the struct's `init`.
/// Swift Testing constructs a new struct instance per test, so the
/// `defaults` property is naturally test-isolated. There's no `deinit`
/// on structs; the suite lives for the test process lifetime, but
/// each test uses a unique UUID-suffixed name so they can't collide.
struct ConsentDataProviderTests {

    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        self.suiteName = "ConsentDataProviderTests-\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    // MARK: - Empty defaults

    @Test func returnsNilFieldsWhenDefaultsEmpty() {
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent == ConsentDataProvider.ConsentData(gdpr: nil, gdprConsent: nil, gpp: nil, gppSid: nil, usPrivacy: nil))
    }

    // MARK: - tcString

    @Test func readsTcStringWhenPresent() {
        defaults.set("CO9-VxxO9-VxxAQAAA==", forKey: "IABTCF_TCString")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdprConsent == "CO9-VxxO9-VxxAQAAA==")
    }

    @Test func rejectsEmptyTcString() {
        // CMP wrote an empty string — invalid per IAB spec, treat as absent.
        defaults.set("", forKey: "IABTCF_TCString")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdprConsent == nil)
    }

    @Test func rejectsWhitespaceOnlyTcString() {
        // Whitespace-only is also invalid — same defensive normalization.
        defaults.set("   ", forKey: "IABTCF_TCString")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdprConsent == nil)
    }

    // MARK: - gdprApplies — multiple wire shapes

    /// Stored as `NSNumber` (CMP wrote `1` directly).
    @Test func gdprAppliesAsNSNumberOne() {
        defaults.set(NSNumber(value: 1), forKey: "IABTCF_gdprApplies")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdpr == 1)
    }

    @Test func gdprAppliesAsNSNumberZero() {
        defaults.set(NSNumber(value: 0), forKey: "IABTCF_gdprApplies")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdpr == 0)
    }

    /// Stored as `Bool` — coerced to 1/0.
    @Test func gdprAppliesAsBoolTrue() {
        defaults.set(true, forKey: "IABTCF_gdprApplies")
        let consent = ConsentDataProvider.collect(from: defaults)
        // UserDefaults stores Bool as NSNumber under the hood, so this
        // hits the NSNumber branch — still 1.
        #expect(consent.gdpr == 1)
    }

    /// Stored as `String` (some misbehaving CMPs write strings).
    @Test func gdprAppliesAsString() {
        defaults.set("1", forKey: "IABTCF_gdprApplies")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gdpr == 1)
    }

    /// Per IAB TCF v2.2 spec, gdprApplies must be 0 or 1.
    /// Anything else (e.g. a buggy CMP writes 5) decays to nil.
    @Test func gdprAppliesRejectsOutOfRangeInts() {
        defaults.set(5, forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)

        defaults.set(-1, forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)

        defaults.set(2, forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)
    }

    @Test func gdprAppliesRejectsFractionalNumbers() {
        defaults.set(NSNumber(value: 1.5), forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)

        defaults.set(NSNumber(value: 0.9), forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)
    }

    @Test func gdprAppliesRejectsOutOfRangeStrings() {
        defaults.set("5", forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)

        defaults.set("abc", forKey: "IABTCF_gdprApplies")
        #expect(ConsentDataProvider.collect(from: defaults).gdpr == nil)
    }

    // MARK: - GPP and US Privacy

    @Test func readsGppStringAndSections() {
        defaults.set("DBABMA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA", forKey: "IABGPP_HDR_GppString")
        defaults.set("2_7", forKey: "IABGPP_GppSID")
        let consent = ConsentDataProvider.collect(from: defaults)
        #expect(consent.gpp == "DBABMA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA")
        #expect(consent.gppSid == [2, 7])
    }

    /// The GPP in-app spec writes `2_7`; some CMPs write `2,7`, or a single section as a number.
    @Test func gppSectionsAcceptCommaAndNumber() {
        defaults.set("2,7", forKey: "IABGPP_GppSID")
        #expect(ConsentDataProvider.collect(from: defaults).gppSid == [2, 7])

        defaults.set(7, forKey: "IABGPP_GppSID")
        #expect(ConsentDataProvider.collect(from: defaults).gppSid == [7])

        defaults.set("", forKey: "IABGPP_GppSID")
        #expect(ConsentDataProvider.collect(from: defaults).gppSid == nil)

        defaults.set("a_b", forKey: "IABGPP_GppSID")
        #expect(ConsentDataProvider.collect(from: defaults).gppSid == nil)
    }

    @Test func readsUsPrivacyString() {
        defaults.set("1YNN", forKey: "IABUSPrivacy_String")
        #expect(ConsentDataProvider.collect(from: defaults).usPrivacy == "1YNN")

        defaults.set(" ", forKey: "IABUSPrivacy_String")
        #expect(ConsentDataProvider.collect(from: defaults).usPrivacy == nil)
    }

    // MARK: - Bridge dict

    @Test func asDictReturnsNSNullForMissingFields() {
        let dict = ConsentDataProvider.collectAsDict(from: defaults)
        #expect(dict["gdprConsent"] is NSNull)
        #expect(dict["gdpr"] is NSNull)
        #expect(dict["gpp"] is NSNull)
        #expect(dict["gppSid"] is NSNull)
        #expect(dict["usPrivacy"] is NSNull)
    }

    @Test func asDictReturnsValuesWhenPresent() {
        defaults.set("CO9-test", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        defaults.set("2_7", forKey: "IABGPP_GppSID")
        let dict = ConsentDataProvider.collectAsDict(from: defaults)
        #expect(dict["gdprConsent"] as? String == "CO9-test")
        #expect(dict["gdpr"] as? Int == 1)
        #expect(dict["gppSid"] as? [Int] == [2, 7])
    }
}
