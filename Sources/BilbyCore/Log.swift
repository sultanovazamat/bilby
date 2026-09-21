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
///   * the file is created 0600, under the user's own Logs directory;
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

    private static let queue = DispatchQueue(label: "net.variant.bilby.log")
    private static let started = Date()

    public static func start() {
        queue.async {
            create()
            // Truncated in place rather than replaced: an atomic write makes a
            // new file with the default 0644, which is the thing being avoided.
            if let handle = FileHandle(forWritingAtPath: path) {
                try? handle.truncate(atOffset: 0)
                try? handle.close()
            }
        }
        write("--- Bilby started ---")
    }

    public static func write(_ message: String) {
        let stamp = String(format: "%7.2fs", Date().timeIntervalSince(started))
        queue.async {
            create()
            let line = "\(stamp)  \(message)\n"
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }

    /// Called on the log's own queue before every write, so a log that is
    /// deleted mid-session comes back with the right permissions rather than
    /// coming back world-readable.
    static func create(at path: String = Log.path) {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: path) else { return }
        try? manager.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 0600 at creation, not a chmod afterwards: the gap between the two
        // would be a window where a meeting's log is readable by anyone.
        manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
}
