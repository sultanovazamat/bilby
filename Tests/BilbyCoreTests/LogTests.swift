import Foundation
import Testing

@testable import BilbyCore

/// The log used to be /tmp/bilby.log at 0644, carrying every recognised
/// sentence and every translation. These two tests are here so that cannot
/// come back quietly: one pins where it goes, the other pins who may read it.
@Suite("The log")
struct LogTests {
    @Test("it is not written where every process on the machine can read it")
    func staysOutOfTmp() {
        let path = Log.defaultPath()
        #expect(!path.hasPrefix("/tmp/"))
        #expect(!path.hasPrefix("/private/tmp/"))
        #expect(path.contains("Library/Logs"))
    }

    @Test("a fresh log file is readable only by its owner")
    func createdPrivate() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let path = directory.appending(path: "bilby.log").path(percentEncoded: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        Log.create(at: path)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
    }
}
