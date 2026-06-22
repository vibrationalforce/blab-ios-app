//
//  SubBassVoice.swift
//  Echoelmusic
//
//  A dedicated mono sub-bass voice — the "Vibration" dimension. It doubles the
//  composed bass one octave down through its own AVAudioSourceNode and a single
//  low oscillator, with a user-pushable `subGain` so the body's bass can be FELT
//  (on a sub, in headphones, or via Core Haptics) as well as heard. Separate from
//  PolySynthVoice so the sub has its own gain and never steals a melodic voice.
//
//  Threading mirrors PolySynthVoice exactly: control plane on MainActor (noteOn/
//  Off enqueue), render closure on the audio thread draining a lock-free SPSC
//  queue. All per-voice state (phase/env/freq) mutates ONLY on the audio thread.
//  `hasEverSounded` + subGain default 0 guarantee pure-zero output until the user
//  both arms a bass note AND pushes the gain — nothing sounds on launch.
//
//  Audio-thread rules (see .claude/rules/swift-audio.md): no malloc / locks / ObjC
//  / GCD / file IO in the render path — only pre-allocated buffers + arithmetic +
//  sinf/tanhf (C math). Monophonic (newest note wins): the bass is a single root
//  line, so one oscillator is correct and cheap.
//

#if canImport(Observation)
import Observation
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation

@MainActor
@Observable
public final class SubBassVoice {

    /// Default felt-sub level. Non-zero by founder decision ("felt sub by
    /// default") so the body's bass is FELT on first play without hunting for a
    /// slider. Launch silence is still guaranteed: the render stays pure-zero
    /// until the first armed bass note (`hasEverSounded`), so nothing sounds at
    /// launch — this only sets how loud the sub is once a bass note plays.
    nonisolated public static let defaultSubGain: Float = 0.35

    /// User-pushable sub level [0...1]. Defaults to `defaultSubGain` so the felt
    /// sub is present by default; the performer can still pull it to 0 or push it
    /// up. MainActor-isolated (UI binding); the audio thread reads its nonisolated
    /// mirror `audioSubGain` instead (a MainActor property can't be read from the
    /// nonisolated render block — same bridge as PolySynthVoice's params).
    public var subGain: Float = SubBassVoice.defaultSubGain {
        didSet { audioSubGain = min(max(subGain, 0), 1) }
    }

    /// Audio-thread-readable mirror of `subGain`. Written on MainActor (didSet),
    /// read on the audio thread. Float-atomic width on Apple → no torn reads.
    /// NB: not named `_subGain` — that collides with the @Observable macro's backing.
    @ObservationIgnored
    nonisolated(unsafe) private var audioSubGain: Float = SubBassVoice.defaultSubGain

    @ObservationIgnored
    nonisolated(unsafe) private var a4Hz: Float = 440

    @ObservationIgnored
    public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()

    /// Lock-free note queue — produced on the control thread, drained on the audio
    /// thread (same discipline as PolySynthVoice.noteCommands).
    @ObservationIgnored
    nonisolated(unsafe) private let noteCommands = SPSCQueue<SubCommand>(capacity: 64)

    // MARK: - Audio-thread-only oscillator state

    @ObservationIgnored nonisolated(unsafe) private var phase: Float = 0
    @ObservationIgnored nonisolated(unsafe) private var currentFreq: Float = 55   // seed in sub range
    @ObservationIgnored nonisolated(unsafe) private var targetFreq: Float = 55
    @ObservationIgnored nonisolated(unsafe) private var env: Float = 0            // 0…1 amplitude env
    @ObservationIgnored nonisolated(unsafe) private var gateOpen = false
    @ObservationIgnored nonisolated(unsafe) private var currentNote: Int32 = -1
    @ObservationIgnored nonisolated(unsafe) private var smoothedGain: Float = 0
    @ObservationIgnored nonisolated(unsafe) private var hasEverSounded = false

    @ObservationIgnored nonisolated private static let sampleRate: Double = 48_000
    @ObservationIgnored nonisolated private static let maxBlockFrames = 4096

    /// Sub band: clamp the oscillator into a true low-frequency range so a note an
    /// octave below the bass can't drift to DC or up out of the "felt" band.
    @ObservationIgnored nonisolated private static let minHz: Float = 28
    @ObservationIgnored nonisolated private static let maxHz: Float = 180

    public init() {}

    // MARK: - Engine attachment

    /// Attach BEFORE `audioEngine.start()` (build-1363 hot-attach rule).
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }

    // MARK: - Note gating (control plane)

    /// Sound the sub at `pitch` (a MIDI note — callers pass the bass root, usually
    /// an octave below the melodic bass). Monophonic: retunes if already sounding.
    public func noteOn(pitch: Int) {
        _ = noteCommands.tryEnqueue(SubCommand(kind: .on, pitch: Int32(pitch)))
    }

    /// Release the sub if `pitch` is the note currently sounding.
    public func noteOff(pitch: Int) {
        _ = noteCommands.tryEnqueue(SubCommand(kind: .off, pitch: Int32(pitch)))
    }

    public func allNotesOff() {
        _ = noteCommands.tryEnqueue(SubCommand(kind: .allOff, pitch: 0))
    }

    /// Match the instrument's concert pitch so the sub stays in tune with the body.
    public func setTuning(a4Hz: Double) {
        self.a4Hz = Float(min(max(a4Hz, 380), 500))
    }

    private nonisolated func frequency(forMIDINote note: Int32) -> Float {
        let f = a4Hz * powf(2, (Float(note) - 69) / 12)
        return min(max(f, Self.minHz), Self.maxHz)
    }

    // MARK: - Source node (audio thread)

    private func makeSourceNode() -> AVAudioSourceNode {
        nonisolated(unsafe) let weakSelf = WeakSub(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
            guard let voice = weakSelf.value else {
                SubBassVoice.silence(audioBufferList: audioBufferList, frameCount: Int(frameCount))
                return noErr
            }
            voice.renderOnAudioThread(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        // Drain note commands on the audio thread (all oscillator-state mutation on
        // this one thread → never races the render).
        while let cmd = noteCommands.dequeue() {
            switch cmd.kind {
            case .on:
                hasEverSounded = true
                currentNote = cmd.pitch
                targetFreq = frequency(forMIDINote: cmd.pitch)
                gateOpen = true
            case .off:
                if cmd.pitch == currentNote { gateOpen = false }
            case .allOff:
                gateOpen = false
            }
        }

        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        // Launch/idle silence: pure zero until the first armed note. The felt-sub
        // default gain (0.35) only sets loudness ONCE a bass note plays — nothing
        // sounds at launch because this gate holds until the first armed note.
        guard hasEverSounded else {
            Self.silence(audioBufferList: audioBufferList, frameCount: frameCount)
            return
        }

        let sr = Float(Self.sampleRate)
        let twoPi: Float = 2 * .pi
        // One-pole coefficients: glide ~5 ms (no pitch click), env attack/release
        // ~15 ms (no thump click), gain glide ~10 ms (no zipper from slider drags).
        let freqGlide: Float = 0.004
        let envCoeff: Float = 0.0015
        let gainCoeff: Float = 0.01
        let gateTarget: Float = gateOpen ? 1 : 0

        for frame in 0..<frameCount {
            currentFreq += freqGlide * (targetFreq - currentFreq)
            env += envCoeff * (gateTarget - env)
            smoothedGain += gainCoeff * (audioSubGain - smoothedGain)
            // Flush the decaying one-poles' denormal tails (matches reverb/delay).
            if env < 1e-15 { env = 0 }
            if smoothedGain < 1e-15 { smoothedGain = 0 }

            phase += twoPi * currentFreq / sr
            if phase > twoPi { phase -= twoPi }

            // Missing-fundamental synthesis: the true sub fundamental (28–55 Hz)
            // is below most phone/laptop speakers, so we add the 2nd + 3rd
            // harmonics off the SAME phase accumulator. The ear reconstructs the
            // (unreproduced) fundamental from the harmonic spacing, so the bass
            // reads at full pitch on small speakers yet is still FELT in full on
            // a sub/haptics. Integer multiples of one phase → no extra state,
            // all C math (audio-thread safe).
            let h1 = sinf(phase)
            let h2 = sinf(2 * phase) * 0.5
            let h3 = sinf(3 * phase) * 0.33
            // Soft-saturate the blend (adds further odd harmonics) and trim the
            // gain so the richer spectrum doesn't clip.
            let shaped = tanhf((h1 + h2 + h3) * 1.3) * 0.5
            let out = shaped * env * smoothedGain

            for buffer in abl {
                guard let raw = buffer.mData else { continue }
                raw.assumingMemoryBound(to: Float.self)[frame] = out
            }
        }
    }

    nonisolated private static func silence(
        audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        frameCount: Int
    ) {
        let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in abl {
            guard let raw = buffer.mData else { continue }
            raw.assumingMemoryBound(to: Float.self).update(repeating: 0, count: frameCount)
        }
    }
}

/// Weak holder so the audio-thread render closure references the MainActor voice
/// without retaining it.
private final class WeakSub: @unchecked Sendable {
    weak var value: SubBassVoice?
    init(_ value: SubBassVoice) { self.value = value }
}

/// Trivial value command across the SPSC queue (no ARC → safe cross-thread).
private struct SubCommand: Sendable {
    enum Kind: UInt8 { case on, off, allOff }
    let kind: Kind
    let pitch: Int32
}
