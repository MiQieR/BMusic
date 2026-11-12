// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BMusic",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15), .iOS(.v17)],
    products: [
        .executable(name: "BMusic", targets: ["BMusic"])
    ],
    dependencies: [
        // Decoding, playback and audio output all live in libmpv. The binary
        // artifacts are cached by SwiftPM after the first resolve.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.1.0-n9.0.2")
    ],
    targets: [
        .executableTarget(
            name: "BMusic",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit")
            ],
            path: "Sources/BMusic",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
