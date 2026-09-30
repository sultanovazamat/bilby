@preconcurrency import AVFoundation
import AppKit
import AudioToolbox
import BilbyCore
import CoreAudio
import Foundation
import Synchronization

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
    /// The ones rendering output right now. Which ones matters, not just
    /// whether any: a tap bound to the quiet half of an app hears nothing.
    public let playingProcesses: [AudioObjectID]
    public var isPlaying: Bool { !playingProcesses.isEmpty }
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
    private let onFailure: (@Sendable (TapFailure) -> Void)?

    /// `onFailure` receives why the capture stopped. Without it
    /// every problem — permission, format, device — looks like silence.
    public init(onFailure: (@Sendable (TapFailure) -> Void)? = nil) {
        self.onFailure = onFailure
    }

    /// Core Audio statuses are four-character codes; the number alone is
    /// unsearchable.
    static func describe(_ status: OSStatus) -> String {
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
        var byApp: [String: (name: String, pid: pid_t?, processes: [AudioObjectID], playing: [AudioObjectID])] =
            [:]

        for object in objects(
            of: kAudioHardwarePropertyProcessObjectList,
            on: AudioObjectID(kAudioObjectSystemObject))
        {
            guard let bundle = property(object, kAudioProcessPropertyBundleID, as: CFString.self) as String?,
                !bundle.isEmpty
            else { continue }
            let pid = property(object, kAudioProcessPropertyPID, as: pid_t.self)
            let playing = property(object, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1
            let key = family(of: bundle)
            guard key != Bundle.main.bundleIdentifier else { continue }  // never ourselves

            var entry = byApp[key] ?? (name: key, pid: nil, processes: [], playing: [])
            entry.processes.append(object)
            if playing { entry.playing.append(object) }
            // Only an app with a Dock presence names the family. Helpers and
            // daemons are real audio processes and belong in the tap, but
            // "Slack Helper" and "Systemsoundserverd" are not things anyone
            // means to listen to.
            if let pid, let app = NSRunningApplication(processIdentifier: pid),
                app.activationPolicy == .regular
            {
                entry.pid = pid
                entry.name = app.localizedName ?? key
            }
            byApp[key] = entry
        }

        return
            byApp
            // A family with no Dock app behind it is a daemon, not a choice.
            .filter { $0.value.pid != nil }
            .map { key, entry in
                AudioApp(
                    id: key, name: entry.name, processes: entry.processes,
                    playingProcesses: entry.playing, pid: entry.pid)
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

    /// Streams what an app is playing, and follows it when it moves.
    ///
    /// `processes` is asked again whenever Core Audio's process list changes,
    /// because a tap is bound to the processes that existed when it was
    /// built. The list must not be empty: an empty process list taps
    /// *nothing*, not everything. A global tap is a different initializer and
    /// needs a permission an unbundled process cannot hold.
    public func buffers(
        of processes: @escaping @Sendable () -> [AudioObjectID],
        cancellation: SessionCancellation = SessionCancellation()
    ) -> AsyncStream<AVAudioPCMBuffer> {
        let output = Self.bufferStream(onFailure: onFailure)
        let capture = Capture(
            processes: processes,
            onFailure: onFailure,
            yield: { output.yield($0) },
            giveUp: { output.finish() })
        output.onTermination { termination in
            capture.stop()
            if case .cancelled = termination { cancellation.cancel() }
        }
        // Queue start before installing the stop callback, so cancellation
        // racing registration cannot queue a new start after teardown.
        if !cancellation.isCancelled { capture.start() }
        cancellation.onCancel {
            capture.stop()
            output.finish()
        }
        return output.stream
    }

    /// A gap in PCM would silently remove words. Stop and report overload
    /// while preserving the queued prefix instead of replacing old buffers.
    static func bufferStream(onFailure: (@Sendable (TapFailure) -> Void)?) -> BoundedStream<AVAudioPCMBuffer> {
        BoundedStream(limit: 100) { onFailure?(.overloaded) }
    }

    // MARK: - Core Audio plumbing

    static func aggregateDescription(tapUUID: UUID, outputUID: String) -> CFDictionary {
        [
            kAudioAggregateDeviceNameKey: "Bilby",
            // Per capture, not per app: Core Audio refuses a second
            // aggregate device with a UID that already exists, so a
            // fixed one left any second Bilby — an installed copy
            // beside a `swift run` build — failing forever.
            kAudioAggregateDeviceUIDKey: "io.github.sultanovazamat.bilby.aggregate.\(tapUUID.uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID.uuidString]],
        ] as CFDictionary
    }

    static func tapFormat(_ tap: AudioObjectID) -> AVAudioFormat? {
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

    /// The device the system is playing through now. The aggregate device is
    /// built around it, so a change here leaves the tap pointed at a device
    /// nothing is coming out of.
    public static var currentOutputUID: String? {
        guard
            let device = property(
                AudioObjectID(kAudioObjectSystemObject),
                kAudioHardwarePropertyDefaultSystemOutputDevice,
                as: AudioObjectID.self
            )
        else { return nil }
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

/// Counts what the realtime callback delivers — and says nothing itself.
///
/// `record` used to take an NSLock and then call `Log.write`, which means
/// `String(format:)`, a `Duration` interpolation and a `DispatchQueue.async`
/// closure, from inside the IOProc block, ninety-four times a second. Taking
/// a lock on Core Audio's realtime thread risks priority inversion and
/// allocating on it risks an overload, and the aggregate device this tap
/// builds has the user's *real output device* inside it: an overload here is
/// audible in the meeting they are listening to. A captions app must not be
/// able to break the audio it is captioning.
///
/// So the callback does one relaxed atomic add, and `Capture.report` does the
/// talking from a task that is nowhere near the realtime thread.
final class FrameCounter: Sendable {
    private let frames = Atomic<Int>(0)

    /// The only thing the realtime thread calls.
    func record(_ count: Int) {
        frames.wrappingAdd(count, ordering: .relaxed)
    }

    var delivered: Int { frames.load(ordering: .relaxed) }
}

/// Owns the Core Audio objects behind one capture, and rebuilds them when the
/// sound moves.
///
/// A process tap is bound to the processes that existed when it was created,
/// and an aggregate device to the output device in use at that moment. Both
/// change underneath a running meeting — headphones go in, a browser spawns a
/// new audio helper for a new tab — and Core Audio reports nothing: it keeps
/// delivering the silence of whatever it was pointed at. Two property
/// listeners say when that has happened, so only the plumbing is rebuilt and
/// the recogniser upstream never notices.
private final class Capture: @unchecked Sendable {
    /// Every Core Audio call and every listener callback happens here, so a
    /// rebuild can never race the teardown it follows.
    private let queue = DispatchQueue(label: "io.github.sultanovazamat.bilby.tap")

    private let processes: @Sendable () -> [AudioObjectID]
    private let onFailure: (@Sendable (TapFailure) -> Void)?
    private var reporting: Task<Void, Never>?
    private let yield: @Sendable (AVAudioPCMBuffer) -> Void
    private let giveUp: @Sendable () -> Void

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?
    private var tapped: [AudioObjectID] = []
    private var output: String?
    private var running = false
    // Stop can arrive while Core Audio is still constructing the tap. This
    // also gates the realtime callback without taking a lock on that thread.
    private let stopped = Atomic(false)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(
        processes: @escaping @Sendable () -> [AudioObjectID],
        onFailure: (@Sendable (TapFailure) -> Void)?,
        yield: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        giveUp: @escaping @Sendable () -> Void
    ) {
        self.processes = processes
        self.onFailure = onFailure
        self.yield = yield
        self.giveUp = giveUp
    }

    func start() {
        queue.async { [self] in
            guard !stopped.load(ordering: .acquiring) else { return }
            running = true
            open()
            if !stopped.load(ordering: .acquiring) { watch() }
        }
    }

    func stop() {
        stopped.store(true, ordering: .releasing)
        queue.async { [self] in
            running = false
            unwatch()
            close()
        }
    }

    // MARK: - The plumbing itself

    private func open() {
        guard running, !stopped.load(ordering: .acquiring) else { return }
        // Ten seconds passed between this device reporting itself started and
        // its first buffer, measured on a live session. Which call spends
        // them decides whether it can be moved off the path the user waits on.
        let begun = ContinuousClock.now
        func since() -> String { "\(ContinuousClock.now - begun)" }
        let current = processes()
        guard !current.isEmpty else { return fail(.appGone) }

        let description = CATapDescription(stereoMixdownOfProcesses: current)
        description.uuid = UUID()
        description.muteBehavior = .unmuted  // the user must still hear the call
        description.isPrivate = true

        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        // A tap macOS would not create is, in practice, a tap macOS refused.
        guard tapStatus == noErr else {
            Log.write("tap: create tap \(SystemAudioTap.describe(tapStatus))")
            return fail(.permission)
        }
        Log.write("tap: process tap created after \(since())")
        guard let format = SystemAudioTap.tapFormat(tap) else {
            return fail(.plumbing("tap reported no audio format"))
        }
        guard let outputUID = SystemAudioTap.currentOutputUID else { return fail(.noOutputDevice) }

        let aggregateStatus = AudioHardwareCreateAggregateDevice(
            SystemAudioTap.aggregateDescription(tapUUID: description.uuid, outputUID: outputUID),
            &aggregate)
        guard aggregateStatus == noErr else {
            return fail(.plumbing("create aggregate \(SystemAudioTap.describe(aggregateStatus))"))
        }

        Log.write("tap: aggregate device created after \(since())")
        let arrived = FrameCounter()
        reporting?.cancel()
        reporting = report(arrived, waitingSince: begun)
        let hand = yield
        // @Sendable is load-bearing. Without it the closure inherits the
        // isolation of wherever it was created, and the Swift runtime
        // asserts that isolation on Core Audio's realtime thread — which
        // traps the process the moment audio starts flowing.
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) {
            @Sendable [self] _, input, _, _, _ in
            guard !stopped.load(ordering: .acquiring) else { return }
            let incoming = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = incoming.first else { return }

            // frameLength must be set before the output buffer list is read:
            // AVAudioPCMBuffer reports mDataByteSize from the length, not the
            // capacity, so on a fresh buffer every size is zero and a min()
            // against it copies nothing at all.
            let bytesPerFrame = max(Int(format.streamDescription.pointee.mBytesPerFrame), 1)
            let frames = Int(first.mDataByteSize) / bytesPerFrame
            arrived.record(frames)
            // Still an allocation on the realtime thread, and deliberately
            // so: the alternative is a ring of reused buffers, which the
            // consumer can be handed while the callback is overwriting it —
            // trading late captions for corrupted audio. The lock and the
            // logging that used to be here were removed instead; those were
            // unbounded, this is one malloc of a known size.
            guard frames > 0,
                let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))
            else { return }
            copy.frameLength = AVAudioFrameCount(frames)

            // Core Audio reuses its list immediately, so copy the bytes.
            // memcpy rather than per-channel: the tap hands over interleaved
            // stereo, where floatChannelData has one buffer.
            let outgoing = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in 0..<min(incoming.count, outgoing.count) {
                guard let from = incoming[index].mData, let into = outgoing[index].mData else { continue }
                memcpy(into, from, min(Int(incoming[index].mDataByteSize), Int(outgoing[index].mDataByteSize)))
            }
            hand(copy)
        }
        guard status == noErr, let proc else {
            return fail(.plumbing("create io proc \(SystemAudioTap.describe(status))"))
        }
        guard !stopped.load(ordering: .acquiring) else {
            close()
            return
        }
        let startStatus = AudioDeviceStart(aggregate, proc)
        guard startStatus == noErr else {
            return fail(.plumbing("start device \(SystemAudioTap.describe(startStatus))"))
        }

        tapped = current
        output = outputUID
        Log.write(
            "tap: started after \(since()) on \(current) — \(format.sampleRate) Hz, \(format.channelCount) ch")
    }

    /// Reports whether audio is flowing, off the realtime thread. Polling a
    /// counter rather than being told by the callback is what keeps
    /// `FrameCounter.record` down to a single atomic add; the cost is that
    /// "FIRST BUFFER after …" is accurate to a tenth of a second, on a figure
    /// that has been measured in whole seconds.
    private func report(
        _ counter: FrameCounter, waitingSince: ContinuousClock.Instant
    ) -> Task<Void, Never> {
        Task.detached {
            var announced = false
            var reported = 0
            while !Task.isCancelled {
                let delivered = counter.delivered
                if !announced, delivered > 0 {
                    announced = true
                    Log.write("tap: FIRST BUFFER after \(ContinuousClock.now - waitingSince)")
                }
                if announced, delivered != reported {
                    reported = delivered
                    Log.write("tap: \(delivered) frames delivered")
                }
                do { try await Task.sleep(for: announced ? .seconds(1) : .milliseconds(100)) } catch { return }
            }
        }
    }

    private func close() {
        reporting?.cancel()
        reporting = nil
        if let proc, aggregate != kAudioObjectUnknown {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        proc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
    }

    private func rebuild(_ reason: String) {
        guard running else { return }
        Log.write("tap: rebuilding — \(reason)")
        close()
        open()
    }

    private func fail(_ failure: TapFailure) {
        Log.write("tap: FAILED — \(failure.detail)")
        onFailure?(failure)
        giveUp()
    }

    // MARK: - Noticing that the sound moved

    private func watch() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        // Proven to fire, and sooner than asking: a process appearing was
        // reported 200 ms before a half-second poll saw it.
        watch(system, kAudioHardwarePropertyProcessObjectList) { [self] in
            let current = processes()
            // An empty list means the app quit. Rebuilding on it is pointless
            // and ignoring it is worse: the aggregate device keeps delivering
            // frames, so every counter still reads healthy, the menu still
            // names the app, and the bar sits on its last sentence forever.
            if current.isEmpty {
                guard !tapped.isEmpty else { return }
                return fail(.appGone)
            }
            guard current != tapped else { return }
            rebuild("\(tapped) became \(current)")
        }
        watch(system, kAudioHardwarePropertyDefaultSystemOutputDevice) { [self] in
            guard let now = SystemAudioTap.currentOutputUID, now != output else { return }
            rebuild("the sound moved to another device")
        }
    }

    private func watch(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // Delivered on the same queue everything else runs on, so a rebuild
        // cannot overlap another.
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else {
            Log.write("tap: could not watch property \(selector)")
            return
        }
        listeners.append((object, address, block))
    }

    private func unwatch() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
        listeners.removeAll()
    }
}
