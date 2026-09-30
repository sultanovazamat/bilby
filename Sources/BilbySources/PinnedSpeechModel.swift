import CryptoKit
import Foundation

enum SpeechModelError: Error, CustomStringConvertible {
    case manifest, unsafeCache, integrity, download

    var description: String {
        switch self {
        case .manifest: "The speech model manifest is missing or invalid."
        case .unsafeCache: "The speech model cache has unsafe permissions or unexpected files."
        case .integrity: "The speech model failed integrity verification."
        case .download: "The speech model download failed. Check your internet connection and try again."
        }
    }
}

struct SpeechModelManifest: Decodable, Sendable {
    struct File: Decodable, Sendable {
        let path: String
        let size: Int64
        let sha256: String
    }

    let repository: String
    let revision: String
    let files: [File]

    func validate() throws {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        guard repository == "FluidInference/parakeet-unified-en-0.6b-coreml",
            revision.count == 40, revision.unicodeScalars.allSatisfy(hex.contains),
            !files.isEmpty, files.count <= 100,
            Set(files.map(\.path)).count == files.count
        else { throw SpeechModelError.manifest }
        for file in files {
            guard Self.validPath(file.path), file.size > 0, file.size <= 700_000_000,
                file.sha256.count == 64, file.sha256.unicodeScalars.allSatisfy(hex.contains)
            else { throw SpeechModelError.manifest }
        }
        guard files.reduce(Int64(0), { $0 + $1.size }) <= 800_000_000,
            Set(files.map(\.path)).isDisjoint(with: directories)
        else { throw SpeechModelError.manifest }
    }

    private static func validPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 512 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && !part.hasPrefix(".download-")
                && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    var directories: Set<String> {
        Set(
            files.flatMap { file in
                let parts = file.path.split(separator: "/")
                return parts.indices.dropFirst().map { parts.prefix($0).joined(separator: "/") }
            })
    }
}

/// The only speech-model download path in Bilby. The shipped manifest pins
/// every byte; FluidAudio only receives an already verified local directory.
actor PinnedSpeechModel {
    typealias Receive = @Sendable (Data) throws -> Void
    typealias Fetch = @Sendable (URL, Int64, @escaping Receive) async throws -> Void

    static let shared = PinnedSpeechModel()
    private let manifest: SpeechModelManifest?
    private let cacheRoot: URL
    private let fetch: Fetch
    private var preparation: Task<URL, Error>?

    init(
        manifest: SpeechModelManifest? = nil,
        cacheRoot: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bilby/SpeechModels", isDirectory: true),
        fetch: @escaping Fetch = SpeechModelDownload.fetch
    ) {
        self.manifest = manifest
        self.cacheRoot = cacheRoot
        self.fetch = fetch
    }

    func prepare(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        if let preparation {
            return try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: {
                preparation.cancel()
            }
        }
        let manifest = try manifest ?? Self.bundledManifest()
        try manifest.validate()
        let cacheRoot = cacheRoot
        let fetch = fetch
        let task = Task.detached {
            try await Self.prepare(manifest, at: cacheRoot, fetch: fetch, progress: progress)
        }
        preparation = task
        defer { preparation = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func prepare(
        _ manifest: SpeechModelManifest, at root: URL, fetch: Fetch,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        let base = try ModelDirectory.openRoot(root)
        let lease = try await base.acquireLock()
        defer { lease.release() }
        let directory = try base.child(manifest.revision, create: true)
        try directory.checkInventory(files: Set(manifest.files.map(\.path)), directories: manifest.directories)
        let total = manifest.files.reduce(Int64(0)) { $0 + $1.size }
        var completed: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let parts = file.path.split(separator: "/").map(String.init)
            let parent = try directory.descendant(Array(parts.dropLast()), create: true)
            let name = parts.last!
            if try !parent.matches(name, file: file) {
                let temporary = ".download-\(UUID().uuidString)"
                let sink = try parent.sink(temporary, file: file)
                defer { parent.remove(temporary) }
                let url = URL(
                    string: "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(file.path)")!
                let prior = completed
                try await fetch(url, file.size) { chunk in
                    let received = try sink.append(chunk)
                    progress(Double(prior + received) / Double(total))
                }
                try Task.checkCancellation()
                try sink.finish()
                try parent.install(temporary, as: name)
            }
            completed += file.size
            progress(Double(completed) / Double(total))
        }
        // Check the entire directory again before CoreML sees any pathname.
        try directory.checkInventory(files: Set(manifest.files.map(\.path)), directories: manifest.directories)
        for file in manifest.files {
            let parts = file.path.split(separator: "/").map(String.init)
            let parent = try directory.descendant(Array(parts.dropLast()), create: false)
            guard try parent.matches(parts.last!, file: file) else { throw SpeechModelError.integrity }
        }
        return root.appendingPathComponent(manifest.revision, isDirectory: true)
    }

    private final class Marker {}

    /// SwiftPM's generated Bundle.module embeds a build-directory fallback.
    /// Resolve the copied resource bundle explicitly for a portable .app.
    static func bundledManifest() throws -> SpeechModelManifest {
        // A packaged app must not fall back to a sidecar outside its signed
        // bundle if its own manifest is absent. Bare tools and tests keep
        // SwiftPM's adjacent-bundle layout.
        let candidates: [URL?] =
            if Bundle.main.bundleURL.pathExtension == "app" {
                [Bundle.main.resourceURL]
            } else {
                [Bundle.main.bundleURL, Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()]
            }
        for directory in candidates.compactMap({ $0 }) {
            let bundleURL = directory.appendingPathComponent("Bilby_BilbySources.bundle")
            if let bundle = Bundle(url: bundleURL),
                let url = bundle.url(forResource: "speech-model", withExtension: "json")
            {
                return try JSONDecoder().decode(SpeechModelManifest.self, from: Data(contentsOf: url))
            }
        }
        throw SpeechModelError.manifest
    }
}
