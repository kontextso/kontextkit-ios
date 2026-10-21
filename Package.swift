// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KontextKit",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        // The shared primitives: device info, privacy, StoreKit, UI. Every Kontext iOS SDK depends on it.
        .library(
            name: "KontextKit",
            targets: ["KontextKit"]
        ),
        // IAB Open Measurement (OMID) on top of it, with the bundled OMSDK xcframework. Only the SDKs that
        // measure with OMID depend on it; the others never link the binary or take on its licence.
        .library(
            name: "KontextKitOM",
            targets: ["KontextKitOM"]
        )
    ],
    targets: [
        .target(
            name: "KontextKit",
            path: "Sources/KontextKit",
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "KontextKitOM",
            dependencies: [
                "KontextKit",
                "OMSDK_Kontextso",
            ],
            path: "Sources/KontextKitOM",
            resources: [
                .copy("omsdk-v1.js"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .binaryTarget(
            name: "OMSDK_Kontextso",
            path: "Frameworks/OMSDK_Kontextso.xcframework"
        ),
        .testTarget(
            name: "KontextKitTests",
            dependencies: ["KontextKit", "KontextKitOM"],
            path: "Tests"
        )
    ]
)
