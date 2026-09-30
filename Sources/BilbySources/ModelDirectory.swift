import CryptoKit
import Darwin
import Foundation

/// All cache operations stay anchored to no-follow directory descriptors.
/// A renamed parent or substituted symlink cannot redirect a write elsewhere.
final class ModelDirectory: @unchecked Sendable {
    let descriptor: Int32

    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    static func openRoot(_ url: URL) throws -> ModelDirectory {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw SpeechModelError.unsafeCache }
        let descriptor = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw SpeechModelError.unsafeCache }
        var directory = ModelDirectory(descriptor)
        var components = url.path.split(separator: "/").map(String.init)
        // macOS owns these two aliases; arbitrary user-created symlinks fail.
        if components.first == "var" || components.first == "tmp" { components.insert("private", at: 0) }
        for component in components {
            guard component != ".", component != ".." else { throw SpeechModelError.unsafeCache }
            directory = try directory.child(component, create: true, privateMode: false)
        }
        try directory.makePrivate()
        return directory
    }

    func child(_ name: String, create: Bool, privateMode: Bool = true) throws -> ModelDirectory {
        if create, mkdirat(descriptor, name, 0o700) != 0, errno != EEXIST { throw SpeechModelError.unsafeCache }
        let next = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard next >= 0 else { throw SpeechModelError.unsafeCache }
        let directory = ModelDirectory(next)
        if privateMode { try directory.makePrivate() }
        return directory
    }

    private func makePrivate() throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid()
        else { throw SpeechModelError.unsafeCache }
        try Self.privatePermissions(descriptor, mode: 0o700)
    }

    static func privatePermissions(_ descriptor: Int32, mode: mode_t) throws {
        guard let acl = acl_init(0) else { throw SpeechModelError.unsafeCache }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard fchmod(descriptor, mode) == 0, acl_set_fd(descriptor, acl) == 0 else {
            throw SpeechModelError.unsafeCache
        }
    }

    func acquireLock() async throws -> ModelCacheLease {
        let opened = openat(descriptor, ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard opened >= 0 else { throw SpeechModelError.unsafeCache }
        let lease = ModelCacheLease(opened)
        var info = stat()
        guard fstat(opened, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_uid == getuid(), info.st_nlink == 1
        else { throw SpeechModelError.unsafeCache }
        try Self.privatePermissions(opened, mode: 0o600)
        while flock(opened, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK else { throw SpeechModelError.unsafeCache }
            try await Task.sleep(for: .milliseconds(100))
        }
        return lease
    }

    func descendant(_ components: [String], create: Bool) throws -> ModelDirectory {
        var directory = self
        for component in components { directory = try directory.child(component, create: create) }
        return directory
    }

    func checkInventory(files: Set<String>, directories: Set<String>, prefix: String = "") throws {
        let copied = dup(descriptor)
        guard copied >= 0 else { throw SpeechModelError.unsafeCache }
        guard let listing = fdopendir(copied) else {
            close(copied)
            throw SpeechModelError.unsafeCache
        }
        defer { closedir(listing) }
        rewinddir(listing)
        while let entry = readdir(listing) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let path = prefix + name
            var info = stat()
            guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw SpeechModelError.unsafeCache }
            let type = info.st_mode & S_IFMT
            // A killed download can leave a staging file; unlinking it never follows it.
            if name.hasPrefix(".download-"), type == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1 {
                remove(name)
            } else if directories.contains(path), type == S_IFDIR {
                try child(name, create: false).checkInventory(
                    files: files, directories: directories, prefix: path + "/")
            } else if !files.contains(path) || type != S_IFREG || info.st_uid != getuid() || info.st_nlink != 1 {
                throw SpeechModelError.unsafeCache
            }
        }
    }

    func matches(_ name: String, file: SpeechModelManifest.File) throws -> Bool {
        let opened = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if opened < 0, errno == ENOENT { return false }
        guard opened >= 0 else { throw SpeechModelError.unsafeCache }
        defer { close(opened) }
        var before = stat()
        guard fstat(opened, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
            before.st_uid == getuid(), before.st_nlink == 1
        else { throw SpeechModelError.unsafeCache }
        try Self.privatePermissions(opened, mode: 0o600)
        if before.st_size != file.size { return false }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = read(opened, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw SpeechModelError.unsafeCache }
            if count == 0 { break }
            total += Int64(count)
            guard total <= file.size else { return false }
            hash.update(data: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(opened, &after) == 0, before.st_size == after.st_size,
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
            before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
        else { throw SpeechModelError.unsafeCache }
        return total == file.size && hash.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    func sink(_ name: String, file: SpeechModelManifest.File) throws -> ModelFileSink {
        let opened = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard opened >= 0 else { throw SpeechModelError.unsafeCache }
        do { try Self.privatePermissions(opened, mode: 0o600) } catch {
            close(opened)
            remove(name)
            throw error
        }
        return ModelFileSink(descriptor: opened, file: file)
    }

    func install(_ temporary: String, as name: String) throws {
        guard renameat(descriptor, temporary, descriptor, name) == 0 else { throw SpeechModelError.unsafeCache }
    }

    func remove(_ name: String) { _ = unlinkat(descriptor, name, 0) }
}

final class ModelCacheLease: @unchecked Sendable {
    private let descriptor: Int32
    init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
    func release() { _ = flock(descriptor, LOCK_UN) }
}

final class ModelFileSink: @unchecked Sendable {
    private let descriptor: Int32
    private let file: SpeechModelManifest.File
    private let lock = NSLock()
    private var size: Int64 = 0
    private var hash = SHA256()

    init(descriptor: Int32, file: SpeechModelManifest.File) {
        self.descriptor = descriptor
        self.file = file
    }
    deinit { close(descriptor) }

    func append(_ data: Data) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        guard Int64(data.count) <= file.size - size else { throw SpeechModelError.integrity }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = write(descriptor, raw.baseAddress! + offset, raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw SpeechModelError.unsafeCache }
                offset += count
            }
        }
        hash.update(data: data)
        size += Int64(data.count)
        return size
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        guard size == file.size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256,
            fsync(descriptor) == 0
        else { throw SpeechModelError.integrity }
    }
}
