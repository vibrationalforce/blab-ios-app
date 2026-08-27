// MonitorInsertAU.swift
// Echoel — V1a (#832): the pass-through insert on the monitor rail.
// V1b-1 (#839): the mic-owned `EchoelFXChain` rides it — NEUTRAL, every stage off.
//
// WHY AN EMPTY NODE SHIPPED FIRST (decisions.csv:398/450): the risk in putting a
// vocal chain on the singer's monitor path is the AUAudioUnit render CONTRACT — bus
// format negotiation, host-owned vs. unit-owned output buffers, the pull-input hop —
// not the DSP that rides on it. V1a proved the contract with zero sound change; the
// founder's v10.79.424 logs show `insert in` on device. V1b-1 now swaps "nothing
// else" for `voiceChain.processInPlace` WITHOUT touching the graph shape — and keeps
// the zero-sound-change property by construction: with all 15 stage flags off,
// `processStereo` returns its input bit-exactly (one `if` per stage, no unconditional
// math on the samples), so any audible difference or CPU cost in the next device log
// is attributable to the CHAIN's presence, not to a stage. Making a stage AUDIBLE
// (the founder's harmonizer/granular ask) is V1b-2, a deliberate separate slice with
// its own door and preset.
//
// OWNERSHIP: `voiceChain` is created HERE and configured HERE. It is never the synth
// voices' instance and never reads their presets — two owners of one preset object is
// the #416/BLE-3 shape this file exists to avoid.
//
// LATENCY: the chain buffers nothing (in-place, sample by sample) — the insert still
// adds no algorithmic delay, and `AudioEngine.monitorInsertLatencyMilliseconds` logs
// what the node reports so the next device log can confirm the 0.
//
// AUDIO THREAD (render block): no allocation, no locks, no ObjC messaging, no self
// capture — only the pre-allocated scratch, the captured `voiceChain` (a pure Swift
// `@unchecked Sendable` final class already running in two synth render paths), and
// the host's pull block. `reset()` runs in `allocateRenderResources` (engine stopped).

import Foundation
#if canImport(AVFoundation)
import AVFoundation
import AudioToolbox

/// Pre-allocated output storage for the case where the host hands the render block a
/// buffer list with `mData == nil` (host asks the unit to supply memory). AVAudioEngine
/// normally provides buffers, but the contract allows nil and a pass-through that
/// crashes on it would fail exactly when a different host shape appears.
/// `@unchecked Sendable`: written only from `allocate`/`release` (engine stopped),
/// read from the render thread — the same discipline as `MonitorTapWindow`.
final class MonitorInsertScratch: @unchecked Sendable {
    private(set) var left: UnsafeMutablePointer<Float>?
    private(set) var right: UnsafeMutablePointer<Float>?
    private(set) var capacity: Int = 0

    func allocate(frames: Int) {
        release()
        capacity = max(frames, 1)
        left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        left?.initialize(repeating: 0, count: capacity)
        right?.initialize(repeating: 0, count: capacity)
    }

    func release() {
        // Un-publish BEFORE freeing (reviewer #832 finding 2): a render that slipped
        // past the contract then fails the capacity guard or the `guard let`, instead
        // of passing both and reading freed memory. Under the documented contract this
        // path never races a render — the ordering is belt-and-braces, like #831.
        capacity = 0
        let l = left
        let r = right
        left = nil
        right = nil
        l?.deallocate()
        r?.deallocate()
    }

    deinit { release() }
}

/// The mic-owned voice-stage settings (#841, V1b-2). Value type on purpose: the box
/// stores a COPY, so the control plane can never mutate what a rebuild is reading.
/// Defaults are ALL-OFF/neutral — a fresh insert sounds exactly like V1a until the
/// singer turns a stage on in the input sheet. Session-local like the voiceTune
/// settings (deliberately NOT persisted; persistence is its own future decision with
/// its own reachable off-switch).
public struct MonitorVoicePreset: Sendable, Equatable {
    /// The harmonizer stage on the singer's monitor. Default OFF (the neutral law).
    public var harmonizerEnabled: Bool = false
    /// First/second harmony interval in semitones (the chain's own defaults:
    /// major third + perfect fifth — `EchoelHarmonizer.interval1/2`, #416).
    public var interval1: Float = 4
    public var interval2: Float = 7
    /// 0…1 wet mix (`EchoelHarmonizer.mix`).
    public var mix: Float = 0.5

    /// The granular texture stage on the singer's monitor (#849, V1b-3). Default OFF
    /// (the neutral law) — the parameter defaults below only matter once he enables.
    public var granularEnabled: Bool = false
    /// 0…1 wet mix of the grain cloud (`EchoelGranular.mix`). The STAGE's own default
    /// is 0 — an enabled stage would be silent — so the door carries an audible one.
    public var granularMix: Float = 0.4
    /// Grain length in milliseconds (`EchoelGranular.grainMilliseconds`).
    public var granularGrainMs: Float = 80
    /// Grain pitch shift in semitones (`EchoelGranular.pitchSemitones`).
    public var granularPitch: Float = 0

    public init() {}
}

/// Holds the mic-owned chain plus the rate it was built at (#840) and the voice
/// preset applied to it (#841). A swap box exists because `EchoelFXChain`'s rate is
/// immutable — following a renegotiated bus rate means REPLACING the chain — while
/// the render block holds one stable reference.
/// `@unchecked Sendable`: `chain`/`sampleRate` are written only from
/// init/`allocateRenderResources` (this node is not rendering then, the AU contract
/// `MonitorInsertScratch` already relies on) and read from the render thread;
/// `preset` is control-plane only: written on the main thread, read in
/// `allocateRenderResources` — which is nonisolated by signature but reached in this
/// app ONLY from the main actor (every graph mutation runs there; the config-change
/// handlers hop via `Task { @MainActor }` first). The render thread never touches
/// the preset — it reads the chain the preset was applied TO (#841 review LOW).
final class MonitorInsertChainBox: @unchecked Sendable {
    private(set) var chain: EchoelFXChain
    private(set) var sampleRate: Float
    private(set) var preset = MonitorVoicePreset()

    init(chain: EchoelFXChain, sampleRate: Float) {
        self.chain = chain
        self.sampleRate = sampleRate
    }

    func replace(chain: EchoelFXChain, sampleRate: Float) {
        self.chain = chain
        self.sampleRate = sampleRate
    }

    func store(preset: MonitorVoicePreset) {
        self.preset = preset
    }
}

/// The pass-through effect unit. Mono or stereo (the monitor rail connects it at the
/// master mixer's output format, which the engine clamps to ≤2 channels).
public final class MonitorInsertAudioUnit: AUAudioUnit {

    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var _inputBusses: AUAudioUnitBusArray?
    private var _outputBusses: AUAudioUnitBusArray?
    private let scratch = MonitorInsertScratch()

    /// V1b-1 (#839) + #840: the mic-owned chain, held in a swap box because its
    /// sample rate is `let` — baked into all 15 stage constructors at init — so
    /// following a renegotiated bus rate means building a FRESH chain, not mutating
    /// one. The box is the `MonitorInsertScratch` discipline: written only while this
    /// node is not rendering (init / `allocateRenderResources`), read from the render
    /// thread through the one captured reference.
    private let chainBox: MonitorInsertChainBox = {
        // ONE rate literal (review NIT, #840): the box's shadow copy must describe
        // the chain it holds — two independent literals here could drift and make
        // the mismatch-detect in allocateRenderResources silently mis-fire.
        let rate: Float = 48_000
        return MonitorInsertChainBox(chain: MonitorInsertAudioUnit.neutralChain(sampleRate: rate),
                                     sampleRate: rate)
    }()

    /// NEEDS-FOUNDER-VERIFY: Monitoring an (Log zeigt „insert in") und normal
    /// sprechen/singen — klingt der Monitor UNVERÄNDERT gegenüber v423, ohne
    /// Knacksen und ohne spürbaren CPU-/Wärme-Sprung? Das ist die #839-Probe:
    /// die Kette läuft dann erstmals auf dem Gerät, beweisbar stumm.
    ///
    /// NEUTRAL by construction — the type's own defaults enable saturation, chorus
    /// and limiter (tuned for the SYNTH bus), so relying on them would ship a sound
    /// change as a side effect of mounting. Every flag is set explicitly; the guard
    /// derives the expected count from the chain's own `…Enabled` declarations so a
    /// 16th stage cannot arrive half-wired.
    /// ⚠️ V1b-2 lives HERE: when the mic preset arrives, this factory is the ONE
    /// place that must re-apply it, so a rate-swap rebuild can never silently drop
    /// the user's settings back to neutral.
    private static func neutralChain(sampleRate: Float) -> EchoelFXChain {
        let chain = EchoelFXChain(sampleRate: sampleRate)
        chain.filterEnabled = false
        chain.saturationEnabled = false
        chain.tapeEnabled = false
        chain.bitcrushEnabled = false
        chain.harmonizerEnabled = false
        chain.chorusEnabled = false
        chain.flangerEnabled = false
        chain.granularEnabled = false
        chain.phaserEnabled = false
        chain.tremoloEnabled = false
        chain.delayEnabled = false
        chain.reverbEnabled = false
        chain.widenerEnabled = false
        chain.compressorEnabled = false
        chain.limiterEnabled = false
        return chain
    }

    /// #841/#849: the ONE place preset values reach a chain (#416) — used by the live
    /// door (`applyVoicePreset`) and by the rate-swap rebuild, so a renegotiated
    /// route can never silently reset the singer's settings to neutral. Per stage:
    /// parameters first, the enable flag LAST — each `…Enabled`'s own `willSet`
    /// resets its stage on the rising edge, so it must see the final values.
    private static func apply(_ preset: MonitorVoicePreset, to chain: EchoelFXChain) {
        chain.harmonizer.interval1 = preset.interval1
        chain.harmonizer.interval2 = preset.interval2
        chain.harmonizer.mix = preset.mix
        chain.harmonizerEnabled = preset.harmonizerEnabled
        chain.granular.mix = preset.granularMix
        chain.granular.grainMilliseconds = preset.granularGrainMs
        chain.granular.pitchSemitones = preset.granularPitch
        chain.granularEnabled = preset.granularEnabled
    }

    /// Control-plane door for the input sheet (#841). Stores the preset in the box
    /// (so a #840 rate rebuild re-applies it) and applies it to the live chain.
    /// Writing a stage flag while the node renders is the established discipline —
    /// the synth chains toggle the same `…Enabled` vars from the FX panel mid-play.
    @MainActor
    public func applyVoicePreset(_ preset: MonitorVoicePreset) {
        chainBox.store(preset: preset)
        Self.apply(preset, to: chainBox.chain)
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain,
                          code: Int(kAudioUnitErr_FailedInitialization))
        }
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        try super.init(componentDescription: componentDescription, options: options)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input,
                                           busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output,
                                            busses: [outputBus])
        maximumFramesToRender = 4096
    }

    public override var inputBusses: AUAudioUnitBusArray {
        _inputBusses ?? AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
    }

    public override var outputBusses: AUAudioUnitBusArray {
        _outputBusses ?? AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [])
    }

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        scratch.allocate(frames: Int(maximumFramesToRender))
        // #840 (closes the #839 review NIT): the chain rate FOLLOWS the negotiated
        // bus format instead of trusting the 48_000 both were created with. A
        // renegotiated rate rebuilds the neutral chain at the real rate, so a future
        // audible stage (V1b-2) can never run its delay/glide maths against the
        // wrong clock. Guarded non-finite/zero (a defensive impossibility under the
        // bus contract, but a Float cast of garbage must not bake into 15 stages).
        let negotiated = Float(outputBus.format.sampleRate)
        if negotiated.isFinite, negotiated > 0, negotiated != chainBox.sampleRate {
            // #841: the rebuild re-applies the stored voice preset BEFORE the box
            // publishes the fresh chain — the box never holds a chain the singer's
            // settings have not reached.
            let fresh = Self.neutralChain(sampleRate: negotiated)
            Self.apply(chainBox.preset, to: fresh)
            chainBox.replace(chain: fresh, sampleRate: negotiated)
        }
        // Every monitor start begins from defined chain state (empty delay lines, no
        // stale glide) — reset() clears STATE only, never the user-set targets. The AU
        // contract guarantees THIS NODE is not rendering during (re)allocation (not
        // that the whole engine is stopped) — the same guarantee scratch relies on;
        // the box swap above shares it, which is why the render block may read the
        // box without a lock.
        chainBox.chain.reset()
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        scratch.release()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Captures ONLY the scratch class and the chain box — never self (an
        // ObjC-backed object whose property access would message the runtime on the
        // render thread). The BOX is captured, not the chain, so a rate-swap in
        // `allocateRenderResources` reaches a render block the host fetched earlier.
        let scratch = self.scratch
        let box = self.chainBox
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pull = pullInputBlock else { return kAudioUnitErr_NoConnection }
            guard Int(frameCount) <= scratch.capacity else {
                return kAudioUnitErr_TooManyFramesToProcess
            }
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            let byteSize = frameCount * UInt32(MemoryLayout<Float>.stride)
            for index in 0..<buffers.count {
                if buffers[index].mData == nil {
                    switch index {
                    case 0:
                        guard let p = scratch.left else { return kAudioUnitErr_Uninitialized }
                        buffers[index].mData = UnsafeMutableRawPointer(p)
                    case 1:
                        guard let p = scratch.right else { return kAudioUnitErr_Uninitialized }
                        buffers[index].mData = UnsafeMutableRawPointer(p)
                    default:
                        return kAudioUnitErr_FormatNotSupported
                    }
                }
                buffers[index].mDataByteSize = byteSize
            }
            var pullFlags = AudioUnitRenderActionFlags()
            // The input renders DIRECTLY into the output buffers; the chain then
            // processes them in place (V1b-1, #839). With every stage off this is
            // bit-identical to the V1a pass-through — the E2E guard asserts exactly
            // that through this very block.
            let status = pull(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }
            // Stereo only: the chain's entry is (left, right). A mono host shape
            // stays pure pass-through rather than processing one buffer as both
            // channels — defensive, since the engine connects this node at the
            // master mixer's stereo output format.
            if buffers.count == 2,
               let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
               let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) {
                // One field read on a pure Swift final class — direct access, no
                // ObjC. Stable within a render: the box is only written while this
                // node is not rendering.
                let chain = box.chain
                chain.processInPlace(left: left, right: right, frameCount: Int(frameCount))
            }
            return noErr
        }
    }
}

/// Registration + instantiation, both on the main actor (registration mutates global
/// component state and must happen exactly once).
@MainActor
public enum MonitorInsertFactory {

    /// 'Ecmi' / 'Echl' — a local component identity; never ships as an extension.
    public static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x4563_6D69,      // 'Ecmi'
        componentManufacturer: 0x4563_686C, // 'Echl'
        componentFlags: 0,
        componentFlagsMask: 0)

    private static var registered = false

    /// Registers the subclass (once) and instantiates the wrapping `AVAudioUnit`.
    /// Completion hops to the main actor; a `nil` unit means instantiation failed and
    /// the monitor chain builds WITHOUT the insert — monitoring must never be hostage
    /// to this node (the caller logs which way it went).
    public static func instantiate(_ completion: @escaping @MainActor (AVAudioUnit?, String?) -> Void) {
        if !registered {
            AUAudioUnit.registerSubclass(MonitorInsertAudioUnit.self,
                                         as: componentDescription,
                                         name: "Echoel: Monitor Insert",
                                         version: 1)
            registered = true
        }
        // The async form, not the completion-handler form: the handler runs on an
        // AVFoundation queue and its non-Sendable `AVAudioUnit?` parameter cannot be
        // sent into a `@MainActor` task under Swift 6 region isolation (reviewer #832
        // finding 1). The async variant returns a `sending` value — same behaviour,
        // provably race-free.
        Task { @MainActor in
            do {
                let unit = try await AVAudioUnit.instantiate(with: componentDescription,
                                                             options: [])
                completion(unit, nil)
            } catch {
                completion(nil, String(describing: error))
            }
        }
    }
}
#endif
