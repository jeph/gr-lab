// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "gr_camera",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "gr-camera", targets: ["gr_camera"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "gr_camera",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            // Swift warnings fail the build (AGENTS.md, "Checks").
            swiftSettings: [.treatAllWarnings(as: .error)]
        )
    ],
    swiftLanguageModes: [.v5]
)
