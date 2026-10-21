// swiftlint:disable:next unused_import
import AVFoundation

/// Provides audio information for ad targeting and viewability.
public enum AudioInfoProvider {

    /// Audio information result.
    public struct AudioInfo: Sendable {
        public let volume: Int           // 0-100 percentage
        public let muted: Bool           // Volume below threshold
        public let outputPluggedIn: Bool // Any output connected
        public let outputType: [String]  // "wired", "hdmi", "bluetooth", "usb", "other"
    }

    /// Dictionary form of `collect()` for bridge layers (RN, Flutter)
    /// that want a `[String: Any]` directly.
    public static func collectAsDict() -> [String: Any] {
        let info = collect()
        return [
            "volume": info.volume,
            "muted": info.muted,
            "outputPluggedIn": info.outputPluggedIn,
            "outputType": info.outputType,
        ]
    }

    /// Collects audio information.
    ///
    /// `outputPluggedIn` only reflects **external** outputs (headphones,
    /// HDMI, Bluetooth, USB). The built-in speaker is always present in
    /// `currentRoute.outputs`, so reporting it would make the flag
    /// permanently `true` and useless. Mirrors the Android implementation,
    /// which explicitly ignores `TYPE_BUILTIN_SPEAKER`.
    ///
    /// `outputVolume` is documented as undefined unless the session is
    /// active, AND iOS only continuously refreshes the property when
    /// something is observing it via KVO (or audio is actively playing).
    /// `ensureSessionActive()` handles both: it activates the session and
    /// installs a permanent KVO observer that pins `outputVolume` live for
    /// the app's lifetime, so the value tracks user volume changes between
    /// `collect()` calls even when no video ad is on screen.
    public static func collect() -> AudioInfo {
        ensureSessionActive()
        let session = AVAudioSession.sharedInstance()
        let volume = session.outputVolume
        let outputs = session.currentRoute.outputs

        var outputTypes: [String] = []
        var hasExternalOutput = false
        for output in outputs {
            switch output.portType {
            case .headphones, .lineOut:
                if !outputTypes.contains("wired") { outputTypes.append("wired") }
                hasExternalOutput = true
            case .HDMI:
                if !outputTypes.contains("hdmi") { outputTypes.append("hdmi") }
                hasExternalOutput = true
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio, .airPlay:
                if !outputTypes.contains("bluetooth") { outputTypes.append("bluetooth") }
                hasExternalOutput = true
            case .usbAudio:
                if !outputTypes.contains("usb") { outputTypes.append("usb") }
                hasExternalOutput = true
            case .builtInSpeaker, .builtInReceiver:
                // Ignore — built-in outputs don't count as "plugged in".
                break
            default:
                if !outputTypes.contains("other") { outputTypes.append("other") }
                hasExternalOutput = true
            }
        }

        return AudioInfo(
            volume: Int((volume * 100).rounded()),
            muted: volume < 0.01,
            outputPluggedIn: hasExternalOutput,
            outputType: outputTypes
        )
    }

    /// One-time activation of the shared `AVAudioSession` with
    /// `.playback + .mixWithOthers`. Used by:
    ///
    /// - `isSoundOn()` — `outputVolume` is documented as undefined when
    ///   the session isn't active, so we need an active session to give
    ///   a reliable reading.
    /// - `collect()` — same reason, plus the KVO observer below keeps
    ///   the value live across preloads.
    /// - OMID video sessions — IAB OMID requires that the SDK observe
    ///   device-volume changes via KVO on `outputVolume`, which only
    ///   fires when the session is active with `.mixWithOthers`
    ///   (sdk-swift PR #119, KontextKit/OMSDK/OMManager).
    ///
    /// All call sites share this single activator. Returns `true` on
    /// success.
    ///
    /// **Why `.playback + .mixWithOthers`**: gentle on host audio, lets
    /// the user's music keep playing. **Why never deactivate**: calling
    /// `setActive(false, .notifyOthersOnDeactivation)` is what caused
    /// the 1-second audio stop fixed in sdk-flutter PR #51.
    ///
    /// `static let` initialiser gives us thread-safe one-shot semantics
    /// for free (Swift's dispatch_once-style lazy static init).
    @discardableResult
    public static func ensureSessionActive() -> Bool { didActivateSession }

    /// Strong reference to a permanent KVO observation on
    /// `outputVolume`. iOS only continuously refreshes the property
    /// when something is observing it (or audio is actively playing),
    /// so without this `collect()` would return the value cached at
    /// session-activation time and never track user volume changes
    /// between preloads. The closure body is intentionally empty —
    /// we don't care about the values, we just need the observation
    /// to exist. Held for the app's lifetime; matches the session
    /// itself never being deactivated.
    nonisolated(unsafe) private static var volumeObservation: NSKeyValueObservation?

    private static let didActivateSession: Bool = {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            volumeObservation = session.observe(\.outputVolume, options: [.new]) { _, _ in }
            return true
        } catch {
            return false
        }
    }()

    /// Returns `true` if the device output volume is above silence,
    /// `nil` if the session couldn't be activated to obtain a reliable
    /// reading.
    public static func isSoundOn() -> Bool? {
        guard ensureSessionActive() else { return nil }
        return AVAudioSession.sharedInstance().outputVolume > 0.0
    }

    /// Returns `isSoundOn` as `NSNumber?` for bridge layers (RN, Flutter).
    public static func isSoundOnAsNumber() -> NSNumber? {
        guard let result = isSoundOn() else { return nil }
        return NSNumber(value: result)
    }
}
