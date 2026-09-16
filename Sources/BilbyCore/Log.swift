import Foundation

/// Appends to /tmp/bilby.log.
///
/// A menu bar app has no console and no window to print into, so without this
/// every failure is invisible to everyone — including whoever is debugging it.
public enum Log {
    public static let path = "/tmp/bilby.log"

    private static let queue = DispatchQueue(label: "net.variant.bilby.log")
    private static let started = Date()

    public static func start() {
        queue.async {
            try? "".write(toFile: path, atomically: true, encoding: .utf8)
        }
        write("--- Bilby started ---")
    }

    public static func write(_ message: String) {
        let stamp = String(format: "%7.2fs", Date().timeIntervalSince(started))
        queue.async {
            let line = "\(stamp)  \(message)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
