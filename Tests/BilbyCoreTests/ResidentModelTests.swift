import Testing

@testable import BilbyCore

@Suite("Resident model")
struct ResidentModelTests {
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
