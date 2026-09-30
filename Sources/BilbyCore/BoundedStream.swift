import Synchronization

/// Stops on overload instead of retaining an unlimited backlog or silently
/// replacing completed captions. The owner reports the failure and stops capture.
public final class BoundedStream<Element: Sendable>: Sendable {
    private typealias Termination = AsyncStream<Element>.Continuation.Termination
    private typealias Handler = @Sendable (Termination) -> Void

    /// Installed before producers can finish. AsyncStream itself does not
    /// replay completion to handlers registered after finish(). This relay
    /// owns no stream/continuation reference, so its callback cannot retain us.
    private final class TerminationRelay: Sendable {
        private struct State {
            var reason: Termination?
            var handler: Handler?
        }
        private let state = Mutex(State())

        func finish(_ reason: Termination) {
            let handler = state.withLock { state -> Handler? in
                guard state.reason == nil else { return nil }
                state.reason = reason
                let handler = state.handler
                state.handler = nil
                return handler
            }
            handler?(reason)
        }

        func register(_ handler: @escaping Handler) {
            let reason = state.withLock { state -> Termination? in
                if let reason = state.reason { return reason }
                state.handler = handler
                return nil
            }
            if let reason { handler(reason) }
        }
    }

    public let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation
    private let overflow: @Sendable () -> Void
    private let overflowed = Mutex(false)
    private let termination = TerminationRelay()

    public init(limit: Int, onOverflow: @escaping @Sendable () -> Void = {}) {
        precondition(limit > 0)
        let pair = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingOldest(limit))
        stream = pair.stream
        continuation = pair.continuation
        overflow = onOverflow
        continuation.onTermination = { [termination] reason in termination.finish(reason) }
    }

    public func yield(_ value: Element) {
        if case .dropped = continuation.yield(value) {
            let report = overflowed.withLock { already in
                guard !already else { return false }
                already = true
                return true
            }
            guard report else { return }
            overflow()
            continuation.finish()
        }
    }

    public func finish() { continuation.finish() }

    public func onTermination(_ handler: @escaping @Sendable (AsyncStream<Element>.Continuation.Termination) -> Void) {
        termination.register(handler)
    }
}
