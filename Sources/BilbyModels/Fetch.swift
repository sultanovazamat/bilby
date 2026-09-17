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

        // int4 failed to compile for the Neural Engine:
        //   MILCompilerForANE error … ANECCompile() FAILED
        // fp16 is the ANE-targeted export per FluidAudio's own notes, and int8
        // is CPU-only. Try each and report which survives.
        for precision in [CanaryPrecision.fp16, .int8, .int4] {
            started = ContinuousClock.now
            print("\nCanary \(precision.rawValue): loading…")
            do {
                let models = try await CanaryModels.downloadAndLoad(precision: precision)
                print("Canary \(precision.rawValue): ready in \(ContinuousClock.now - started)")
                let wanted = Set(["en", "ru", "uk", "de", "fr"].map { "<|\($0)|>" })
                let found = models.tokenizer.vocabulary
                    .filter { wanted.contains($0.value) }
                    .sorted { $0.key < $1.key }
                print("  language tokens: \(found.map { "\($0.value)=\($0.key)" }.joined(separator: ", "))")
                break
            } catch {
                print("Canary \(precision.rawValue): FAILED — \(error)")
            }
        }
    }
}
