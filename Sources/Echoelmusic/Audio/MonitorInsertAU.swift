// MonitorInsertAU.swift
// Echoel — V1a (#832): the EMPTY pass-through insert on the monitor rail.
//
// WHY AN EMPTY NODE SHIPS ON ITS OWN (decisions.csv:398/450): the risk in putting a
// vocal chain on the singer's monitor path is the AUAudioUnit render CONTRACT — bus
// format negotiation, host-owned vs. unit-owned output buffers, the pull-input hop —
// not the DSP that will later ride on it. This slice proves the contract with zero
// sound change: the render block pulls the input straight into the output buffers and
// does nothing else. V1b then swaps "nothing else" for the processing stage WITHOUT
// touching the graph shape again.
//
// LATENCY: a pass-through AU adds no algorithmic delay and buffers nothing — the
// founder's ask says "latenzfrei", and `AudioEngine.monitorInsertLatencyMilliseconds`
// logs what the node itself reports so the next device log can confirm the 0.
//
// AUDIO THREAD (render block): no allocation, no locks, no ObjC messaging, no self
// capture — only the pre-allocated scratch (filled in `allocateRenderResources`, which
// runs while the engine is stopped) and the host's pull block.

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
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        scratch.release()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Captures ONLY the scratch class — never self (an ObjC-backed object whose
        // property access would message the runtime on the render thread).
        let scratch = self.scratch
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
            // The input renders DIRECTLY into the output buffers — the pass-through IS
            // this call; there is deliberately no per-sample loop for V1b to inherit.
            return pull(&pullFlags, timestamp, frameCount, 0, outputData)
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
