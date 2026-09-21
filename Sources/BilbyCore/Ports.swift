/// The core's only dependencies on the outside world.
///
/// Audio capture and speech recognition are deliberately absent: the core
/// never sees a sample or a framework type, it consumes `Utterance` values and
/// asks for translations. That is what lets the whole product be tested with
/// strings.

public protocol Translating: Sendable {
    func translate(_ text: String, to language: Language) async throws -> String
}
