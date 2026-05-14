import Testing
import CoreTelephony
@testable import KontextKit

struct NetworkInfoProviderTests {

    // MARK: - mapRadioAccess (pure function table)

    @Test func mapsLTE() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyLTE) == "lte")
    }

    @Test func mapsGPRS() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyGPRS) == "gprs")
    }

    @Test func mapsEdge() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyEdge) == "edge")
    }

    @Test func mapsWCDMAToThreeG() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyWCDMA) == "3g")
    }

    @Test func mapsHSPAVariantsToHspa() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyHSDPA) == "hspa")
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyHSUPA) == "hspa")
    }

    @Test func mapsCDMA1xToTwoG() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyCDMA1x) == "2g")
    }

    @Test func mapsCDMAEvDoVariantsToThreeG() {
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyCDMAEVDORev0) == "3g")
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyCDMAEVDORevA) == "3g")
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyCDMAEVDORevB) == "3g")
        #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyeHRPD) == "3g")
    }

    /// 5G constants only exist on iOS 14.1+. KontextKit's minimum is iOS 14,
    /// so the runtime check is genuine — guard the test body the same way.
    @Test func mapsFiveGVariants() {
        if #available(iOS 14.1, *) {
            #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyNR) == "5g")
            #expect(NetworkInfoProvider.mapRadioAccess(CTRadioAccessTechnologyNRNSA) == "5g")
        }
    }

    @Test func mapsUnknownConstantToNil() {
        #expect(NetworkInfoProvider.mapRadioAccess("CTRadioAccessTechnologyMystery") == nil)
    }

    // MARK: - collect / collectAsDict (smoke tests)

    @Test @MainActor func typeIsOneOfFourValidValues() async {
        let info = await NetworkInfoProvider.collect()
        #expect(["wifi", "cellular", "ethernet", "other"].contains(info.type))
    }

    /// On iOS 16+ Apple removed access to `CTCarrier.carrierName`, so
    /// `collect()` is documented to always return `nil` for this field.
    /// CI runs iOS 18, so the contract is exercised here.
    @Test @MainActor func carrierIsAlwaysNilOnIOS16Plus() async {
        let info = await NetworkInfoProvider.collect()
        #expect(info.carrier == nil)
    }

    @Test @MainActor func dictHasTypeKey() async {
        let dict = await NetworkInfoProvider.collectAsDict()
        #expect(dict["type"] != nil)
    }

    /// Bridge dict omits nil fields — carrier on iOS 16+ is always nil,
    /// so the key must not appear at all (otherwise RN/Flutter consumers
    /// would see `NSNull` and have to special-case it).
    @Test @MainActor func dictOmitsNilCarrier() async {
        let dict = await NetworkInfoProvider.collectAsDict()
        #expect(dict["carrier"] == nil)
    }

    // MARK: - detail gating

    /// `detail` describes the *active connection's* access technology.
    /// CoreTelephony reports the cellular radio's RAT even when Wi-Fi
    /// is the active path (the radio stays up on 5G/LTE for calls and
    /// fallback) — without gating, the SDK would ship `{type: "wifi",
    /// detail: "5g"}`, which misrepresents the data path to DSPs.
    ///
    /// Sim/CI runners report `type == "wifi"` or `"other"`, never
    /// `"cellular"`. So at least on those, `detail` MUST be nil. (A
    /// real cellular device exercises the positive branch via the
    /// `mapRadioAccess` table tests above plus the production code
    /// path.)
    @Test @MainActor func detailIsNilOnNonCellular() async {
        let info = await NetworkInfoProvider.collect()
        if info.type != "cellular" {
            #expect(info.detail == nil)
        }
    }

    @Test @MainActor func dictOmitsDetailOnNonCellular() async {
        let info = await NetworkInfoProvider.collect()
        let dict = await NetworkInfoProvider.collectAsDict()
        if info.type != "cellular" {
            // Bridge dict drops nil — sdk-react-native / sdk-flutter
            // consumers see "field absent", not NSNull.
            #expect(dict["detail"] == nil)
        }
    }
}
