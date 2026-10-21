import Foundation
import AppTrackingTransparency
import UIKit

/// Manages App Tracking Transparency (ATT) authorization requests.
///
/// All version checks and edge cases handled internally:
/// - Returns `notSupported` (4) on pre-iOS 14
/// - Skips ATT request on iOS 14.0–14.4 (not required, risks permanent denial)
/// - Only requests when status is `.notDetermined`
/// - Handles race condition where OS returns `.denied` while status is still
///   `.notDetermined` (retries on next foreground)
/// - `runStartupFlow()` guaranteed to run only once per app session
@MainActor
public final class TrackingAuthorizationManager {
    public static let shared = TrackingAuthorizationManager()

    /// Status value for platforms/versions that don't support ATT.
    public static let notSupported = 4

    private var observer: NSObjectProtocol?
    private var didRunStartup = false

    private init() {}

    // No `deinit` cleanup: this is a `.shared` singleton and lives for
    // the full process lifetime, so deinit never runs in practice.
    // Adding deinit-side observer removal would require touching
    // `@MainActor`-isolated state from a nonisolated context (which
    // strict-concurrency rejects); the cleanup is unreachable code anyway.

    // MARK: - Status

    /// The current ATT authorization status as an integer.
    /// Returns 4 (`notSupported`) on pre-iOS 14 devices.
    public static var currentStatus: Int {
        if #available(iOS 14, *) {
            return Int(ATTrackingManager.trackingAuthorizationStatus.rawValue)
        }
        return notSupported
    }

    /// Returns `currentStatus` as `NSNumber` for bridge layers.
    public static var currentStatusAsNumber: NSNumber {
        NSNumber(value: currentStatus)
    }

    // MARK: - Request Authorization

    /// Requests tracking authorization from the user.
    ///
    /// On pre-iOS 14, immediately calls completion with `notSupported` (4).
    /// On iOS 14+, shows the ATT dialog and returns the user's choice.
    public func requestAuthorization(completion: @escaping @Sendable (Int) -> Void) {
        guard #available(iOS 14, *) else {
            DispatchQueue.main.async { completion(Self.notSupported) }
            return
        }

        requestAuthorizationWhenActive(completion: completion)
    }

    @available(iOS 14, *)
    private func requestAuthorizationWhenActive(completion: @escaping @Sendable (Int) -> Void) {
        guard UIApplication.shared.applicationState == .active else {
            addObserver(completion: completion)
            return
        }

        removeObserver()
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            if status == .denied
                && ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                Task { @MainActor in self?.addObserver(completion: completion) }
                return
            }
            DispatchQueue.main.async {
                completion(Int(status.rawValue))
            }
        }
    }

    /// Async version of requestAuthorization.
    public func requestAuthorization() async -> Int {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Startup Flow

    /// Runs the full ATT startup flow once per app session:
    /// 1. Skips on non-iOS or pre-iOS 14.5
    /// 2. Checks if status is `.notDetermined`
    /// 3. Requests authorization
    /// 4. Returns resolved IDs (with zero UUID normalization)
    ///
    /// Idempotent — calling multiple times returns the same result.
    /// Manual overrides for advertisingId/vendorId take precedence.
    public func runStartupFlow(
        manualAdvertisingId: String? = nil,
        manualVendorId: String? = nil
    ) async -> (advertisingId: String?, vendorId: String?) {
        // Only run once
        if !didRunStartup {
            didRunStartup = true

            // Only request ATT on iOS 14.5+
            if #available(iOS 14.5, *) {
                if Self.currentStatus == 0 { // notDetermined
                    _ = await requestAuthorization()
                }
            }
        }

        return AdvertisingIdProvider.resolveIds(
            manualAdvertisingId: manualAdvertisingId,
            manualVendorId: manualVendorId
        )
    }

    // MARK: - Private

    private func addObserver(completion: @escaping @Sendable (Int) -> Void) {
        removeObserver()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification queue is .main, but the observer block
            // is `nonisolated` — hop into MainActor explicitly.
            Task { @MainActor in self?.requestAuthorization(completion: completion) }
        }
    }

    private func removeObserver() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
