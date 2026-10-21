@preconcurrency import OMSDK_Kontextso
import WebKit

/// A single OMID measurement session bound to one `WKWebView`.
///
/// Created by `OMManager.createSession(...)` — the `start()` call is
/// done internally as the last step of creation, so consumers don't
/// need to invoke it. Consumer responsibility is the teardown trio:
/// `retire()` → `finish()` → drop the reference.
@MainActor
public final class OMSession {
    private let session: OMIDKontextsoAdSession
    private let webView: WKWebView
    private let adEvents: OMIDKontextsoAdEvents

    init(session: OMIDKontextsoAdSession, webView: WKWebView) throws {
        self.session = session
        self.webView = webView
        self.adEvents = try OMIDKontextsoAdEvents(adSession: session)
    }

    /// Begins the OMID session. Internal — `OMManager.createSession`
    /// calls this as the last creation step; no external caller exists.
    func start() {
        session.start()
    }

    /// Notifies the in-iframe JS verification scripts that the session
    /// is about to end, so they can flush their final measurement
    /// events while the WebView is still alive. Required by IAB OMID
    /// to precede `finish()`.
    public func retire() {
        webView.evaluateJavaScript("window.postMessage({ type: 'retire-iframe' }, '*');", completionHandler: nil)
    }

    /// Terminates the OMID session natively and **holds the WebView
    /// alive for 1 second** so verification scripts can handle the
    /// `sessionFinish` event. Per `OMIDAdSession.h`:
    ///
    /// > "Note that ending an OMID ad session sends a message to the
    /// > verification scripts running inside the webview supplied by
    /// > the integration. So that the verification scripts have enough
    /// > time to handle the `sessionFinish` event, the integration must
    /// > maintain a strong reference to the webview for at least 1.0
    /// > seconds after ending the session."
    ///
    /// The hold is implemented as a fire-and-forget MainActor `Task`
    /// that strongly captures the WebView. Callers can drop their
    /// `OMSession` reference (and any other strong WebView reference)
    /// immediately after this returns — the WebView stays alive until
    /// the Task's `Task.sleep(1s)` completes, regardless of whether the
    /// surrounding ad/cover/cell has been torn down.
    ///
    /// Pair with `retire()` — retire first so JS can flush, then finish
    /// to dispatch the session-finish event.
    public func finish() {
        let heldWebView = self.webView
        session.finish()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = heldWebView
        }
    }

    /// Reports an OMID error. `errorType == "video"` maps to OMID's
    /// `.media`; everything else maps to `.generic`. Message defaults
    /// to "unknown" when nil.
    public func logError(errorType: String?, message: String?) {
        let omErrorType: OMIDErrorType = errorType == "video" ? .media : .generic
        session.logError(withType: omErrorType, message: message ?? "unknown")
    }
}
