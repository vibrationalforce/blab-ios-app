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
        saturationEnabled = c.saturationEnabled; saturationDrive = c.saturationDrive; saturationMix = c.saturationMix
        harmonizerEnabled = c.harmonizerEnabled; harmInterval1 = c.harmonizer.interval1
        harmInterval2 = c.harmonizer.interval2; harmVoice2 = c.harmonizer.voice2Enabled; harmMix = c.harmonizer.mix
        reverbEnabled = c.reverbEnabled; reverbRoomSize = c.reverb.roomSize
        reverbDamping = c.reverb.damping; reverbMix = c.reverb.mix; reverbWidth = c.reverb.width
        tapeEnabled = c.tapeEnabled; tapeDepth = c.tape.depth
        tapeSaturation = c.tape.saturation; tapeTone = c.tape.tone
        bitcrushEnabled = c.bitcrushEnabled; bitcrushBits = c.bitcrush.bits
        bitcrushDownsample = c.bitcrush.downsample; bitcrushMix = c.bitcrush.mix
        widenerEnabled = c.widenerEnabled; widenerWidth = c.widener.width
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

    // Saturation (analog warmth — on by default)
    var saturationEnabled: Bool { didSet { chain.saturationEnabled = saturationEnabled } }
    var saturationDrive: Float { didSet { chain.saturationDrive = saturationDrive } }
    var saturationMix: Float { didSet { chain.saturationMix = saturationMix } }

    // Tape / Bandmaschine / VHS (analog character — wow&flutter + saturation + HF loss)
    var tapeEnabled: Bool { didSet { chain.tapeEnabled = tapeEnabled } }
    var tapeDepth: Float { didSet { chain.tape.depth = tapeDepth } }
    var tapeSaturation: Float { didSet { chain.tape.saturation = tapeSaturation } }
    var tapeTone: Float { didSet { chain.tape.tone = tapeTone } }

    // Bitcrush (digital lo-fi)
    var bitcrushEnabled: Bool { didSet { chain.bitcrushEnabled = bitcrushEnabled } }
    var bitcrushBits: Float { didSet { chain.bitcrush.bits = bitcrushBits } }
    var bitcrushDownsample: Float { didSet { chain.bitcrush.downsample = bitcrushDownsample } }
    var bitcrushMix: Float { didSet { chain.bitcrush.mix = bitcrushMix } }

    // Stereo widener (M/S)
    var widenerEnabled: Bool { didSet { chain.widenerEnabled = widenerEnabled } }
    var widenerWidth: Float { didSet { chain.widener.width = widenerWidth } }

    // Harmonizer (added harmony voices above the melody)
    var harmonizerEnabled: Bool { didSet { chain.harmonizerEnabled = harmonizerEnabled } }
    var harmInterval1: Float { didSet { chain.harmonizer.interval1 = harmInterval1 } }
    var harmInterval2: Float { didSet { chain.harmonizer.interval2 = harmInterval2 } }
    var harmVoice2: Bool { didSet { chain.harmonizer.voice2Enabled = harmVoice2 } }
    var harmMix: Float { didSet { chain.harmonizer.mix = harmMix } }

    // Reverb (room / hall space)
    var reverbEnabled: Bool { didSet { chain.reverbEnabled = reverbEnabled } }
    var reverbRoomSize: Float { didSet { chain.reverb.roomSize = reverbRoomSize } }
    var reverbDamping: Float { didSet { chain.reverb.damping = reverbDamping } }
    var reverbMix: Float { didSet { chain.reverb.mix = reverbMix } }
    var reverbWidth: Float { didSet { chain.reverb.width = reverbWidth } }

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
        flangerEnabled = c.flangerEnabled; flangerRate = c.flanger.rate
        flangerDepth = c.flanger.depth; flangerFeedback = c.flanger.feedback; flangerMix = c.flanger.mix
        phaserEnabled = c.phaserEnabled; phaserRate = c.phaser.rate
        phaserDepth = c.phaser.depth; phaserFeedback = c.phaser.feedback; phaserMix = c.phaser.mix
        tremoloEnabled = c.tremoloEnabled; tremoloRate = c.tremolo.rate
        tremoloDepth = c.tremolo.depth; tremoloPan = c.tremolo.stereoPan
        compEnabled = c.compressorEnabled; compThreshold = c.compressor.thresholdDb
        compRatio = c.compressor.ratio; compMakeup = c.compressor.makeupDb
        limiterEnabled = c.limiterEnabled; limiterCeiling = c.limiter.ceilingDb
        saturationEnabled = c.saturationEnabled; saturationDrive = c.saturationDrive; saturationMix = c.saturationMix
        harmonizerEnabled = c.harmonizerEnabled; harmInterval1 = c.harmonizer.interval1
        harmInterval2 = c.harmonizer.interval2; harmVoice2 = c.harmonizer.voice2Enabled; harmMix = c.harmonizer.mix
        reverbEnabled = c.reverbEnabled; reverbRoomSize = c.reverb.roomSize
        reverbDamping = c.reverb.damping; reverbMix = c.reverb.mix; reverbWidth = c.reverb.width
        tapeEnabled = c.tapeEnabled; tapeDepth = c.tape.depth
        tapeSaturation = c.tape.saturation; tapeTone = c.tape.tone
        bitcrushEnabled = c.bitcrushEnabled; bitcrushBits = c.bitcrush.bits
        bitcrushDownsample = c.bitcrush.downsample; bitcrushMix = c.bitcrush.mix
        widenerEnabled = c.widenerEnabled; widenerWidth = c.widener.width
    }

    // MARK: - Preset save / recall

    /// Snapshot the live chain as a saveable/shareable preset.
    func snapshot(name: String, tags: [String] = []) -> FXPreset {
        FXPreset.capture(from: chain, fxEnabled: fxEnabled, name: name, tags: tags)
    }

    /// Apply a saved/community preset to the live chain, flip the master gate to
    /// match, and refresh every UI mirror.
    func apply(_ preset: FXPreset) {
        preset.apply(to: chain)
        fxEnabled = preset.fxEnabled   // didSet bridges the voice's master gate
        reseed()
    }

    /// Macro-morph: continuously blend from preset `a` toward preset `b` by `amount`
    /// [0…1] and write the result live (keeps the master gate as-is). The view drives
    /// this from the morph fader; `reseed()` refreshes every UI mirror.
    func morph(from a: FXPreset, to b: FXPreset, amount: Float) {
        a.morphed(to: b, amount: amount).apply(to: chain)
        reseed()
    }
}

// MARK: - View

@MainActor
struct EchoelFXView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(FXBioModulator.self) private var modulator
    @State private var vm: FXViewModel
    /// The user's own saved presets (local). The curated community set is bundled.
    @State private var presetStore = FXPresetStore()
    @State private var showSaveSheet = false
    @State private var saveName = ""
    /// Preset being renamed (drives the rename alert).
    @State private var renameTarget: FXPreset?
    @State private var renameText = ""
    /// Live filter over preset names + tags (both My presets and Community).
    @State private var presetQuery = ""
    // Macro morph: snapshot of the sound when a target is picked (A), the target (B),
    // and the live morph amount A→B.
    @State private var morphA: FXPreset?
    @State private var morphTarget: FXPreset?
    @State private var morphAmount: Float = 0

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
                presetSection
                macroMorphSection
                FXBioModSection(modulator: modulator)
                BioModLiveView(modulator: modulator)   // live: which body channel moves which FX param
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
                            .font(EchoelTheme.font(13, .semibold))
                            .foregroundStyle(EchoelTheme.accent)
                    }
                    .accessibilityHint("Apply a production sound like Underwater or Telephone, then tweak below")
                } footer: {
                    Text("Applies the EchoelFX chain: filter → modulation → delay → dynamics. Stamp a character (Underwater, Telephone, Cassette…) for an instant sound, then tweak. Off by default.")
                }
                .listRowBackground(EchoelTheme.fill)

                effectSection("Filter", isOn: $vm.filterEnabled) {
                    Picker("Type", selection: $vm.filterMode) {
                        Text("Low-pass").tag(EchoelSVFilter.Mode.lowpass)
                        Text("High-pass").tag(EchoelSVFilter.Mode.highpass)
                        Text("Band-pass").tag(EchoelSVFilter.Mode.bandpass)
                        Text("Notch").tag(EchoelSVFilter.Mode.notch)
                    }
                    .pickerStyle(.segmented)
                    field("Cutoff", $vm.filterCutoff, 80...18000, unit: "Hz", decimals: 0)
                    field("Resonance", $vm.filterResonance, 0...0.95)
                }

                effectSection("Saturation", isOn: $vm.saturationEnabled) {
                    field("Drive", $vm.saturationDrive, 0...1)
                    field("Mix", $vm.saturationMix, 0...1)
                }

                effectSection("Tape / VHS", isOn: $vm.tapeEnabled) {
                    field("Wow & Flutter", $vm.tapeDepth, 0...1)
                    field("Saturation", $vm.tapeSaturation, 0...1)
                    field("Brightness", $vm.tapeTone, 0...1)
                }

                effectSection("Bitcrush", isOn: $vm.bitcrushEnabled) {
                    field("Bits", $vm.bitcrushBits, 1...16, unit: "bit", decimals: 0)
                    field("Downsample", $vm.bitcrushDownsample, 1...64, unit: "×", decimals: 0)
                    field("Mix", $vm.bitcrushMix, 0...1)
                }

                effectSection("Harmonizer", isOn: $vm.harmonizerEnabled) {
                    field("Voice 1", $vm.harmInterval1, -12...12, unit: "st", decimals: 0)
                    Toggle("Voice 2", isOn: $vm.harmVoice2).tint(EchoelTheme.accent)
                    field("Voice 2 interval", $vm.harmInterval2, -12...12, unit: "st", decimals: 0)
                    field("Mix", $vm.harmMix, 0...1)
                }

                effectSection("Reverb", isOn: $vm.reverbEnabled) {
                    field("Size", $vm.reverbRoomSize, 0...1)
                    field("Damping", $vm.reverbDamping, 0...1)
                    field("Width", $vm.reverbWidth, 0...1)
                    field("Mix", $vm.reverbMix, 0...1)
                }

                effectSection("Stereo Width", isOn: $vm.widenerEnabled) {
                    field("Width", $vm.widenerWidth, 0...2)
                }

                effectSection("Delay", isOn: $vm.delayEnabled) {
                    Picker("Mode", selection: $vm.delayMode) {
                        Text("Digital").tag(EchoelDelay.Mode.digital)
                        Text("Tape").tag(EchoelDelay.Mode.tape)
                        Text("Ping-Pong").tag(EchoelDelay.Mode.pingPong)
                    }
                    .pickerStyle(.segmented)
                    field("Time", $vm.delayTime, 0.02...1.5, unit: "s")
                    syncMenu($vm.delayTime, .seconds(0.02...1.5))
                    field("Feedback", $vm.delayFeedback, 0...0.95)
                    field("Mix", $vm.delayMix, 0...1)
                    field("Tone", $vm.delayTone, 0...1)
                    if vm.delayMode == .tape {
                        field("Wow/Flutter", $vm.delayWow, 0...1)
                        field("Drive", $vm.delayDrive, 0...1)
                    }
                }

                effectSection("Chorus", isOn: $vm.chorusEnabled) {
                    field("Rate", $vm.chorusRate, 0.05...8, unit: "Hz")
                    syncMenu($vm.chorusRate, .hertz(0.05...8))
                    field("Depth", $vm.chorusDepth, 0...1)
                    field("Mix", $vm.chorusMix, 0...1)
                }

                effectSection("Flanger", isOn: $vm.flangerEnabled) {
                    field("Rate", $vm.flangerRate, 0.05...8, unit: "Hz")
                    syncMenu($vm.flangerRate, .hertz(0.05...8))
                    field("Depth", $vm.flangerDepth, 0...1)
                    field("Feedback", $vm.flangerFeedback, -0.95...0.95)
                    field("Mix", $vm.flangerMix, 0...1)
                }

                effectSection("Phaser", isOn: $vm.phaserEnabled) {
                    field("Rate", $vm.phaserRate, 0.05...8, unit: "Hz")
                    syncMenu($vm.phaserRate, .hertz(0.05...8))
                    field("Depth", $vm.phaserDepth, 0...1)
                    field("Feedback", $vm.phaserFeedback, 0...0.95)
                    field("Mix", $vm.phaserMix, 0...1)
                }

                effectSection("Tremolo", isOn: $vm.tremoloEnabled) {
                    field("Rate", $vm.tremoloRate, 0.05...8, unit: "Hz")
                    syncMenu($vm.tremoloRate, .hertz(0.05...8))
                    field("Depth", $vm.tremoloDepth, 0...1)
                    Toggle("Auto-Pan", isOn: $vm.tremoloPan).tint(EchoelTheme.accent)
                }

                effectSection("Compressor", isOn: $vm.compEnabled) {
                    field("Threshold", $vm.compThreshold, -48...0, unit: "dB", decimals: 1)
                    field("Ratio", $vm.compRatio, 1...20, decimals: 1)
                    field("Make-up", $vm.compMakeup, 0...18, unit: "dB", decimals: 1)
                }

                effectSection("Limiter", isOn: $vm.limiterEnabled) {
                    field("Ceiling", $vm.limiterCeiling, -12...0, unit: "dB", decimals: 1)
                }
            }
            .navigationTitle("EchoelFX")
            .searchable(text: $presetQuery, prompt: "Search presets & tags")
            .scrollContentBackground(.hidden)              // drop the stock grey grouped background…
            .background(EchoelTheme.bg.ignoresSafeArea())  // …and show the Echoel black, like the rest of the app
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(EchoelTheme.bg, for: .navigationBar)   // themed nav bar, not stock grey
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(EchoelTheme.accent)                                 // search + Done in the bio-green accent
            .preferredColorScheme(.dark)                             // system controls render dark, on-brand
            .alert("Save preset", isPresented: $showSaveSheet) {
                TextField("Name", text: $saveName)
                Button("Save") {
                    let trimmed = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                    presetStore.save(vm.snapshot(name: trimmed.isEmpty ? "My Preset" : trimmed))
                    saveName = ""
                }
                Button("Cancel", role: .cancel) { saveName = "" }
            } message: {
                Text("Saves the full effects chain — every parameter — as your own preset.")
            }
            .alert("Rename preset", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let t = renameTarget { presetStore.rename(id: t.id, to: renameText) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }

    // MARK: - Macro morph

    /// All presets that can be a morph target (your own + curated community).
    private var morphTargets: [FXPreset] { presetStore.sortedPresets + FXPreset.curatedCommunity }

    /// One fader that continuously morphs the CURRENT sound toward a chosen preset —
    /// the performance "macro". Picking a target snapshots the current sound as A;
    /// the fader blends A→target live (every continuous parameter glides).
    @ViewBuilder
    private var macroMorphSection: some View {
        Section {
            Menu {
                ForEach(morphTargets) { preset in
                    Button(preset.name) {
                        morphA = vm.snapshot(name: "Morph A")
                        morphTarget = preset
                        morphAmount = 0
                    }
                }
            } label: {
                Label(morphTarget.map { "Morph → \($0.name)" } ?? "Morph toward a preset…",
                      systemImage: "slider.horizontal.3")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .accessibilityHint("Pick a preset to morph the current sound toward")
            if let a = morphA, let b = morphTarget {
                EchoelValueField(
                    label: "Morph",
                    value: Binding(get: { morphAmount },
                                   set: { morphAmount = $0; vm.morph(from: a, to: b, amount: $0) }),
                    range: 0...1, decimals: 2)
            }
        } header: {
            Text("Macro morph").font(EchoelTheme.font(13, .bold)).textCase(nil)
        } footer: {
            Text(morphTarget == nil
                 ? "Blend the current sound continuously toward any preset with one fader — for live transitions."
                 : "0 = current sound · 1 = the target preset. Every parameter glides between them.")
        }
        .listRowBackground(EchoelTheme.fill)
    }

    // MARK: - Presets (save your own / recall)

    @ViewBuilder
    private var presetSection: some View {
        Section {
            Button { showSaveSheet = true } label: {
                Label("Save current sound…", systemImage: "square.and.arrow.down")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            if presetStore.presets.isEmpty {
                Text("No saved presets yet. Dial in a sound below, then save it.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
            } else {
                ForEach(presetStore.sortedPresets.filter { $0.matches(presetQuery) }) { preset in
                    Button {
                        vm.apply(preset)
                        presetStore.markUsed(id: preset.id)
                    } label: {
                        HStack {
                            if presetStore.isFavorite(id: preset.id) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.accent)
                            }
                            Text(preset.name).foregroundStyle(EchoelTheme.text)
                            Spacer()
                            Image(systemName: "arrow.up.forward.circle")
                                .foregroundStyle(EchoelTheme.dim)
                        }
                    }
                    .accessibilityHint("Apply this preset to the effects chain")
                    .contextMenu {
                        Button { renameText = preset.name; renameTarget = preset } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button { presetStore.duplicate(id: preset.id) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button { presetStore.toggleFavorite(id: preset.id) } label: {
                            Label(presetStore.isFavorite(id: preset.id) ? "Unstar" : "Favorite",
                                  systemImage: "star")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            presetStore.toggleFavorite(id: preset.id)
                        } label: {
                            Label(presetStore.isFavorite(id: preset.id) ? "Unstar" : "Favorite",
                                  systemImage: presetStore.isFavorite(id: preset.id) ? "star.slash" : "star")
                        }.tint(EchoelTheme.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            presetStore.delete(id: preset.id)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            if let url = preset.communityMailtoURL() { openURL(url) }
                        } label: { Label("Submit", systemImage: "paperplane") }
                        .tint(EchoelTheme.accent)
                    }
                }
            }
        } header: {
            Text("My presets").font(EchoelTheme.font(13, .bold)).textCase(nil)
        } footer: {
            Text("Saved on this device — favorites and recently-used rise to the top. Swipe right to ★, left to Submit or Delete.")
        }
        .listRowBackground(EchoelTheme.fill)

        Section {
            ForEach(FXPreset.curatedCommunity.filter { $0.matches(presetQuery) }) { preset in
                Button { vm.apply(preset) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).foregroundStyle(EchoelTheme.text)
                        if !preset.tags.isEmpty {
                            Text(preset.tags.joined(separator: " · "))
                                .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                        }
                    }
                }
                .accessibilityHint("Apply this community preset to the effects chain")
            }
        } header: {
            Text("Community presets").font(EchoelTheme.font(13, .bold)).textCase(nil)
        } footer: {
            Text("Curated by Echoel. Submitting your own to the community comes next.")
        }
        .listRowBackground(EchoelTheme.fill)
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
                Text(title).font(EchoelTheme.font(13, .bold))
            }
            .tint(EchoelTheme.accent)
            .textCase(nil)
        }
        // Match the EchoelPanel vocabulary used elsewhere: rows on EchoelTheme.fill
        // instead of the stock secondary grouped background, so FX looks like the
        // rest of the app (one card style app-wide).
        .listRowBackground(EchoelTheme.fill)
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
                .font(EchoelTheme.font(12, .semibold))
                .foregroundStyle(EchoelTheme.accent)
        }
        .accessibilityHint("Set this rate from a musical note division at the current tempo")
    }

    /// A parameter row — the app-wide standard control (`EchoelValueField`): a
    /// labelled numeric value with its unit, adjusted by a vertical-fader drag (a
    /// transient fader appears on press) or tap-to-type. Same component the Sound
    /// editor uses, so every parameter across the app reads and behaves the same.
    private func field(
        _ title: String,
        _ value: Binding<Float>,
        _ range: ClosedRange<Float>,
        unit: String = "",
        decimals: Int = 2
    ) -> some View {
        EchoelValueField(label: title, value: value, range: range, unit: unit, decimals: decimals)
    }
}

// MARK: - Bio-reactive modulation section

/// The Echoel signature applied to FX: the body (and free LFOs) sculpt the chain
/// live — coherence opening a reverb, breath sweeping a filter, heartbeat driving a
/// tremolo. Edits the driver's routes; the driver writes them at ~30 Hz around the
/// user's base value and enables the targeted stage so the move is heard.
@MainActor
private struct FXBioModSection: View {
    @Bindable var modulator: FXBioModulator

    var body: some View {
        Section {
            ForEach($modulator.routes) { $route in
                FXModRouteRow(route: $route) {
                    modulator.routes.removeAll { $0.id == route.id }
                }
            }
            Menu {
                ForEach(FXModTarget.allCases) { target in
                    Button(target.displayName) {
                        modulator.routes.append(FXModRoute(carrier: .bio(.coherence), target: target))
                    }
                }
            } label: {
                Label("Add bio modulation…", systemImage: "waveform.path.ecg")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.accent)
            }
            .accessibilityHint("Map the body or an LFO onto an effect parameter")
        } header: {
            Text("Bio-reactive").font(EchoelTheme.font(13, .bold)).textCase(nil)
        } footer: {
            Text(modulator.routes.isEmpty
                 ? "Let the body shape the effects: e.g. coherence → reverb, breath → filter, heart rate → tremolo. Add a route to begin."
                 : "Each route moves its parameter around your set value at ~30 Hz. The targeted stage turns on automatically.")
        }
        .listRowBackground(EchoelTheme.fill)
    }
}

// MARK: - Bio-modulation LIVE view (Item 2 — the body moving the sound, visible)

/// The Echoel thesis made visible: for each active route, which body channel is
/// moving which effect parameter, right now. A DEDICATED LEAF — it reads the ~10 Hz
/// `liveContributions` in its OWN body so only this view churns; the route-editing
/// section above (with its menu Pickers) never observes it and never freezes
/// (menu-freeze law). No flashing — a continuously-updating bar, not a strobe.
@MainActor
private struct BioModLiveView: View {
    let modulator: FXBioModulator

    var body: some View {
        Section {
            if modulator.isRunning, !modulator.liveContributions.isEmpty {
                ForEach(modulator.liveContributions) { c in
                    BioModContributionRow(contribution: c)
                }
            } else {
                Text(modulator.isRunning
                     ? "Add a bio route above to watch the body move a parameter."
                     : "Start a session to watch the body move these parameters.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Live — body → sound").font(EchoelTheme.font(13, .bold)).textCase(nil)
        }
        .listRowBackground(EchoelTheme.fill)
    }
}

/// One live contribution row: `carrier → target`, a signal bar (the raw normalized
/// body value driving it), and the signed offset it is pushing the parameter by.
/// Legible number first, bar second (science-first); solid fills, no glow.
@MainActor
private struct BioModContributionRow: View {
    let contribution: BioModContribution

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(contribution.carrierName)
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(EchoelTheme.dim)
                Text(contribution.targetName)
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                Spacer(minLength: 0)
                // "—", never "+0.00", when the body did not report this carrier: the
                // same rule the bio strip applies, and for the same reason — a confident
                // zero reads as "you are at the bottom of the scale" rather than "this
                // was not measured". The route contributes nothing in that state, so a
                // number here would also contradict the engine.
                Text(contribution.measured ? signed(contribution.offset) : "—")
                    .font(EchoelTheme.font(11).monospacedDigit()).foregroundStyle(EchoelTheme.dim)
            }
            signalBar
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// VoiceOver must not state a percentage the body never produced either — that was
    /// the more misleading half, since "0 percent" sounds like a reading.
    private var accessibilityText: String {
        guard contribution.measured else {
            return "\(contribution.carrierName) to \(contribution.targetName), not measured"
        }
        return "\(contribution.carrierName) moving \(contribution.targetName), "
            + "\(Int((contribution.signal01 * 100).rounded())) percent"
    }

    /// Adaptive precision so a filter-cutoff offset in Hz (+4200) and a dimensionless
    /// mix (+0.30) both read cleanly.
    private func signed(_ v: Float) -> String {
        let a = abs(v)
        let decimals = a >= 100 ? 0 : (a >= 10 ? 1 : 2)
        return (v >= 0 ? "+" : "−") + String(format: "%.\(decimals)f", a)
    }

    private var signalBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EchoelTheme.border.opacity(0.4))
                // No fill at all when unmeasured — the `max(2, …)` floor would otherwise
                // draw a small but real bar, which is the same fabricated zero as "+0.00".
                if contribution.measured {
                    Capsule().fill(EchoelTheme.accent)
                        .frame(width: Swift.max(2, geo.size.width * CGFloat(Swift.min(1, Swift.max(0, contribution.signal01)))))
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

// MARK: - Bio-modulation route row

/// One bio→FX modulation route: carrier · target · depth (+ polarity / LFO rate),
/// on the app-wide value-field vocabulary. A swipe deletes it.
@MainActor
private struct FXModRouteRow: View {
    @Binding var route: FXModRoute
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: $route.enabled).labelsHidden().tint(EchoelTheme.accent)
                    .accessibilityLabel("Route enabled")
                Picker("Source", selection: $route.carrier) {
                    ForEach(FXModCarrier.allChoices, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(EchoelTheme.dim)
                Picker("Target", selection: $route.target) {
                    ForEach(FXModTarget.allCases) { t in Text(t.displayName).tag(t) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                Spacer(minLength: 0)
            }
            EchoelValueField(label: "Depth", value: $route.depth, range: 0...1, decimals: 2)
            HStack(spacing: 12) {
                Toggle("Bipolar", isOn: $route.bipolar).tint(EchoelTheme.accent)
                    .font(EchoelTheme.font(12))
                Picker("Curve", selection: $route.curve) {
                    ForEach(ResponseCurve.allCases, id: \.self) { c in
                        Text(c.rawValue.capitalized).tag(c)
                    }
                }
                .pickerStyle(.menu).tint(EchoelTheme.text)
                .accessibilityLabel("Response curve")
                if route.carrier == .lfo {
                    EchoelValueField(label: "LFO rate", value: $route.lfoRateHz,
                                     range: 0.05...8, unit: "Hz")
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}
#endif
