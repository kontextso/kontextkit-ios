import Foundation

private final class BundleToken {}

extension Bundle {
    /// Resource bundle accessor that works under both Swift Package
    /// Manager and CocoaPods.
    ///
    /// SwiftPM auto-generates `Bundle.module` from the package's
    /// `resources:` declaration. CocoaPods does not — so we look up
    /// the `KontextKit.bundle` that the podspec's `resource_bundles`
    /// produces, falling back to the framework's own bundle.
    static let kontextKitResources: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let bundleName = "KontextKit"
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
