import Foundation

/// Reads SKAdNetwork identifiers declared in the app's `Info.plist`.
///
/// Apple stores these under the `SKAdNetworkItems` array, with each
/// entry having a `SKAdNetworkIdentifier` string. Naming follows
/// Apple's casing (matches the Info.plist keys + `SKAdNetworkManager`
/// in the same module).
public enum SKAdNetworkIdsProvider {

    /// Returns all `SKAdNetworkIdentifier` values from the app's
    /// `Info.plist`'s `SKAdNetworkItems` array. Empty array if the
    /// key is missing or malformed.
    public static func collect() -> [String] {
        let rawItems = Bundle.main.infoDictionary?["SKAdNetworkItems"] as? [[String: String]]
        return rawItems?.compactMap { $0["SKAdNetworkIdentifier"] } ?? []
    }
}
