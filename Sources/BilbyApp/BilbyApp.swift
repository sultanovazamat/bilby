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
            Menu("Listen to") {
                ForEach(delegate.sources) { source in
                    Button {
                        delegate.listen(to: source)
                    } label: {
                        // The icon is how you recognise an app; the name is how
                        // you confirm it.
                        if let icon = source.icon { Image(nsImage: icon) }
                        Text(source.isPlaying ? "\(source.name) — playing" : source.name)
                    }
                }
                if delegate.sources.isEmpty {
                    Text("No apps that play audio")
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

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isListening = false
    private(set) var isHidden = false
    private(set) var sources: [AudioApp] = []
    private(set) var diagnosticLine = "Idle"
    @ObservationIgnored private var isWarm = false

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let diagnostics = Diagnostics()

    /// Names what pressing it will do, the way a player does.
    var playTitle: String {
        if isListening { return "Pause" }
        if let first = sources.first(where: \.isPlaying) ?? sources.first {
            return "Listen to \(first.name)"
        }
        return "No apps that play audio"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.start()
        Log.write("app: launched, build \(Bundle.main.bundlePath)")
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        self.panel = panel
        refreshSources()
    }

    /// Loads the chosen engine's models in the background, so pressing play
    /// opens the audio tap immediately instead of fifty seconds later.
    private func warmUp() {
        let transcriber = UnifiedTranscriber(onAudio: { [diagnostics] in diagnostics.audio($0) })
        Task.detached { await transcriber.warmUp() }
    }

    /// Opening the menu means the user is about to act, which is the moment
    /// worth spending on. Warming up at launch cost 14 seconds of CPU and
    /// 400 MB every login, before anyone had asked for anything.
    func menuOpened() {
        refreshSources()
        guard !isWarm else { return }
        isWarm = true
        warmUp()
    }

    func refreshSources() {
        diagnosticLine = isListening ? diagnostics.summary : "Idle"
        let found = SystemAudioTap.candidates()
        if found.map(\.id) != sources.map(\.id) {
            Log.write("app: sources — \(found.map { "\($0.name)\($0.isPlaying ? " ▶︎" : "")" })")
        }
        sources = found
    }

    func togglePlayback() {
        if isListening { stop() } else if let first = sources.first(where: \.isPlaying) ?? sources.first { listen(to: first) }
    }

    func listen(to app: AudioApp) {
        Log.write("app: listening to \(app.name) — \(app.processes.count) audio processes")
        let counter = diagnostics
        let tap = SystemAudioTap(onFailure: { counter.failed($0) })
        let processes = app.processes
        start { tap.buffers(of: processes) }
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
            let transcriber = UnifiedTranscriber(onAudio: { counter.audio($0) })
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
