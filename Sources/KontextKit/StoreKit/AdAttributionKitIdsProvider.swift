import Foundation

/// Reads AdAttributionKit network identifiers declared in the app's
/// `Info.plist`.
///
/// Apple stores these under the `AdNetworkIdentifiers` key as a plain
/// array of strings (unlike SKAdNetwork's array of dictionaries, see
/// `SKAdNetworkIdsProvider`). Ad servers report both lists so a DSP can
/// tell which attribution framework the app supports.
public enum AdAttributionKitIdsProvider {

    /// Returns the `AdNetworkIdentifiers` values from the app's
    /// `Info.plist`. Empty array if the key is missing or malformed.
    public static func collect() -> [String] {
        Bundle.main.infoDictionary?["AdNetworkIdentifiers"] as? [String] ?? []
    }
}
