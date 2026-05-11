import Foundation

/// Factory for the NSError objects returned by KontextKit's manager
/// public APIs. Bridge layers (RN, Flutter) read `domain` as the
/// stable error identifier and `localizedDescription` as the
/// human-readable message; `details` carries extra context (e.g. the
/// underlying error description) for consumers that want it.
enum Errors {
    static func make(domain: String, message: String, details: Any? = nil) -> NSError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let details {
            userInfo["details"] = details
        }
        return NSError(domain: domain, code: 1, userInfo: userInfo)
    }
}
