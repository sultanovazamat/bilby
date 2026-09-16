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

        started = ContinuousClock.now
        print("Canary 1B v2 (int4): loading…")
        let canary: CanaryModels
        do {
            canary = try await CanaryModels.downloadAndLoad()
            print("Canary: ready in \(ContinuousClock.now - started)")
        } catch {
            print("Canary: FAILED — \(error)")
            return
        }

        // Canary's prompt carries the task: source language, target language,
        // punctuation. Translating instead of transcribing is one token.
        let vocabulary = canary.tokenizer.vocabulary
        let wanted = Set(["en", "ru", "uk", "de", "fr", "es", "pl", "tr"].map { "<|\($0)|>" })
        print("\nlanguage tokens in the vocabulary:")
        for (id, token) in vocabulary.sorted(by: { $0.key < $1.key }) where wanted.contains(token) {
            print("  \(token) = \(id)")
        }
        print("\nevery task-ish special token:")
        for (id, token) in vocabulary.sorted(by: { $0.key < $1.key })
        where token.hasPrefix("<|") && token.count <= 14 {
            print("  \(id)\t\(token)")
        }
    }
}
