/// A model that stays loaded for as long as the app runs, lent to one session
/// at a time.
///
/// Loading the speech model costs about 15 s from cold. A warm-up that loaded
/// it and let it go bought nothing: the session loaded it again, and two
/// minutes after a warm-up, choosing an app took 15.3 s to reach the audio tap
/// — which is also what asks macOS for permission, so the prompt waited too.
///
/// Lent rather than shared: a model is fed by one session. A new session can
/// start while the last one is still ending — switching apps does exactly
/// that — so it waits for the model to come back instead of loading a second
/// copy, and replaces one that never does.
public actor ResidentModel<Model: AnyObject & Sendable> {
    private let load: @Sendable () async throws -> Model
    /// How long a session waits for the last one to hand the model back.
    private let patience: Duration
    private var model: Model?
    private var loading: Task<Model, Error>?
    private var lent = false

    public init(patience: Duration = .seconds(2), load: @escaping @Sendable () async throws -> Model) {
        self.patience = patience
        self.load = load
    }

    /// Loads the model now, if it is not loaded yet, so the first session does
    /// not wait. `custom` loads it this once instead of the usual way — the
    /// app's warm-up does, to report download progress.
    public func warm(loading custom: (@Sendable () async throws -> Model)? = nil) async throws {
        _ = try await loaded(by: custom ?? load)
    }

    /// The model, for one session.
    public func borrow() async throws -> Model {
        // The last session is handing it back: a switch of app ends one
        // session as the next begins.
        let deadline = ContinuousClock.now + patience
        while lent, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        // It never came back. Whatever holds it is not using it any more.
        if lent { model = nil }
        let lending = try await loaded(by: load)
        lent = true
        return lending
    }

    /// Back from a session, and kept for the next. A model this no longer
    /// holds — one already replaced — changes nothing.
    public func giveBack(_ returned: Model) {
        guard returned === model else { return }
        lent = false
    }

    /// A fresh model, for a session whose model stopped working. The session
    /// holds the new one, and the old one is let go.
    public func replace() async throws -> Model {
        model = nil
        return try await loaded(by: load)
    }

    private func loaded(by loader: @escaping @Sendable () async throws -> Model) async throws -> Model {
        if let model { return model }
        if let loading { return try await loading.value }
        let task = Task { try await loader() }
        loading = task
        defer { loading = nil }
        let fresh = try await task.value
        model = fresh
        return fresh
    }
}
