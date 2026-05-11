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
    /// For `creativeType == .video`, also ensures the shared
    /// `AVAudioSession` is active (`.playback + .mixWithOthers`) so OMID's
    /// device-volume KVO can fire — required for IAB certification of
    /// HTML video ads (sdk-swift PR #119). The activation is one-shot via
    /// `AudioInfoProvider.ensureSessionActive()`; `AudioInfoProvider`
    /// owns the single shared activator used by both `isSoundOn()` and
    /// us, so we never thrash the session.
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
            _ = AudioInfoProvider.ensureSessionActive()
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
        guard let url = Bundle.module.url(forResource: "omsdk-v1", withExtension: "js"),
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
