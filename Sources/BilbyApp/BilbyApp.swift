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
        MenuBarExtra {
            // Enumerating Core Audio processes is not free, and warming the
            // model costs seconds. Both happen when the menu opens — the only
            // moment the list has to be right and the user is about to act.
            Color.clear.frame(height: 0).onAppear { delegate.menuOpened() }

            Button(delegate.playTitle) { delegate.togglePlayback() }
                .keyboardShortcut("p")

            // Only speak up when something is wrong. A running app should not
            // narrate itself.
            if let problem = delegate.problem { Text(problem) }

            Divider()

            Menu("Listen to") {
                ForEach(delegate.sources) { source in
                    Button {
                        delegate.listen(to: source)
                    } label: {
                        if let icon = source.icon { Image(nsImage: icon) }
                        Text(source.isPlaying ? "\(source.name) — playing" : source.name)
                    }
                }
                if delegate.sources.isEmpty { Text("No apps have played audio yet") }
            }

            Menu("Translate to") {
                ForEach(delegate.languages) { language in
                    Button(language.isInstalled ? language.name : "\(language.name) — download") {
                        delegate.translate(into: language)
                    }
                }
                if delegate.languages.isEmpty { Text("Loading…") }
            }

            Divider()

            Button("Setup…") { delegate.showSetup() }
            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: BilbyMark.menuBarImage())
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isListening = false
    private(set) var isHidden = false
    private(set) var sources: [AudioApp] = []
    private(set) var languages: [Languages.Entry] = []
    /// Nil until the user has chosen one; setup asks before anything can run.
    private(set) var target: Language? = UserDefaults.standard.string(forKey: "targetLanguage").map(Language.init)
    /// How far the recogniser is. Drives the bar's status line and the
    /// last setup page.
    private(set) var readiness: Readiness = .idle {
        didSet {
            setupModel?.update(readiness: readiness)
            refreshStatus()
        }
    }
    @ObservationIgnored private var warming: Task<Readiness, Never>?
    /// Which start is current, so a stream that ends late cannot finish a
    /// session that replaced it.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var listening: AudioApp?
    @ObservationIgnored private var setup: SetupWindow?
    @ObservationIgnored private var setupModel: SetupModel?
    @ObservationIgnored private var setupListening: Task<Void, Never>?

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

    /// Shown once at first launch, and afterwards for a language download,
    /// which needs a window for Apple's sheet to appear over.
    func showSetup(at step: SetupModel.Step = .welcome, language: String? = nil) {
        if let setup, step == .welcome {
            setup.present()
            return
        }
        setup?.close()
        let model = SetupModel(
            checkAudio: { AudioPermission.check() },
            openSettings: { [weak self] in self?.openPermissionSettings() },
            // The last step listens for real: the app proves itself instead of
            // describing itself.
            startListening: { [weak self] in self?.listenToWhateverPlays() },
            loadLanguages: {
                await Languages.available().map {
                    SetupModel.LanguageChoice(code: $0.code, name: $0.name, isInstalled: $0.isInstalled)
                }
            },
            selectTarget: { [weak self] code in self?.chooseTarget(code) },
            warmUp: { [weak self] in self?.warm() },
            selectedLanguageCode: language ?? target?.code,
            startingAt: step
        )
        setupModel = model
        let content = SetupView(model: model) { [weak self] in
            self?.markSetUp()
            self?.setup?.close()
        }
        .background {
            SetupLanguageDownload(model: model)
        }
        let window = SetupWindow(
            content: content,
            onClose: { [weak self] in
                // Closing from the last page is finishing, not abandoning.
                if model.isComplete { self?.markSetUp() }
                model.stopWatching()
                self?.setupListening?.cancel()
                self?.setupListening = nil
                self?.setupModel = nil
                self?.setup = nil
            })
        setup = window
        window.present()
    }

    private func markSetUp() { UserDefaults.standard.set(true, forKey: "didSetUp") }

    func openPermissionSettings() {
        if let url = AudioPermission.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// The last setup page listens for real, to whichever app is playing.
    private func listenToWhateverPlays() {
        setupListening?.cancel()
        setupListening = Task { [weak self] in
            while let self, !Task.isCancelled {
                refreshSources()
                if let source = sources.first(where: \.isPlaying) {
                    listen(to: source)
                    return
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.start()
        Log.write("app: launched, build \(Bundle.main.bundlePath)")
        let panel = CaptionPanel(content: CaptionBar(model: model))
        panel.placeAtBottom()
        self.panel = panel
        refreshSources()
        if !UserDefaults.standard.bool(forKey: "didSetUp") { showSetup() }
    }

    /// Loads the recogniser once. Listening awaits the same task, so pressing
    /// Start during a download waits for it instead of starting a second one.
    @discardableResult
    func warm() -> Task<Readiness, Never> {
        if let warming, !readiness.isFailure { return warming }
        readiness = .preparing
        let transcriber = UnifiedTranscriber()
        // The delegate lives as long as the app, so capturing it is fine; a
        // weak capture cannot be referenced from the nested closures below.
        let task = Task.detached { () -> Readiness in
            let final = await transcriber.warmUp { partial in
                Task { @MainActor in
                    guard !self.readiness.isSettled else { return }
                    self.readiness = partial
                }
            }
            await MainActor.run { self.readiness = final }
            return final
        }
        warming = task
        return task
    }

    /// Opening the menu means the user is about to act, which is the moment
    /// worth spending on. Warming up at launch cost 14 seconds of CPU and
    /// 400 MB every login, before anyone had asked for anything.
    func menuOpened() {
        refreshSources()
        Task { languages = await Languages.available() }
        warm()
    }

    /// The bar's line while it has no words to show.
    private func refreshStatus() {
        guard isListening, model.lines.isEmpty, model.live.isEmpty else {
            model.status = nil
            return
        }
        model.status = StatusText.waiting(readiness: readiness, app: listening?.name)
    }

    /// Shown only when the pipeline is stuck, so the menu stays quiet when
    /// everything works.
    var problem: String? {
        guard isListening else { return nil }
        let summary = diagnostics.summary
        return summary.hasPrefix("Audio ") && summary.contains("lines") ? nil : summary
    }

    func translate(into language: Languages.Entry) {
        guard language.isInstalled else {
            showSetup(at: .language, language: language.code)
            return
        }
        chooseTarget(language.code)
        if isListening, let source = listening { listen(to: source) }
    }

    private func chooseTarget(_ code: String) {
        target = Language(code)
        UserDefaults.standard.set(code, forKey: "targetLanguage")
        Log.write("language: translating into \(code)")
    }

    func refreshSources() {
        let found = SystemAudioTap.candidates()
        if found.map(\.id) != sources.map(\.id) {
            Log.write("app: sources — \(found.map { "\($0.name)\($0.isPlaying ? " ▶︎" : "")" })")
        }
        sources = found
    }

    func togglePlayback() {
        if isListening {
            stop()
        } else if let first = sources.first(where: \.isPlaying) ?? sources.first {
            listen(to: first)
        }
    }

    func listen(to app: AudioApp) {
        guard target != nil else {
            showSetup(at: .language)
            return
        }
        listening = app
        Log.write("app: listening to \(app.name) — \(app.processes.count) audio processes")
        let counter = diagnostics
        let tap = SystemAudioTap(onFailure: { counter.failed($0) })
        let processes = app.processes
        start { tap.buffers(of: processes) }
    }

    func toggleCaptions() {
        isHidden.toggle()
        if isHidden { panel?.orderOut(nil) } else { panel?.orderFrontRegardless() }
    }

    func stop() {
        running?.cancel()
        running = nil
        finish()
    }

    /// The stream ended, by Stop or by itself. Either way the menu must not
    /// keep offering Stop for something that is no longer running.
    private func finish() {
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

        guard let chosenTarget = target else { return }
        let counter = diagnostics
        generation += 1
        let mine = generation
        running = Task { [weak self] in
            guard let self else { return }
            refreshStatus()
            let ready = await warm().value
            guard ready == .ready, !Task.isCancelled else {
                if generation == mine { finish() }
                return
            }
            // Wall clock against the audio clock: `line.at` is when the words
            // were spoken, so the difference is what the user actually waits.
            let started = ContinuousClock.now
            func lag(_ spokenAt: Duration) -> String {
                let elapsed = ContinuousClock.now - started
                let seconds =
                    Double((elapsed - spokenAt).components.seconds)
                    + Double((elapsed - spokenAt).components.attoseconds) / 1e18
                return String(format: "%.2fs", seconds)
            }
            let transcriber = UnifiedTranscriber(onAudio: { counter.audio($0) })
            let utterances = transcriber.utterances(from: audio)
            var firstWords: String?
            _ = firstWords
            let session = CaptionSession(translator: AppleTranslator(), target: chosenTarget)
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
                    // Feed the setup window while it is open, so its empty
                    // state fills with the user's own audio.
                    if let line = model.lines.first(where: { $0.id == id }) {
                        setupModel?.show(line.source, text)
                    }
                    let spokenAt = model.lines.first { $0.id == id }?.at ?? .zero
                    Log.write("lag \(lag(spokenAt)) to translation — \(text)")
                }
                model.apply(event)
                panel?.fitContent()
            }
            if generation == mine { finish() }
        }
    }
}

/// Observe request identity inside a View, rather than capturing the initial
/// nil request while AppKit constructs its hosting window.
private struct SetupLanguageDownload: View {
    let model: SetupModel

    var body: some View {
        if let request = model.preparation {
            LanguagePreparation(target: request.code) { error in
                model.completePreparation(request, error: error)
            }
            .id(request.id)
        }
    }
}
