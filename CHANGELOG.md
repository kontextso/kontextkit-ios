# Changelog

## 0.0.1
Initial release. Extracted from the `kontextso/sdk-v4` monorepo as a standalone Swift package and CocoaPod.

* Device-info providers — `AppInfoProvider`, `HardwareInfoProvider`, `OSInfoProvider`, `ScreenInfoProvider`, `BatteryInfoProvider`, `AudioInfoProvider`, `NetworkInfoProvider`.
* IDFA access via `AdvertisingIdProvider` and ATT prompts via `TrackingAuthorizationManager`.
* StoreKit attribution — `SKAdNetworkManager`, `SKAdNetworkIdsProvider`, `SKOverlayManager`, `SKStoreProductManager`.
* IAB OMID integration via the bundled `OMSDK_Kontextso.xcframework` (v1.6.4) and `OMManager` lifecycle.
* IAB TCF consent reader (`TCFDataProvider`).
* Brightness control (`BrightnessManager`) and in-app browser (`InAppBrowserManager`).
* Bundled `omsdk-v1.js` for WebView injection.
