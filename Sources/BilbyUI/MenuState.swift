import BilbyCore

/// Everything the menu shows, computed from plain values so it is tested
/// with strings. The delegate assembles one from its state; the menu reads it.
public struct MenuState: Equatable, Sendable {
    public struct App: Equatable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let isPlaying: Bool
        public init(id: String, name: String, isPlaying: Bool) {
            self.id = id
            self.name = name
            self.isPlaying = isPlaying
        }
    }

    public struct Language: Equatable, Sendable, Identifiable {
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

    public var apps: [App] = []
    /// The app being captioned, while captions run.
    public var listening: App?
    /// The app captioned last, so Start goes back to it.
    public var lastListened: App?
    public var languages: [Language] = []
    public var target: String?
    public var readiness: Readiness = .idle
    public var textSize: TextSize = .system
    public var pipeline: Diagnostics.State = .noAudio

    public init() {}

    /// The app being captioned, and nothing else.
    ///
    /// Bilby used to name a single app on the menu's first line and start
    /// captioning it, guessing between whatever was making sound. The guess
    /// was alphabetical, so a meeting lost to a browser, and a notification
    /// chirp arriving as the menu opened could take the line. Choosing from
    /// the list is one more click and no wrong answers; choosing the checked
    /// app again stops.
    public var checkedApp: String? { listening?.id }

    /// The line at the top: what is being captioned, and what it is being
    /// read in. Menus are built once when they open and cannot animate, so
    /// the live signal stays on the menu bar icon; this is the state.
    public var header: String {
        guard let listening else { return "Not listening" }
        guard let target, let language = languages.first(where: { $0.code == target })?.name else {
            return listening.name
        }
        return "\(listening.name) → \(language)"
    }

    public var installedLanguages: [Language] { languages.filter(\.isInstalled) }
    /// Names the direction, not the noun: the submenu under it is a list of
    /// languages, so calling it "Language" said the same word twice.
    public var languageTitle: String {
        if let target, let name = languages.first(where: { $0.code == target })?.name {
            return "Translate to: \(name)"
        }
        return "Translate to"
    }

    /// One line under the primary item, only when there is something to say.
    public var statusLine: String? {
        if let listening, !readiness.isSettled {
            return StatusText.waiting(readiness: readiness, app: listening.name)
        }
        if case .failed(let message) = readiness { return message }
        if let listening { return StatusText.problem(pipeline, app: listening.name) }
        if case .failed = pipeline, let lastListened { return StatusText.problem(pipeline, app: lastListened.name) }
        return nil
    }

    public var showsFixPermission: Bool {
        StatusText.isPermission(pipeline)
    }
}
