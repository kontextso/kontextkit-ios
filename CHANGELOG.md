# Changelog

## 0.0.4
* `OMManager.createSession` now activates the shared `AVAudioSession` with `.playback + .mixWithOthers + setActive(true)` **per video OMID session** — once per call, immediately before the OMID session is created. Restores the per-session activation pattern from sdk-swift v3 PR #119 (which is what IAB Tech Lab certified for HTML video ads) and the IAB OMSDK demo's `WebViewVideoController.swift`. The previous one-shot lazy activation through `AudioInfoProvider.ensureSessionActive()` was a regression: device-volume KVO observed by OMID would freeze after the first `/preload`-driven activation, so hardware volume-up/-down events never reached the validation script. With this change, device-volume `volumeChange` events fire correctly on every hardware press. No deactivation path — calling `setActive(false, .notifyOthersOnDeactivation)` is what produced the 1-second audio-cut bug in sdk-flutter PR #51, and `.mixWithOthers` keeps the active session gentle on host audio so a permanent activation is fine.

## 0.0.3
* `InstallIdProvider` — new device-info provider returning a per-app-install identifier (UUID v7) persisted in `UserDefaults` under `"kontextso.installId"`. Generated on first call, validated against the canonical UUID shape on read (overwrites on corruption), and stable across launches and conversations until the user uninstalls or clears app data. Sibling iOS SDKs (sdk-swift, sdk-react-native, sdk-flutter) attach it to every `/init`, `/preload`, `/error`, and `/debug` request so the ad server can key pacing, frequency caps, and per-install diagnostics to a stable identity independent of `conversationId` or `userId`.

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
