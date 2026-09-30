import BilbyCore
import ServiceManagement

/// Registers Bilby as a login item through the system's own mechanism, so it
/// appears in System Settings → General → Login Items like any other app and
/// can be removed there.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Says what happened, so the checkbox can tell the truth.
    public static func set(_ on: Bool) -> LoginItemOutcome {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.failure("login item", error: error)
            return .failed
        }
        return on && SMAppService.mainApp.status == .requiresApproval ? .needsApproval : .done
    }
}
