import Darwin
import Foundation
import Testing

@testable import BilbyCore

/// Filesystem fixtures never touch the app's real log or capture real speech.
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

        Log.write(Data("first".utf8), to: path)

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
    }

    @Test("an existing log loses its group and world read permissions before reuse")
    func existingLogBecomesPrivate() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let file = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("previous run".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

        Log.write(Data("new run".utf8), to: file.path, truncate: true)

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(mode.intValue == 0o600)
        #expect(try String(contentsOf: file, encoding: .utf8) == "new run")
    }

    @Test("a symlink in the parent path cannot redirect log creation")
    func rejectsSymlinkParent() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let target = directory.appending(path: "target")
        let link = directory.appending(path: "redirect")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        Log.write(Data("test".utf8), to: link.appending(path: "bilby.log").path, truncate: true)

        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "bilby.log").path))
    }

    @Test("symlink and hardlink targets cannot be truncated or appended to", arguments: [true, false])
    func rejectsLinkedFiles(symbolic: Bool) throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let target = directory.appending(path: "unrelated.txt")
        let link = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("untouched".utf8).write(to: target)
        if symbolic {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        } else {
            try FileManager.default.linkItem(at: target, to: link)
        }

        Log.write(Data("new run".utf8), to: link.path, truncate: true)
        Log.write(Data("later write".utf8), to: link.path)

        #expect(try String(contentsOf: target, encoding: .utf8) == "untouched")
    }

    @Test("an existing FIFO is rejected without waiting for a reader")
    func rejectsFIFO() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let file = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(mkfifo(file.path, 0o600) == 0)

        Log.write(Data("test".utf8), to: file.path, truncate: true)

        var attributes = stat()
        #expect(lstat(file.path, &attributes) == 0)
        #expect(attributes.st_mode & S_IFMT == S_IFIFO)
    }

    @Test("deleting the log recreates a private file and subsequent writes append")
    func recreatesDeletedFile() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let file = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }

        Log.write(Data("old".utf8), to: file.path)
        try FileManager.default.removeItem(at: file)
        Log.write(Data("new".utf8), to: file.path)
        Log.write(Data(" appended".utf8), to: file.path)

        #expect(try String(contentsOf: file, encoding: .utf8) == "new appended")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("error diagnostics omit descriptions, recovery text, and userInfo")
    func privateErrorDetailsAreNotLogged() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let file = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }
        let error = NSError(
            domain: "BilbyLogTests", code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "PRIVATE_DESCRIPTION_SENTINEL",
                NSLocalizedRecoverySuggestionErrorKey: "PRIVATE_RECOVERY_SENTINEL",
                "transcript": "PRIVATE_TRANSCRIPT_SENTINEL",
            ]
        )

        let message = Log.failureMessage("translation", error: error)
        Log.write(Data(message.utf8), to: file.path)

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents == "translation: FAILED — BilbyLogTests (42)")
        #expect(!contents.contains("PRIVATE_"))
    }

    @Test("an existing ACL cannot grant other users access to a private-mode log")
    func clearsAdditionalReadGrants() throws {
        let directory = URL.temporaryDirectory.appending(path: "bilby-log-\(UUID().uuidString)")
        let file = directory.appending(path: "bilby.log")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: file)
        let chmod = Process()
        chmod.executableURL = URL(filePath: "/bin/chmod")
        chmod.arguments = ["+a", "group:everyone allow read", file.path]
        try chmod.run()
        chmod.waitUntilExit()
        try #require(chmod.terminationStatus == 0)
        let original = try #require(acl_get_file(file.path, ACL_TYPE_EXTENDED))
        defer { acl_free(UnsafeMutableRawPointer(original)) }
        var entry: acl_entry_t?
        try #require(acl_get_entry(original, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == 0)

        Log.write(Data("new".utf8), to: file.path, truncate: true)

        if let current = acl_get_file(file.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(current)) }
            #expect(acl_get_entry(current, Int32(ACL_FIRST_ENTRY.rawValue), &entry) != 0)
        } else {
            // macOS can represent removal as no ACL, rather than an empty ACL.
            #expect(errno == ENOENT)
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == "new")
    }
}
