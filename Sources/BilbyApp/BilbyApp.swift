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
        MenuBarExtra {
            // Enumerating Core Audio processes is not free, and warming the
            // model costs seconds. Both happen when the menu opens — the only
            // moment the list has to be right and the user is about to act.
            Color.clear.frame(height: 0).onAppear { delegate.menuOpened() }
            let menu = delegate.menu

            Button(menu.primaryTitle) { delegate.togglePlayback() }
                .keyboardShortcut("p")
                .disabled(!menu.primaryEnabled)
            // Only speak up when something is wrong. A running app should not
            // narrate itself.
            if let line = menu.statusLine { Text(line) }

            Divider()

            // A list is worth showing only when there is a choice to make.
            if menu.showsListenTo {
                Menu("Listen To") {
                    ForEach(menu.apps) { app in
                        Toggle(
                            isOn: Binding(
                                get: { menu.checkedApp == app.id }, set: { _ in delegate.listen(toID: app.id) })
                        ) {
                            Label {
                                Text(app.isPlaying ? "\(app.name), playing" : app.name)
                            } icon: {
                                if let icon = delegate.icon(for: app.id) { Image(nsImage: icon) }
                            }
                        }
                    }
                }
            }

            Menu(menu.languageTitle) {
                ForEach(menu.installedLanguages) { language in
                    Toggle(
                        isOn: Binding(
                            get: { menu.target == language.code }, set: { _ in delegate.translate(into: language.code) })
                    ) {
                        Text(language.name)
                    }
                }
                if !menu.installedLanguages.isEmpty { Divider() }
                Button("Add Language…") { delegate.showSetup(at: .language) }
            }

            Toggle(
                "Show Sentence History",
                isOn: Binding(get: { delegate.showsHistory }, set: { delegate.setHistory($0) }))

            Divider()

            if menu.showsFixPermission {
                Button("Fix Permission…") { delegate.openPermissionSettings() }
            }
            Button("Quit Bilby") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(nsImage: BilbyMark.menuBarImage(listening: delegate.isListening))
        }
    }
}

@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var isListening = false
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
    /// The app being captioned, or the last one, for Start to go back to.
    private(set) var listening: AudioApp?
    /// The pipeline's last reported stage, refreshed when the menu opens
    /// and when a line lands. Diagnostics itself is not observable.
    private(set) var pipeline: Diagnostics.State = .noAudio
    /// Bar or panel. Modes, not layers: the panel replaces the bar.
    private(set) var showsHistory = UserDefaults.standard.bool(forKey: "showsHistory")
    @ObservationIgnored private var setup: SetupWindow?
    @ObservationIgnored private var setupModel: SetupModel?
    @ObservationIgnored private var setupListening: Task<Void, Never>?

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var history: HistoryPanel?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private let diagnostics = Diagnostics()

    var menu: MenuState {
        func app(_ source: AudioApp) -> MenuState.App {
            MenuState.App(id: source.id, name: source.name, isPlaying: source.isPlaying)
        }
        var state = MenuState()
        state.apps = sources.map(app)
        state.listening = isListening ? listening.map(app) : nil
        state.lastListened = listening.map(app)
        state.languages = languages.map {
            MenuState.Language(code: $0.code, name: $0.name, isInstalled: $0.isInstalled)
        }
        state.target = target?.code
        state.readiness = readiness
        state.pipeline = pipeline
        return state
    }

    func icon(for id: String) -> NSImage? {
        sources.first { $0.id == id }?.icon
    }

    func setHistory(_ on: Bool) {
        showsHistory = on
        UserDefaults.standard.set(on, forKey: "showsHistory")
        present()
    }

    /// Puts whichever caption surface the mode calls for on screen, or
    /// neither.
    private func present() {
        guard isListening else {
            panel?.orderOut(nil)
            history?.orderOut(nil)
            return
        }
        if showsHistory {
            panel?.orderOut(nil)
            history?.orderFrontRegardless()
        } else {
            history?.orderOut(nil)
            panel?.orderFrontRegardless()
            panel?.fitContent()
        }
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
        let history = HistoryPanel(content: HistoryView(model: model))
        history.onClose = { [weak self] in self?.setHistory(false) }
        self.history = history
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
        pipeline = diagnostics.state
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

    func translate(into code: String) {
        guard languages.first(where: { $0.code == code })?.isInstalled == true else {
            showSetup(at: .language, language: code)
            return
        }
        chooseTarget(code)
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
        } else if let id = menu.candidate?.id, let source = sources.first(where: { $0.id == id }) {
            listen(to: source)
        }
    }

    func listen(toID id: String) {
        guard let source = sources.first(where: { $0.id == id }) else { return }
        listen(to: source)
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

    func stop() {
        running?.cancel()
        running = nil
        finish()
    }

    /// The stream ended, by Stop or by itself. Either way the menu must not
    /// keep offering Stop for something that is no longer running.
    private func finish() {
        isListening = false
        pipeline = diagnostics.state
        model.clear()
        present()
    }

    private func start(audio: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>) {
        stop()
        diagnostics.reset()
        isListening = true
        present()

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
                    pipeline = diagnostics.state
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
                if !showsHistory { panel?.fitContent() }
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
