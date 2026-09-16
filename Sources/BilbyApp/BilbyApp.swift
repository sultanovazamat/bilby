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

            if delegate.isListening {
                Button(delegate.isHidden ? "Show captions" : "Hide captions") {
                    delegate.toggleCaptions()
                }
                .keyboardShortcut("c", modifiers: [.option, .command])
            }

            Divider()

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

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isListening = false
    private(set) var isHidden = false
    private(set) var sources: [AudioProcess] = []

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var refresher: Timer?

    /// Names what pressing it will do, the way a player does.
    var playTitle: String {
        if isListening { return "Pause" }
        if let first = sources.first { return "Listen to \(first.name)" }
        return "Nothing is playing"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        self.panel = panel
        refreshSources()
        // Keeps the menu honest without the user pressing Refresh.
        refresher = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in self.refreshSources() }
        }
    }

    func refreshSources() { sources = SystemAudioTap.playing() }

    func togglePlayback() {
        if isListening { stop() } else if let first = sources.first { listen(to: first) }
    }

    func listen(to source: AudioProcess) {
        let tap = SystemAudioTap()
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
        isListening = true
        isHidden = false
        panel?.orderFrontRegardless()
        running = Task {
            let utterances = AppleTranscriber().utterances(from: audio)
            let session = CaptionSession(translator: AppleTranslator(), target: Language("ru"))
            for await event in session.events(from: utterances) {
                model.apply(event)
                panel?.fitContent()
            }
        }
    }
}
