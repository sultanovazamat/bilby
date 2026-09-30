import Synchronization
import Testing

@testable import BilbyCore

@Suite("Bounded caption delivery")
struct BoundedStreamTests {
    private final class Counter: Sendable {
        let value = Mutex(0)
    }
    private final class WeakOwner {
        weak var value: BoundedStream<Int>?
        init(_ value: BoundedStream<Int>?) { self.value = value }
    }
    @Test("a stalled consumer stops the producer instead of silently replacing captions")
    func stopsOnOverflow() async {
        let failures = Mutex(0)
        let output = BoundedStream<Int>(limit: 3) { failures.withLock { $0 += 1 } }
        output.yield(1)
        output.yield(2)
        output.yield(3)
        output.yield(4)
        output.yield(5)
        var received: [Int] = []
        for await value in output.stream { received.append(value) }
        #expect(received == [1, 2, 3])
        #expect(failures.withLock { $0 } == 1)
    }

    @Test("normal completion keeps the pending values and reports no overflow")
    func finishesNormally() async {
        let failed = Mutex(false)
        let output = BoundedStream<Int>(limit: 3) { failed.withLock { $0 = true } }
        output.yield(1)
        output.yield(2)
        output.finish()
        var received: [Int] = []
        for await value in output.stream { received.append(value) }
        #expect(received == [1, 2])
        #expect(!failed.withLock { $0 })
    }

    @Test("overflow terminates upstream work")
    func cancelsProducer() async {
        let stopped = Mutex(false)
        let output = BoundedStream<Int>(limit: 1)
        output.onTermination { _ in stopped.withLock { $0 = true } }
        output.yield(1)
        output.yield(2)
        #expect(stopped.withLock { $0 })
    }

    @Test("overflow is reported before normal stream completion can hide the failure")
    func reportsBeforeFinishing() {
        let reported = Mutex(false)
        let reportedAtTermination = Mutex(false)
        let output = BoundedStream<Int>(limit: 1) { reported.withLock { $0 = true } }
        output.onTermination { _ in
            reportedAtTermination.withLock { $0 = reported.withLock { $0 } }
        }
        output.yield(1)
        output.yield(2)
        #expect(reportedAtTermination.withLock { $0 })
    }

    @Test("a termination handler registered after completion still runs exactly once")
    func lateTerminationHandler() {
        let called = Mutex(0)
        let output = BoundedStream<Int>(limit: 1)
        output.finish()
        output.onTermination { termination in
            if case .finished = termination { called.withLock { $0 += 1 } }
        }
        #expect(called.withLock { $0 } == 1)
        output.finish()
        #expect(called.withLock { $0 } == 1)
    }

    @Test("registration racing completion neither loses nor repeats termination")
    func concurrentTerminationRegistration() async {
        let called = Counter()
        let outputs = (0..<100).map { _ in BoundedStream<Int>(limit: 1) }
        await withTaskGroup(of: Void.self) { group in
            for output in outputs {
                group.addTask { output.finish() }
                group.addTask { output.onTermination { _ in called.value.withLock { $0 += 1 } } }
            }
        }
        #expect(called.value.withLock { $0 } == 100)
        withExtendedLifetime(outputs) {}
    }

    @Test("termination bookkeeping does not retain the stream owner")
    func releasesOwner() {
        var output: BoundedStream<Int>? = BoundedStream(limit: 1)
        let owner = WeakOwner(output)
        let stream = output!.stream
        output = nil
        #expect(owner.value == nil)
        withExtendedLifetime(stream) {}
    }
}
