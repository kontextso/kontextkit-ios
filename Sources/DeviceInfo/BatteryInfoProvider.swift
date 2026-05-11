import Foundation
import UIKit

/// Provides battery and power information for ad targeting.
public enum BatteryInfoProvider {

    /// Battery information result.
    public struct BatteryInfo: Sendable {
        public let batteryLevel: Double?   // 0-100 percentage, nil if unavailable
        public let batteryState: String    // "charging", "full", "unplugged", "unknown"
        public let lowPowerMode: Bool
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly.
    @MainActor
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        var dict: [String: Any] = [
            "batteryState": info.batteryState,
            "lowPowerMode": info.lowPowerMode,
        ]
        if let batteryLevel = info.batteryLevel {
            dict["batteryLevel"] = batteryLevel
        }
        return dict
    }

    /// Collects battery information.
    ///
    /// Temporarily enables battery monitoring to read the values,
    /// then restores the previous monitoring state.
    @MainActor
    public static func collect() -> BatteryInfo {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasMonitoring }

        let rawLevel = device.batteryLevel
        let batteryLevel: Double? = rawLevel >= 0 ? Double(rawLevel) * 100 : nil

        let batteryState: String
        switch device.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        case .unknown: batteryState = "unknown"
        @unknown default: batteryState = "unknown"
        }

        return BatteryInfo(
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

}
