import Darwin
import Foundation

/// Appends to ~/Library/Logs/Bilby/bilby.log.
///
/// A menu bar app has no console and no window to print into, so without this
/// every failure is invisible to everyone — including whoever is debugging it.
///
/// Not /tmp, which is where this wrote until it was noticed: that directory is
/// world-readable and world-writable, the file was created 0644, and the log
/// carried every recognised sentence and every translation verbatim. So the
/// full transcript of a private meeting sat in the most readable directory on
/// the machine, for any process to read, until the next launch truncated it.
/// Nothing left the Mac, which is what the product promises — it just left the
/// app, which is not what anyone means by that promise.
///
/// Two rules keep it that way, and both matter:
///   * the file is opened without following links and made owner-only before use;
///   * nothing a person said or had translated is written into it. Lengths and
///     counts are enough to find a stall, and a transcript is not.
///
/// $BILBY_LOG_PATH redirects the whole thing, which is how check-app-portable.sh
/// reads one run's output without racing every other Bilby on the machine.
public enum Log {
    public static let path: String = {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["BILBY_LOG_PATH"], !override.isEmpty { return override }
        return defaultPath()
    }()

    /// Under the user's own Logs directory, which is theirs to read and nobody
    /// else's. Kept separate from `path` so a test can check where this lands
    /// without depending on whether this process was handed an override.
    static func defaultPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/Bilby/bilby.log")
            .path(percentEncoded: false)
    }

    private static let queue = DispatchQueue(label: "io.github.sultanovazamat.bilby.log")
    private static let started = Date()

    public static func start() {
        queue.async {
            write(Data(), to: path, truncate: true)
        }
        write("--- Bilby started ---")
    }

    public static func write(_ message: String) {
        let stamp = String(format: "%7.2fs", Date().timeIntervalSince(started))
        queue.async {
            let line = "\(stamp)  \(message)\n"
            write(Data(line.utf8), to: path)
        }
    }

    /// Use a static operation name. Error descriptions and userInfo can contain
    /// transcript text, paths, or URLs and must never be interpolated into logs.
    public static func failure(_ operation: String, error: Error) {
        write(failureMessage(operation, error: error))
    }

    static func failureMessage(_ operation: String, error: Error) -> String {
        let failure = error as NSError
        return "\(operation): FAILED — \(failure.domain) (\(failure.code))"
    }

    /// Open and validate the same descriptor that will be truncated/written.
    /// No path-based check followed by another open may touch the log target.
    static func write(_ data: Data, to path: String, truncate: Bool = false) {
        guard let (parent, name) = openParent(of: path) else { return }
        defer { close(parent) }
        // NONBLOCK avoids waiting forever on a FIFO before its type can be checked.
        let flags = O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        let descriptor = openat(parent, name, flags, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        guard let privateACL = acl_init(0) else { return }
        defer { acl_free(UnsafeMutableRawPointer(privateACL)) }

        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0,
            attributes.st_mode & S_IFMT == S_IFREG,
            attributes.st_uid == geteuid(),
            attributes.st_nlink == 1,
            fchmod(descriptor, 0o600) == 0,
            // Mode bits alone do not revoke macOS ACL read grants.
            acl_set_fd(descriptor, privateACL) == 0,
            fstat(descriptor, &attributes) == 0,
            attributes.st_mode & 0o7777 == 0o600
        else { return }
        if truncate && ftruncate(descriptor, 0) != 0 { return }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    private static func openParent(of path: String) -> (Int32, String)? {
        guard !path.isEmpty, !path.utf8.contains(0) else { return nil }
        let absolute = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        var components = absolute.split(separator: "/").map(String.init)
        guard !components.contains("."), !components.contains(".."), let name = components.popLast() else {
            return nil
        }
        // These are system-owned macOS aliases, including the standard temp
        // paths used by the portable-app check. All other symlinks are refused.
        if components.first == "tmp" || components.first == "var" { components.insert("private", at: 0) }

        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        var parent = open("/", flags)
        guard parent >= 0 else { return nil }
        for component in components {
            var next = openat(parent, component, flags)
            if next < 0 && errno == ENOENT {
                guard mkdirat(parent, component, 0o700) == 0 || errno == EEXIST else {
                    close(parent)
                    return nil
                }
                next = openat(parent, component, flags)
            }
            close(parent)
            guard next >= 0 else { return nil }
            var attributes = stat()
            guard fstat(next, &attributes) == 0,
                attributes.st_uid == geteuid() || attributes.st_uid == 0,
                attributes.st_mode & 0o022 == 0
                    || (attributes.st_uid == 0 && attributes.st_mode & S_ISVTX != 0)
            else {
                close(next)
                return nil
            }
            parent = next
        }
        return (parent, name)
    }
}
