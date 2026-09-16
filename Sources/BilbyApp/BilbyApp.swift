import AVFoundation
import AppKit
import CoreAudio
import BilbyCore
import BilbySources
import BilbyUI
import SwiftUI

@main
struct BilbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Bilby", systemImage: "captions.bubble") {
            Text(delegate.status)

            Divider()

            // Apps making sound right now. Tapping one app rather than the whole
            // machine keeps Spotify and notification dings out of the captions.
            Menu("Listen to") {
                ForEach(delegate.sources) { source in
                    Button(source.name) { delegate.listen(to: source) }
                }
                if delegate.sources.isEmpty {
                    Text("Nothing is playing").foregroundStyle(.secondary)
                }
                Divider()
                Button("Everything on this Mac") { delegate.listenToEverything() }
            }
            Button("Refresh") { delegate.refreshSources() }

            Divider()

            Button(delegate.isHidden ? "Show captions" : "Hide captions") {
                delegate.toggleCaptions()
            }
            .keyboardShortcut("c", modifiers: [.option, .command])
            Button("Stop") { delegate.stop() }

            Divider()

            Button("Play test audio") { delegate.playTestAudio() }
            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isHidden = false
    private(set) var sources: [AudioProcess] = []
    private(set) var status = "Idle"

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var running: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        panel.orderFrontRegardless()
        self.panel = panel
        refreshSources()
    }

    func refreshSources() { sources = SystemAudioTap.playing() }

    func listen(to source: AudioProcess) {
        start(from: [source.id], label: source.name)
    }

    func listenToEverything() {
        start(from: [], label: "this Mac")
    }

    func playTestAudio() {
        let file = AudioFileSource(url: URL(filePath: "/tmp/meeting.aiff"))
        start(label: "test audio") { file.buffers() }
    }

    func toggleCaptions() {
        isHidden.toggle()
        if isHidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    func stop() {
        running?.cancel()
        running = nil
        model.clear()
        status = "Idle"
    }

    private func start(from processes: [AudioObjectID], label: String) {
        let tap = SystemAudioTap()
        start(label: label) { tap.buffers(of: processes) }
    }

    private func start(
        label: String,
        audio: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) {
        stop()
        status = "Listening — \(label)"
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
