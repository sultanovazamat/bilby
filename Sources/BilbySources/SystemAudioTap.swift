@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import AppKit
import Foundation

/// An app that is currently playing sound.
public struct AudioProcess: Sendable, Identifiable, Hashable {
    public let id: AudioObjectID
    public let bundleID: String
    public let pid: pid_t

    /// Browsers play audio from a helper process, so the bundle id ends in
    /// something like "com.google.Chrome.helper" — the last component is the
    /// least useful part of it. Ask the system for the real name first, then
    /// fall back to the last component that is not boilerplate.
    public var name: String {
        if let running = NSRunningApplication(processIdentifier: pid),
           let localized = running.localizedName {
            return localized
        }
        let boilerplate: Set<String> = [
            "helper", "plugin", "renderer", "gpu", "audio", "service",
            "framework", "app", "xpc",
        ]
        let meaningful = bundleID
            .split(separator: ".")
            .map(String.init)
            .filter { !boilerplate.contains($0.lowercased()) }
        return meaningful.last ?? bundleID
    }
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

    public init() {}

    /// Apps making sound right now.
    public static func playing() -> [AudioProcess] {
        objects(of: kAudioHardwarePropertyProcessObjectList, on: AudioObjectID(kAudioObjectSystemObject))
            .filter { property($0, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) == 1 }
            .compactMap { object in
                guard let bundleID = property(object, kAudioProcessPropertyBundleID, as: CFString.self)
                else { return nil }
                return AudioProcess(
                    id: object,
                    bundleID: bundleID as String,
                    pid: property(object, kAudioProcessPropertyPID, as: pid_t.self) ?? -1
                )
            }
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

            guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
                  let format = Self.tapFormat(tap),
                  let outputUID = Self.defaultOutputUID(),
                  AudioHardwareCreateAggregateDevice(
                      Self.aggregateDescription(tapUUID: description.uuid, outputUID: outputUID),
                      &aggregate
                  ) == noErr
            else {
                continuation.finish()
                return
            }

            // @Sendable is load-bearing. Without it the closure inherits the
            // isolation of wherever it was created, and the Swift runtime
            // asserts that isolation on Core Audio's realtime thread — which
            // traps the process the moment audio starts flowing.
            let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) {
                @Sendable _, input, _, _, _ in
                guard let copy = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: 4096
                ) else { return }

                // Core Audio reuses its list immediately, so copy the bytes.
                // memcpy rather than per-channel: the tap hands over
                // interleaved stereo, where floatChannelData has one buffer.
                let incoming = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: input)
                )
                let outgoing = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                var frames = 0
                for index in 0..<min(incoming.count, outgoing.count) {
                    guard let from = incoming[index].mData,
                          let into = outgoing[index].mData else { continue }
                    let bytes = min(Int(incoming[index].mDataByteSize),
                                    Int(outgoing[index].mDataByteSize))
                    memcpy(into, from, bytes)
                    outgoing[index].mDataByteSize = UInt32(bytes)
                    frames = max(frames, bytes / Int(format.streamDescription.pointee.mBytesPerFrame))
                }
                copy.frameLength = AVAudioFrameCount(frames)
                guard frames > 0 else { return }
                continuation.yield(copy)
            }
            guard status == noErr, let proc, AudioDeviceStart(aggregate, proc) == noErr else {
                continuation.finish()
                return
            }

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
