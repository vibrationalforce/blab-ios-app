#if canImport(SwiftUI)
import SwiftUI

// ComposeView.swift
// Echoel — "your heartbeat composes". Pick a key, choose Studio (BPM-locked, for
// DAW handoff) or Flow (sync-free, follows the heart for meditation), then
// Generate: the live bio snapshot drives BioComposer to write an in-key melody
// into the shared piano roll and set the tempo. The melody is audible
// immediately because the roll is wired app-wide to PolySynthVoice via the
// transport's onTick — so Generate + play = sound.

@MainActor
struct ComposeView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(PianoRollModel.self) private var pianoRoll
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(PolySynthVoice.self) private var synth
    @Environment(SessionContext.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var style: MusicStyle = .dubTechno
    @State private var rootIndex = 0
    @State private var scale: Scale = .dorian
    @State private var mode: ComposerMode = .studioLocked
    @State private var lockedBPM: Double = 124
    @State private var fxCharacter: FXCharacter = .auto
    @State private var lastNoteCount: Int?
    /// Progressive disclosure: Beginners get the simplest path (Sound → Key →
    /// Generate); Producers+ also see the Effects character and Session details.
    @AppStorage("echoel.skillLevel") private var skillLevelRaw = SkillLevel.beginner.rawValue
    private var skillLevel: SkillLevel { SkillLevel(rawValue: skillLevelRaw) ?? .beginner }

    private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private var key: MusicalKey { MusicalKey(root: rootIndex, scale: scale) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    bioReadout
                    styleSection
                    keySection
                    modeSection
                    // Producer+ depth: hand-pick the effect character and stamp
                    // the session/export name. Beginners stay on the essentials
                    // (genre auto-FX + default naming still apply under the hood).
                    if skillLevel >= .producer {
                        fxSection
                        sessionSection
                    }
                    generateSection
                }
                .padding(16)
                .onChange(of: style) { _, newStyle in applyStyle(newStyle) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoelTheme.bg)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Compose from Body")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EchoelTheme.accent)
        }
        .padding(16)
        .background(EchoelTheme.bg)
    }

    // MARK: - Bio readout (what's driving the music)

    private var bioReadout: some View {
        let frame = bus.latestBio
        return HStack(spacing: 16) {
            stat("HR", frame.map { "\(Int($0.heartRateBPM))" } ?? "—", "bpm")
            stat("Coherence", frame.map { String(format: "%.2f", $0.coherence) } ?? "—", "")
            stat("HRV", frame.map { String(format: "%.2f", $0.hrvNormalized) } ?? "—", "")
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bioReadoutLabel(frame))
    }

    private func bioReadoutLabel(_ frame: BioSampleFrame?) -> String {
        guard let frame else { return "No live bio yet — generation uses neutral defaults" }
        // Int(Float) traps on NaN/Inf (a sensor can briefly emit one); format the
        // BPM defensively so a bad reading never crashes the label.
        let bpm = frame.heartRateBPM.isFinite ? Int(frame.heartRateBPM) : 0
        return "Live: \(bpm) bpm, coherence \(String(format: "%.2f", frame.coherence))"
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(EchoelTheme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
                if !unit.isEmpty { Text(unit).font(.system(size: 9)).foregroundStyle(EchoelTheme.dim) }
            }
        }
    }

    // MARK: - Style (the primary choice — which sound world)

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Sound")
            VStack(spacing: 8) {
                ForEach(MusicStyle.allCases) { s in
                    styleRow(s)
                }
            }
        }
    }

    private func styleRow(_ s: MusicStyle) -> some View {
        let selected = (s == style)
        return Button { style = s } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? EchoelTheme.accent : EchoelTheme.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text(s.lineage)
                        .font(.system(size: 11))
                        .foregroundStyle(EchoelTheme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(selected ? EchoelTheme.accent.opacity(0.12) : EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .stroke(selected ? EchoelTheme.accent : EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(s.displayName), \(s.lineage)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// Adopt a style's musical defaults (scale, transport, tempo) so each genre
    /// lands in the right place; the user can still tweak below.
    private func applyStyle(_ s: MusicStyle) {
        scale = s.scale
        mode = s.defaultMode
        lockedBPM = s.defaultTempo
    }

    // MARK: - Key

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Key")
            HStack(spacing: 10) {
                Picker("Root", selection: $rootIndex) {
                    ForEach(0..<12, id: \.self) { Text(noteNames[$0]).tag($0) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent)
                .accessibilityLabel("Root note")

                Picker("Scale", selection: $scale) {
                    ForEach(Scale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent)
                .accessibilityLabel("Scale")
                Spacer(minLength: 0)
            }
            Text("Generated melodies stay in \(key.name).")
                .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
        }
    }

    // MARK: - FX character

    private var fxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Effects")
            Picker("FX", selection: $fxCharacter) {
                ForEach(FXCharacter.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu).tint(EchoelTheme.accent)
            .labelsHidden()
            .accessibilityLabel("Effect character")
            Text(fxCharacter.blurb)
                .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
        }
        // Re-stamp the chosen character onto the live take immediately, so the
        // producer can audition Underwater / Telephone / … without regenerating.
        .onChange(of: fxCharacter) { _, _ in
            fxCharacter.apply(to: synth.fxChain, bpm: beatPlayer.pattern.tempo, genre: style)
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Mode")
            Picker("Mode", selection: $mode) {
                Text("Studio (locked)").tag(ComposerMode.studioLocked)
                Text("Flow (sync-free)").tag(ComposerMode.flowFree)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tempo mode: Studio locked for DAW, or Flow sync-free for meditation")

            if mode == .studioLocked {
                HStack {
                    Text("Lock BPM").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim)
                    Spacer()
                    Stepper("\(Int(lockedBPM)) BPM", value: $lockedBPM, in: style.tempoRange, step: 1)
                        .fixedSize().font(.system(size: 12)).foregroundStyle(EchoelTheme.text)
                        .accessibilityValue("\(Int(lockedBPM)) BPM")
                }
                Text("Locked to \(Int(lockedBPM)) BPM — quantized, ready for Ableton / FL Studio.")
                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
            } else {
                Text("Tempo follows your heart — sync-free, for meditation and self-observation.")
                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    // MARK: - Session (artist · Kammerton · auto name)

    private var sessionSection: some View {
        @Bindable var session = session
        let bpm = beatPlayer.pattern.tempo
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Session")
            HStack(spacing: 10) {
                Text("Artist").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim).frame(width: 78, alignment: .leading)
                TextField("Echoel", text: $session.artistName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13)).foregroundStyle(EchoelTheme.text)
                    .submitLabel(.done)
                    .accessibilityLabel("Artist name for session and export filenames")
            }
            HStack(spacing: 10) {
                Text("Kammerton").font(.system(size: 12)).foregroundStyle(EchoelTheme.dim).frame(width: 78, alignment: .leading)
                Picker("Kammerton", selection: $session.a4Hz) {
                    ForEach(TuningReference.presets, id: \.self) { hz in
                        Text("A\(SessionNaming.trimmed(hz)) Hz").tag(hz)
                    }
                }
                .pickerStyle(.menu).tint(EchoelTheme.accent)
                .labelsHidden()
                .accessibilityLabel("Concert pitch — A4 reference in hertz")
                Spacer(minLength: 0)
            }
            Text("Saves as  \(session.sessionName(bpm: bpm))")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(EchoelTheme.dim)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityLabel("Session and export name: \(session.sessionName(bpm: bpm))")
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { generate() } label: {
                Label(lastNoteCount == nil ? "Generate from Body" : "Regenerate",
                      systemImage: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Writes an in-key melody from your live biodata and plays it")

            if let n = lastNoteCount {
                Text("Generated \(n) note\(n == 1 ? "" : "s") in \(key.name). Edit it in the piano roll, then export.")
                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(EchoelTheme.text)
    }

    // MARK: - Action

    private func generate() {
        let frame = bus.latestBio
        let input = BioComposer.Input(
            heartRateBPM: frame?.heartRateBPM ?? 70,
            hrvNormalized: frame?.hrvNormalized ?? 0.5,
            coherence: frame?.coherence ?? 0.5,
            breathPhase: frame?.breathPhase ?? 0,
            breathDepth: 0.5,
            key: key,
            style: style,
            mode: mode,
            lockedTempo: lockedBPM,
            seed: UInt64.random(in: UInt64.min...UInt64.max)
        )
        let composition = BioComposer.compose(input)
        // The session name follows what was actually generated (the key).
        session.adopt(key: key)
        // Give the voice the genre's timbre so the take sounds like its reference
        // (dub chord wash / trap bell / calm pad), not the generic synth.
        synth.apply(style.synthPatch)
        // …and the take's effect space: the chosen FX character (Underwater,
        // Telephone, …) or, on Auto, the genre's signature space (dub delay,
        // vapor chorus, psy roll) — tempo-synced so the echo locks to the grid.
        fxCharacter.apply(to: synth.fxChain, bpm: composition.suggestedTempo, genre: style)
        pianoRoll.load(composition.notes)
        // Studio mode brings a heartbeat-seeded beat; Flow stays ambient (the
        // grid is empty, which clears any prior beat).
        beatPlayer.pattern.load(steps: composition.drumSteps, accents: composition.drumAccents)
        beatPlayer.pattern.setTempo(composition.suggestedTempo)
        lastNoteCount = composition.notes.count
        if !beatPlayer.pattern.isPlaying { beatPlayer.pattern.play() }
    }
}
#endif
