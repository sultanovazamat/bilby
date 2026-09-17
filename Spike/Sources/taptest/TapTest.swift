import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Does Core Audio know about an app before it has played anything?
///
/// The menu can only offer what can actually be tapped, and a tap needs an
/// AudioObjectID. If Core Audio only registers a process once it has made a
/// sound, then "list every open app" and "list what we can listen to" are
/// different lists, and the menu has to say so.
@main
struct TapTest {
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids)

        var known: [pid_t: (bundle: String, playing: Bool)] = [:]
        for id in ids {
            guard let pid = property(id, kAudioProcessPropertyPID, as: pid_t.self) else { continue }
            let bundle = property(id, kAudioProcessPropertyBundleID, as: CFString.self) as String? ?? "—"
            let playing = property(id, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            known[pid] = (bundle, playing)
        }

        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        print("Core Audio knows \(ids.count) processes · \(apps.count) apps have a dock presence\n")
        print("app                        core audio?   playing?")
        for app in apps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            let name = app.localizedName ?? "?"
            let entry = known[app.processIdentifier]
            print(String(format: "%-26s %-13s %s",
                         (name as NSString).utf8String!,
                         (entry == nil ? "no" : "yes" as NSString).utf8String!,
                         ((entry?.playing ?? false) ? "▶︎ playing" : "") as String))
        }

        let orphans = known.filter { pid, _ in !apps.contains { $0.processIdentifier == pid } }
        print("\naudio processes with no dock app (would be hidden): \(orphans.count)")
        for (_, v) in orphans.prefix(8) { print("  \(v.bundle)\(v.playing ? "  ▶︎" : "")") }
    }

    static func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
