import AppKit
import Foundation

/// Where BilbyUI's images live at runtime.
///
/// SwiftPM's generated `Bundle.module` looks in exactly two places: the top
/// level of the app bundle, where a signed app cannot keep a bundle, and the
/// absolute path of the build directory on the machine that built it. Both
/// miss a real installation, and a miss is a fatalError on the first
/// onboarding page. This looks where `make-app.sh` puts the bundle and where
/// SwiftPM leaves it for tests and tools, and answers nil rather than
/// crashing.
enum UIResources {
    private final class Marker {}

    static let bundle: Bundle? = {
        let name = "Bilby_BilbyUI.bundle"
        let candidates = [
            Bundle.main.resourceURL,  // Bilby.app/Contents/Resources
            Bundle.main.bundleURL,  // a bare executable: beside it
            Bundle(for: Marker.self).bundleURL.deletingLastPathComponent(),  // tests: beside the .xctest
        ]
        for directory in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: directory.appendingPathComponent(name)) { return bundle }
        }
        return nil
    }()

    /// A screenshot by name. An `NSImage`, not SwiftUI's `Image(_:bundle:)`:
    /// the latter draws nothing for a loose PNG in a SwiftPM bundle — it
    /// rendered an empty frame — while `image(forResource:)` draws it.
    static func screenshot(named name: String) -> NSImage? {
        bundle?.image(forResource: name)
    }
}
