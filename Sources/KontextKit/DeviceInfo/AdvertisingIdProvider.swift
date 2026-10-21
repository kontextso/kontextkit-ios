import Foundation
import AdSupport
import AppTrackingTransparency
import UIKit

/// Provides access to IDFA (Advertising Identifier) and IDFV (Vendor Identifier).
///
/// All returned IDs are normalized: zero UUIDs and empty strings → nil.
public enum AdvertisingIdProvider {

    private static let zeroUUID = "00000000-0000-0000-0000-000000000000"

    /// Returns the IDFA (Identifier for Advertisers) if tracking is authorized.
    ///
    /// Requires ATT authorization status `.authorized`. Returns `nil` if
    /// tracking is not authorized, not available, or zero UUID.
    public static func getAdvertisingId() -> String? {
        guard ATTrackingManager.trackingAuthorizationStatus == .authorized else {
            return nil
        }
        return normalize(ASIdentifierManager.shared().advertisingIdentifier.uuidString)
    }

    /// Returns the IDFV (Identifier for Vendor), normalized.
    ///
    /// Does not require ATT authorization.
    /// Returns `nil` if unavailable or zero UUID.
    /// Main-actor isolated because `UIDevice.current` is a main-actor
    /// property in modern SDKs.
    @MainActor
    public static func getVendorId() -> String? {
        return normalize(UIDevice.current.identifierForVendor?.uuidString)
    }

    /// Resolves advertising and vendor IDs with optional manual overrides.
    ///
    /// Manual overrides take precedence. All values are normalized
    /// (zero UUIDs and empty strings → nil).
    /// Main-actor isolated because it calls `getVendorId()`.
    @MainActor
    public static func resolveIds(
        manualAdvertisingId: String? = nil,
        manualVendorId: String? = nil
    ) -> (advertisingId: String?, vendorId: String?) {
        let advertisingId = normalize(manualAdvertisingId) ?? getAdvertisingId()
        let vendorId = normalize(manualVendorId) ?? getVendorId()
        return (advertisingId, vendorId)
    }

    /// Normalizes an identifier: nil, empty, or zero UUID → nil.
    private static func normalize(_ id: String?) -> String? {
        guard let id, !id.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if id.lowercased() == zeroUUID { return nil }
        return id
    }
}
