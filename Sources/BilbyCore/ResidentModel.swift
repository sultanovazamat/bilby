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
    private let reset: @Sendable (Model) async throws -> Void
    /// How long a session waits for the last one to hand the model back.
    private let patience: Duration
    private var model: Model?
    private var loading: Task<Model, Error>?
    private var lent = false
    /// Actor methods can resume after a timeout has started another load or
    /// lease. Old completions must not publish into that newer state.
    private var loadGeneration = 0
    private var leaseGeneration = 0

    public init(
        patience: Duration = .seconds(2),
        reset: @escaping @Sendable (Model) async throws -> Void = { _ in },
        load: @escaping @Sendable () async throws -> Model
    ) {
        self.patience = patience
        self.reset = reset
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
        try Task.checkCancellation()
        // The old session may still be loading or cleaning up. Give this
        // session its own instance; do not join the old in-flight load.
        if lent { forget() }
        return try await lend()
    }

    /// Clears private session state before making the model available again.
    /// A failed reset discards it. A stale return still clears that instance,
    /// but cannot free a replacement currently used by another session.
    public func giveBack(_ returned: Model) async {
        do {
            try await reset(returned)
        } catch {
            guard returned === model else { return }
            forget()
            lent = false
            return
        }
        guard returned === model else { return }
        lent = false
    }

    /// A fresh model, for a session whose model stopped working. The session
    /// holds the new one, and the old one is let go.
    public func replace() async throws -> Model {
        try Task.checkCancellation()
        forget()
        return try await lend()
    }

    private func forget() {
        loadGeneration += 1
        model = nil
        loading = nil
    }

    private func lend() async throws -> Model {
        // Reserve before awaiting: otherwise two cold borrowers both see an
        // available slot and receive the same instance from loaded().
        lent = true
        leaseGeneration += 1
        let generation = leaseGeneration
        do {
            return try await loaded(by: load)
        } catch {
            if generation == leaseGeneration { lent = false }
            throw error
        }
    }

    private func loaded(by loader: @escaping @Sendable () async throws -> Model) async throws -> Model {
        if let model { return model }
        let task: Task<Model, Error>
        if let loading {
            task = loading
        } else {
            loadGeneration += 1
            task = Task { try await loader() }
            loading = task
        }
        let generation = loadGeneration
        do {
            let fresh = try await task.value
            if generation == loadGeneration {
                model = fresh
                loading = nil
            }
            return fresh
        } catch {
            if generation == loadGeneration { loading = nil }
            throw error
        }
    }
}
