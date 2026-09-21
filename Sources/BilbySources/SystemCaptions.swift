import BilbyCore
import MediaAccessibility

/// What macOS has been told about caption size.
///
/// Accessibility settings asks this once, for the whole machine, and Apple's
/// own players honour the answer. Reading it means someone who has already
/// said they want large captions does not have to say it again here.
public enum SystemCaptions {
    /// 1 when nobody has touched the setting.
    public static var scale: Double {
        Double(MACaptionAppearanceGetRelativeCharacterSize(.user, nil))
    }
}
