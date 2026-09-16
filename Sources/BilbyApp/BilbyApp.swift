import AVFoundation
import AppKit
import BilbyCore
import BilbySources
import BilbyUI
import CoreAudio
import SwiftUI

@main
struct BilbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The icon is the state: a bubble when idle, a waveform when listening.
        MenuBarExtra("Bilby", systemImage: delegate.isListening ? "waveform" : "captions.bubble") {
            // One obvious control, like a player. It picks the app that is
            // making sound, so the common case needs no decision at all.
            Button(delegate.playTitle) { delegate.togglePlayback() }
                .keyboardShortcut("p")

            // Never leave the user staring at an empty bar wondering.
            Text(delegate.diagnosticLine)

            if delegate.isListening {
                Button(delegate.isHidden ? "Show captions" : "Hide captions") {
                    delegate.toggleCaptions()
                }
                .keyboardShortcut("c", modifiers: [.option, .command])
            }

            Divider()

            // Two recognisers, switchable on a live call, because the only
            // honest comparison is the same audio through both.
            Menu("Engine — \(delegate.engine.name)") {
                ForEach(Engine.allCases, id: \.self) { engine in
                    Button(engine.name) { delegate.use(engine) }
                }
            }

            Menu("Listen to") {
                ForEach(delegate.sources) { source in
                    Button(source.name) { delegate.listen(to: source) }
                }
                if delegate.sources.isEmpty {
                    Text("Nothing is playing")
                }
                Divider()
                Button("Refresh") { delegate.refreshSources() }
                Button("Test audio file") { delegate.playTestAudio() }
            }

            Divider()

            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

enum Engine: String, CaseIterable, Sendable {
    case apple, parakeet, unified

    var name: String {
        switch self {
        case .apple: "Apple — 3.6s bursts, punctuated"
        case .parakeet: "Parakeet EOU — 160ms, no punctuation"
        case .unified: "Parakeet Unified — ~1s, punctuated"
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var engine: Engine = .unified
    private(set) var isListening = false
    private(set) var isHidden = false
    private(set) var sources: [AudioProcess] = []
    private(set) var diagnosticLine = "Idle"

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var refresher: Timer?
    @ObservationIgnored private let diagnostics = Diagnostics()

    /// Names what pressing it will do, the way a player does.
    var playTitle: String {
        if isListening { return "Pause" }
        if let first = sources.first { return "Listen to \(first.name)" }
        return "Nothing is playing"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.start()
        Log.write("app: launched, build \(Bundle.main.bundlePath)")
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        self.panel = panel
        refreshSources()
        warmUp(engine)
        // Keeps the menu honest without the user pressing Refresh.
        refresher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.refreshSources()
                self.diagnosticLine = self.isListening ? self.diagnostics.summary : "Idle"
            }
        }
    }

    func use(_ engine: Engine) {
        let wasListening = isListening
        self.engine = engine
        Log.write("app: engine — \(engine.rawValue)")
        stop()
        warmUp(engine)
        if wasListening, let first = sources.first { listen(to: first) }
    }

    /// Loads the chosen engine's models in the background, so pressing play
    /// opens the audio tap immediately instead of fifty seconds later.
    private func warmUp(_ engine: Engine) {
        let transcriber = Self.transcriber(for: engine, counting: diagnostics)
        Task.detached { await transcriber.warmUp() }
    }

    static func transcriber(for engine: Engine, counting diagnostics: Diagnostics) -> any AudioTranscribing {
        switch engine {
        case .apple: AppleTranscriber(onAudio: { diagnostics.audio($0) })
        case .parakeet: ParakeetTranscriber(onAudio: { diagnostics.audio($0) })
        case .unified: UnifiedTranscriber(onAudio: { diagnostics.audio($0) })
        }
    }

    func refreshSources() {
        let found = SystemAudioTap.playing()
        if found.map(\.bundleID) != sources.map(\.bundleID) {
            Log.write("app: playing — \(found.map { "\($0.name) [\($0.bundleID)] pid \($0.pid)" })")
        }
        sources = found
    }

    func togglePlayback() {
        if isListening { stop() } else if let first = sources.first { listen(to: first) }
    }

    func listen(to source: AudioProcess) {
        Log.write("app: listening to \(source.name) [\(source.bundleID)] object \(source.id)")
        let counter = diagnostics
        let tap = SystemAudioTap(onFailure: { counter.failed($0) })
        let id = source.id
        start { tap.buffers(of: [id]) }
    }

    func playTestAudio() {
        let file = AudioFileSource(url: URL(filePath: "/tmp/meeting.aiff"))
        start { file.buffers() }
    }

    func toggleCaptions() {
        isHidden.toggle()
        if isHidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    func stop() {
        running?.cancel()
        running = nil
        isListening = false
        model.clear()
        panel?.orderOut(nil)
    }

    private func start(audio: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>) {
        stop()
        diagnostics.reset()
        isListening = true
        isHidden = false
        panel?.orderFrontRegardless()

        let counter = diagnostics
        let chosen = engine
        running = Task {
            // Wall clock against the audio clock: `line.at` is when the words
            // were spoken, so the difference is what the user actually waits.
            let started = ContinuousClock.now
            func lag(_ spokenAt: Duration) -> String {
                let elapsed = ContinuousClock.now - started
                let seconds = Double((elapsed - spokenAt).components.seconds)
                    + Double((elapsed - spokenAt).components.attoseconds) / 1e18
                return String(format: "%.2fs", seconds)
            }
            let transcriber = Self.transcriber(for: chosen, counting: counter)
            let utterances = transcriber.utterances(from: audio)
            var firstWords: String?
            _ = firstWords
            let session = CaptionSession(translator: AppleTranslator(), target: Language("ru"))
            for await event in session.events(from: utterances) {
                switch event {
                case .live(let text):
                    if !text.isEmpty, firstWords == nil { firstWords = text }
                    diagnostics.heardSomething()
                case .line(let line):
                    Log.write("lag \(lag(line.at)) to line — \(line.source)")
                    diagnostics.committedLine()
                case .draft(let text):
                    Log.write("draft — \(text)")
                case .translated(let id, let text):
                    let spokenAt = model.lines.first { $0.id == id }?.at ?? .zero
                    Log.write("lag \(lag(spokenAt)) to translation — \(text)")
                }
                model.apply(event)
                panel?.fitContent()
            }
        }
    }
}
