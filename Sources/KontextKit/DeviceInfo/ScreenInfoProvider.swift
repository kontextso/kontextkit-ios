import UIKit

/// Provides screen information for ad targeting.
public enum ScreenInfoProvider {

    /// Screen information result. The facts as the system reports them; a
    /// consumer whose server wants `width * dpr` multiplies itself.
    public struct ScreenInfo: Sendable {
        /// Logical pixels (points), what UIKit lays out in: `UIScreen.main.bounds`.
        public let width: Int
        public let height: Int
        /// Device pixel ratio, `UIScreen.main.scale`. Note that `width * dpr`
        /// is the rendered size, not the panel: a Plus-size iPhone renders at
        /// 3x and downsamples to a panel whose `nativeScale` is lower.
        public let dpr: Double
        /// The panel's pixels, `UIScreen.main.nativeBounds`, in the same
        /// orientation as `width` and `height`.
        public let nativeWidth: Int
        public let nativeHeight: Int
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
        // `nativeBounds` is always portrait; follow the interface orientation of `bounds`.
        let native = UIScreen.main.nativeBounds
        let isLandscape = bounds.width > bounds.height
        return ScreenInfo(
            width: Int(bounds.width),
            height: Int(bounds.height),
            dpr: scale,
            nativeWidth: Int(isLandscape ? native.height : native.width),
            nativeHeight: Int(isLandscape ? native.width : native.height),
            // Derive orientation from the screen bounds rather than
            // `UIDevice.current.orientation`, which can be `.faceUp`,
            // `.faceDown`, or `.unknown` when the device is flat or
            // freshly launched — those cases would falsely report
            // "portrait" regardless of UI orientation. Mirrors the
            // Android implementation (widthPixels > heightPixels).
            orientation: isLandscape ? "landscape" : "portrait",
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
            "nativeWidth": info.nativeWidth,
            "nativeHeight": info.nativeHeight,
            "orientation": info.orientation,
            "darkMode": info.darkMode,
            "brightness": info.brightness,
        ]
    }
}
