import AVFoundation
import Foundation
import Testing
import UIKit
@testable import KontextKit

struct ProviderTests {

    // MARK: - HardwareInfoProvider

    @Test @MainActor func hardwareInfoReturnsBrand() {
        let info = HardwareInfoProvider.collect()
        #expect(info.brand == "Apple")
    }

    @Test @MainActor func hardwareInfoReturnsNonEmptyModel() {
        let info = HardwareInfoProvider.collect()
        #expect(!info.model.isEmpty)
    }

    /// The simulator is an iPhone or an iPad; the type follows the idiom.
    @Test @MainActor func hardwareInfoTypeFollowsTheIdiom() {
        let info = HardwareInfoProvider.collect()
        let expected: HardwareInfoProvider.HardwareType = UIDevice.current.userInterfaceIdiom == .pad ? .tablet : .phone
        #expect(info.type == expected)
        #expect(HardwareInfoProvider.collectAsDict()["type"] as? String == expected.rawValue)
    }

    /// `bootTime` must always be `nil` on iOS — Apple's required-reason API
    /// rules forbid sending boot time off-device under any of the three
    /// approved reasons (35F9.1, 8FFB.1, 3D61.1).
    @Test @MainActor func hardwareInfoBootTimeIsNilOnIOS() {
        let info = HardwareInfoProvider.collect()
        #expect(info.bootTime == nil)
    }

    @Test func hardwareInfoDeviceModelIsNotEmpty() {
        let model = HardwareInfoProvider.getDeviceModel()
        #expect(!model.isEmpty)
    }

    @Test @MainActor func hardwareInfoAsDictHasAllKeys() {
        let dict = HardwareInfoProvider.collectAsDict()
        #expect(dict["brand"] != nil)
        #expect(dict["model"] != nil)
        #expect(dict["type"] != nil)
        // bootTime intentionally omitted on iOS.
        #expect(dict["bootTime"] == nil)
    }

    // MARK: - AppInfoProvider

    @Test func appInfoReturnsBundleId() {
        let info = AppInfoProvider.collect()
        #expect(!info.bundleId.isEmpty)
    }

    @Test func appInfoReturnsVersion() {
        let info = AppInfoProvider.collect()
        #expect(!info.version.isEmpty)
    }

    /// `lastUpdateTime` must always be `nil` on iOS — Apple exposes no
    /// public API for app update time. The field exists for cross-platform
    /// shape parity with Android.
    @Test func appInfoLastUpdateTimeIsNilOnIOS() {
        let info = AppInfoProvider.collect()
        #expect(info.lastUpdateTime == nil)
    }

    /// `processStartMs` is captured at static init — should be a sensible
    /// epoch ms (post-2020) and not in the future at test time.
    @Test func appInfoProcessStartMsIsPlausible() {
        let year2020: Int64 = 1_577_836_800_000
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        #expect((year2020...now).contains(AppInfoProvider.processStartMs))
    }

    @Test func appInfoAsDictHasRequiredKeys() {
        let dict = AppInfoProvider.collectAsDict()
        #expect(dict["bundleId"] != nil)
        #expect(dict["version"] != nil)
        #expect(dict["processStartMs"] != nil)
        // lastUpdateTime intentionally omitted on iOS (always nil).
        #expect(dict["lastUpdateTime"] == nil)
    }

    // MARK: - AudioInfoProvider

    /// `isSoundOn` returns nil OR a boolean — never crashes on the
    /// session activation path. Simulator behavior varies; the contract
    /// is just "doesn't throw and returns Bool? sensibly".
    @Test func isSoundOnReturnsBoolOrNil() {
        let result = AudioInfoProvider.isSoundOn()
        // Either nil (session config failed) or a real bool — both OK.
        if let result {
            #expect(result == true || result == false)
        }
    }

    @Test func isSoundOnAsNumberMatchesIsSoundOn() {
        let asNumber = AudioInfoProvider.isSoundOnAsNumber()
        let asBool = AudioInfoProvider.isSoundOn()
        switch (asNumber, asBool) {
        case (nil, nil): break
        case (let n?, let b?):
            #expect(n.boolValue == b)
        default:
            Issue.record("isSoundOn / isSoundOnAsNumber returned mismatched optionality")
        }
    }

    @Test func collectingAudioLeavesTheAppsSessionAsItWas() throws {
        let session = AVAudioSession.sharedInstance()
        let original = (session.category, session.mode, session.categoryOptions)
        defer { try? session.setCategory(original.0, mode: original.1, options: original.2) }
        // The one-shot activation done first, so a parallel test cannot fire it in the middle of this one.
        AudioInfoProvider.ensureSessionActive()
        try session.setCategory(.ambient, mode: .moviePlayback, options: [.duckOthers])
        let set = (session.category, session.mode, session.categoryOptions)
        _ = AudioInfoProvider.collect()
        _ = AudioInfoProvider.collectAsDict()
        #expect(session.category == set.0 && session.mode == set.1 && session.categoryOptions == set.2, "the app's audio session is the app's")
    }

    @Test func audioInfoReturnsVolumeInRange() {
        let info = AudioInfoProvider.collect()
        #expect(info.volume >= 0 && info.volume <= 100)
    }

    @Test func audioInfoMutedConsistentWithVolume() {
        let info = AudioInfoProvider.collect()
        if info.muted {
            #expect(info.volume == 0)
        }
    }

    @Test func audioInfoAsDictHasAllKeys() {
        let dict = AudioInfoProvider.collectAsDict()
        #expect(dict["volume"] != nil)
        #expect(dict["muted"] != nil)
        #expect(dict["outputPluggedIn"] != nil)
        #expect(dict["outputType"] != nil)
    }

    /// `ensureSessionActive()` is the explicit opt-in: it activates once per process and reports the same
    /// result on every call after.
    @Test func ensureSessionActiveActivatesOnce() {
        let first = AudioInfoProvider.ensureSessionActive()
        #expect(AudioInfoProvider.ensureSessionActive() == first)
    }

    /// Two consecutive reads stay in range; neither one touches the session.
    @Test func consecutiveCollectsStayInRange() {
        let first = AudioInfoProvider.collect()
        let second = AudioInfoProvider.collect()
        #expect((0...100).contains(first.volume))
        #expect((0...100).contains(second.volume))
    }

    // MARK: - BatteryInfoProvider

    @Test @MainActor func batteryInfoReturnsBatteryState() {
        let info = BatteryInfoProvider.collect()
        let validStates = ["charging", "full", "unplugged", "unknown"]
        #expect(validStates.contains(info.batteryState))
    }

    @Test @MainActor func batteryInfoReturnsLowPowerMode() {
        // Just verify it doesn't crash — value depends on device state
        let info = BatteryInfoProvider.collect()
        _ = info.lowPowerMode
    }

    @Test @MainActor func batteryInfoAsDictHasRequiredKeys() {
        let dict = BatteryInfoProvider.collectAsDict()
        #expect(dict["batteryState"] != nil)
        #expect(dict["lowPowerMode"] != nil)
    }

    // MARK: - ScreenInfoProvider

    /// Points, the scale, and the panel: on a simulator the panel is `points * scale`
    /// (no Plus-size downsampling), and it follows the interface orientation.
    @Test @MainActor func screenInfoReturnsPointsScaleAndThePanel() {
        let info = ScreenInfoProvider.collect()
        let bounds = UIScreen.main.bounds
        #expect(info.width == Int(bounds.width))
        #expect(info.height == Int(bounds.height))
        #expect(info.dpr == Double(UIScreen.main.scale))
        #expect(info.nativeWidth == Int(bounds.width * UIScreen.main.nativeScale))
        #expect(info.nativeHeight == Int(bounds.height * UIScreen.main.nativeScale))
        #expect((info.width > info.height) == (info.nativeWidth > info.nativeHeight))
    }

    @Test @MainActor func screenInfoReturnsValidOrientation() {
        let info = ScreenInfoProvider.collect()
        #expect(info.orientation == "portrait" || info.orientation == "landscape")
    }

    @Test @MainActor func screenInfoAsDictHasAllKeys() {
        let dict = ScreenInfoProvider.collectAsDict()
        #expect(dict["width"] != nil)
        #expect(dict["height"] != nil)
        #expect(dict["dpr"] != nil)
        #expect(dict["nativeWidth"] != nil)
        #expect(dict["nativeHeight"] != nil)
        #expect(dict["orientation"] != nil)
        #expect(dict["darkMode"] != nil)
    }
}
