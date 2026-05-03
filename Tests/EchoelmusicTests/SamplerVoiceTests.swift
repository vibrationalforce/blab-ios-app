#if canImport(AVFoundation)
import XCTest
import AVFoundation
@testable import Echoelmusic

@MainActor
final class SamplerVoiceTests: XCTestCase {

    // MARK: - Init / load

    func testInit_notLoaded() {
        let voice = SamplerVoice()
        XCTAssertFalse(voice.isLoaded)
        XCTAssertNil(voice.sourceURL)
        XCTAssertFalse(voice._testIsPlaying)
        XCTAssertEqual(voice._testBufferCount, 0)
    }

    func testLoadSample_marksLoadedAndPopulatesBuffer() throws {
        let url = try makeTempWav(seconds: 0.05, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }

        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        XCTAssertTrue(voice.isLoaded)
        XCTAssertEqual(voice.sourceURL, url)
        XCTAssertGreaterThan(voice._testBufferCount, 0)
        XCTAssertLessThanOrEqual(voice._testBufferCount, SamplerVoice.maxSampleFrames)
    }

    func testLoadSample_capsAtMaxSampleFrames() throws {
        // 3-second tone at 44.1k = 132,300 frames > 88,200 cap.
        let url = try makeTempWav(seconds: 3.0, frequency: 220)
        defer { try? FileManager.default.removeItem(at: url) }

        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        XCTAssertEqual(voice._testBufferCount, SamplerVoice.maxSampleFrames)
    }

    // MARK: - Trigger / render

    func testFire_beforeRender_buffersTrigger() throws {
        let url = try makeTempWav(seconds: 0.02, frequency: 880)
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        // fire() before any render — render block must pick up the trigger.
        voice.fire()
        XCTAssertFalse(voice._testIsPlaying, "fire() alone shouldn't start playback")

        renderOneBlock(voice: voice, frameCount: 64)
        XCTAssertTrue(voice._testIsPlaying, "after one render block, playback should be active")
        XCTAssertGreaterThan(voice._testPosition, 0)
    }

    func testRender_withoutFire_isSilent() throws {
        let url = try makeTempWav(seconds: 0.02, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        let frames = 128
        let (out, abl) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out, abl: abl) }
        voice._testRender(frameCount: frames, audioBufferList: abl)

        for i in 0..<frames {
            XCTAssertEqual(out[i], 0, accuracy: 1e-6, "frame \(i) should be silent")
        }
        XCTAssertFalse(voice._testIsPlaying)
    }

    func testRender_afterFire_producesNonZeroAudio() throws {
        let url = try makeTempWav(seconds: 0.05, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        let frames = 256
        let (out, abl) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out, abl: abl) }
        voice.fire()
        voice._testRender(frameCount: frames, audioBufferList: abl)

        var rms: Float = 0
        for i in 0..<frames { rms += out[i] * out[i] }
        rms = (rms / Float(frames)).squareRoot()
        XCTAssertGreaterThan(rms, 0.05, "RMS of rendered tone block should be audible")
    }

    func testRender_pastSampleEnd_returnsToSilence() throws {
        // Very short sample — guaranteed to finish in one big block.
        let url = try makeTempWav(seconds: 0.01, frequency: 1000)  // 441 frames
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)
        let bufCount = voice._testBufferCount

        let frames = 4096
        let (out, abl) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out, abl: abl) }
        voice.fire()
        voice._testRender(frameCount: frames, audioBufferList: abl)

        XCTAssertFalse(voice._testIsPlaying, "after rendering past sample end, voice must stop")
        // Tail (after sample length) must be zeroed.
        for i in bufCount..<frames {
            XCTAssertEqual(out[i], 0, accuracy: 1e-6, "frame \(i) past sample end must be silent")
        }
    }

    func testFire_retrigger_resetsPosition() throws {
        let url = try makeTempWav(seconds: 0.05, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        let frames = 128
        let (out1, abl1) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out1, abl: abl1) }
        voice.fire()
        voice._testRender(frameCount: frames, audioBufferList: abl1)
        let posAfterFirst = voice._testPosition
        XCTAssertGreaterThan(posAfterFirst, 0)

        let (out2, abl2) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out2, abl: abl2) }
        voice.fire()
        voice._testRender(frameCount: frames, audioBufferList: abl2)
        // Retrigger resets to 0 then renders `frames` samples → position = frames.
        XCTAssertEqual(voice._testPosition, frames)
    }

    func testSilence_stopsPlayback() throws {
        let url = try makeTempWav(seconds: 0.5, frequency: 440)
        defer { try? FileManager.default.removeItem(at: url) }
        let voice = SamplerVoice()
        try voice.loadSample(from: url)

        let frames = 128
        let (out, abl) = makeOutputBuffer(frameCount: frames)
        defer { destroyOutputBuffer(out: out, abl: abl) }
        voice.fire()
        voice._testRender(frameCount: frames, audioBufferList: abl)
        XCTAssertTrue(voice._testIsPlaying)

        voice.silence()
        voice._testRender(frameCount: frames, audioBufferList: abl)
        XCTAssertFalse(voice._testIsPlaying)
    }

    // MARK: - Source node

    func testSourceNode_outputFormatMono44k() {
        let voice = SamplerVoice()
        let format = voice.sourceNode.outputFormat(forBus: 0)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertEqual(format.sampleRate, SamplerVoice.sampleRate, accuracy: 0.1)
    }

    // MARK: - Helpers

    /// Writes a temporary mono int16 WAV at 44.1 kHz with a sine wave.
    private func makeTempWav(seconds: Double, frequency: Double) throws -> URL {
        let sr: Double = 44_100
        let frames = Int(seconds * sr)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sampler-voice-\(UUID().uuidString).wav")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sr,
            channels: 1,
            interleaved: false
        ) else { throw NSError(domain: "test", code: 0) }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { throw NSError(domain: "test", code: 1) }
        buffer.frameLength = AVAudioFrameCount(frames)
        let ch = buffer.floatChannelData![0]
        for i in 0..<frames {
            ch[i] = Float(sin(2 * .pi * frequency * Double(i) / sr) * 0.5)
        }
        try file.write(from: buffer)
        return url
    }

    private func makeOutputBuffer(frameCount: Int) -> (UnsafeMutablePointer<Float>, UnsafeMutablePointer<AudioBufferList>) {
        let out = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        out.initialize(repeating: 0, count: frameCount)
        let abl = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        abl.pointee.mNumberBuffers = 1
        abl.pointee.mBuffers.mNumberChannels = 1
        abl.pointee.mBuffers.mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
        abl.pointee.mBuffers.mData = UnsafeMutableRawPointer(out)
        return (out, abl)
    }

    private func destroyOutputBuffer(out: UnsafeMutablePointer<Float>, abl: UnsafeMutablePointer<AudioBufferList>) {
        out.deinitialize(count: 1)
        out.deallocate()
        abl.deallocate()
    }

    private func renderOneBlock(voice: SamplerVoice, frameCount: Int) {
        let (out, abl) = makeOutputBuffer(frameCount: frameCount)
        defer { destroyOutputBuffer(out: out, abl: abl) }
        voice._testRender(frameCount: frameCount, audioBufferList: abl)
    }
}
#endif
