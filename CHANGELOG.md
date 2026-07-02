# Changelog

## 0.1.0
### Breaking
`NetworkInfoProvider` no longer detects `network.type`. `NetworkInfo.type` is now `String?` (always nil), `NetworkInfo.detail` is removed, and `collectAsDict()` omits the `type`, `carrier`, and `detail` keys. Consumers that read these fields (sdk-swift, sdk-react-native, sdk-flutter) must update — only `userAgent` is still populated.

* Remove on-device `network.type` detection. It resolved the type by bridging `NWPathMonitor.pathUpdateHandler` into a `CheckedContinuation`, but that handler is not one-shot: it re-fires on every path change and `monitor.cancel()` does not retract callbacks already dispatched to the monitor's queue, so a second callback resumed the continuation twice and crashed the app (`EXC_BREAKPOINT`) on flapping/constrained networks. This ran on every `/preload`, so at scale it was a high-volume production crash present in every KontextKit release to date (and in sdk-swift 1.0.5+ before the code was extracted here). The ad server does not use `network.type` for ad selection — it only forwards it to DSPs as OpenRTB `connectiontype` — so the value is removed rather than guarded: a continuation that no longer exists cannot be double-resumed.
* Drop `network.carrier` and `network.detail` collection (CoreTelephony). `carrier` was already always nil on iOS 16+; `detail` (cellular radio access technology) was only meaningful alongside `type`. `userAgent` — the one field the ad server consumes — is unchanged.

## 0.0.5
* `Frameworks/OMLICENSE`: ship the IAB Tech Lab OM License v1.1 text alongside the bundled `OMSDK_Kontextso.xcframework`. Required by OM License Section 4(a) for any Object-form redistribution — without this file in the published pod, downstream consumers receive the binary but not the license text it ships under. Wired into the podspec via `s.preserve_paths`. The xcframework binary is unchanged (still IAB OMSDK 1.6.4); this is a license-compliance fix only. Mirrors the equivalent fix for the Android redistribution in `kontextkit-android` 0.0.6 (`omsdk-android/LICENSE`). KontextKit's own Swift sources remain Apache-2.0.

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
