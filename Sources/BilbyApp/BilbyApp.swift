import AppKit
import BilbyCore
import BilbySources
import BilbyUI
import SwiftUI

@main
struct BilbyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Bilby", systemImage: "captions.bubble") {
            // The panel is click-through, so every control lives here.
            Button(delegate.isHidden ? "Show captions" : "Hide captions") {
                delegate.toggleCaptions()
            }
            .keyboardShortcut("c", modifiers: [.option, .command])

            Divider()

            Button("Play test audio") { delegate.playTestAudio() }
            Button("Stop") { delegate.stop() }

            Divider()

            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isHidden = false

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var running: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggleCaptions() {
        isHidden.toggle()
        if isHidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    func stop() {
        running?.cancel()
        running = nil
        model.clear()
    }

    /// Everything the live tap will do, minus the tap.
    func playTestAudio() {
        stop()
        running = Task {
            let file = AudioFileSource(url: URL(filePath: "/tmp/meeting.aiff"))
            let utterances = AppleTranscriber().utterances(from: { file.buffers() })
            let session = CaptionSession(translator: AppleTranslator(), target: Language("ru"))
            for await event in session.events(from: utterances) {
                model.apply(event)
                panel?.fitContent()
            }
        }
    }
}
