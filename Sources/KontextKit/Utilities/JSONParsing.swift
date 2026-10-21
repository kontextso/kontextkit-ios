import Foundation

/// Shared JSON parsing utility for bridge layers.
public enum JSONParsing {
    /// Parses a JSON string into a dictionary. Returns nil on failure.
    public static func parse(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}
