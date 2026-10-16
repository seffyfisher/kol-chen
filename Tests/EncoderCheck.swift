import AudioToolbox
import AVFoundation
import Foundation

// Exercise the production file writer with known stereo tones, without recording
// the user's system audio or requesting any privacy permission.
@main
struct EncoderCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for interleaved in [true, false] {
            for sampleRate in [44_100.0, 48_000.0] {
                let name = "\(interleaved ? "interleaved" : "planar")-\(Int(sampleRate))"
                let url = root.appendingPathComponent(name + ".m4a")
                try? FileManager.default.removeItem(at: url)
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: interleaved)!
                let sink = try AudioFileSink(url: url, format: format.streamDescription.pointee)
                let totalFrames = Int(sampleRate * 3)
                var offset = 0
                while offset < totalFrames {
                    let count = min(512, totalFrames - offset)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                    buffer.frameLength = AVAudioFrameCount(count)
                    let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                    for frame in 0..<count {
                        let time = Double(offset + frame) / sampleRate
                        let left = Float(0.3 * sin(2 * .pi * 440 * time))
                        let right = Float(0.2 * sin(2 * .pi * 880 * time))
                        if interleaved {
                            let data = list[0].mData!.assumingMemoryBound(to: Float.self)
                            data[frame * 2] = left
                            data[frame * 2 + 1] = right
                        } else {
                            list[0].mData!.assumingMemoryBound(to: Float.self)[frame] = left
                            list[1].mData!.assumingMemoryBound(to: Float.self)[frame] = right
                        }
                    }
                    sink.consume(buffer.audioBufferList)
                    offset += count
                    // Allow the async encoder to drain, as during live delivery.
                    Thread.sleep(forTimeInterval: Double(count) / sampleRate / 3)
                }
                let stats = sink.stats()
                precondition(stats.frames == UInt64(totalFrames))
                precondition(abs(stats.seconds - 3) < 0.001)
                precondition(stats.peak > 0.29 && stats.peak < 0.31)
                precondition(abs(stats.peakLeft - 0.3) < 0.001)
                precondition(abs(stats.peakRight - 0.2) < 0.001)
                precondition(stats.error == noErr)
                try sink.finish()
                try sink.finish() // Idempotent finalization.
                let read = try AVAudioFile(forReading: url)
                precondition(read.processingFormat.channelCount == 2)
                precondition(abs(Double(read.length) / read.processingFormat.sampleRate - 3) < 0.05)
                print("PASS: \(name), stereo M4A finalized, 3 seconds")
            }
        }
        let sentinelURL = root.appendingPathComponent("existing.m4a")
        let sentinel = Data("must not overwrite".utf8)
        try sentinel.write(to: sentinelURL)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        do {
            _ = try AudioFileSink(url: sentinelURL, format: format.streamDescription.pointee)
            fatalError("Should reject an existing file")
        } catch {
            let preserved = try Data(contentsOf: sentinelURL)
            precondition(preserved == sentinel)
            print("PASS: existing files are preserved")
        }
    }
}
