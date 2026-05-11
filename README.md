# KontextKit

Shared iOS-native primitives used by Kontext's SDKs ([sdk-swift](https://github.com/kontextso/sdk-swift), sdk-react-native, sdk-flutter).

KontextKit is **not an SDK on its own** — it's the platform-utility layer that every Kontext iOS integration sits on top of. It wraps Apple system APIs (IDFA/ATT, StoreKit attribution, device info, TCF consent) and the IAB OMID (Open Measurement) native framework, so each SDK doesn't have to re-derive them.

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/kontextso/kontextkit-ios.git", from: "0.0.1")
]
```

### CocoaPods

```ruby
pod 'KontextKit', '~> 0.0.1'
```

## Requirements

- iOS 14.0+
- Swift 5.9+

## Usage

Most apps should not depend on KontextKit directly — install one of the Kontext SDKs instead and it will pull KontextKit in transitively. See the [Kontext Swift SDK docs](https://docs.kontext.so/sdk/v4/swift) for the integration guide.

## License

Apache 2.0. See [LICENSE](./LICENSE).
