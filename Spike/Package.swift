// swift-tools-version: 6.0
import PackageDescription

// Throwaway. Answers the three questions that decide whether Bilby exists.
let package = Package(
    name: "Spike",
    platforms: [.macOS("26.0")],
    targets: [.executableTarget(name: "probe")]
)
