import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

func check(_ label: String, _ status: OSStatus) -> Bool {
    let ok = status == noErr
    var code = status.bigEndian
    let chars = withUnsafeBytes(of: &code) { bytes in
        String(bytes.map { Character(UnicodeScalar($0)) })
    }
    print("\(ok ? "✓" : "✗") \(label)\(ok ? "" : "  status=\(status) '\(chars)'")")
    return ok
}

func property<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { value.deallocate() }
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
    return value.pointee
}

@main
struct TapTest {
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)   // keep output when we crash
        print("=== 1. processes ===")
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        _ = check("AudioObjectGetPropertyDataSize", AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        _ = check("AudioObjectGetPropertyData", AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids))
        print("  \(ids.count) process objects")

        var playing: [AudioObjectID] = []
        for id in ids {
            let running = property(id, kAudioProcessPropertyIsRunningOutput, as: UInt32.self) ?? 0
            let bundle = property(id, kAudioProcessPropertyBundleID, as: CFString.self) as String? ?? "?"
            if running == 1 { playing.append(id); print("  ▶︎ \(bundle)") }
        }
        print("  playing: \(playing.count)")

        print("\n=== 2. create tap ===")
        guard !playing.isEmpty else { print("  nothing is playing — start audio first"); return }
        let description = CATapDescription(stereoMixdownOfProcesses: playing)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tap)) else { return }
        print("  tap id \(tap)")

        print("\n=== 3. tap format ===")
        var asbd = AudioStreamBasicDescription()
        var asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard check("kAudioTapPropertyFormat",
                    AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &asbdSize, &asbd)) else { return }
        guard let format = AVAudioFormat(streamDescription: &asbd) else { print("✗ AVAudioFormat nil"); return }
        print("  \(format.sampleRate) Hz, \(format.channelCount) ch, \(format)")

        print("\n=== 4. aggregate device ===")
        guard let output = property(system, kAudioHardwarePropertyDefaultSystemOutputDevice, as: AudioObjectID.self),
              let uid = property(output, kAudioDevicePropertyDeviceUID, as: CFString.self) as String?
        else { print("✗ no default output"); return }
        print("  output uid \(uid)")

        let dict = [
            kAudioAggregateDeviceNameKey: "BilbyTap",
            kAudioAggregateDeviceUIDKey: "net.variant.bilby.taptest",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ] as CFDictionary
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard check("AudioHardwareCreateAggregateDevice",
                    AudioHardwareCreateAggregateDevice(dict, &aggregate)) else { return }

        print("\n=== 5. io proc, 5 seconds ===")
        let counter = Counter()
        var proc: AudioDeviceIOProcID?
        guard check("AudioDeviceCreateIOProcIDWithBlock",
                    AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { @Sendable _, input, _, _, _ in
                        let list = input.pointee
                        let frames = list.mNumberBuffers > 0
                            ? Int(list.mBuffers.mDataByteSize) / 4 : 0
                        counter.add(frames)
                    }), let proc else { return }
        guard check("AudioDeviceStart", AudioDeviceStart(aggregate, proc)) else { return }
        try await Task.sleep(for: .seconds(5))
        print("  callbacks \(counter.calls), frames \(counter.frames)")
        _ = check("AudioDeviceStop", AudioDeviceStop(aggregate, proc))
        _ = check("destroy aggregate", AudioHardwareDestroyAggregateDevice(aggregate))
        _ = check("destroy tap", AudioHardwareDestroyProcessTap(tap))
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls = 0
    private(set) var frames = 0
    func add(_ n: Int) { lock.lock(); calls += 1; frames += n; lock.unlock() }
}
