// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DailyLang",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "DailyLangCore",
            targets: ["DailyLangCore"]
        ),
    ],
    targets: [
        .target(
            name: "DailyLangCore"
        ),
        .testTarget(
            name: "DailyLangCoreTests",
            dependencies: ["DailyLangCore"]
        ),
    ]
)

