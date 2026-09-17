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
        // Brings streaming Parakeet EOU and speaker diarization as CoreML models
        // on the Neural Engine. Costs us the zero-dependency claim; buys 25
        // source languages, explicit end-of-utterance, and 160 ms cadence
        // against Apple's measured 3.6 s bursts.
        // `traits: []` opts out of NemoTextProcessing, a prebuilt xcframework we did
        // not build and cannot read. Text normalisation is cosmetic for captions;
        // shipping an opaque binary inside an app whose promise is "nothing leaves
        // your machine" is not a trade worth making.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4", traits: [])
    ],
    targets: [
        // Pure Swift. Must never import a platform framework —
        // see Scripts/check-core-purity.sh.
        .target(name: "BilbyCore"),
        // Apple's frameworks live here and nowhere else.
        .target(name: "BilbySources", dependencies: ["BilbyCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "BilbyUI", dependencies: ["BilbyCore"]),
        .executableTarget(name: "BilbyApp", dependencies: ["BilbyCore", "BilbySources", "BilbyUI"]),
        .executableTarget(name: "BilbyPreview", dependencies: ["BilbyUI"]),
        .executableTarget(name: "BilbyModels", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "BilbyCoreTests", dependencies: ["BilbyCore"]),
    ]
)
