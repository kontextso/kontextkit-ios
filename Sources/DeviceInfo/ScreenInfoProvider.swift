import UIKit

/// Provides screen information for ad targeting.
public enum ScreenInfoProvider {

    /// Screen information result.
    public struct ScreenInfo: Sendable {
        public let width: Int        // Physical pixels
        public let height: Int       // Physical pixels
        public let dpr: Double       // Device pixel ratio
        public let orientation: String  // "portrait" or "landscape"
        public let darkMode: Bool
        /// Brightness as a percentage (0–100). Native `UIScreen.main.brightness`
        /// is 0–1; we normalise here so consumers see the same scale as
        /// `audio.volume` and `power.batteryLevel`.
        public let brightness: Double
    }

    /// Collects screen information.
    @MainActor
    public static func collect() -> ScreenInfo {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return ScreenInfo(
            width: Int(bounds.width * scale),
            height: Int(bounds.height * scale),
            dpr: scale,
            // Derive orientation from the screen bounds rather than
            // `UIDevice.current.orientation`, which can be `.faceUp`,
            // `.faceDown`, or `.unknown` when the device is flat or
            // freshly launched — those cases would falsely report
            // "portrait" regardless of UI orientation. Mirrors the
            // Android implementation (widthPixels > heightPixels).
            orientation: bounds.width > bounds.height ? "landscape" : "portrait",
            darkMode: UITraitCollection.current.userInterfaceStyle == .dark,
            // Read via BrightnessManager so the 0–100 normalisation lives
            // in one place; otherwise this and BrightnessManager.get()
            // could drift on units (0–1 vs 0–100).
            brightness: BrightnessManager.get()
        )
    }

    /// Returns a dictionary representation suitable for JSON serialization.
    @MainActor
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        return [
            "width": info.width,
            "height": info.height,
            "dpr": info.dpr,
            "orientation": info.orientation,
            "darkMode": info.darkMode,
            "brightness": info.brightness,
        ]
    }
}
