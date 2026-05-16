import AVFAudio
import Foundation
@preconcurrency import OMSDK_Kontextso
import WebKit

/// Public manager-protocol for OMID session creation. Exposed so consumer
/// SDKs can inject mocks in tests without instantiating the binary OMID
/// SDK.
public protocol OMManaging: Sendable {
    @discardableResult
    func activate() -> Bool

    func createSession(_ webView: WKWebView, url: URL?, creativeType: OMCreativeType) async throws -> OMSession
}

/// Manages the OMID native-SDK lifecycle and creates per-WebView OM
/// sessions. Shared across all Kontext iOS SDKs (sdk-swift,
/// sdk-react-native iOS, sdk-flutter iOS); each SDK passes its own
/// `OMPartner` identity at construction.
public final class OMManager: OMManaging {
    public enum OMError: Error {
        case sdkIsNotActive
        case partnerIsNotAvailable
        /// Underlying OMID/`WebKit` error — exposed as `Error` so callers
        /// can inspect type/domain rather than just a stringified message.
        case sessionCreationFailed(Error)
    }

    private let partner: OMIDKontextsoPartner?

    public init(partner: OMPartner) {
        self.partner = OMIDKontextsoPartner(name: partner.name, versionString: partner.version)
    }

    /// Activates the OMID native SDK. Idempotent — subsequent calls return
    /// the already-active state.
    ///
    /// `OMIDKontextsoSDK.shared.activate()` is documented as synchronous
    /// in the IAB OMID iOS spec, which is why the immediate post-call
    /// `isActive` read is reliable.
    @discardableResult
    public func activate() -> Bool {
        if isActive {
            return true
        }
        OMIDKontextsoSDK.shared.activate()
        return isActive
    }

    /// Creates an OMID context, configuration, waits 50 ms for geometry
    /// stabilization (matching sdk-kotlin / sdk-react-native), and starts
    /// the session on the main actor.
    ///
    /// For `creativeType == .video`, calls `setCategory(.playback,
    /// .mixWithOthers) + setActive(true)` on the shared `AVAudioSession`
    /// per-session, immediately before the OMID session is created — the
    /// exact pattern from the IAB OMSDK demo (WebViewVideoController.swift)
    /// and the sdk-swift v3 certification (PR #119). OMID's internal
    /// device-volume KVO observer relies on the session being freshly
    /// active at session-start time; a one-shot lazy activation that
    /// happens earlier in the app lifecycle (e.g. during the first
    /// `/preload`'s `getDevice()`) is not equivalent — iOS stops
    /// publishing `outputVolume` changes once an interposing audio
    /// source (the WKWebView's media element) takes over, even with
    /// `.mixWithOthers`. Errors are swallowed so a failed activation
    /// never blocks OMID session creation; the worst case is missing
    /// `deviceVolume` change events.
    ///
    /// Intentionally does NOT call `setActive(false)` when the session
    /// finishes — that path was the root of the 1-second audio-cut bug
    /// fixed in sdk-flutter PR #51, and the active session is gentle on
    /// host audio thanks to `.mixWithOthers`.
    ///
    /// Honours cancellation: if the caller cancels during the 50 ms
    /// settle window, this throws `CancellationError` rather than going
    /// on to allocate an OMID session that would immediately leak.
    public func createSession(
        _ webView: WKWebView,
        url: URL?,
        creativeType: OMCreativeType
    ) async throws -> OMSession {
        if creativeType == .video {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        guard isActive else {
            throw OMError.sdkIsNotActive
        }
        guard let partner else {
            throw OMError.partnerIsNotAvailable
        }

        do {
            let context = try OMIDKontextsoAdSessionContext(
                partner: partner,
                webView: webView,
                contentUrl: url?.absoluteString,
                customReferenceIdentifier: nil
            )

            let omCreativeType: OMIDCreativeType
            let impressionOwner: OMIDOwner
            let mediaEventsOwner: OMIDOwner
            switch creativeType {
            case .display:
                omCreativeType = .htmlDisplay
                impressionOwner = .javaScriptOwner
                mediaEventsOwner = .noneOwner
            case .video:
                omCreativeType = .video
                impressionOwner = .javaScriptOwner
                mediaEventsOwner = .javaScriptOwner
            }

            let configuration = try OMIDKontextsoAdSessionConfiguration(
                creativeType: omCreativeType,
                impressionType: .beginToRender,
                impressionOwner: impressionOwner,
                mediaEventsOwner: mediaEventsOwner,
                isolateVerificationScripts: false
            )

            let session = try OMIDKontextsoAdSession(
                configuration: configuration,
                adSessionContext: context
            )

            return try await MainActor.run {
                // `mainAdView` is `weak UIView *` on OMID's side; assign
                // on main per UIKit threading conventions, alongside the
                // OMSession init + start that already require main.
                session.mainAdView = webView
                let omSession = try OMSession(session: session, webView: webView)
                omSession.start()
                return omSession
            }
        } catch {
            throw OMError.sessionCreationFailed(error)
        }
    }

    /// Returns the contents of the bundled `omsdk-v1.js` script. Consumer
    /// SDKs inject this at WebView creation (`atDocumentStart`) so the
    /// OMID JS layer is present before any ad content loads.
    public static func omsdkScript() -> String? {
        guard let url = Bundle.kontextKitResources.url(forResource: "omsdk-v1", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return script
    }
}

// MARK: - Private

private extension OMManager {
    var isActive: Bool {
        OMIDKontextsoSDK.shared.isActive
    }
}
