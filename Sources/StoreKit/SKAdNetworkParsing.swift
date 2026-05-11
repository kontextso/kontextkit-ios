import Foundation

/// SKAdNetwork input parsing shared by `SKStoreProductManager`,
/// `SKOverlayManager`, and `SKAdNetworkManager`. All three consume the
/// same SKAdNetwork dict shape from the bridge layer; the type
/// conversions to `UUID` / `NSNumber` happen at the call site because
/// Apple's StoreKit APIs require different types for the same logical
/// fields.
enum SKAdNetworkParsing {
    /// Extracts the fidelity-0 entry (used by SKAdNetworkManager for
    /// direct SKAN attribution).
    static func fidelity0Values(from skan: [String: Any]) -> (nonce: String, timestamp: String, signature: String)? {
        fidelityValues(forFidelity: 0, from: skan)
    }

    /// Extracts the fidelity-1 entry (used by StoreKit-rendered surfaces:
    /// SKStoreProduct + SKOverlay).
    static func fidelity1Values(from skan: [String: Any]) -> (nonce: String, timestamp: String, signature: String)? {
        fidelityValues(forFidelity: 1, from: skan)
    }

    /// Common SKAN attribution fields shared by SKStoreProduct and
    /// SKOverlay. `itunesItem` and `nonce`-as-UUID validation stay at
    /// the call site because Apple's two APIs have asymmetric
    /// requirements: StoreKit needs a UUID for the nonce, SKAdImpression
    /// needs a String; SKStoreProduct doesn't read `itunesItem` from
    /// the SKAN dict (it comes from a separate parameter), SKOverlay
    /// does.
    struct Fields {
        let version: String
        let network: String
        let sourceAppInt: Int
        let campaignInt: Int
        let nonce: String
        let timestampInt: Int
        let signature: String
    }

    /// Parses + validates the common SKAN fields. Returns `nil` if any
    /// required field (version, network, sourceApp, fidelity-1 entry,
    /// numeric timestamp) is missing or malformed. `sourceApp` and
    /// `campaign` accept missing/non-numeric values and fall back to
    /// `0`, which is what Apple specifies for "no App Store ID known".
    static func fields(from skan: [String: Any]) -> Fields? {
        guard
            let version = ValueCoercion.string(skan["version"]),
            let network = ValueCoercion.string(skan["network"]),
            let sourceApp = ValueCoercion.string(skan["sourceApp"]),
            let f1 = fidelity1Values(from: skan),
            let timestampInt = Int(f1.timestamp)
        else { return nil }

        return Fields(
            version: version,
            network: network,
            sourceAppInt: Int(sourceApp) ?? 0,
            campaignInt: ValueCoercion.int(skan["campaign"]) ?? 0,
            nonce: f1.nonce,
            timestampInt: timestampInt,
            signature: f1.signature
        )
    }

    /// Optional iOS 16.1+ source identifier (SKAdNetwork v4.0).
    /// Returns `nil` if missing or non-numeric.
    static func sourceIdentifier(from skan: [String: Any]) -> Int? {
        ValueCoercion.int(skan["sourceIdentifier"])
    }

    private static func fidelityValues(forFidelity fidelity: Int, from skan: [String: Any]) -> (nonce: String, timestamp: String, signature: String)? {
        guard let fidelities = skan["fidelities"] as? [[String: Any]],
              let entry = fidelities.first(where: { ValueCoercion.int($0["fidelity"]) == fidelity }),
              let nonce = ValueCoercion.string(entry["nonce"]),
              let timestamp = ValueCoercion.string(entry["timestamp"]),
              let signature = ValueCoercion.string(entry["signature"])
        else { return nil }
        return (nonce, timestamp, signature)
    }
}
