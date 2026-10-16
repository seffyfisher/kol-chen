import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

struct RecordingError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw RecordingError(message: "\(operation) (audio error \(status)).")
        }
    }
}

struct CaptureStats: Sendable {
    let seconds: Double
    let peak: Float
    let peakLeft: Float
    let peakRight: Float
    let error: OSStatus
    let frames: UInt64
}

/// Only the audio callback writes samples. UI reads use atomics; no UI work,
/// allocations, disk I/O, or locking is performed on the audio callback.
final class AudioFileSink: @unchecked Sendable {
    private let file: ExtAudioFileRef
    private let format: AudioStreamBasicDescription
    private let totalFrames = Atomic<UInt64>(0)
    private let peakLeftBits = Atomic<UInt32>(0)
    private let peakRightBits = Atomic<UInt32>(0)
    private let writeError = Atomic<Int32>(noErr)
    private var closed = false // Accessed only after the audio callback is stopped.

    init(url: URL, format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame == 2,
              format.mSampleRate > 0, format.mBytesPerFrame > 0 else {
            throw RecordingError(message: "This audio device did not provide a supported stereo audio format.")
        }
        self.format = format
        var encoded = AudioStreamBasicDescription()
        encoded.mSampleRate = format.mSampleRate
        encoded.mFormatID = kAudioFormatMPEG4AAC
        encoded.mChannelsPerFrame = format.mChannelsPerFrame
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try RecordingError.check(AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &size, &encoded), "Could not configure M4A audio")
        var created: ExtAudioFileRef?
        // Never overwrite an existing recording, even if the supplied URL collides.
        try RecordingError.check(ExtAudioFileCreateWithURL(url as CFURL, kAudioFileM4AType, &encoded, nil, 0, &created), "Could not create the recording")
        guard let created else { throw RecordingError(message: "Could not open the audio file.") }
        file = created
        do {
            var client = format
            try RecordingError.check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, UInt32(MemoryLayout.size(ofValue: client)), &client), "Could not configure the audio input")
            var converter: AudioConverterRef?
            var converterSize = UInt32(MemoryLayout<AudioConverterRef?>.size)
            try RecordingError.check(ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &converterSize, &converter), "Could not configure the encoder")
            if let converter {
                var bitRate: UInt32 = 192_000
                try RecordingError.check(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, UInt32(MemoryLayout.size(ofValue: bitRate)), &bitRate), "Could not set recording quality")
                var config: CFArray?
                try withUnsafePointer(to: &config) { pointer in
                    try RecordingError.check(ExtAudioFileSetProperty(file, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<CFArray?>.size), pointer), "Could not apply recording quality")
                }
            }
            // Prime the asynchronous writer before entering the realtime callback.
            try RecordingError.check(ExtAudioFileWriteAsync(file, 0, nil), "Could not start the file writer")
        } catch {
            ExtAudioFileDispose(file)
            closed = true
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func consume(_ data: UnsafePointer<AudioBufferList>) {
        guard writeError.load(ordering: .relaxed) == noErr else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: data))
        guard let first = buffers.first, first.mData != nil else { return }
        let frames = first.mDataByteSize / format.mBytesPerFrame
        guard frames > 0 else { return }
        let expectedBuffers = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 2 : 1
        guard buffers.count == expectedBuffers,
              buffers.allSatisfy({ $0.mData != nil && $0.mDataByteSize >= frames * format.mBytesPerFrame }) else {
            writeError.store(kAudio_ParamError, ordering: .relaxed)
            return
        }
        let status = ExtAudioFileWriteAsync(file, frames, data)
        guard status == noErr else {
            writeError.store(status, ordering: .relaxed)
            return
        }
        var left: Float = 0
        var right: Float = 0
        if expectedBuffers == 1 {
            let pointer = first.mData!.assumingMemoryBound(to: Float.self)
            for frame in 0..<Int(frames) {
                left = max(left, abs(pointer[frame * 2]))
                right = max(right, abs(pointer[frame * 2 + 1]))
            }
        } else {
            let leftData = buffers[0].mData!.assumingMemoryBound(to: Float.self)
            let rightData = buffers[1].mData!.assumingMemoryBound(to: Float.self)
            for frame in 0..<Int(frames) {
                left = max(left, abs(leftData[frame]))
                right = max(right, abs(rightData[frame]))
            }
        }
        peakLeftBits.max(left.bitPattern, ordering: .relaxed)
        peakRightBits.max(right.bitPattern, ordering: .relaxed)
        totalFrames.wrappingAdd(UInt64(frames), ordering: .relaxed)
    }

    func stats() -> CaptureStats {
        let frames = totalFrames.load(ordering: .relaxed)
        let left = Float(bitPattern: peakLeftBits.exchange(0, ordering: .relaxed))
        let right = Float(bitPattern: peakRightBits.exchange(0, ordering: .relaxed))
        return CaptureStats(seconds: Double(frames) / format.mSampleRate,
                            peak: max(left, right), peakLeft: left, peakRight: right,
                            error: writeError.load(ordering: .relaxed), frames: frames)
    }

    func finish() throws {
        guard !closed else { return }
        closed = true
        let status = ExtAudioFileDispose(file) // Flush pending writes and finalize M4A.
        try RecordingError.check(status, "Could not finish saving the recording")
        try RecordingError.check(writeError.load(ordering: .relaxed), "Recording stopped because audio could not be written")
    }

    deinit { if !closed { ExtAudioFileDispose(file) } }
}

/// All device lifetime operations run on this actor, away from the main thread.
actor AudioRecorder {
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var sink: AudioFileSink?
    private var started = false

    var isRunning: Bool { started || ioProc != nil }

    func start(url: URL) throws {
        guard tap == 0 else { throw RecordingError(message: "A recording is already running.") }
        do {
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "kol-chen system audio"
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try RecordingError.check(AudioHardwareCreateProcessTap(description, &tap), "Could not access system audio. Allow the recorder in System Settings → Privacy & Security → Screen & System Audio Recording")

            var format = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout.size(ofValue: format))
            try RecordingError.check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Could not read the system audio format")

            // A private, tap-only aggregate has no hardware microphone inputs.
            // It is never selected as the system's output device.
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "kol-chen Capture",
                kAudioAggregateDeviceUIDKey: "com.seffyfisher.kol-chen.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try RecordingError.check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device), "Could not prepare audio capture")
            let newSink = try AudioFileSink(url: url, format: format)
            sink = newSink
            try RecordingError.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, input, _, _, _ in
                newSink.consume(input)
            }, "Could not attach the recorder")
            try RecordingError.check(AudioDeviceStart(device, ioProc), "Could not start recording. Check the recorder's system audio permission")
            started = true
        } catch {
            let createdFile = sink != nil
            do { try stop() }
            catch let cleanupError {
                throw RecordingError(message: "\(error.localizedDescription) \(cleanupError.localizedDescription)")
            }
            if createdFile { try? FileManager.default.removeItem(at: url) }
            throw error
        }
    }

    func stats() -> CaptureStats? { sink?.stats() }

    @discardableResult
    func stop() throws -> CaptureStats? {
        // Stop delivery before flushing or releasing the file and callback.
        if started {
            let status = AudioDeviceStop(device, ioProc)
            // Retain all resources if stopping fails; destroying a live sink is unsafe.
            try RecordingError.check(status, "Could not stop audio capture")
            started = false
        }
        if let ioProc {
            try RecordingError.check(AudioDeviceDestroyIOProcID(device, ioProc), "Could not release audio capture")
            self.ioProc = nil
        }
        let finalStats = sink?.stats()
        var finishError: Error?
        do { try sink?.finish() } catch { finishError = error }
        sink = nil
        if device != 0 {
            AudioHardwareDestroyAggregateDevice(device)
            device = 0
        }
        if tap != 0 {
            AudioHardwareDestroyProcessTap(tap)
            tap = 0
        }
        if let finishError { throw finishError }
        return finalStats
    }
}
