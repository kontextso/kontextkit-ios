import Foundation

/// Per-app-install identifier. Generated as a UUID v7 on first SDK use,
/// persisted to `UserDefaults`, and attached to every ad-server request
/// (`/init`, `/preload`, `/error`, `/debug`) so the server can key pacing,
/// frequency caps, and per-install diagnostics to a stable client identity
/// independent of `conversationId` or `userId`.
///
/// Survives app launches; resets only when the user uninstalls the app
/// (or clears app data). Matches the `kontextso:installId` localStorage
/// key used by `@kontextso/sdk-js` so web and native installs share the
/// same shape on the wire.
public enum InstallIdProvider {

    /// UserDefaults key under which the install ID is persisted.
    private static let storageKey = "kontextso.installId"

    /// Returns the persisted install ID, generating + storing one on
    /// first call. The stored value is validated against the canonical
    /// UUID shape (8-4-4-4-12 hex) and overwritten if corrupted — guards
    /// against accidental tampering, partial UserDefaults migration, or
    /// a future change to the generator.
    public static func getOrCreate(
        defaults: UserDefaults = .standard
    ) -> String {
        if let existing = defaults.string(forKey: storageKey),
           isCanonicalUUID(existing) {
            return existing
        }
        let fresh = UUIDv7.generate()
        defaults.set(fresh, forKey: storageKey)
        return fresh
    }

    /// Validates any canonical UUID shape (8-4-4-4-12 hex). Intentionally
    /// not version- or variant-locked so a future change to the generator
    /// (e.g. v8) doesn't invalidate the IDs already in users' UserDefaults.
    static func isCanonicalUUID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        return UUID(uuidString: value) != nil
    }
}
