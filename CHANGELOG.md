# Changelog

## 0.0.2
* `NetworkInfoProvider`: `detail` is now reported only when `type == "cellular"`. CoreTelephony reports the cellular radio's RAT independently of the active network path, so previously `{type: "wifi", detail: "5g"}` could appear when the cellular radio was up for calls/fallback but Wi-Fi was carrying data. Mirrors sdk-react-native's behaviour.
* `AudioInfoProvider`: live volume tracking now works across consecutive `collect()` calls. `outputVolume` is undefined unless the session is active, and iOS only refreshes the property while something is observing it via KVO. `collect()` now calls `ensureSessionActive()` and the activator installs a permanent KVO observer on `outputVolume`, so volume updates are reflected without needing a video ad on screen.

## 0.0.1
Initial release. Extracted from the `kontextso/sdk-v4` monorepo as a standalone Swift package and CocoaPod.

* Device-info providers — `AppInfoProvider`, `HardwareInfoProvider`, `OSInfoProvider`, `ScreenInfoProvider`, `BatteryInfoProvider`, `AudioInfoProvider`, `NetworkInfoProvider`.
* IDFA access via `AdvertisingIdProvider` and ATT prompts via `TrackingAuthorizationManager`.
* StoreKit attribution — `SKAdNetworkManager`, `SKAdNetworkIdsProvider`, `SKOverlayManager`, `SKStoreProductManager`.
* IAB OMID integration via the bundled `OMSDK_Kontextso.xcframework` (v1.6.4) and `OMManager` lifecycle.
* IAB TCF consent reader (`TCFDataProvider`).
* Brightness control (`BrightnessManager`) and in-app browser (`InAppBrowserManager`).
* Bundled `omsdk-v1.js` for WebView injection.
