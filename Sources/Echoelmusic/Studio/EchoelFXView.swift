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

    @ObservationIgnored private let voice: BioReactiveSynthVoice
    @ObservationIgnored private var chain: EchoelFXChain { voice.fxChain }

    init(voice: BioReactiveSynthVoice) {
        self.voice = voice
        let c = voice.fxChain
        fxEnabled = voice.isFXEnabled
        // Seed mirrors from the live chain so the UI reflects current state.
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
    var fxEnabled: Bool { didSet { voice.setFXEnabled(fxEnabled) } }

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
}

// MARK: - View

@MainActor
struct EchoelFXView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm: FXViewModel

    init(voice: BioReactiveSynthVoice) {
        _vm = State(wrappedValue: FXViewModel(voice: voice))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Insert FX", isOn: $vm.fxEnabled)
                        .tint(EchoelTheme.accent)
                } footer: {
                    Text("Applies the EchoelFX chain to the bio-synth voice: modulation → delay → dynamics. Off by default.")
                }

                effectSection("Delay", isOn: $vm.delayEnabled) {
                    Picker("Mode", selection: $vm.delayMode) {
                        Text("Digital").tag(EchoelDelay.Mode.digital)
                        Text("Tape").tag(EchoelDelay.Mode.tape)
                        Text("Ping-Pong").tag(EchoelDelay.Mode.pingPong)
                    }
                    .pickerStyle(.segmented)
                    slider("Time", $vm.delayTime, 0.02...1.5, "%.0f ms") { $0 * 1000 }
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
                    slider("Depth", $vm.chorusDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.chorusMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Flanger", isOn: $vm.flangerEnabled) {
                    slider("Rate", $vm.flangerRate, 0.05...8, "%.2f Hz") { $0 }
                    slider("Depth", $vm.flangerDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Feedback", $vm.flangerFeedback, -0.95...0.95, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.flangerMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Phaser", isOn: $vm.phaserEnabled) {
                    slider("Rate", $vm.phaserRate, 0.05...8, "%.2f Hz") { $0 }
                    slider("Depth", $vm.phaserDepth, 0...1, "%.0f%%") { $0 * 100 }
                    slider("Feedback", $vm.phaserFeedback, 0...0.95, "%.0f%%") { $0 * 100 }
                    slider("Mix", $vm.phaserMix, 0...1, "%.0f%%") { $0 * 100 }
                }

                effectSection("Tremolo", isOn: $vm.tremoloEnabled) {
                    slider("Rate", $vm.tremoloRate, 0.05...8, "%.2f Hz") { $0 }
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
