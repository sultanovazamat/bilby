// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Bilby",
    // macOS 26 is set by the translator, not the recogniser. Recognition needs
    // only 14.4 (Core Audio process taps), but
    // `TranslationSession(installedSource:target:)` — the one that works
    // outside SwiftUI — is 26-only. Supporting 15 means going back to the
    // view-bound `.translationTask` path for every translation, not just the
    // one-time language download.
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "BilbyCore", targets: ["BilbyCore"]),
        .executable(name: "Bilby", targets: ["BilbyApp"]),
    ],
    dependencies: [
        // Reviewed speech engine revision. Runtime model bytes are pinned
        // separately by the manifest bundled with BilbySources.
        // `traits: []` opts out of NemoTextProcessing, a prebuilt xcframework we did
        // not build and cannot read. Text normalisation is cosmetic for captions;
        // shipping an opaque binary inside an app whose promise is "nothing leaves
        // your machine" is not a trade worth making.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "41540ea237350afe5117a082b5c28eda642d0612", traits: [])
    ],
    targets: [
        // Pure Swift. Must never import a platform framework —
        // see Scripts/check-core-purity.sh.
        .target(name: "BilbyCore"),
        // Apple's frameworks live here and nowhere else.
        .target(
            name: "BilbySources", dependencies: ["BilbyCore", .product(name: "FluidAudio", package: "FluidAudio")],
            resources: [.process("Resources")]),
        .target(name: "BilbyUI", dependencies: ["BilbyCore"], resources: [.process("Resources")]),
        .executableTarget(name: "BilbyApp", dependencies: ["BilbyCore", "BilbySources", "BilbyUI"]),
        .executableTarget(name: "BilbyPreview", dependencies: ["BilbyCore", "BilbyUI"]),
        .testTarget(name: "BilbyCoreTests", dependencies: ["BilbyCore"]),
        .testTarget(name: "BilbyUITests", dependencies: ["BilbyUI"]),
        .testTarget(name: "BilbySourcesTests", dependencies: ["BilbySources"]),
    ]
)
