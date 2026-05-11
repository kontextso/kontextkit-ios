# KontextKit (iOS) — Project Context for Claude

## What this repo is

KontextKit is a **shared internal library**, not a public SDK. It's consumed by Kontext's iOS-targeting SDKs — `sdk-swift`, `sdk-react-native` (iOS half), and `sdk-flutter` (iOS half) — so that platform-utility code is written once and shared, not re-derived three times.

Distributed via Swift Package Manager and CocoaPods.

## Inclusion rule (high bar)

Code belongs in KontextKit only if **one** of the following holds:

1. **It touches Apple system APIs only callable from native code.** The JS/Dart layers in `sdk-react-native` and `sdk-flutter` can't reach these directly, so the native wrapper has to live somewhere.
   Examples: `AdSupport` (IDFA), `AppTrackingTransparency` (ATT), device/screen/audio/network info, `StoreKit` (SKAdNetwork, SKOverlay, SKStoreProductViewController), TCF reads from `UserDefaults`, the IAB OMID native SDK.

2. **It has hidden complexity that's risky to re-derive across SDKs.** IAB OMID is the canonical example: correct `loaded`/`impression` event ordering, audio-session refcount, orphan-mount fix, IAB certification. Three SDKs writing this independently means three slightly-different implementations and three certification paths.

If neither bar is met, default to per-SDK code (Swift `struct`s in sdk-swift, etc). Code that gets copied 2–3 times is cheaper than a shared API that's wrong for one of the consumers.

**Does NOT belong here:** domain models (`Bid`, `Message`, `AdEvent`), networking flows (`Preload`, `HTTPRetry`, `ErrorCapture`), the public-API surface (`Session`, `Ad`, entry-point classes), UI components.

## Naming convention

Two suffixes carry meaning. Pick whichever fits the code's *shape*, not its domain.

- **`*Provider`** — stateless, read-only. Static functions on a `struct` (or `enum` namespace) that return a `Sendable` snapshot via `static func collect() -> XxxInfo`. No singletons, no observers, no side effects.
- **`*Manager`** — stateful and/or side-effecting. Either a `final class` singleton (`shared`) holding observers/lifecycle, or an `enum` namespace owning system-property reads+writes (`UIScreen.brightness`-style).

Why not `*Service`? Not iOS-idiomatic; Apple uses `*Manager` for the same shape (`CLLocationManager`, `CMMotionManager`, `ATTrackingManager`, `ASIdentifierManager`).

`JSONParsing` and `ValueCoercion` are unsuffixed `enum` namespaces — pure stateless utilities used at boundaries. When a utility has zero alignment with either suffix, no suffix is fine.

## Layout

```
Sources/
  DeviceInfo/        AdvertisingIdProvider, App/HW/OS/Screen/Battery/Audio/NetworkInfoProvider, BrightnessManager
  Privacy/           TCFDataProvider, TrackingAuthorizationManager
  StoreKit/          SKAdNetworkManager, SKAdNetworkIdsProvider, SKAdNetworkParsing, SKOverlayManager, SKStoreProductManager
  UI/                InAppBrowserManager, Scenes
  OMSDK/             OMManager, OMSession, OMPartner, OMCreativeType, omsdk-v1.js
  Utilities/         BundleResources, Errors, JSONParsing, ValueCoercion
  PrivacyInfo.xcprivacy
Tests/               mirrors Sources/ layout
Frameworks/          OMSDK_Kontextso.xcframework (binary, IAB-shipped)
```

## Build / test / lint

`swift build` will fail — UIKit isn't on host macOS. Use Xcode/iOS Simulator:

```sh
# Build
xcodebuild -scheme KontextKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest,arch=arm64' build

# Test
xcodebuild -scheme KontextKit -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest,arch=arm64' test

# Lint
swiftlint lint
```

CI runs both `lint` and `test` jobs on `macos-15`. See `.github/workflows/ci.yml`.

## Release

See [RELEASING.md](./RELEASING.md) for the CocoaPods + git-tag flow.

Versioning: semver. The xcframework version (IAB OMID) is independent of KontextKit's semver — bumping the framework is a regular KontextKit minor/major bump.

## Conventions

- **Swift 5.9**, iOS 14.0+ deployment target. `StrictConcurrency` experimental feature enabled — anything crossing actor boundaries needs to be `Sendable`.
- **No comments** unless the why is non-obvious (hidden constraint, subtle invariant, workaround for a specific bug, behavior that would surprise a reader). Don't ref PRs or tickets in code.
- **`@MainActor` isolation** for anything touching UIKit or ATT. Callers from RN/Flutter bridges hop to MainActor explicitly.
- **`Sendable` snapshots** out of `*Provider`s — never leak mutable references to platform state.

## Related repos

- [sdk-swift](https://github.com/kontextso/sdk-swift) — primary consumer; ships KontextKit transitively
- [sdk-v4](https://github.com/kontextso/sdk-v4) — monorepo; KontextKit was historically developed here before extraction
- [kontextkit-kotlin](https://github.com/kontextso/kontextkit-kotlin) — Android counterpart (planned)
