/// Decides when a running capture has stopped listening to the right thing.
///
/// The tap is built once, around the processes an app owned and the output
/// device in use at that moment. Both change underneath it: headphones go in,
/// a new browser tab starts playing from a process that did not exist. Core
/// Audio does not complain — it keeps delivering the silence of whatever it
/// was pointed at — so nothing notices unless something asks.
public struct TapWatch: Sendable, Equatable {
    public enum Verdict: Equatable, Sendable {
        case fine
        /// Said in the words the menu will show.
        case rebuild(String)
    }

    private let output: String?
    private let processes: Set<UInt32>
    /// Core Audio's "this process is rendering output" flag blinks off during
    /// continuous playback — measured on a video that never stopped — so one
    /// reading is not evidence.
    private var strikes = 0

    public init(output: String?, processes: Set<UInt32>) {
        self.output = output
        self.processes = processes
    }

    public mutating func check(output: String?, playing: Set<UInt32>) -> Verdict {
        if output != self.output {
            return .rebuild("the sound moved to another device")
        }
        guard !playing.isEmpty, playing.isDisjoint(with: processes) else {
            strikes = 0
            return .fine
        }
        strikes += 1
        guard strikes >= 2 else { return .fine }
        return .rebuild("the app is playing through something else")
    }
}
