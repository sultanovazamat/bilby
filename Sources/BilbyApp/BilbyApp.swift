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
            Button("Play test audio") { delegate.playTestAudio() }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CaptionModel()
    private var panel: CaptionPanel?
    private var running: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Everything the live tap will do, minus the tap.
    func playTestAudio() {
        running?.cancel()
        running = Task {
            let file = AudioFileSource(url: URL(filePath: "/tmp/meeting.aiff"))
            let utterances = AppleTranscriber().utterances(from: { file.buffers() })
            let session = CaptionSession(
                translator: AppleTranslator(),
                target: Language("ru")
            )
            for await event in session.events(from: utterances) {
                model.apply(event)
                panel?.placeAtBottom()
            }
        }
    }
}
