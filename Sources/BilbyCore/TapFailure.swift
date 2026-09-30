/// Why a capture stopped, in terms the interface can act on.
///
/// This is an enum and it lives here, rather than each stage passing a
/// sentence along, because the interface has to tell these apart to say
/// anything useful — and BilbyUI cannot depend on BilbySources, where the
/// capture lives. So it used to tell them apart by matching the *prefix of a
/// log message* written in the other module:
///
///     static func isPermission(_ reason: String) -> Bool {
///         reason.hasPrefix("create tap")
///     }
///
/// Reword that log line and the "Fix Permission…" menu item disappears,
/// leaving a refused user with "Something went wrong" and no route to the
/// Settings pane. Nothing could test the coupling, because no test can see
/// both sides of it. A case a compiler checks cannot come apart that way.
public enum TapFailure: Equatable, Sendable {
    /// macOS refused the tap. The one failure a person can act on themselves.
    case permission
    /// No sound output selected — headphones unplugged, nothing to attach to.
    case noOutputDevice
    /// The app being listened to is not playing audio any more, or has quit.
    case appGone
    /// A downstream stage stopped consuming captions; capture stops as well.
    case overloaded
    /// Core Audio would not describe or assemble the capture. The detail is
    /// for the log; there is nothing here a person can do.
    case plumbing(String)

    /// What the log gets. Carries the Core Audio status the user must not see.
    public var detail: String {
        switch self {
        case .permission: return "tap refused — no permission"
        case .noOutputDevice: return "no default output device"
        case .appGone: return "the app stopped playing audio"
        case .overloaded: return "caption delivery exceeded its bounded queue"
        case .plumbing(let reason): return reason
        }
    }
}
