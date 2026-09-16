// swift-tools-version: 6.0
import PackageDescription

// Throwaway. Answers the three questions that decide whether Bilby exists.
let package = Package(
    name: "Spike",
    platforms: [.macOS("26.0")],
    dependencies: [.package(path: "..")],
    targets: [
        .executableTarget(name: "probe"),
        .executableTarget(name: "prepare"),
        .executableTarget(name: "latency", dependencies: [.product(name: "BilbyCore", package: "Bilby")]),
    ]
)
