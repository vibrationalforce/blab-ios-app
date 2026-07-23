#if canImport(AVFoundation)
import Foundation
import AVFoundation
import os

/// AUv3 Audio Unit — Bio-Reactive Instrument (Music Device)
///
/// A playable DAW instrument: host MIDI notes drive the pitch (walked from the
/// render block's realtime event list) while bio-reactive parameters (coherence,
/// HRV, heart rate, breath) shape the timbre. Before the first MIDI note a
/// free-running bio tone plays as the idle default (armed once in
/// `allocateRenderResources`); once the host plays notes, a note-off releases the
/// voice like any instrument. Parameters are automatable from Logic Pro,
/// GarageBand, AUM, etc.
///
/// Component: aumu/echl/Echo (instrument — MIDI in, no audio input needed)
public final class EchoelmusicAudioUnit: AUAudioUnit {

    private static let auLog = OSLog(
        subsystem: "com.echoelmusic.app.auv3",
        category: "AudioUnit"
    )

    // MARK: - DSP

    private let synth = EchoelDDSP(sampleRate: 48000)
    private let texture = EchoelCellular(cellCount: 128, sampleRate: 48000)
    private var isNoteOn = false

    /// Shared vitals from the main app over the App Group. Refreshed OFF the
    /// render thread by `vitalsTimer`; the render block never reads UserDefaults.
    private let bioFeedback = BioFeedbackManager()
    nonisolated(unsafe) private var vitalsTimer: DispatchSourceTimer?

    /// Timestamp of the last shared frame folded into the bio params — dedupe
    /// so an unchanged store never re-fires the param observer. Touched only
    /// on the vitals timer's serial queue.
    nonisolated(unsafe) private var lastVitalsTimestamp: TimeInterval = -1

    /// Only shared vitals younger than this may overwrite the host-automatable
    /// bio params. Stale / absent / non-egress data ⇒ the params keep whatever
    /// the host, automation, or preset set — byte-identical behavior to running
    /// without the main app. `nonisolated` explicitly: read from the vitals
    /// timer queue (CLAUDE.md static-let isolation gotcha).
    nonisolated private static let vitalsMaxAge: TimeInterval = 2

    /// Pre-allocated scratch buffers for render block — NO heap allocation on audio thread
    nonisolated(unsafe) private var padScratch = [Float](repeating: 0, count: 4096)
    nonisolated(unsafe) private var texScratch = [Float](repeating: 0, count: 4096)

    /// Lock-free master-gain mirror for the render thread. The host sets gain via
    /// the ObjC/KVO-backed `AUParameter.value`, which must NOT be read on the audio
    /// thread — the value observer writes it here and the render block reads this
    /// plain Float (atomic-width, no ObjC, no locks). Captured by the block instead
    /// of `self` (capture a value holder, not the actor).
    private final class GainMirror { nonisolated(unsafe) var value: Float = 0.7 }
    private let gainMirror = GainMirror()

    /// Render-thread mirror of the four bio parameters (same pattern as GainMirror).
    /// The parameter value observer can fire on ANY control thread (the vitals utility
    /// queue via pullSharedVitals, host automation, the plugin UI), so it writes these
    /// atomic-width Floats; the render block reads them and calls `applyBioReactive`
    /// RENDER-SIDE (throttled ~10 Hz). That keeps the synth's `harmonicAmplitudes`
    /// array single-owner (render-thread only): its every-6th-call in-place rewrite
    /// (`updateSpectralEnvelope`, verified all-subscript, no realloc) can then never
    /// race a concurrent render read AND never triggers a copy-on-write allocation
    /// (COW copies only when a 2nd thread holds a reference). This closes the
    /// KNOWN-SMELL bio-path COW hazard documented on EchoelDDSP. A MIRROR (not an SPSC
    /// queue like PolySynthVoice v337) is required here because the producer side is
    /// multi-threaded, which single-producer SPSC forbids.
    private final class BioMirror {
        nonisolated(unsafe) var coherence: Float = 0.5
        nonisolated(unsafe) var hrv: Float = 0.5
        nonisolated(unsafe) var heartRate: Float = 0.5
        nonisolated(unsafe) var breathPhase: Float = 0.5
    }
    private let bioMirror = BioMirror()
    /// Render-owned frame accumulator throttling the render-side bio application to
    /// ~10 Hz (the vitals poll rate) — bounds the audio-thread cost to what it was.
    /// Touched ONLY by the render thread (single-owner), so the plain field is safe.
    private final class BioRenderState { nonisolated(unsafe) var frameAccum = 0 }
    private let bioRenderState = BioRenderState()

    // MARK: - Buses

    private var _outputBusArray: AUAudioUnitBusArray!
    private var outputBus: AUAudioUnitBus!

    // MARK: - Parameters

    private var _parameterTree: AUParameterTree!

    // Bio parameters (automatable from host)
    private var coherenceParam: AUParameter!
    private var hrvParam: AUParameter!
    private var heartRateParam: AUParameter!
    private var breathPhaseParam: AUParameter!
    private var baseFreqParam: AUParameter!
    private var textureAmountParam: AUParameter!
    private var reverbMixParam: AUParameter!
    private var masterGainParam: AUParameter!

    // MARK: - Init

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        try super.init(componentDescription: componentDescription, options: options)

        guard let defaultFormat = AVAudioFormat(
            standardFormatWithSampleRate: 48000, channels: 2
        ) else {
            throw NSError(domain: "com.echoelmusic.app.auv3", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }

        outputBus = try AUAudioUnitBus(format: defaultFormat)
        _outputBusArray = AUAudioUnitBusArray(
            audioUnit: self, busType: .output, busses: [outputBus]
        )

        // Configure texture
        texture.synthMode = .additive
        texture.rule = .rule90
        texture.gain = 0.15
        texture.frequency = 110
        texture.evolutionRate = 8

        setupParameterTree()
        os_log(.info, log: Self.auLog, "AUv3 Instrument initialized")
    }

    // MARK: - Parameter Tree

    enum ParameterAddress: UInt64 {
        case coherence = 0
        case hrv = 1
        case heartRate = 2
        case breathPhase = 3
        case baseFrequency = 4
        case textureAmount = 5
        case reverbMix = 6
        case masterGain = 7
    }

    private func setupParameterTree() {
        coherenceParam = AUParameterTree.createParameter(
            withIdentifier: "coherence", name: "Coherence",
            address: ParameterAddress.coherence.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        coherenceParam.value = 0.5

        hrvParam = AUParameterTree.createParameter(
            withIdentifier: "hrv", name: "HRV",
            address: ParameterAddress.hrv.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        hrvParam.value = 0.5

        heartRateParam = AUParameterTree.createParameter(
            withIdentifier: "heartRate", name: "Heart Rate",
            address: ParameterAddress.heartRate.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        heartRateParam.value = 0.5

        breathPhaseParam = AUParameterTree.createParameter(
            withIdentifier: "breathPhase", name: "Breath Phase",
            address: ParameterAddress.breathPhase.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        breathPhaseParam.value = 0.5

        baseFreqParam = AUParameterTree.createParameter(
            withIdentifier: "baseFrequency", name: "Base Frequency",
            address: ParameterAddress.baseFrequency.rawValue,
            min: 40, max: 440, unit: .hertz, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        baseFreqParam.value = 220

        textureAmountParam = AUParameterTree.createParameter(
            withIdentifier: "textureAmount", name: "Texture",
            address: ParameterAddress.textureAmount.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        textureAmountParam.value = 0.3

        reverbMixParam = AUParameterTree.createParameter(
            withIdentifier: "reverbMix", name: "Reverb",
            address: ParameterAddress.reverbMix.rawValue,
            min: 0, max: 1, unit: .generic, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        reverbMixParam.value = 0.3

        masterGainParam = AUParameterTree.createParameter(
            withIdentifier: "masterGain", name: "Master Gain",
            address: ParameterAddress.masterGain.rawValue,
            min: 0, max: 1, unit: .linearGain, unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil, dependentParameters: nil
        )
        masterGainParam.value = 0.7

        let bioGroup = AUParameterTree.createGroup(
            withIdentifier: "bio", name: "Bio-Reactive",
            children: [coherenceParam, hrvParam, heartRateParam, breathPhaseParam]
        )
        let soundGroup = AUParameterTree.createGroup(
            withIdentifier: "sound", name: "Sound",
            children: [baseFreqParam, textureAmountParam, reverbMixParam, masterGainParam]
        )

        _parameterTree = AUParameterTree.createTree(withChildren: [bioGroup, soundGroup])
        self.parameterTree = _parameterTree

        // Value provider — read from synth
        let synthRef = synth
        let textureRef = texture
        _parameterTree.implementorValueProvider = { param in
            guard let addr = ParameterAddress(rawValue: param.address) else { return param.value }
            switch addr {
            case .coherence:    return synthRef.harmonicity
            case .hrv:          return synthRef.brightness
            case .heartRate:    return param.value
            case .breathPhase:  return synthRef.amplitude
            case .baseFrequency: return synthRef.frequency
            case .textureAmount: return textureRef.gain
            case .reverbMix:    return synthRef.reverbMix
            case .masterGain:   return param.value
            }
        }

        // Value observer — write to synth
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            guard let self,
                  let addr = ParameterAddress(rawValue: param.address) else { return }
            switch addr {
            case .coherence, .hrv, .heartRate, .breathPhase:
                // Mirror the four bio params for the render thread; applyBioReactive now
                // runs RENDER-SIDE (see internalRenderBlock) so the synth's
                // harmonicAmplitudes array stays single-owner — no cross-thread COW race
                // and no audio-thread allocation. texture.coherence is a scalar
                // (atomic-width Float) — safe to set directly here.
                self.bioMirror.coherence = self.coherenceParam.value
                self.bioMirror.hrv = self.hrvParam.value
                self.bioMirror.heartRate = self.heartRateParam.value
                self.bioMirror.breathPhase = self.breathPhaseParam.value
                self.texture.coherence = self.coherenceParam.value
            case .baseFrequency:
                self.synth.frequency = value
                self.texture.frequency = value * 0.5
            case .textureAmount:
                self.texture.gain = value
            case .reverbMix:
                self.synth.reverbMix = value
            case .masterGain:
                self.gainMirror.value = value // mirror for the render thread
            }
        }
    }

    // MARK: - AUAudioUnit Overrides

    public override var inputBusses: AUAudioUnitBusArray {
        // Instrument — no audio input (MIDI drives pitch)
        AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [])
    }

    public override var outputBusses: AUAudioUnitBusArray { _outputBusArray }

    public override var canProcessInPlace: Bool { false }
    public override var supportsUserPresets: Bool { true }
    public override var latency: TimeInterval { 0 }
    public override var tailTime: TimeInterval { 2.0 }

    // MARK: - Presets

    public override var factoryPresets: [AUAudioUnitPreset]? {
        (0..<3).map { i in
            let p = AUAudioUnitPreset()
            p.number = i
            p.name = ["Ambient Calm", "Deep Sleep", "Active Focus"][i]
            return p
        }
    }

    public override var currentPreset: AUAudioUnitPreset? {
        didSet {
            guard let p = currentPreset, p.number >= 0 else { return }
            switch p.number {
            case 0: // Ambient Calm
                baseFreqParam.value = 220; coherenceParam.value = 0.7
                textureAmountParam.value = 0.2; reverbMixParam.value = 0.4
            case 1: // Deep Sleep
                baseFreqParam.value = 55; coherenceParam.value = 0.8
                textureAmountParam.value = 0.1; reverbMixParam.value = 0.6
            case 2: // Active Focus
                baseFreqParam.value = 330; coherenceParam.value = 0.5
                textureAmountParam.value = 0.4; reverbMixParam.value = 0.2
            default: break
            }
        }
    }

    // MARK: - State

    public override var fullState: [String: Any]? {
        get {
            var s = super.fullState ?? [:]
            let params = [coherenceParam, hrvParam, heartRateParam, breathPhaseParam,
                          baseFreqParam, textureAmountParam, reverbMixParam, masterGainParam]
            for p in params.compactMap({ $0 }) {
                s[p.identifier] = p.value
            }
            return s
        }
        set {
            super.fullState = newValue
            guard let s = newValue else { return }
            let params = [coherenceParam, hrvParam, heartRateParam, breathPhaseParam,
                          baseFreqParam, textureAmountParam, reverbMixParam, masterGainParam]
            for p in params.compactMap({ $0 }) {
                // fullState is host/preset-file controlled (third-party documents).
                // Reject non-finite values and clamp to each param's range so a
                // malformed preset can't inject NaN/huge gain into the render block.
                if let v = s[p.identifier] as? Float, v.isFinite {
                    p.value = min(max(v, p.minValue), p.maxValue)
                }
            }
        }
    }

    // MARK: - Rendering

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        // Start generating
        synth.amplitude = 0.6
        synth.noteOn(frequency: baseFreqParam.value)
        isNoteOn = true
        startVitalsPolling()
        os_log(.info, log: Self.auLog, "Instrument started: %.0f Hz", baseFreqParam.value)
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        vitalsTimer?.cancel()
        vitalsTimer = nil
        if isNoteOn { synth.noteOff(); isNoteOn = false }
        os_log(.info, log: Self.auLog, "Instrument stopped")
    }

    // MARK: - Shared vitals (App Group → bio params)

    /// Starts a 10 Hz utility-queue timer (NOT the render thread) that reads the
    /// latest vitals shared by the main app and pushes them into the bio params.
    /// 10 Hz matches the app's publish tick so breath phase moves like a live
    /// signal; the per-frame timestamp dedupe below keeps actual param writes
    /// at the source frame rate. UserDefaults reads are cfprefsd-cached — this
    /// stays control-plane cheap.
    private func startVitalsPolling() {
        let timer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.echoelmusic.app.auv3.vitals", qos: .utility)
        )
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in self?.pullSharedVitals() }
        timer.resume()
        vitalsTimer = timer
    }

    /// Folds the latest App-Group vitals into the bio params; the existing
    /// param observer applies them to the synth. Runs off the render thread.
    ///
    /// Guard chain (any failure leaves the params EXACTLY as the host set them —
    /// live bridge and host automation share the same `AUParameter.value` path):
    ///   1. decodes + all-finite (BioFeedbackManager rejects NaN/∞ payloads),
    ///   2. `egressAllowed` — 5.1.3: HealthKit-store frames must never surface
    ///      in host-visible params; only Echoel's own measurements pass,
    ///   3. fresh (< ~2 s on the shared reference-date clock) — a quit/crashed
    ///      main app stops steering within 2 s instead of freezing the params
    ///      on the last value forever,
    ///   4. new timestamp — an unchanged store never re-fires the observer.
    private func pullSharedVitals() {
        guard let vitals = bioFeedback.refreshFromSharedStore(),
              vitals.egressAllowed,
              vitals.isFresh(within: Self.vitalsMaxAge),
              vitals.timestamp != lastVitalsTimestamp else { return }
        lastVitalsTimestamp = vitals.timestamp
        coherenceParam.value = min(max(vitals.coherence, 0), 1)
        hrvParam.value = min(max(vitals.hrvNormalized, 0), 1)
        heartRateParam.value = max(0, min(1, (vitals.heartRateBPM - 40) / 160))
        breathPhaseParam.value = min(max(vitals.breathPhase, 0), 1)
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let synthRef = self.synth
        let textureRef = self.texture
        let gainBox = self.gainMirror
        let padRef = self.padScratch
        let texRef = self.texScratch
        let bioBox = self.bioMirror
        let bioState = self.bioRenderState
        // ~10 Hz throttle for the render-side bio application (sampleRate/10 frames).
        let bioInterval = max(1, Int(self.synth.sampleRate / 10))

        return { (actionFlags, timestamp, frameCount, outputBusNumber,
                  outputData, renderEvent, pullInputBlock) in

            let count = min(Int(frameCount), 4096)

            // MIDI note input (music-device / aumu). Walk the host's realtime event
            // list and drive the mono voice's pitch. This is pure pointer + scalar
            // work plus EchoelDDSP.noteOn/noteOff (both scalar-assignment only) — no
            // allocation, no lock, no ObjC, no GCD: audio-thread safe. Block-granular
            // (all events applied before the block renders); the last note in the
            // block wins for a mono voice. With NO note event, nothing changes and the
            // free-running bio tone armed in allocateRenderResources keeps playing.
            // Only legacy AUMIDIEvent (.MIDI) is handled — correct for the default
            // MIDI-1.0 protocol, where hosts translate to legacy events. A future host
            // negotiating MIDI-2.0 UMP would deliver .MIDIEventList instead (add a
            // branch here if that is ever adopted).
            var event: UnsafePointer<AURenderEvent>? = renderEvent
            while let e = event {
                let header = e.pointee.head
                if header.eventType == .MIDI {
                    let midi = e.pointee.MIDI
                    if midi.length >= 3 {
                        switch EchoelMIDIDecode.action(status: midi.data.0,
                                                       data1: midi.data.1,
                                                       data2: midi.data.2) {
                        case let .noteOn(frequency, velocity):
                            synthRef.noteVelocity = velocity
                            synthRef.noteOn(frequency: frequency)
                        case .noteOff:
                            synthRef.noteOff()
                        case .ignore:
                            break
                        }
                    }
                }
                // `AURenderEventHeader.next` imports as an UnsafeMutablePointer while the
                // list head is a const UnsafePointer — convert so the walk stays const.
                event = header.next.map { UnsafePointer($0) }
            }

            // Apply bio params RENDER-SIDE (throttled ~10 Hz) from the atomic mirrors —
            // never read AUParameter here. Running applyBioReactive on the render thread
            // keeps the synth's harmonicAmplitudes array single-owner: no cross-thread
            // COW race, and its in-place rewrite triggers no allocation. See BioMirror.
            bioState.frameAccum += count
            if bioState.frameAccum >= bioInterval {
                bioState.frameAccum = 0
                synthRef.applyBioReactive(coherence: bioBox.coherence,
                                          hrvVariability: bioBox.hrv,
                                          heartRate: bioBox.heartRate,
                                          breathPhase: bioBox.breathPhase)
            }

            // Use pre-allocated scratch (captured by value — COW safe since we own them)
            var pad = padRef
            var tex = texRef
            for i in 0..<count { pad[i] = 0; tex[i] = 0 }

            synthRef.render(buffer: &pad, frameCount: count)
            textureRef.render(buffer: &tex, frameCount: count)

            // Mix and apply master gain (lock-free mirror — never read AUParameter here)
            let gain = gainBox.value
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            for buf in ablPointer {
                guard let data = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<count {
                    data[i] = (pad[i] + tex[i]) * gain
                }
            }

            return noErr
        }
    }
}
#endif
