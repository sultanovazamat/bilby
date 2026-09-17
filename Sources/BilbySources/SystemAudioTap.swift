@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import AppKit
import BilbyCore
import Foundation

/// An app you can listen to, with every audio process it owns.
///
/// Browsers and chat apps play through helper processes: the sound from a
/// YouTube tab comes from `com.google.Chrome.helper`, which has no icon, no
/// window and no Dock presence. Tapping the parent alone would capture
/// nothing, so an entry carries every process belonging to the app and the tap
/// takes them together.
public struct AudioApp: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let processes: [AudioObjectID]
    public let isPlaying: Bool
    /// The app's icon, for the menu. Absent for processes whose owner has quit.
    public var icon: NSImage? { pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon } }

    let pid: pid_t?
}

/// Captures what another app is playing, straight from Core Audio.
///
/// Since macOS 14.4 a process tap reads an app's decoded output with no virtual
/// driver — no BlackHole, no kext, nothing for the user to install. The audio
/// is digital and pre-speaker, so it carries no room noise, and it contains
/// everyone on the call except the user, because apps do not play your own
/// microphone back to you. That is exactly what captions need, and it is why
/// Bilby never asks for microphone access.
public final class SystemAudioTap: @unchecked Sendable {
    private let onFailure: (@Sendable (String) -> Void)?

    /// `onFailure` receives the Core Audio status that stopped us. Without it
    /// every problem — permission, format, device — looks like silence.
    public init(onFailure: (@Sendable (String) -> Void)? = nil) {
        self.onFailure = onFailure
    }

    /// Core Audio statuses are four-character codes; the number alone is
    /// unsearchable.
    private static func describe(_ status: OSStatus) -> String {
        var code = status.bigEndian
        let characters = withUnsafeBytes(of: &code) { bytes in
            String(bytes.map { Character(UnicodeScalar($0)) })
        }
        let printable = characters.allSatisfy { $0.isLetter || $0.isNumber || $0.isPunctuation }
        return printable ? "\(status) '\(characters)'" : "\(status)"
    }

    /// Apps worth offering, each with all of its audio processes.
    ///
    /// Core Audio only knows a process once it has touched audio, so this is
    /// never "every open app" — measured on one machine, 23 audio processes
    /// against 5 apps with a Dock icon, and the one actually playing was a
    /// browser helper with no icon at all.
    public static func candidates() -> [AudioApp] {
        var byApp: [String: (name: String, pid: pid_t?, processes: [AudioObjectID], playing: Bool)] = [:]

        for object in objects(of: kAudioHardwarePropertyProcessObjectList,
                              on: AudioObjectID(kAudioObjectSystemObject)) {
            guard let bundle = property(object, kAudioProcessPropertyBundleID, as: CFString.self) as String?,
                  !bundle.isEmpty else { continue }
            let pid = property(object, kAudioProcessPropertyPID, as: pid_t.self)
            let playing = property(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            let key = family(of: bundle)
            guard key != Bundle.main.bundleIdentifier else { continue }  // never ourselves

            var entry = byApp[key] ?? (name: key, pid: nil, processes: [], playing: false)
            entry.processes.append(object)
            entry.playing = entry.playing || playing
            // Only an app with a Dock presence names the family. Helpers and
            // daemons are real audio processes and belong in the tap, but
            // "Slack Helper" and "Systemsoundserverd" are not things anyone
            // means to listen to.
            if let pid, let app = NSRunningApplication(processIdentifier: pid),
               app.activationPolicy == .regular {
                entry.pid = pid
                entry.name = app.localizedName ?? key
            }
            byApp[key] = entry
        }

        return byApp
            // A family with no Dock app behind it is a daemon, not a choice.
            .filter { $0.value.pid != nil }
            .map { key, entry in
                AudioApp(id: key, name: entry.name, processes: entry.processes,
                         isPlaying: entry.playing, pid: entry.pid)
            }
        // Whatever is audible first, then the rest by name.
        .sorted { ($0.isPlaying ? 0 : 1, $0.name) < ($1.isPlaying ? 0 : 1, $1.name) }
    }

    /// Collapses `com.google.Chrome.helper` and friends onto `com.google.Chrome`.
    private static func family(of bundle: String) -> String {
        let noise: Set<String> = ["helper", "renderer", "gpu", "plugin", "service", "xpc", "framework"]
        var parts = bundle.split(separator: ".").map(String.init)
        while let last = parts.last, noise.contains(last.lowercased()) || last.contains(" ") {
            parts.removeLast()
        }
        return parts.count >= 2 ? parts.joined(separator: ".") : bundle
    }


    /// Streams what the given processes are playing.
    ///
    /// The list must not be empty: an empty process list taps *nothing*, not
    /// everything. A global tap is a different initializer and needs a
    /// permission an unbundled process cannot hold.
    public func buffers(of processes: [AudioObjectID]) -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            var tap = AudioObjectID(kAudioObjectUnknown)
            var aggregate = AudioObjectID(kAudioObjectUnknown)
            var proc: AudioDeviceIOProcID?

            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.uuid = UUID()
            description.muteBehavior = .unmuted          // the user must still hear the call
            description.isPrivate = true

            func giveUp(_ reason: String) {
                Log.write("tap: FAILED — \(reason)")
                onFailure?(reason)
                continuation.finish()
            }
            Log.write("tap: starting for processes \(processes)")

            let arrived = FrameCounter()
            let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
            guard tapStatus == noErr else {
                return giveUp("create tap \(Self.describe(tapStatus))")
            }
            guard let format = Self.tapFormat(tap) else {
                return giveUp("tap reported no audio format")
            }
            guard let outputUID = Self.defaultOutputUID() else {
                return giveUp("no default output device")
            }
            let aggregateStatus = AudioHardwareCreateAggregateDevice(
                Self.aggregateDescription(tapUUID: description.uuid, outputUID: outputUID),
                &aggregate
            )
            guard aggregateStatus == noErr else {
                return giveUp("create aggregate \(Self.describe(aggregateStatus))")
            }

            // @Sendable is load-bearing. Without it the closure inherits the
            // isolation of wherever it was created, and the Swift runtime
            // asserts that isolation on Core Audio's realtime thread — which
            // traps the process the moment audio starts flowing.
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) {
                @Sendable _, input, _, _, _ in
                let incoming = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: input)
                )
                guard let first = incoming.first else { return }

                // frameLength must be set before the output buffer list is
                // read: AVAudioPCMBuffer reports mDataByteSize from the length,
                // not the capacity, so on a fresh buffer every size is zero and
                // a min() against it copies nothing at all.
                let bytesPerFrame = max(Int(format.streamDescription.pointee.mBytesPerFrame), 1)
                let frames = Int(first.mDataByteSize) / bytesPerFrame
                arrived.record(frames)
                guard frames > 0,
                      let copy = AVAudioPCMBuffer(
                          pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)
                      )
                else { return }
                copy.frameLength = AVAudioFrameCount(frames)

                // Core Audio reuses its list immediately, so copy the bytes.
                // memcpy rather than per-channel: the tap hands over
                // interleaved stereo, where floatChannelData has one buffer.
                let outgoing = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for index in 0..<min(incoming.count, outgoing.count) {
                    guard let from = incoming[index].mData,
                          let into = outgoing[index].mData else { continue }
                    memcpy(into, from, min(Int(incoming[index].mDataByteSize),
                                           Int(outgoing[index].mDataByteSize)))
                }
                continuation.yield(copy)
            }
            guard status == noErr, let proc else {
                return giveUp("create io proc \(Self.describe(status))")
            }
            let startStatus = AudioDeviceStart(aggregate, proc)
            guard startStatus == noErr else {
                return giveUp("start device \(Self.describe(startStatus))")
            }
            Log.write("tap: running — \(format.sampleRate) Hz, \(format.channelCount) ch")

            // Immutable copies: the teardown closure runs on another thread.
            let (tapID, aggregateID, procID) = (tap, aggregate, proc)
            continuation.onTermination = { _ in
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                AudioHardwareDestroyAggregateDevice(aggregateID)
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    // MARK: - Core Audio plumbing

    private static func aggregateDescription(tapUUID: UUID, outputUID: String) -> CFDictionary {
        [
            kAudioAggregateDeviceNameKey: "Bilby",
            kAudioAggregateDeviceUIDKey: "net.variant.bilby.aggregate",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID.uuidString]],
        ] as CFDictionary
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AVAudioFormat? {
        var description = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &description) == noErr
        else { return nil }
        return AVAudioFormat(streamDescription: &description)
    }

    private static func defaultOutputUID() -> String? {
        guard let device = property(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            as: AudioObjectID.self
        ) else { return nil }
        return property(device, kAudioDevicePropertyDeviceUID, as: CFString.self) as String?
    }

    private static func property<T>(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr
        else { return nil }
        return value.pointee
    }

    private static func objects(
        of selector: AudioObjectPropertySelector, on object: AudioObjectID
    ) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}


/// Logs the first buffer and then one line a second, so the log shows whether
/// audio is flowing without drowning in a line per callback.
final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var lastReport = Date.distantPast

    func record(_ count: Int) {
        lock.lock()
        frames += count
        let total = frames
        let due = Date().timeIntervalSince(lastReport) > 1
        if due { lastReport = Date() }
        lock.unlock()
        if due { Log.write("tap: \(total) frames delivered") }
    }
}
