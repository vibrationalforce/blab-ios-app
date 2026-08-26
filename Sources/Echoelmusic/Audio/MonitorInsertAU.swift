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

/// The pass-through effect unit. Mono or stereo (the monitor rail connects it at the
/// master mixer's output format, which the engine clamps to ≤2 channels).
public final class MonitorInsertAudioUnit: AUAudioUnit {

    private let inputBus: AUAudioUnitBus
    private let outputBus: AUAudioUnitBus
    private var _inputBusses: AUAudioUnitBusArray?
    private var _outputBusses: AUAudioUnitBusArray?
    private let scratch = MonitorInsertScratch()

    /// V1b-1 (#839): the mic-owned chain. NEUTRAL by construction — the type's own
    /// defaults enable saturation, chorus and limiter (tuned for the SYNTH bus), so
    /// relying on them would ship a sound change as a side effect of mounting.
    /// Every flag is set explicitly; the guard derives the expected count from the
    /// chain's own `…Enabled` declarations so a 16th stage cannot arrive half-wired.
    private let voiceChain: EchoelFXChain = {
        let chain = EchoelFXChain(sampleRate: 48_000)
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
    }()

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
        // Every monitor start begins from defined chain state (empty delay lines, no
        // stale glide) — reset() clears STATE only, never the user-set targets. The AU
        // contract guarantees THIS NODE is not rendering during (re)allocation (not
        // that the whole engine is stopped) — the same guarantee scratch relies on.
        // ⚠️ V1b-2 PRECONDITION (review NIT, #839): the chain's 48_000 at construction
        // duplicates the bus-format rate below. Harmless while every stage is off (no
        // rate-dependent math runs); before a stage becomes AUDIBLE, derive the chain
        // rate from the negotiated bus format so a renegotiation cannot detune it.
        voiceChain.reset()
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        scratch.release()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Captures ONLY the scratch class and the chain — never self (an ObjC-backed
        // object whose property access would message the runtime on the render thread).
        let scratch = self.scratch
        let chain = self.voiceChain
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
