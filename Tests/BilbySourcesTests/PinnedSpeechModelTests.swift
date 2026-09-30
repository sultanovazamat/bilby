import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing

@testable import BilbySources

@Suite struct PinnedSpeechModelTests {
    private let payload = Data("verified model fixture".utf8)

    private func fixture(path: String = "model.mlmodelc/coremldata.bin") throws -> (URL, SpeechModelManifest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bilby-model-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (
            root,
            SpeechModelManifest(
                repository: "FluidInference/parakeet-unified-en-0.6b-coreml",
                revision: String(repeating: "a", count: 40),
                files: [.init(path: path, size: Int64(payload.count), sha256: digest(payload))])
        )
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func downloadsAndRevalidatesWithoutAnotherRequest() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = payload
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { url, size, receive in
            #expect(url.scheme == "https")
            #expect(url.path.contains("/resolve/\(manifest.revision)/"))
            #expect(size == data.count)
            try receive(data)
        }
        let directory = try await model.prepare()
        #expect(try Data(contentsOf: directory.appendingPathComponent(manifest.files[0].path)) == payload)
        let offline = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, _ in
            Issue.record("A verified cache must not make a request")
            throw CancellationError()
        }
        #expect(try await offline.prepare() == directory)
    }

    @Test(arguments: ["", "../escape.json", "/absolute.json", "a/../escape.json", "a//b", "a/./b", "a%2fb"])
    func rejectsInvalidManifestPaths(path: String) async throws {
        let (root, manifest) = try fixture(path: path)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, _ in
            Issue.record("An invalid path must fail before requesting bytes")
        }
        await #expect(throws: Error.self) { try await model.prepare() }
    }

    @Test func refusesSameSizeCorruptionAndCleansStaging() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let corrupt = Data(repeating: 120, count: payload.count)
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in
            try receive(corrupt)
        }
        await #expect(throws: Error.self) { try await model.prepare() }
        let paths = FileManager.default.subpaths(atPath: root.path) ?? []
        #expect(!paths.contains(where: { $0.contains(".download-") || $0.hasSuffix("coremldata.bin") }))
    }

    @Test func stopsAnOversizedStreamBeforeWritingExtraBytes() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = payload
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in
            try receive(data)
            try receive(Data([0]))
            Issue.record("The excess chunk must throw immediately")
        }
        await #expect(throws: Error.self) { try await model.prepare() }
    }

    @Test func rejectsSymlinksAndUnexpectedFiles() async throws {
        for useSymlink in [false, true] {
            let (root, manifest) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent(manifest.revision)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if useSymlink {
                try FileManager.default.createSymbolicLink(
                    at: directory.appendingPathComponent("model.mlmodelc"), withDestinationURL: root)
            } else {
                try Data([0]).write(to: directory.appendingPathComponent("unexpected.json"))
            }
            let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, _ in
                Issue.record("Unsafe cache contents must fail before downloading")
            }
            await #expect(throws: Error.self) { try await model.prepare() }
        }
    }

    @Test func verifiesCachedBytesAgainOnEveryPreparation() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = payload
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in try receive(data) }
        let directory = try await model.prepare()
        try Data(repeating: 120, count: payload.count).write(
            to: directory.appendingPathComponent(manifest.files[0].path))
        let offline = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, _ in throw CancellationError() }
        await #expect(throws: Error.self) { try await offline.prepare() }
    }

    @Test func shippedManifestResolvesAndPinsEveryFile() throws {
        let manifest = try PinnedSpeechModel.bundledManifest()
        try manifest.validate()
        #expect(manifest.files.count == 13)
        #expect(manifest.revision == "d32e972dd4315f1dc3f6be28fb2aab0ab3e80358")
    }

    @Test func downloadedFilesArePrivateAndHardLinksAreRejected() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = payload
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in try receive(data) }
        let directory = try await model.prepare()
        let file = directory.appendingPathComponent(manifest.files[0].path)
        let info = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((info[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let directoryInfo = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((directoryInfo[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("hard-link"))
        await #expect(throws: Error.self) { try await model.prepare() }
    }

    @Test func cancellationRemovesPartiallyWrittenFiles() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = payload
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in
            try receive(data.prefix(3))
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await model.prepare() }
        #expect(!(FileManager.default.subpaths(atPath: root.path) ?? []).contains(where: { $0.contains(".download-") }))
    }

    @Test func cancellingTheCallerStopsItsDownload() async throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let model = PinnedSpeechModel(manifest: manifest, cacheRoot: root) { _, _, receive in
            try receive(Data([0]))
            signal.yield()
            try await Task.sleep(for: .seconds(60))
            Issue.record("Cancellation must end the download")
        }
        let task = Task { try await model.prepare() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!(FileManager.default.subpaths(atPath: root.path) ?? []).contains(where: { $0.contains(".download-") }))
    }

    @Test func aReplacedParentCannotRedirectAnOpenDirectory() throws {
        let (root, manifest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try ModelDirectory.openRoot(root)
        let held = try base.child("held", create: true)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("held"), to: root.appendingPathComponent("original"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("held"), withDestinationURL: outside)
        let sink = try held.sink(".download-fixture", file: manifest.files[0])
        _ = try sink.append(payload)
        try sink.finish()
        try held.install(".download-fixture", as: "verified.bin")
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("verified.bin").path))
        #expect(try Data(contentsOf: root.appendingPathComponent("original/verified.bin")) == payload)
    }

    @Test func refusesRedirectsOutsideHTTPSModelHosts() {
        for url in [
            "http://huggingface.co/model", "https://huggingface.co.attacker.example/model",
            "https://user:password@huggingface.co/model", "https://huggingface.co:1234/model",
        ] {
            #expect(!SpeechModelDownload.allowed(URL(string: url)!))
        }
        #expect(SpeechModelDownload.allowed(URL(string: "https://cas-bridge.xethub.hf.co/model")!))
    }

    @Test func rejectsOversizedResponseHeadersBeforeReceivingBody() throws {
        let url = URL(string: "https://huggingface.co/model")!
        let download = SpeechModelDownload(expected: 4) { _ in Issue.record("No body should be accepted") }
        let response = try #require(
            HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "1000000000"]))
        let disposition = Mutex<URLSession.ResponseDisposition?>(nil)
        let task = URLSession.shared.dataTask(with: url)
        download.urlSession(URLSession.shared, dataTask: task, didReceive: response) { decision in
            disposition.withLock { $0 = decision }
        }
        #expect(disposition.withLock { $0 } == .cancel)
    }
}
