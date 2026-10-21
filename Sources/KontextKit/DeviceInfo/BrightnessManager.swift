import Foundation
import UIKit

/// Owns the device's screen brightness — read and write.
///
/// Apple's `UIScreen.main.brightness` is the underlying API; we wrap it
/// here so every KontextKit consumer (sdk-swift, sdk-react-native,
/// sdk-flutter, sdk-kotlin) sees the same 0–100 scale (matches
/// `audio.volume` and `power.batteryLevel`).
///
/// `enum` chosen as a namespace for static-only methods — prevents
/// instantiation without the boilerplate `private init()`.
public enum BrightnessManager {

    /// Returns the current screen brightness as a percentage, 0–100.
    @MainActor
    public static func get() -> Double {
        Double(UIScreen.main.brightness) * 100
    }

    /// Sets the screen brightness. Value is clamped to 0...100.
    /// Returns the actual value applied (post-clamp).
    @MainActor
    public static func set(_ value: Double) -> Double {
        let clamped = max(0, min(100, value))
        UIScreen.main.brightness = CGFloat(clamped / 100)
        return clamped
    }

    // MARK: - ObjC-compatible bridge methods

    /// Returns brightness as `NSNumber` (0–100) for bridge layers (RN, Flutter).
    @MainActor
    public static func getAsNumber() -> NSNumber {
        NSNumber(value: get())
    }

    /// Sets brightness and returns the result as `NSNumber` for bridge layers.
    @MainActor
    public static func setAsNumber(_ value: Double) -> NSNumber {
        NSNumber(value: set(value))
    }
}
