# KontextKit

> **Internal use only.** KontextKit is **not a standalone library**. It exists so that Kontext's iOS SDKs ([sdk-swift](https://github.com/kontextso/sdk-swift), sdk-react-native, sdk-flutter) can share the same underlying code instead of re-deriving it three times.

KontextKit ships as two products. `KontextKit` holds the shared primitives (device info, privacy, StoreKit, UI); `KontextKitOM` adds IAB Open Measurement with the bundled `OMSDK_Kontextso.xcframework` and is taken only by the SDKs that measure with OMID (CocoaPods: subspec `KontextKit/OMSDK`).

If you're building an app, install one of the Kontext SDKs instead — it will pull KontextKit in transitively. See the [Kontext Swift SDK docs](https://docs.kontext.so/sdk/v4/swift) for the integration guide.

## License

Apache 2.0. See [LICENSE](./LICENSE).
