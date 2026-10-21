import Testing
import UIKit
@testable import KontextKit

@MainActor
struct OSInfoProviderTests {

    /// `ios` on an iPhone, `ipados` on an iPad: the simulator decides which.
    @Test func osInfoNameFollowsTheIdiom() {
        let info = OSInfoProvider.collect()
        let expected: OSInfoProvider.OSName = UIDevice.current.userInterfaceIdiom == .pad ? .ipados : .ios
        #expect(info.name == expected)
        #expect(OSInfoProvider.OSName.ipados.rawValue == "ipados")
    }

    @Test func osInfoVersionIsNonEmpty() {
        let info = OSInfoProvider.collect()
        #expect(!info.version.isEmpty)
    }

    @Test func osInfoTimezoneIsNonEmpty() {
        let info = OSInfoProvider.collect()
        #expect(!info.timezone.isEmpty)
    }

    /// Locale is BCP-47 (`-` separator), not POSIX (`_`). This is the
    /// load-bearing assertion — sdk-swift had a regression here years
    /// ago (PR #71) and the server's `osSchema.locale` shape requires
    /// BCP-47.
    @Test func osInfoLocaleIsBcp47NotPosix() {
        let info = OSInfoProvider.collect()
        #expect(!info.locale.contains("_"), "Locale should be BCP-47 (en-US), not POSIX (en_US): got \(info.locale)")
    }

    @Test func osInfoLocaleIsNonEmpty() {
        let info = OSInfoProvider.collect()
        #expect(!info.locale.isEmpty)
    }

    /// `bcp47Locale()` is exposed for direct access; same shape contract.
    @Test func bcp47LocaleNeverContainsUnderscore() {
        let locale = OSInfoProvider.bcp47Locale()
        #expect(!locale.contains("_"))
        #expect(!locale.isEmpty)
    }

    @Test func osInfoAsDictHasAllKeys() {
        let dict = OSInfoProvider.collectAsDict()
        #expect(["ios", "ipados"].contains(dict["name"] as? String))
        #expect(dict["version"] != nil)
        #expect(dict["locale"] != nil)
        #expect(dict["timezone"] != nil)
    }
}
