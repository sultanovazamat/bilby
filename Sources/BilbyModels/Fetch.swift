import AVFoundation
import FluidAudio
import Foundation

/// Downloads the streaming models ahead of time, and probes Canary's prompt.
///
/// A caption bar that spends its first minutes downloading is a bad
/// introduction, and in a menu bar app the progress has nowhere to show.
@main
struct Fetch {
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)

        var started = ContinuousClock.now
        do {
            print("Parakeet EOU 160 ms: loading…")
            try await StreamingEouAsrManager(chunkSize: .ms160).loadModels()
            print("Parakeet EOU 160 ms: ready in \(ContinuousClock.now - started)")
        } catch {
            print("Parakeet EOU: FAILED — \(error)")
        }

        started = ContinuousClock.now
        do {
            print("Parakeet Unified: loading…")
            try await StreamingUnifiedAsrManager().loadModels()
            print("Parakeet Unified: ready in \(ContinuousClock.now - started)")
        } catch {
            print("Parakeet Unified: FAILED — \(error)")
        }

        // int4 is the only precision on disk: the downloader saw a complete
        // directory and never fetched fp16 or int8. Retry it first — the ANE
        // compiler failed while the machine was deep in swap, which may have
        // been the whole story — then force-download fp16, the ANE-targeted
        // export, if it fails again.
        started = ContinuousClock.now
        print("\nCanary int4 (already on disk): loading…")
        do {
            let models = try await CanaryModels.downloadAndLoad(precision: .int4)
            print("Canary int4: ready in \(ContinuousClock.now - started)")
            report(models)
            return
        } catch {
            print("Canary int4: FAILED — \(error)")
        }

        started = ContinuousClock.now
        print("\nCanary fp16 (forcing a fresh download): loading…")
        do {
            let directory = try await CanaryModels.download(precision: .fp16, force: true)
            let models = try CanaryModels.load(from: directory, precision: .fp16)
            print("Canary fp16: ready in \(ContinuousClock.now - started)")
            report(models)
        } catch {
            print("Canary fp16: FAILED — \(error)")
        }
    }

    /// Canary's prompt carries the task. Swapping the target-language token is
    /// the difference between transcribing English and translating to Russian.
    private static func report(_ models: CanaryModels) {
        let wanted = Set(["en", "ru", "uk", "de", "fr"].map { "<|\($0)|>" })
        let found = models.tokenizer.vocabulary
            .filter { wanted.contains($0.value) }
            .sorted { $0.key < $1.key }
        print("  language tokens: \(found.map { "\($0.value)=\($0.key)" }.joined(separator: ", "))")
    }
}
