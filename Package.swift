// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bilby",
    // SpeechAnalyzer and FoundationModels are macOS 26 only.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BilbyCore", targets: ["BilbyCore"]),
        .executable(name: "Bilby", targets: ["BilbyApp"]),
    ],
    targets: [
        // Pure Swift. Must never import a platform framework —
        // see Scripts/check-core-purity.sh.
        .target(name: "BilbyCore"),
        // Apple's frameworks live here and nowhere else.
        .target(name: "BilbySources", dependencies: ["BilbyCore"]),
        .target(name: "BilbyUI", dependencies: ["BilbyCore"]),
        .executableTarget(name: "BilbyApp", dependencies: ["BilbyCore", "BilbySources", "BilbyUI"]),
        .testTarget(name: "BilbyCoreTests", dependencies: ["BilbyCore"]),
    ]
)
