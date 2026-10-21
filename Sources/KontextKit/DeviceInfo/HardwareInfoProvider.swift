import UIKit

/// Provides hardware device information for ad targeting.
public enum HardwareInfoProvider {

    /// Hardware information result.
    public struct HardwareInfo: Sendable {
        public let brand: String   // Always "Apple" on iOS
        public let model: String   // Device model identifier (e.g. "iPhone14,2")
        public let type: String    // "handset", "tablet", or "other"
        /// Always `nil` on iOS. Apple's required-reason API rules for
        /// `NSPrivacyAccessedAPICategorySystemBootTime` (8FFB.1, 35F9.1)
        /// forbid sending boot time — or any value derived from it —
        /// off-device. Field is kept in the schema for cross-platform
        /// shape parity (Android still reports it).
        public let bootTime: Int64?
    }

    /// Collects hardware information.
    @MainActor
    public static func collect() -> HardwareInfo {
        let type: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: type = "handset"
        case .pad: type = "tablet"
        default: type = "other"   // .mac (Catalyst), .carPlay, .vision, .tv, .unspecified
        }

        return HardwareInfo(
            brand: "Apple",
            model: getDeviceModel(),
            type: type,
            bootTime: nil
        )
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly. `bootTime` is omitted on
    /// iOS — never sent off-device per Apple's required-reason rules.
    @MainActor
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        var dict: [String: Any] = [
            "brand": info.brand,
            "model": info.model,
            "type": info.type,
        ]
        if let bootTime = info.bootTime {
            dict["bootTime"] = bootTime
        }
        return dict
    }

    /// Returns the device model identifier (e.g. "iPhone14,2", "iPad7,1").
    /// Empty string only if `utsname.machine` is non-UTF-8 (never observed
    /// on real iOS hardware); empty is the same "missing" signal we use for
    /// `bundleId` so the server doesn't get a fake-looking placeholder.
    public static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? ""
            }
        }
    }
}
