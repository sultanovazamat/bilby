import Synchronization
import Testing

@testable import BilbyCore

@Suite("Session cancellation")
struct SessionCancellationTests {
    private final class Counter: Sendable {
        let value = Mutex(0)
    }
    @Test("cancellation runs every handler once and handles late registration")
    func cancellationIsImmediateAndIdempotent() {
        let cancellation = SessionCancellation()
        let calls = Mutex(0)
        cancellation.onCancel { calls.withLock { $0 += 1 } }
        cancellation.cancel()
        cancellation.cancel()
        cancellation.onCancel { calls.withLock { $0 += 1 } }
        #expect(cancellation.isCancelled)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test("handlers may reenter cancellation without holding its mutex")
    func reentrantHandlerDoesNotDeadlock() {
        let cancellation = SessionCancellation()
        let calls = Mutex(0)
        cancellation.onCancel {
            cancellation.cancel()
            cancellation.onCancel { calls.withLock { $0 += 1 } }
        }
        cancellation.cancel()
        #expect(calls.withLock { $0 } == 1)
    }

    @Test("registration racing cancellation never misses or repeats a handler")
    func concurrentRegistration() async {
        let cancellation = SessionCancellation()
        let calls = Counter()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { cancellation.onCancel { calls.value.withLock { $0 += 1 } } }
                group.addTask { cancellation.cancel() }
            }
        }
        #expect(calls.value.withLock { $0 } == 100)
    }
}
