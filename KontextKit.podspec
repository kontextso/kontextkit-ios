Pod::Spec.new do |s|
  s.name         = "KontextKit"
  s.version      = "0.0.4"
  s.summary      = "Kontext shared native modules for iOS SDKs"
  s.description  = <<-DESC
    KontextKit bundles the iOS-native primitives shared across every Kontext
    SDK that targets iOS — sdk-swift, sdk-react-native (iOS), and sdk-flutter
    (iOS). It contains:

    - System-info collectors (hardware, OS, screen, battery, audio, network).
    - IDFA/IDFV access (`AdvertisingIdProvider`) and ATT prompts
      (`TrackingAuthorizationManager`).
    - StoreKit attribution (`SKAdNetworkManager`, `SKOverlayManager`,
      `SKStoreProductManager`, `SKAdNetworkIdsProvider`).
    - IAB OMID (Open Measurement) integration via the bundled
      `OMSDK_Kontextso.xcframework`.
    - IAB TCF (Transparency & Consent Framework) UserDefaults reader.
    - Brightness control, in-app browser (`SFSafariViewController`).

    The point is to write platform-utility code once and share it across SDKs
    rather than re-deriving it three times. See the README for the decision
    rule and naming convention.
  DESC
  s.homepage     = "https://github.com/kontextso/kontextkit-ios"
  s.license      = { :type => "Apache-2.0", :file => "LICENSE" }
  s.authors      = { "Kontext" => "support@kontext.so" }

  s.platforms    = { :ios => "14.0" }
  s.source       = { :git => "https://github.com/kontextso/kontextkit-ios.git", :tag => "#{s.version}" }

  s.source_files = "Sources/**/*.swift"
  s.resource_bundles = {
    "KontextKit" => ["Sources/OMSDK/omsdk-v1.js", "Sources/PrivacyInfo.xcprivacy"]
  }
  s.vendored_frameworks = "Frameworks/OMSDK_Kontextso.xcframework"
  s.frameworks = "SafariServices", "AdSupport", "AppTrackingTransparency",
                 "StoreKit", "CoreTelephony", "AVFoundation", "Network", "WebKit"
  s.swift_version = "5.9"
end
