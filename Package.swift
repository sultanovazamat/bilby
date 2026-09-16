// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bilby",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BilbyCore", targets: ["BilbyCore"])
    ],
    targets: [
        // Pure Swift. Must never import Speech, Translation, AVFoundation or
        // FoundationModels — see Scripts/check-core-purity.sh.
        .target(name: "BilbyCore"),
        .testTarget(name: "BilbyCoreTests", dependencies: ["BilbyCore"]),
    ]
)
