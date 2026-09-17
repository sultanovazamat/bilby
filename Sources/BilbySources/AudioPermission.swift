import AudioToolbox
import BilbyCore
import CoreAudio
import Foundation

/// Whether macOS will let us hear other apps.
///
/// There is no public API to ask. `CGPreflightScreenCaptureAccess` answers a
/// different question — it reports false on a machine where our taps work
/// fine, because capturing an app's audio and recording the screen are
/// separate grants. So the check is to try: build a tap, throw it away, and
/// see whether Core Audio allowed it.
///
/// Trying is also what raises the system prompt, so check and request are the
/// same act — which is honest, and saves asking twice.
public enum AudioPermission: Sendable {
    /// Opens Privacy & Security at the pane that holds this switch.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )

    public static var isGranted: Bool {
        guard let victim = SystemAudioTap.candidates().first?.processes.first else {
            // Nothing to tap yet says nothing about permission.
            return true
        }
        let description = CATapDescription(stereoMixdownOfProcesses: [victim])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tap)
        defer { if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) } }

        if status != noErr { Log.write("permission: tap refused, status \(status)") }
        return status == noErr
    }
}
