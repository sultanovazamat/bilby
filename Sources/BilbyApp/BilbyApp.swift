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

            // The only way in. Naming one app on a line of its own meant
            // guessing which of several was meant, and the guess was
            // alphabetical.
            Menu("Listen to") {
                ForEach(menu.apps) { app in
                    Toggle(
                        isOn: Binding(
                            get: { menu.checkedApp == app.id }, set: { _ in delegate.chooseApp(app.id) })
                    ) {
                        Label {
                            Text(app.isPlaying ? "\(app.name), playing" : app.name)
                        } icon: {
                            if let icon = delegate.icon(for: app.id) { Image(nsImage: icon) }
                        }
                    }
                }
                if menu.apps.isEmpty { Text("No apps have played audio yet") }
            }
            // Only speak up when something is wrong. A running app should not
            // narrate itself.
            if let line = menu.statusLine { Text(line) }

            Divider()

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
    /// Bar or panel. Modes, not layers: one replaces the other. Chosen with
    /// the buttons on the windows themselves, and remembered.
    private(set) var mode: CaptionMode =
        CaptionMode(rawValue: UserDefaults.standard.string(forKey: "captionMode") ?? "") ?? .bar
    @ObservationIgnored private var setup: SetupWindow?
    @ObservationIgnored private var setupModel: SetupModel?
    @ObservationIgnored private var setupListening: Task<Void, Never>?

    @ObservationIgnored private let model = CaptionModel()
    @ObservationIgnored private var panel: CaptionPanel?
    @ObservationIgnored private var history: HistoryPanel?
    /// Asking AppKit for an app's icon means finding its running process.
    /// The menu redraws far more often than the list of apps changes.
    @ObservationIgnored private var icons: [String: NSImage] = [:]
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

    func icon(for id: String) -> NSImage? { icons[id] }

    func setMode(_ new: CaptionMode) {
        mode = new
        UserDefaults.standard.set(new.rawValue, forKey: "captionMode")
        present()
    }

    /// The three buttons both caption windows carry. Red stops captioning,
    /// the way closing a document window ends it, rather than hiding a
    /// session that would go on running unseen.
    func perform(_ control: WindowControl) {
        switch control {
        case .close: stop()
        case .collapse: setMode(.bar)
        case .expand: setMode(.panel)
        }
    }

    /// Puts whichever caption surface the mode calls for on screen, or
    /// neither.
    private func present() {
        guard isListening else {
            panel?.orderOut(nil)
            history?.orderOut(nil)
            return
        }
        if mode == .panel {
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
            opensAtLogin: LoginItem.isEnabled,
            setOpensAtLogin: { LoginItem.set($0) },
            loadLanguages: {
                await Languages.available().map {
                    SetupModel.LanguageChoice(code: $0.code, name: $0.name, isInstalled: $0.isInstalled)
                }
            },
            selectTarget: { [weak self] code in self?.applyTarget(code) },
            warmUp: { [weak self] in self?.warmAndReport() ?? .idle },
            selectedLanguageCode: language ?? target?.code,
            startingAt: step
        )
        setupModel = model
        let content = SetupView(model: model) { [weak self] in
            // Only the last page finishes setup. Opened for a language, the
            // window closes without pretending the first run happened.
            if model.isComplete { self?.markSetUp() }
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

    /// Starts the recogniser loading if it is not already, and says where it
    /// stands, which may already be ready.
    private func warmAndReport() -> Readiness {
        warm()
        return readiness
    }

    /// A language chosen in setup: remembered, and applied to a running
    /// session without losing what it has shown so far.
    private func applyTarget(_ code: String) {
        guard code != target?.code else { return }
        chooseTarget(code)
        if isListening, let source = listening { listen(to: source, keepingHistory: true) }
    }

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
        // Resolve the resource bundle now, so its log line says where the
        // images came from before any page asks for them.
        _ = UIResources.bundle
        let controls: (WindowControl) -> Void = { [weak self] in self?.perform($0) }
        self.panel = CaptionPanel(content: CaptionBar(model: model, perform: controls))
        self.history = HistoryPanel(content: HistoryView(model: model, perform: controls))
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
        // The delegate lives as long as the app, so a strong capture is fine.
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
        // The hosting view no longer resizes the window by itself, so a
        // status line that appears between sentences has to ask.
        if mode == .bar { panel?.fitContent() }
    }

    func translate(into code: String) {
        guard languages.first(where: { $0.code == code })?.isInstalled == true else {
            showSetup(at: .language, language: code)
            return
        }
        applyTarget(code)
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
        for source in found where icons[source.id] == nil { icons[source.id] = source.icon }
    }

    /// Chosen from the list. The app being captioned carries the checkmark,
    /// so choosing it again means stop — which is what unchecking a checked
    /// item means everywhere else.
    func chooseApp(_ id: String) {
        if isListening, listening?.id == id {
            stop()
            return
        }
        guard let source = sources.first(where: { $0.id == id }) else { return }
        listen(to: source, keepingHistory: isListening)
    }

    func listen(to app: AudioApp, keepingHistory: Bool = false) {
        guard target != nil else {
            showSetup(at: .language)
            return
        }
        listening = app
        Log.write("app: listening to \(app.name) — \(app.processes.count) audio processes")
        let counter = diagnostics
        let tap = SystemAudioTap(onFailure: { counter.failed($0) })
        // Asked again whenever Core Audio's process list changes, so a new
        // browser tab's audio helper is picked up without the recogniser
        // noticing anything happened.
        let id = app.id
        start(
            audio: {
                tap.buffers(of: { SystemAudioTap.candidates().first { $0.id == id }?.processes ?? [] })
            }, keepingHistory: keepingHistory)
    }

    func stop() {
        running?.cancel()
        running = nil
        finish()
    }

    /// The stream ended, by Stop or by itself. Either way the menu must not
    /// keep offering Stop for something that is no longer running.
    private func finish(keepingHistory: Bool = false) {
        guard isListening else { return }
        isListening = false
        pipeline = diagnostics.state
        model.clear(keepingHistory: keepingHistory)
        present()
    }

    private func start(
        audio: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>, keepingHistory: Bool
    ) {
        guard let chosenTarget = target else { return }
        running?.cancel()
        running = nil
        finish(keepingHistory: keepingHistory)
        diagnostics.reset()
        isListening = true
        present()

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
                if mode == .bar { panel?.fitContent() }
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
