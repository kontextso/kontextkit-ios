import UIKit

/// Window-scene + view-controller lookup helpers shared by the
/// presentation managers. Filters to the foreground scene so we
/// don't pick up backgrounded scenes on iPad multi-window setups.
@MainActor
enum Scenes {
    /// The currently-foreground `UIWindowScene`, if any.
    static func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
    }

    /// The topmost view controller that can present a modal — walks
    /// `UINavigationController.visibleViewController`,
    /// `UITabBarController.selectedViewController`, and the
    /// `presentedViewController` chain.
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let seed = base ?? activeScene()?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        guard let seed else { return nil }

        if let nav = seed as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = seed as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = seed.presentedViewController {
            return topViewController(base: presented)
        }
        return seed
    }
}
