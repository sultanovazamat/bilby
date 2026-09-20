import BilbyCore
import Foundation
import Observation

/// First-run state, independent of rendering and the platform permission and
/// download APIs. Only the permission page may probe access; only a prepared
/// language can start the live demonstration.
@MainActor
@Observable
public final class SetupModel {
    public enum Step: Int, CaseIterable, Sendable {
        case welcome, permission, language, tryIt

        /// Steps that are about where to click show the real thing.
        var screenshot: String? {
            switch self {
            case .welcome: "menu-bar"
            case .tryIt: "menu-sources"
            default: nil
            }
        }

        var title: String {
            switch self {
            case .welcome: "Never lose the thread."
            case .permission: "Let Bilby listen."
            case .language: "Make yourself at home."
            case .tryIt: "Now, hear it your way."
            }
        }
    }

    public struct LanguageChoice: Identifiable, Sendable {
        public let code: String
        public let name: String
        public let isInstalled: Bool
        public var id: String { code }

        public init(code: String, name: String, isInstalled: Bool) {
            self.code = code
            self.name = name
            self.isInstalled = isInstalled
        }
    }

    /// Identity matters: a cancelled download must not complete a later one.
    public struct Preparation: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let code: String
    }

    public private(set) var step: Step
    /// Where the window opened. Opened for a language from the menu, it ends
    /// after the download instead of replaying welcome and permission.
    public let startedAt: Step
    public var finishesAfterLanguage: Bool { startedAt == .language }
    /// Reaching the last page is finishing: closing the window from there
    /// must not bring the whole flow back at the next launch.
    public var isComplete: Bool { step == .tryIt }
    public private(set) var audio: AudioAccess = .unknown
    public var hasAudioAccess: Bool { audio == .granted }
    public private(set) var languages: [LanguageChoice] = []
    public private(set) var selectedLanguageCode: String
    public private(set) var isLoadingLanguages = false
    public private(set) var languageError: String?
    public private(set) var preparation: Preparation?
    public private(set) var caption: (source: String, translation: String)?
    /// Whether Bilby starts at login, offered on the last page.
    public private(set) var opensAtLogin: Bool
    /// What to tell the user when registering did not simply work.
    public private(set) var loginNote: String?
    /// How far the recogniser is, for the last page.
    public private(set) var readiness: Readiness = .idle

    private let checkAudio: @Sendable () -> AudioAccess
    private let openSettings: () -> Void
    private let startListening: () -> Void
    private let loginItemHandler: (Bool) -> LoginItemOutcome
    private let fetchLanguages: () async -> [LanguageChoice]
    private let selectTarget: (String) -> Void
    /// Starts the recogniser loading if it is not already, and reports where
    /// it stands — which may already be ready.
    private let warmUp: () -> Readiness
    private let preferredLanguages: [String]
    private var hasWarmedUp = false
    /// How often the permission page re-checks. Tests shorten it.
    private let pollInterval: Duration
    private var isActive = true

    public init(
        checkAudio: @escaping @Sendable () -> AudioAccess,
        openSettings: @escaping () -> Void,
        startListening: @escaping () -> Void,
        opensAtLogin: Bool = false,
        setOpensAtLogin: @escaping (Bool) -> LoginItemOutcome = { _ in .done },
        loadLanguages: @escaping () async -> [LanguageChoice] = { [] },
        selectTarget: @escaping (String) -> Void = { _ in },
        warmUp: @escaping () -> Readiness = { .ready },
        selectedLanguageCode: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages,
        startingAt: Step = .welcome,
        pollInterval: Duration = .seconds(1)
    ) {
        self.step = startingAt
        self.startedAt = startingAt
        self.checkAudio = checkAudio
        self.openSettings = openSettings
        self.startListening = startListening
        self.opensAtLogin = opensAtLogin
        self.loginItemHandler = setOpensAtLogin
        self.fetchLanguages = loadLanguages
        self.selectTarget = selectTarget
        self.warmUp = warmUp
        self.selectedLanguageCode = selectedLanguageCode ?? ""
        self.preferredLanguages = preferredLanguages
        self.pollInterval = pollInterval
        if startingAt.rawValue >= Step.language.rawValue { ensureWarm() }
    }

    public var selectedLanguage: LanguageChoice? {
        languages.first { $0.code == selectedLanguageCode }
    }

    public var canContinue: Bool {
        guard isActive else { return false }
        switch step {
        case .welcome: return true
        // Nothing to probe is not a refusal: the prompt comes with the first
        // start, and holding the page hostage until then helps nobody.
        case .permission: return audio == .granted || audio == .nothingToProbe
        case .language: return selectedLanguage?.isInstalled == true && preparation == nil
        case .tryIt: return true
        }
    }

    public func advance() {
        guard canContinue, let next = Step(rawValue: step.rawValue + 1) else { return }
        if step == .language { selectTarget(selectedLanguageCode) }
        step = next
        if next == .language { ensureWarm() }
        if next == .tryIt { startListening() }
    }

    /// Asked for once, when the user has committed by reaching the language
    /// page, so the recogniser is usually ready by the last page.
    public func ensureWarm() {
        guard isActive, !hasWarmedUp else { return }
        hasWarmedUp = true
        readiness = warmUp()
    }

    public func retryWarmUp() {
        guard isActive else { return }
        readiness = warmUp()
    }

    /// Leaving from the language page, when the window opened there: the
    /// chosen language is handed on, as advance() would have done.
    public func finish() {
        guard isActive, step == .language, selectedLanguage?.isInstalled == true else { return }
        selectTarget(selectedLanguageCode)
    }

    public func update(readiness: Readiness) {
        self.readiness = readiness
    }

    public func setOpensAtLogin(_ on: Bool) {
        switch loginItemHandler(on) {
        case .done:
            opensAtLogin = on
            loginNote = nil
        case .needsApproval:
            opensAtLogin = on
            loginNote = "macOS needs you to approve this in System Settings → General → Login Items."
        case .failed:
            opensAtLogin = false
            loginNote = "Bilby couldn’t be added to your login items."
        }
    }

    public func show(_ source: String, _ translation: String) {
        guard isActive, step == .tryIt, !translation.isEmpty else { return }
        caption = (source, translation)
    }

    public func requestAudioAccess() {
        guard isActive, step == .permission else { return }
        // Asking and checking are the same act — building a tap is what raises
        // the prompt. If that did not settle it, send the user to the switch:
        // being asked and then left on the same screen is the worst outcome.
        audio = checkAudio()
        if audio == .refused { openSettings() }
    }

    /// Owned by the visible page's SwiftUI task, so leaving or closing the
    /// page cancels polling.
    ///
    /// Permission granted before this page opened is shown as granted, not
    /// skipped past: a step that flashes by teaches nothing, and this is the
    /// page that says where Bilby lives. Only a grant that happens while the
    /// user is watching moves them on by itself, because that is the moment
    /// where waiting for a click would feel obtuse.
    public func watchPermission() async {
        // A closed page must not probe: probing is what raises the prompt.
        guard isActive, step == .permission else { return }
        let arrival = checkAudio()
        audio = arrival

        while isActive, step == .permission, !Task.isCancelled {
            do { try await Task.sleep(for: pollInterval) } catch { return }
            guard isActive, step == .permission else { return }
            let now = checkAudio()
            guard now != audio else { continue }
            audio = now
            if now == .granted, arrival != .granted { advance() }
        }
    }

    public func loadLanguages() async {
        guard isActive, step == .language, !isLoadingLanguages, languages.isEmpty else { return }
        isLoadingLanguages = true
        languageError = nil
        defer { isLoadingLanguages = false }
        let entries = await fetchLanguages()
        guard isActive, step == .language, !Task.isCancelled else { return }
        languages = entries
        if selectedLanguage == nil {
            selectedLanguageCode = Self.defaultLanguage(preferred: preferredLanguages, among: entries) ?? ""
        }
        if entries.isEmpty { languageError = "Languages couldn’t be loaded. Try again." }
    }

    /// The first language the user already reads that Apple can translate
    /// into. English is skipped: it is the source, so never the target. No
    /// match leaves the choice to the user rather than guessing.
    static func defaultLanguage(preferred: [String], among languages: [LanguageChoice]) -> String? {
        for tag in preferred {
            let code = tag.split(separator: "-").first.map { $0.lowercased() } ?? ""
            if code != "en", languages.contains(where: { $0.code == code }) { return code }
        }
        return nil
    }

    public func selectLanguage(_ code: String) {
        guard isActive, step == .language, languages.contains(where: { $0.code == code }) else { return }
        guard code != selectedLanguageCode else { return }
        preparation = nil
        languageError = nil
        selectedLanguageCode = code
    }

    public func prepareLanguage() {
        guard isActive, step == .language, let language = selectedLanguage,
            !language.isInstalled, preparation == nil
        else { return }
        languageError = nil
        preparation = Preparation(code: language.code)
    }

    public func completePreparation(_ request: Preparation, error: String?) {
        guard isActive, step == .language, preparation == request else { return }
        preparation = nil
        languageError = error
        guard error == nil else { return }
        languages = languages.map {
            $0.code == request.code ? LanguageChoice(code: $0.code, name: $0.name, isInstalled: true) : $0
        }
    }

    public func cancelPreparation() {
        preparation = nil
    }

    public func stopWatching() {
        isActive = false
        preparation = nil
    }
}
