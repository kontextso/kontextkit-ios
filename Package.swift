// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KontextKit",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "KontextKit",
            targets: ["KontextKit"]
        )
    ],
    targets: [
        .target(
            name: "KontextKit",
            dependencies: [
                "OMSDK_Kontextso",
            ],
            path: "Sources",
            resources: [
                .copy("OMSDK/omsdk-v1.js"),
                .copy("PrivacyInfo.xcprivacy"),
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
            dependencies: ["KontextKit"],
            path: "Tests"
        )
    ]
)
