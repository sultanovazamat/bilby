import Synchronization

/// Stops every stage directly. Capture must not depend on a translator
/// returning before cancellation can travel upstream through its iterator.
public final class SessionCancellation: Sendable {
    private struct State {
        var cancelled = false
        var handlers: [@Sendable () -> Void] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var isCancelled: Bool { state.withLock { $0.cancelled } }

    public func onCancel(_ handler: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { state in
            guard !state.cancelled else { return true }
            state.handlers.append(handler)
            return false
        }
        if runNow { handler() }
    }

    public func cancel() {
        let handlers = state.withLock { state -> [@Sendable () -> Void] in
            guard !state.cancelled else { return [] }
            state.cancelled = true
            let handlers = state.handlers
            state.handlers.removeAll()
            return handlers
        }
        // A handler can finish a stream whose termination calls cancel().
        // Running outside the mutex makes that reentrancy safe.
        for handler in handlers { handler() }
    }
}
