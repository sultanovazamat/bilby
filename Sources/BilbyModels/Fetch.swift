import FluidAudio
import Foundation

/// Downloads the streaming models ahead of time.
///
/// The app can do this on first launch, but a caption bar that spends its
/// first three minutes downloading is a bad introduction — and in a terminal
/// the progress is visible, which it is not inside a menu bar app.
@main
struct Fetch {
    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        let manager = StreamingEouAsrManager(chunkSize: .ms160)
        print("downloading Parakeet EOU 160 ms …")
        let started = ContinuousClock.now
        do {
            try await manager.loadModels()
            print("ready in \(ContinuousClock.now - started)")
        } catch {
            print("FAILED — \(error)")
            exit(1)
        }
    }
}
