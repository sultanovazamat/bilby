import Testing

@testable import BilbyCore

@Suite("Resident model")
struct ResidentModelTests {
    actor DelayedFirstLoad {
        enum Failure: Error { case oldLoad }
        private(set) var count = 0
        private var first: CheckedContinuation<Model, Error>?

        func next() async throws -> Model {
            count += 1
            let number = count
            if number == 1 {
                return try await withCheckedThrowingContinuation { first = $0 }
            }
            return Model(number)
        }

        func waitUntilStarted() async throws {
            while first == nil { try await Task.sleep(for: .milliseconds(1)) }
        }

        func complete(failing: Bool = false) {
            if failing { first?.resume(throwing: Failure.oldLoad) } else { first?.resume(returning: Model(1)) }
            first = nil
        }
    }

    @Test("concurrent cold borrowers cannot share a model still being loaded")
    func concurrentColdBorrowersAreIsolated() async throws {
        let loads = DelayedFirstLoad()
        let resident = ResidentModel(patience: .milliseconds(40)) { try await loads.next() }
        let first = Task { try await resident.borrow() }
        try await loads.waitUntilStarted()
        let second = Task { try await resident.borrow() }
        try await Task.sleep(for: .milliseconds(100))
        await loads.complete()
        let old = try await first.value
        let fresh = try await second.value
        #expect(old !== fresh)
        #expect(fresh.load == 2)
        // The late first load must not overwrite the model now lent out.
        await resident.giveBack(fresh)
        let reused = try await resident.borrow()
        #expect(reused === fresh)
    }

    @Test("an obsolete load failure cannot release a newer session's lease")
    func oldLoadFailureDoesNotFreeCurrentLease() async throws {
        let loads = DelayedFirstLoad()
        let resident = ResidentModel(patience: .milliseconds(40)) { try await loads.next() }
        let first = Task { try await resident.borrow() }
        try await loads.waitUntilStarted()
        let second = Task { try await resident.borrow() }
        try await Task.sleep(for: .milliseconds(100))
        await loads.complete(failing: true)
        _ = try? await first.value
        let current = try? await second.value
        #expect(current?.load == 2)
        let next = try await resident.borrow()
        #expect(next.load == 3)
    }

    @Test("a cleanup exceeding the hand-back deadline cannot free its replacement")
    func slowCleanupDoesNotFreeReplacement() async throws {
        let loads = Loads()
        let resident = ResidentModel(
            patience: .milliseconds(40),
            reset: { _ in try await Task.sleep(for: .milliseconds(120)) },
            load: { await loads.next() })
        let old = try await resident.borrow()
        let cleanup = Task { await resident.giveBack(old) }
        let current = try await resident.borrow()
        #expect(current !== old)
        await cleanup.value
        let next = try await resident.borrow()
        #expect(next.load == 3)
    }
    actor SensitiveModel {
        enum ResetFailure: Error { case failed }
        private(set) var text = "Private conversation"
        private(set) var hasCallback = true
        var fails = false

        func failReset() { fails = true }
        func clear() throws {
            hasCallback = false
            if fails { throw ResetFailure.failed }
            text = ""
        }
    }

    @Test("returning a resident model clears session data before it can be reused")
    func clearsBeforeReuse() async throws {
        let resident = ResidentModel(reset: { try await $0.clear() }, load: { SensitiveModel() })
        let first = try await resident.borrow()
        await resident.giveBack(first)
        let next = try await resident.borrow()
        #expect(next === first)
        #expect(await next.text.isEmpty)
        #expect(await !next.hasCallback)
    }

    @Test("a model that cannot clear its session data is discarded")
    func discardsFailedReset() async throws {
        let resident = ResidentModel(reset: { try await $0.clear() }, load: { SensitiveModel() })
        let first = try await resident.borrow()
        await first.failReset()
        await resident.giveBack(first)
        #expect(await !first.hasCallback)
        let next = try await resident.borrow()
        #expect(next !== first)
    }

    @Test("cancelling a session still clears its resident model")
    func cancelledSessionClearsModel() async throws {
        let resident = ResidentModel(reset: { try await $0.clear() }, load: { SensitiveModel() })
        let first = try await resident.borrow()
        let cleanup = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await resident.giveBack(first)
        }
        await cleanup.value
        #expect(await first.text.isEmpty)
        #expect(await !first.hasCallback)
    }
    /// Stands in for the speech model: which load produced it is its identity.
    final class Model: Sendable {
        let load: Int
        init(_ load: Int) { self.load = load }
    }

    /// Counts loads, which cost 15 s each from cold in the real thing.
    actor Loads {
        private(set) var count = 0
        func next() -> Model {
            count += 1
            return Model(count)
        }
    }

    @Test("the model warmed before listening is the one listening uses")
    func warmedIsUsed() async throws {
        let loads = Loads()
        let resident = ResidentModel { await loads.next() }
        try await resident.warm()
        let model = try await resident.borrow()
        #expect(model.load == 1)
        #expect(await loads.count == 1)
    }

    @Test("a warm-up that brings its own loader is what listening then borrows")
    func warmUpLoaderIsKept() async throws {
        let loads = Loads()
        let resident = ResidentModel { await loads.next() }
        try await resident.warm(loading: { Model(99) })
        let model = try await resident.borrow()
        #expect(model.load == 99)
        #expect(await loads.count == 0)
    }

    @Test("a finished session hands its model to the next")
    func handedToTheNext() async throws {
        let loads = Loads()
        let resident = ResidentModel { await loads.next() }
        let first = try await resident.borrow()
        await resident.giveBack(first)
        let second = try await resident.borrow()
        #expect(second === first)
        #expect(await loads.count == 1)
    }

    @Test("a session starting while the last one ends waits for its model instead of loading another")
    func waitsForTheLastSession() async throws {
        let loads = Loads()
        let resident = ResidentModel { await loads.next() }
        let first = try await resident.borrow()
        async let second = resident.borrow()
        try await Task.sleep(for: .milliseconds(60))
        await resident.giveBack(first)
        #expect(try await second === first)
        #expect(await loads.count == 1)
    }

    @Test("a model never handed back is replaced rather than waited for forever")
    func neverHandedBack() async throws {
        let loads = Loads()
        let resident = ResidentModel(patience: .milliseconds(80)) { await loads.next() }
        _ = try await resident.borrow()
        let second = try await resident.borrow()
        #expect(second.load == 2)
    }

    @Test("a late hand-back of a replaced model does not free the one in use")
    func staleHandBack() async throws {
        let loads = Loads()
        let resident = ResidentModel(patience: .milliseconds(80)) { await loads.next() }
        let stale = try await resident.borrow()
        _ = try await resident.borrow()  // replaces it: the first session never came back
        await resident.giveBack(stale)
        // The second model is still lent, so a third session waits, then loads.
        let third = try await resident.borrow()
        #expect(third.load == 3)
    }

    @Test("a restart gets a fresh model, which is then kept")
    func restartReplaces() async throws {
        let loads = Loads()
        let resident = ResidentModel { await loads.next() }
        _ = try await resident.borrow()
        let fresh = try await resident.replace()
        await resident.giveBack(fresh)
        let next = try await resident.borrow()
        #expect(fresh.load == 2)
        #expect(next === fresh)
    }
}
