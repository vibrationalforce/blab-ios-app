import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Interactive composer that assembles world music prompts for generative sound models
struct PromptSoundDesignerView: View {
    @Environment(\.dismiss) private var dismiss

    private let database = MusicPromptDatabase.shared
    private let globalInstrumentPool = [
        "Subbass",
        "Modular Synth",
        "Granular Sampler",
        "Handpan",
        "Streicher-Ensemble",
        "Analog Lead",
        "Hybrid Choir",
        "E-Piano",
        "Kontakt Percussion"
    ]

    // MARK: - State

    @State private var searchText: String = ""
    @State private var selectedStyle: MusicStyle
    @State private var selectedTonalSystem: TonalSystem
    @State private var selectedPitchStandard: PitchStandard
    @State private var selectedCompositionSchool: CompositionSchool?
    @State private var selectedMood: String
    @State private var selectedTimeSignature: String
    @State private var tempo: Int
    @State private var loopLengthBars: Int = 4
    @State private var selectedInstrumentation: Set<String>
    @State private var selectedTexturalFocus: Set<String>
    @State private var selectedRhythmicConcepts: Set<String>
    @State private var selectedMelodicConcept: String
    @State private var customInstrument: String = ""
    @State private var generatedPrompt: String = ""
    @State private var copyStatus: String?

    // MARK: - Init

    init() {
        let database = MusicPromptDatabase.shared
        let defaultStyle = database.styles.first ?? MusicStyle(
            name: "Afrobeat",
            region: "Global",
            description: "Polyphone Grooves",
            moods: ["Energetisch"],
            primaryInstruments: ["Percussion"],
            tempoRange: 100...120,
            meters: ["4/4"],
            tonalSystemNames: ["12-TET"],
            textureKeywords: ["Layered Percussion"],
            rhythmicConcepts: ["Polyrhythmik"]
        )

        let tonal = database.tonalSystems(for: defaultStyle).first ?? database.tonalSystems.first!
        let pitch = database.pitchStandards(for: defaultStyle).first ?? database.pitchStandards.first!
        let composition = database.compositionSchools(for: defaultStyle).first
        let mood = defaultStyle.defaultMood
        let meter = defaultStyle.defaultMeter
        let tempo = defaultStyle.defaultTempo
        let melodic = database.melodicConcepts.first ?? "Melodische Leitidee"

        _selectedStyle = State(initialValue: defaultStyle)
        _selectedTonalSystem = State(initialValue: tonal)
        _selectedPitchStandard = State(initialValue: pitch)
        _selectedCompositionSchool = State(initialValue: composition)
        _selectedMood = State(initialValue: mood)
        _selectedTimeSignature = State(initialValue: meter)
        _tempo = State(initialValue: tempo)
        _selectedInstrumentation = State(initialValue: Set(defaultStyle.primaryInstruments.prefix(3)))
        _selectedTexturalFocus = State(initialValue: Set(defaultStyle.textureKeywords.prefix(2)))
        _selectedRhythmicConcepts = State(initialValue: Set(defaultStyle.rhythmicConcepts.prefix(1)))
        _selectedMelodicConcept = State(initialValue: melodic)
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    styleSelectionSection
                    tonalSection
                    arrangementSection
                    texturalSection
                    generationSection
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Prompt Composer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onChange(of: selectedStyle) { newValue in
                adaptToStyle(newValue)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Sections

    private var styleSelectionSection: some View {
        GroupBox("Musikstil & Kontext") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Suche nach Region, Stil oder Stimmung", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Picker("Stil", selection: $selectedStyle) {
                    ForEach(filteredStyles, id: \.self) { style in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(style.name).font(.headline)
                            Text("Region: \(style.region)").font(.caption).foregroundColor(.secondary)
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Beschreibung")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(selectedStyle.description)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Stimmung", selection: $selectedMood) {
                    ForEach(selectedStyle.moods, id: \.self) { mood in
                        Text(mood).tag(mood)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var tonalSection: some View {
        GroupBox("Tonsystem & Zeit") {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Tonsystem", selection: $selectedTonalSystem) {
                    ForEach(database.tonalSystems(for: selectedStyle), id: \.self) { system in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(system.name).font(.headline)
                            Text(system.description).font(.caption).foregroundColor(.secondary)
                        }
                        .tag(system)
                    }
                }
                .pickerStyle(.menu)

                Picker("Kammerton", selection: $selectedPitchStandard) {
                    ForEach(database.pitchStandards(for: selectedStyle), id: \.self) { pitch in
                        Text("\(pitch.name) – \(String(format: "%.1f", pitch.frequency)) Hz")
                            .tag(pitch)
                    }
                }
                .pickerStyle(.menu)

                Picker("Kompositionsschule", selection: $selectedCompositionSchool) {
                    Text("Keine").tag(Optional<CompositionSchool>.none)
                    ForEach(database.compositionSchools(for: selectedStyle), id: \.self) { school in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.name).font(.headline)
                            Text(school.characteristics.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(Optional(school))
                    }
                }
                .pickerStyle(.menu)

                Picker("Taktart", selection: $selectedTimeSignature) {
                    ForEach(selectedStyle.meters, id: \.self) { meter in
                        Text(meter).tag(meter)
                    }
                }
                .pickerStyle(.segmented)

                Stepper(value: $tempo, in: selectedStyle.tempoRange, step: 1) {
                    Text("Tempo: \(tempo) BPM")
                }

                Stepper(value: $loopLengthBars, in: 2...16, step: 1) {
                    Text("Loop-Länge: \(loopLengthBars) Takte")
                }
            }
        }
    }

    private var arrangementSection: some View {
        GroupBox("Instrumentation & Melodik") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instrumente")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(instrumentOptions, id: \.self) { instrument in
                            SelectionChip(title: instrument, isSelected: selectedInstrumentation.contains(instrument)) {
                                toggleSelection(instrument, set: &selectedInstrumentation)
                            }
                        }
                    }
                }

                HStack {
                    TextField("Eigenes Instrument", text: $customInstrument)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Hinzufügen") { addCustomInstrument() }
                        .buttonStyle(.borderedProminent)
                        .disabled(customInstrument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Picker("Melodische Leitidee", selection: $selectedMelodicConcept) {
                    ForEach(database.melodicConcepts, id: \.self) { concept in
                        Text(concept).tag(concept)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var texturalSection: some View {
        GroupBox("Textur & Rhythmus") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Texturen")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(texturalOptions, id: \.self) { texture in
                            SelectionChip(title: texture, isSelected: selectedTexturalFocus.contains(texture)) {
                                toggleSelection(texture, set: &selectedTexturalFocus)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Rhythmische Ideen")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(rhythmicOptions, id: \.self) { rhythm in
                            SelectionChip(title: rhythm, isSelected: selectedRhythmicConcepts.contains(rhythm)) {
                                toggleSelection(rhythm, set: &selectedRhythmicConcepts)
                            }
                        }
                    }
                }
            }
        }
    }

    private var generationSection: some View {
        GroupBox("Prompt-Ausgabe") {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    generatePrompt()
                } label: {
                    Label("Prompt generieren", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !generatedPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Generierter Prompt")
                            .font(.headline)
                        TextEditor(text: $generatedPrompt)
                            .frame(minHeight: 220)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                        HStack {
                            Spacer()
                            Button(action: copyPrompt) {
                                Label("In Zwischenablage kopieren", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }

                        if let copyStatus {
                            Text(copyStatus)
                                .font(.footnote)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var filteredStyles: [MusicStyle] {
        let results = database.searchStyles(keyword: searchText)
        if results.isEmpty {
            return database.styles
        }
        return results
    }

    private var instrumentOptions: [String] {
        let base = selectedStyle.primaryInstruments
        let extended = globalInstrumentPool.filter { !base.contains($0) }
        return base + extended
    }

    private var texturalOptions: [String] {
        let base = selectedStyle.textureKeywords
        let extended = database.texturalDescriptors.filter { !base.contains($0) }
        return base + extended
    }

    private var rhythmicOptions: [String] {
        let base = selectedStyle.rhythmicConcepts
        let extended = database.rhythmicConcepts.filter { !base.contains($0) }
        return base + extended
    }

    private func toggleSelection(_ value: String, set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func addCustomInstrument() {
        let trimmed = customInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedInstrumentation.insert(trimmed)
        customInstrument = ""
    }

    private func adaptToStyle(_ style: MusicStyle) {
        if let newTonal = database.tonalSystems(for: style).first {
            selectedTonalSystem = newTonal
        }

        if let newPitch = database.pitchStandards(for: style).first {
            selectedPitchStandard = newPitch
        }

        selectedCompositionSchool = database.compositionSchools(for: style).first
        selectedMood = style.defaultMood
        selectedTimeSignature = style.defaultMeter
        tempo = style.defaultTempo
        selectedInstrumentation = Set(style.primaryInstruments.prefix(3))
        selectedTexturalFocus = Set(style.textureKeywords.prefix(2))
        selectedRhythmicConcepts = Set(style.rhythmicConcepts.prefix(1))
    }

    private func generatePrompt() {
        let configuration = PromptSoundConfiguration(
            style: selectedStyle,
            tonalSystem: selectedTonalSystem,
            pitchStandard: selectedPitchStandard,
            compositionSchool: selectedCompositionSchool,
            mood: selectedMood,
            tempo: tempo,
            timeSignature: selectedTimeSignature,
            loopLengthBars: loopLengthBars,
            instrumentation: Array(selectedInstrumentation).sorted(),
            texturalFocus: Array(selectedTexturalFocus).sorted(),
            rhythmicConcepts: Array(selectedRhythmicConcepts).sorted(),
            melodicConcept: selectedMelodicConcept
        )

        generatedPrompt = configuration.buildPrompt()
        copyStatus = nil
    }

    private func copyPrompt() {
        guard !generatedPrompt.isEmpty else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = generatedPrompt
        #endif
        copyStatus = "Prompt kopiert!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyStatus = nil
        }
    }
}

// MARK: - Selection Chip

private struct SelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundColor(isSelected ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PromptSoundDesignerView()
}
