import Foundation

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif

extension Bundle {
    /// Resource bundle accessor for the `KontextKitOM` target that works
    /// under both Swift Package Manager and CocoaPods.
    ///
    /// SwiftPM auto-generates `Bundle.module` per target from its
    /// `resources:` declaration. CocoaPods does not — so we look up the
    /// `KontextKitOM.bundle` that the `KontextKit/OMSDK` subspec's
    /// `resource_bundles` produces, falling back to the framework's own bundle.
    static let kontextKitOMResources: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let bundleName = "KontextKitOM"
        let candidates: [URL?] = [
            Bundle(for: BundleToken.self).resourceURL,
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent("\(bundleName).bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle(for: BundleToken.self)
        #endif
    }()
}
