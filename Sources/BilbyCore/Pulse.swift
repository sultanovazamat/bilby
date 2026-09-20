import Foundation
import Synchronization

/// What the caption pipeline last managed to do.
///
/// A frozen caption bar looks identical whether the speaker stopped talking,
/// recognition died, or a translation went out and never came back. Audio
/// arriving is not progress — the tap logs frames whatever happens upstream.
/// This records where progress actually stopped, so the log names the stage
/// instead of leaving the next person to guess between three.
public final class Pulse: Sendable {
    private struct State {
        var utterances = 0
        var lastUtterance = ContinuousClock.now
        var translations = 0
        var began: ContinuousClock.Instant?
        var subject = ""
        /// Loudest sample since the last report. A frame count cannot tell
        /// a paused video from a recogniser that has given up; this can.
        var peak: Float = 0
        /// Whether this stage sees audio at all. The caption loop does not,
        /// and a stage that cannot hear must not report silence.
        var listens = false
        /// A stall is said once, not every time it is looked at.
        var announced = false
    }

    private let state = Mutex(State())

    public init() {}

    /// Audio arrived, and how loud it was.
    public func sawAudio(peak: Float) {
        state.withLock {
            $0.peak = max($0.peak, peak)
            $0.listens = true
        }
    }

    /// Speech reached the engine.
    public func heard() {
        state.withLock {
            $0.utterances += 1
            $0.lastUtterance = ContinuousClock.now
        }
    }

    public func translating(_ subject: String) {
        state.withLock {
            $0.began = ContinuousClock.now
            $0.subject = subject
        }
    }

    public func translated() {
        state.withLock {
            $0.began = nil
            $0.translations += 1
        }
    }

    /// A line worth logging: the first time this stage has been stuck for
    /// longer than `limit`, and once more when it comes back.
    public func report(stage: String, after limit: Duration = .seconds(5)) -> String? {
        state.withLock { state in
            let now = ContinuousClock.now
            var problem: String?
            if let began = state.began, now - began >= limit {
                problem = "translation of “\(state.subject)” has not come back in \(Self.seconds(now - began))"
            } else if state.utterances > 0, now - state.lastUtterance >= limit {
                problem =
                    "nothing recognised for \(Self.seconds(now - state.lastUtterance))"
                    + (state.listens ? Self.sound(state.peak) : "")
            }
            state.peak = 0

            switch (problem, state.announced) {
            case (let problem?, false):
                state.announced = true
                return "\(stage): STALLED — \(problem)\(Self.counts(state))"
            case (nil, true):
                state.announced = false
                return "\(stage): recovered\(Self.counts(state))"
            default:
                return nil
            }
        }
    }

    /// Silence is the commonest reason for no captions and the least
    /// alarming, so the log should say so rather than imply a fault.
    private static func sound(_ peak: Float) -> String {
        guard peak > 0.003 else { return " while the audio is silent" }
        return String(format: " while audio is playing (peak %.2f)", peak)
    }

    private static func counts(_ state: State) -> String {
        var parts = ["heard \(state.utterances)"]
        if state.translations > 0 { parts.append("translated \(state.translations)") }
        return " · " + parts.joined(separator: ", ")
    }

    private static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1fs", value)
    }
}
