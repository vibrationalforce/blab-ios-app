#if canImport(SwiftUI)
import SwiftUI

// PatchEditorView.swift
// Echoel — the DDSP sound editor: shape the polyphonic synth's envelope, tone,
// filter, space and vibrato, then save it as your own instrument. Live: every
// change is applied to PolySynthVoice immediately so you hear it as you tune.

@MainActor
struct PatchEditorView: View {

    @Environment(PolySynthVoice.self) private var voice
    @Environment(PatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var patch: SynthPatch
    @State private var showSaveAs = false
    @State private var saveAsName = ""

    /// Reports the live patch back to the host (so the one-window studio can keep
    /// the current sound for project save). Optional — defaults to a no-op.
    private let onApply: (SynthPatch) -> Void

    init(initial: SynthPatch, onApply: @escaping (SynthPatch) -> Void = { _ in }) {
        _patch = State(initialValue: initial)
        self.onApply = onApply
    }

    private var isFactory: Bool { store.isFactory(patch) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    presetBar
                    previewKeys
                    section("Level") {
                        // Per-instrument output level (founder 2026-07-11 "Level pro
                        // Instrument"). 1.00 = unity; the factory sounds are auto-matched,
                        // trim here to taste.
                        EchoelValueField(label: "Output", value: levelBinding,
                                         range: 0.3...1.5, unit: "", decimals: 2)
                    }
                    section("Envelope") {
                        slider("Attack", $patch.attack, 0.005...3, unit: "s")
                        slider("Decay", $patch.decay, 0.01...2, unit: "s")
                        slider("Sustain", $patch.sustain, 0...1)
                        slider("Release", $patch.release, 0.1...5, unit: "s")
                    }
                    section("Tone") {
                        slider("Harmonicity", $patch.harmonicity, 0.3...1)
                        slider("Brightness", $patch.brightness, 0...1)
                        slider("Noise", $patch.noiseLevel, 0...0.3)
                        picker("Shape", selection: $patch.spectralShape,
                               options: EchoelDDSP.SpectralShape.allCases.map { $0.rawValue })
                        picker("Noise color", selection: $patch.noiseColor,
                               options: EchoelDDSP.NoiseColor.allCases.map { $0.rawValue })
                    }
                    section("Filter") {
                        slider("Cutoff", $patch.filterCutoff, 60...12000, unit: "Hz", decimals: 0)
                        slider("Resonance", $patch.filterResonance, 0...0.95)
                        slider("LFO → Filter", $patch.lfoToFilterDepth, 0...1)
                        slider("LFO rate", $patch.filterLFORate, 0.01...10, unit: "Hz")
                    }
                    section("Space") {
                        slider("Reverb", $patch.reverbMix, 0...1)
                        slider("Reverb decay", $patch.reverbDecay, 0.1...5, unit: "s")
                    }
                    section("Vibrato") {
                        slider("Rate", $patch.vibratoRate, 0...10, unit: "Hz")
                        slider("Depth", $patch.vibratoDepth, 0...1)
                    }
                    section("Unison") {
                        EchoelValueField(label: "Voices", value: unisonVoicesBinding,
                                         range: 1...Float(EchoelPolyDDSP.maxUnison), unit: "", decimals: 0)
                        EchoelValueField(label: "Detune", value: unisonDetuneBinding,
                                         range: 0...50, unit: "cents", decimals: 0)
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Sound")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { voice.apply(patch); onApply(patch) }
            .onChange(of: patch) { _, new in voice.apply(new); onApply(new) }
            .alert("Save as", isPresented: $showSaveAs) {
                TextField("Name", text: $saveAsName)
                Button("Save") {
                    let saved = store.saveAs(patch, name: saveAsName.isEmpty ? "My Sound" : saveAsName)
                    patch = saved
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Preset bar

    private var presetBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(store.sortedPatches) { p in
                    Button {
                        patch = p
                        store.markUsed(id: p.id)
                    } label: {
                        if store.isFavorite(id: p.id) {
                            Label(p.name, systemImage: "star.fill")
                        } else {
                            Text(p.name)
                        }
                    }
                }
                if !CommunityLibrary.patches.isEmpty {
                    Section("Community") {
                        ForEach(CommunityLibrary.patches) { p in
                            Button(p.name) { patch = p }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if store.isFavorite(id: patch.id) {
                        Image(systemName: "star.fill").font(.system(size: 10))
                            .foregroundStyle(EchoelTheme.accent)
                    }
                    Text(patch.name).font(EchoelTheme.font(13, .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }

            Spacer(minLength: 0)

            toolButton(store.isFavorite(id: patch.id) ? "★" : "☆") {
                store.toggleFavorite(id: patch.id)
            }
            toolButton("Submit") {
                if let url = patch.communityMailtoURL() { openURL(url) }
            }
            if !isFactory {
                toolButton("Save") { store.save(patch) }
            }
            toolButton("Save as…") { saveAsName = patch.name + " copy"; showSaveAs = true }
            if !isFactory {
                toolButton("Delete", danger: true) {
                    store.delete(id: patch.id)
                    patch = store.patches.first ?? SynthPatch(name: "Custom")
                }
            }
        }
    }

    private func toolButton(_ title: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EchoelTheme.font(12, .semibold))
                .foregroundStyle(danger ? EchoelTheme.danger : EchoelTheme.text)
                .padding(.horizontal, 10).frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview keys (press-and-hold to audition the sound)

    private var previewKeys: some View {
        HStack(spacing: 3) {
            ForEach([60, 62, 64, 65, 67, 69, 71, 72], id: \.self) { midi in
                RoundedRectangle(cornerRadius: 4)
                    .fill(EchoelTheme.fill)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                        if pressing { voice.noteOn(pitch: midi, velocity: 0.8) }
                        else { voice.noteOff(pitch: midi) }
                    }, perform: {})
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(EchoelTheme.font(11, .bold))
                .foregroundStyle(EchoelTheme.dim)
            VStack(spacing: 8) { content() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
    }

    /// Scrubbable numeric value (no slider). Signature preserved so call sites are
    /// unchanged; `decimals` flows through to the field's fine-scrub grid.
    private func slider(_ label: String, _ value: Binding<Float>, _ range: ClosedRange<Float>,
                        unit: String = "", decimals: Int = 2) -> some View {
        EchoelValueField(label: label, value: value, range: range, unit: unit, decimals: decimals)
    }

    // Output level ↔ optional-patch-field bridge (nil = unity → shows as 1.00).
    private var levelBinding: Binding<Float> {
        Binding(get: { patch.outputLevel ?? 1.0 },
                set: { patch.outputLevel = $0 })
    }

    // Unison ↔ optional-patch-field bridges (nil = off → shows as 1 voice / 0 cents).
    private var unisonVoicesBinding: Binding<Float> {
        Binding(get: { Float(patch.unisonVoices ?? 1) },
                set: { patch.unisonVoices = max(1, Int($0.rounded())) })
    }
    private var unisonDetuneBinding: Binding<Float> {
        Binding(get: { patch.unisonDetuneCents ?? 0 },
                set: { patch.unisonDetuneCents = max(0, $0) })
    }

    private func picker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
                .frame(width: 96, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
            }
            .pickerStyle(.menu)
            .tint(EchoelTheme.text)
            Spacer(minLength: 0)
        }
    }
}
#endif
