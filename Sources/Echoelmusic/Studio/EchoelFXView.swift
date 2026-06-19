//
//  EchoelFXView.swift
//  Echoelmusic — Studio
//
//  Control surface for the insert FX chain on the bio-reactive synth voice
//  (EchoelFX tool). The DSP chain (EchoelFXChain) is an audio-thread object and
//  intentionally NOT @Observable; this view drives it through a small @Observable
//  view-model that write-throughs plain Float/Bool/enum params (the same
//  atomic-width cross-thread contract the voice already documents).
//
//  Honors §UI: solid dark ground, labels above values, small radii, single
//  bio-green accent, no glow/glassmorphism, no decorative charts.
//

#if canImport(SwiftUI)
import SwiftUI

// MARK: - View model (write-through mirror of EchoelFXChain)

@MainActor
@Observable
final class FXViewModel {

    /// The audio-thread FX chain this surface drives. Stored DIRECTLY (not via a
    /// specific voice) so the same control surface works for any voice that owns an
    /// EchoelFXChain — the bio breath voice and the polyphonic melody voice both.
    @ObservationIgnored private let chain: EchoelFXChain
    /// Master insert-FX gate, injected as a setter so the view-model stays
    /// voice-agnostic (each voice exposes its own `setFXEnabled`).
    @ObservationIgnored private let setMaster: (Bool) -> Void

    /// Live tempo, so delay times / LFO rates can be entered as note divisions.
    var bpm: Double

    init(chain: EchoelFXChain, bpm: Double = 120,
         masterEnabled: @escaping () -> Bool,
         setMasterEnabled: @escaping (Bool) -> Void) {
        self.chain = chain
        self.bpm = bpm
        self.setMaster = setMasterEnabled
        let c = chain
        fxEnabled = masterEnabled()
        // Seed mirrors from the live chain so the UI reflects current state.
        filterEnabled = c.filterEnabled; filterMode = c.filterL.mode
        filterCutoff = c.filterL.cutoff; filterResonance = c.filterL.resonance
        delayEnabled = c.delayEnabled; delayMode = c.delay.mode
        delayMix = c.delay.mix; delayTime = c.delay.timeSeconds
        delayFeedback = c.delay.feedback; delayTone = c.delay.tone
        delayWow = c.delay.wow; delayDrive = c.delay.drive
        chorusEnabled = c.chorusEnabled; chorusRate = c.chorus.rate
        chorusDepth = c.chorus.depth; chorusMix = c.chorus.mix
        flangerEnabled = c.flangerEnabled; flangerRate = c.flanger.rate
        flangerDepth = c.flanger.depth; flangerFeedback = c.flanger.feedback; flangerMix = c.flanger.mix
        phaserEnabled = c.phaserEnabled; phaserRate = c.phaser.rate
        phaserDepth = c.phaser.depth; phaserFeedback = c.phaser.feedback; phaserMix = c.phaser.mix
        tremoloEnabled = c.tremoloEnabled; tremoloRate = c.tremolo.rate
        tremoloDepth = c.tremolo.depth; tremoloPan = c.tremolo.stereoPan
        compEnabled = c.compressorEnabled; compThreshold = c.compressor.thresholdDb
        compRatio = c.compressor.ratio; compMakeup = c.compressor.makeupDb
        limiterEnabled = c.limiterEnabled; limiterCeiling = c.limiter.ceilingDb
    }

    // Master
    var fxEnabled: Bool { didSet { setMaster(fxEnabled) } }

    // Filter (tone — underwater low-pass, telephone band-pass, lo-fi)
    var filterEnabled: Bool { didSet { chain.filterEnabled = filterEnabled } }
    var filterMode: EchoelSVFilter.Mode { didSet { chain.filterL.mode = filterMode; chain.filterR.mode = filterMode } }
    var filterCutoff: Float { didSet { chain.filterL.cutoff = filterCutoff; chain.filterR.cutoff = filterCutoff } }
    var filterResonance: Float { didSet { chain.filterL.resonance = filterResonance; chain.filterR.resonance = filterResonance } }

    // Delay
    var delayEnabled: Bool { didSet { chain.delayEnabled = delayEnabled } }
    var delayMode: EchoelDelay.Mode { didSet { chain.delay.mode = delayMode } }
    var delayMix: Float { didSet { chain.delay.mix = delayMix } }
    var delayTime: Float { didSet { chain.delay.timeSeconds = delayTime } }
    var delayFeedback: Float { didSet { chain.delay.feedback = delayFeedback } }
    var delayTone: Float { didSet { chain.delay.tone = delayTone } }
    var delayWow: Float { didSet { chain.delay.wow = delayWow } }
    var delayDrive: Float { didSet { chain.delay.drive = delayDrive } }

    // Chorus
    var chorusEnabled: Bool { didSet { chain.chorusEnabled = chorusEnabled } }
    var chorusRate: Float { didSet { chain.chorus.rate = chorusRate } }
    var chorusDepth: Float { didSet { chain.chorus.depth = chorusDepth } }
    var chorusMix: Float { didSet { chain.chorus.mix = chorusMix } }

    // Flanger
    var flangerEnabled: Bool { didSet { chain.flangerEnabled = flangerEnabled } }
    var flangerRate: Float { didSet { chain.flanger.rate = flangerRate } }
    var flangerDepth: Float { didSet { chain.flanger.depth = flangerDepth } }
    var flangerFeedback: Float { didSet { chain.flanger.feedback = flangerFeedback } }
    var flangerMix: Float { didSet { chain.flanger.mix = flangerMix } }

    // Phaser
    var phaserEnabled: Bool { didSet { chain.phaserEnabled = phaserEnabled } }
    var phaserRate: Float { didSet { chain.phaser.rate = phaserRate } }
    var phaserDepth: Float { didSet { chain.phaser.depth = phaserDepth } }
    var phaserFeedback: Float { didSet { chain.phaser.feedback = phaserFeedback } }
    var phaserMix: Float { didSet { chain.phaser.mix = phaserMix } }

    // Tremolo
    var tremoloEnabled: Bool { didSet { chain.tremoloEnabled = tremoloEnabled } }
    var tremoloRate: Float { didSet { chain.tremolo.rate = tremoloRate } }
    var tremoloDepth: Float { didSet { chain.tremolo.depth = tremoloDepth } }
    var tremoloPan: Bool { didSet { chain.tremolo.stereoPan = tremoloPan } }

    // Compressor
    var compEnabled: Bool { didSet { chain.compressorEnabled = compEnabled } }
    var compThreshold: Float { didSet { chain.compressor.thresholdDb = compThreshold } }
    var compRatio: Float { didSet { chain.compressor.ratio = compRatio } }
    var compMakeup: Float { didSet { chain.compressor.makeupDb = compMakeup } }

    // Limiter
    var limiterEnabled: Bool { didSet { chain.limiterEnabled = limiterEnabled } }
    var limiterCeiling: Float { didSet { chain.limiter.ceilingDb = limiterCeiling } }

    // MARK: - Production characters

    /// Stamp a one-tap production character (Underwater, Telephone, …) onto the
    /// chain, turn the insert on, and refresh every slider so the UI reflects the
    /// new state. `.auto` is excluded here (no genre context in the FX tool).
    func applyCharacter(_ character: FXCharacter) {
        // Non-auto characters carry their own preset; the genre arg is unused.
        character.apply(to: chain, bpm: bpm, genre: .selfObservation)
        fxEnabled = true
        reseed()
    }

    /// Re-read every mirror from the live chain (after a character stamp). The
    /// write-back through each `didSet` is idempotent — same values land on the
    /// chain — so this only resynchronises the UI.
    func reseed() {
        let c = chain
        filterEnabled = c.filterEnabled; filterMode = c.filterL.mode
        filterCutoff = c.filterL.cutoff; filterResonance = c.filterL.resonance
        delayEnabled = c.delayEnabled; delayMode = c.delay.mode
        delayMix = c.delay.mix; delayTime = c.delay.timeSeconds
        delayFeedback = c.delay.feedback; delayTone = c.delay.tone
        delayWow = c.delay.wow; delayDrive = c.delay.drive
        chorusEnabled = c.chorusEnabled; chorusRate = c.chorus.rate
        chorusDepth = c.chorus.depth; chorusMix = c.chorus.mix
        phaserEnabled = c.phaserEnabled; phaserRate = c.phaser.rate
        phaserDepth = c.phaser.depth; phaserMix = c.phaser.mix
    }
}

// MARK: - View

@MainActor
struct EchoelFXView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm: FXViewModel

    /// Drive any voice's insert chain. `fxEnabled`/`setFXEnabled` bridge the
    /// voice's master gate so the surface stays decoupled from the voice type.
    init(chain: EchoelFXChain, bpm: Double = 120,
         fxEnabled: @escaping () -> Bool,
         setFXEnabled: @escaping (Bool) -> Void) {
        _vm = State(wrappedValue: FXViewModel(chain: chain, bpm: bpm,
                                              masterEnabled: fxEnabled,
                                              setMasterEnabled: setFXEnabled))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Insert FX", isOn: $vm.fxEnabled)
                        .tint(EchoelTheme.accent)
                    Menu {
                        ForEach(FXCharacter.allCases.filter { $0 != .auto }) { ch in
                            Button { vm.applyCharacter(ch) } label: {
                                Text(ch.displayName)
                            }
                        }
                    } label: {
                        Label("Stamp a character…", systemImage: "wand.and.stars")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(EchoelTheme.accent)
                    }
                    .accessibilityHint("Apply a production sound like Underwater or Telephone, then tweak below")
                } footer: {
                    Text("Applies the EchoelFX chain: filter → modulation → delay → dynamics. Stamp a character (Underwater, Telephone, Cassette…) for an instant sound, then tweak. Off by default.")
                }

                effectSection("Filter", isOn: $vm.filterEnabled) {
                    Picker("Type", selection: $vm.filterMode) {
                        Text("Low-pass").tag(EchoelSVFilter.Mode.lowpass)
                        Text("High-pass").tag(EchoelSVFilter.Mode.highpass)
                        Text("Band-pass").tag(EchoelSVFilter.Mode.bandpass)
                        Text("Notch").tag(EchoelSVFilter.Mode.notch)
                    }
                    .pickerStyle(.segmented)
                    slider("Cutoff", $vm.filterCutoff, 80...18000, "%.0f Hz") { $0 }
                    slider("Resonance", $vm.filterResonance, 0...0.95, "%.0f%%") { $0 * 100 }
                }

                effectSection("Delay", isOn: $vm.delayEnabled) {
                    Picker("Mode", selection: $vm.delayMode) {
                        Text("Digital").tag(EchoelDelay.Mode.digital)
                        Text("Tape").tag(EchoelDelay.Mode.tape)
                        Text("Ping-Pong").tag(EchoelDelay.Mode.pingPong)
                    }
                    .pickerStyle(.segmented)
                    slider("Time", $vm.delayTime, 0.02...1.5, "%.0f ms") { $0 * 1000 }
                    syncMenu($vm.delayTime, .seconds(0.02...1.5))
                    slider("Feedback", $vm.delayFeedback, 0...0.95, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.delayMix, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Tone", $vm.delayTone, 0...1, "%.0f%%") { $0 * 100 }
                    if vm.delayMode == .tape {
                        slider("Wow/Flutter", $vm.delayWow, 0...1, "%.0f%%") { $0 * 100 }
                        slider("Drive", $vm.delayDrive, 0...1, "%.0f%%") { $0 * 100 }
                    }
                }

                effectSection("Chorus", isOn: $vm.chorusEnabled) {
                    slider("Rate", $vm.chorusRate, 0.05...8, "%.2f Hz") { $0 }
                    syncMenu($vm.chorusRate, .hertz(0.05...8))
                    slider("Depth", $vm.chorusDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.chorusMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Flanger", isOn: $vm.flangerEnabled) {
                    slider("Rate", $vm.flangerRate, 0.05...8, "%.2f Hz") { $0 }
                    syncMenu($vm.flangerRate, .hertz(0.05...8))
                    slider("Depth", $vm.flangerDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Feedback", $vm.flangerFeedback, -0.95...0.95, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.flangerMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Phaser", isOn: $vm.phaserEnabled) {
                    slider("Rate", $vm.phaserRate, 0.05...8, "%.2f Hz") { $0 }
                    syncMenu($vm.phaserRate, .hertz(0.05...8))
                    slider("Depth", $vm.phaserDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Feedback", $vm.phaserFeedback, 0...0.95, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.phaserMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Tremolo", isOn: $vm.tremoloEnabled) {
                    slider("Rate", $vm.tremoloRate, 0.05...8, "%.2f Hz") { $0 }
                    syncMenu($vm.tremoloRate, .hertz(0.05...8))
                    slider("Depth", $vm.tremoloDepth, 0...1, "%.0f%%") { $0 * 100 }
                    Toggle("Auto-Pan", isOn: $vm.tremoloPan).tint(EchoelTheme.accent)
                }

                effectSection("Compressor", isOn: $vm.compEnabled) {
                    slider("Threshold", $vm.compThreshold, -48...0, "%.1f dB") { $0 }
                    slider("Ratio", $vm.compRatio, 1...20, "%.1f:1") { $0 }
                    slider("Make-up", $vm.compMakeup, 0...18, "%.1f dB") { $0 }
                }

                effectSection("Limiter", isOn: $vm.limiterEnabled) {
                    slider("Ceiling", $vm.limiterCeiling, -12...0, "%.1f dB") { $0 }
                }
            }
            .navigationTitle("EchoelFX")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func effectSection<Content: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Toggle(isOn: isOn) {
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .tint(EchoelTheme.accent)
            .textCase(nil)
        }
        // Per-stage controls are inert until the master Insert FX gate is on.
        .disabled(!vm.fxEnabled)
    }

    /// Whether a tempo-sync menu sets an LFO rate (Hz) or a delay time (seconds).
    private enum SyncKind {
        case hertz(ClosedRange<Float>)
        case seconds(ClosedRange<Float>)
    }

    /// A "Sync to tempo" menu: pick a note division and the rate/time is set from
    /// the live BPM (the studio calculator, in the effects). Clamped to the
    /// parameter's valid range so the audio thread never gets an out-of-range value.
    @ViewBuilder
    private func syncMenu(_ value: Binding<Float>, _ kind: SyncKind) -> some View {
        Menu {
            ForEach(TempoSyncOption.common) { opt in
                Button {
                    switch kind {
                    case .hertz(let r):   value.wrappedValue = opt.clampedRate(bpm: vm.bpm, in: r)
                    case .seconds(let r): value.wrappedValue = opt.clampedSeconds(bpm: vm.bpm, in: r)
                    }
                } label: {
                    switch kind {
                    case .hertz:
                        Text("\(opt.label)  ·  \(Precision.two(opt.hertz(bpm: vm.bpm))) Hz")
                    case .seconds:
                        Text("\(opt.label)  ·  \(Precision.two(opt.milliseconds(bpm: vm.bpm))) ms")
                    }
                }
            }
        } label: {
            Label("Sync · \(Precision.two(vm.bpm)) BPM", systemImage: "metronome")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EchoelTheme.accent)
        }
        .accessibilityHint("Set this rate from a musical note division at the current tempo")
    }

    /// A labelled slider with a live, formatted value read-out.
    /// `display` maps the raw stored value to the number shown.
    private func slider(
        _ title: String,
        _ value: Binding<Float>,
        _ range: ClosedRange<Float>,
        _ format: String,
        display: @escaping (Float) -> Float
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(EchoelTheme.dim)
                Spacer()
                Text(String(format: format, display(value.wrappedValue)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
            }
            Slider(value: value, in: range).tint(EchoelTheme.accent)
        }
        .padding(.vertical, 2)
    }
}
#endif
