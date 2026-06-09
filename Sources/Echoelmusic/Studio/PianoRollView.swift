#if canImport(SwiftUI)
import SwiftUI
import Foundation

// PianoRollView.swift
// Echoel — melodic step lane (piano roll) that drives the live DDSP synth voice
// via EngineBus.controllerEvents. Shares the ONE PatternEngine clock with the
// drum grid (via pattern.onTick), so drums + melody play on the same transport
// — no second-timer drift. v1 = 16 step-cells × pitch rows (each active cell is
// a hit, monophonic last-note-wins, matching the bio synth voice). Note-length /
// polyphony are later refinements (see PLAN_DAW_BUILDOUT.md B1).
//
// User control: the body still modulates the synth's timbre (bio is a modulation
// source); the piano roll decides the notes. Nothing plays until the user adds
// notes and presses play.

/// Editable melodic pattern + its trigger logic (publishes note events to the bus).
@MainActor
@Observable
public final class PianoRollModel {

    public static let stepCount = 16
    /// Two octaves + root (C..C two octaves up).
    public static let rowCount = 25

    /// `notes[row][step]` — row 0 = root (lowest), increasing semitone upward.
    public private(set) var notes: [[Bool]]

    /// MIDI note of row 0 (default C3 = 48 → range C3…C5).
    public var rootNote: Int = 48

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var lastNote: UInt8?

    public init() {
        self.notes = Array(
            repeating: Array(repeating: false, count: PianoRollModel.stepCount),
            count: PianoRollModel.rowCount
        )
    }

    public func toggle(row: Int, step: Int) {
        guard notes.indices.contains(row), notes[row].indices.contains(step) else { return }
        notes[row][step].toggle()
    }

    public func clear() {
        for r in notes.indices { for s in notes[r].indices { notes[r][s] = false } }
    }

    /// Wire to the shared clock. Each tick triggers the highest active note for
    /// that step (mono), or releases on a rest.
    public func start(pattern: PatternEngine, bus: EngineBus) {
        self.bus = bus
        pattern.onTick = { [weak self] step in self?.trigger(step) }
    }

    /// Unwire from the clock and release any held note.
    public func stop(pattern: PatternEngine) {
        pattern.onTick = nil
        allNotesOff()
    }

    public func allNotesOff() {
        if let prev = lastNote { sendNote(.noteOff, prev); lastNote = nil }
    }

    // MARK: - Trigger

    private func trigger(_ step: Int) {
        guard let row = highestActiveRow(at: step) else {
            allNotesOff()
            return
        }
        let midi = UInt8(min(127, max(0, rootNote + row)))
        if let prev = lastNote, prev != midi { sendNote(.noteOff, prev) }
        sendNote(.noteOn, midi)
        lastNote = midi
    }

    private func highestActiveRow(at step: Int) -> Int? {
        for row in stride(from: PianoRollModel.rowCount - 1, through: 0, by: -1) {
            if notes[row][step] { return row }
        }
        return nil
    }

    private func sendNote(_ kind: ControllerEvent.Kind, _ note: UInt8) {
        bus?.publish(controller: ControllerEvent(
            timestamp: CFAbsoluteTimeGetCurrent(),
            kind: kind, channel: 1, note: note, value: 0, auxCC: 0
        ))
    }

    /// Note name (C, C#, …) for a row, for the keyboard labels.
    public func name(forRow row: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let midi = rootNote + row
        let octave = midi / 12 - 1
        return "\(names[((midi % 12) + 12) % 12])\(octave)"
    }

    /// True for black keys (sharps) — for row tinting.
    public func isSharp(row: Int) -> Bool {
        let pc = ((rootNote + row) % 12 + 12) % 12
        return [1, 3, 6, 8, 10].contains(pc)
    }
}

/// Piano-roll editor surface. Presented from the Tools tab; drives the live synth.
@MainActor
struct PianoRollView: View {

    let pattern: PatternEngine
    let bus: EngineBus
    @Bindable var model: PianoRollModel
    @Environment(\.dismiss) private var dismiss

    private let columnsPerGroup = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                transport
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                grid
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Piano Roll")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { model.clear() }
                }
            }
            .onAppear { model.start(pattern: pattern, bus: bus) }
            .onDisappear { model.stop(pattern: pattern) }
        }
    }

    // MARK: Transport (shared clock with the drum grid)

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                if pattern.isPlaying { pattern.stop(); model.allNotesOff() }
                else { pattern.play() }
            } label: {
                Image(systemName: pattern.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(pattern.isPlaying ? EchoelTheme.danger : EchoelTheme.accent))
            }
            .buttonStyle(.plain)

            Stepper(value: $model.rootNote, in: 24...72, step: 12) {
                Text("Octave \(model.rootNote / 12 - 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
            }
            Spacer(minLength: 0)
            Text("Shares the beat transport · tempo \(Int(pattern.tempo)) BPM")
                .font(.caption2)
                .foregroundStyle(EchoelTheme.dim)
        }
    }

    // MARK: Grid (high pitch on top)

    private var grid: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(stride(from: PianoRollModel.rowCount - 1, through: 0, by: -1).map { $0 }, id: \.self) { row in
                    rowView(row)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func rowView(_ row: Int) -> some View {
        HStack(spacing: 3) {
            Text(model.name(forRow: row))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(model.isSharp(row: row) ? EchoelTheme.dim : EchoelTheme.text)
                .frame(width: 34, alignment: .leading)
            ForEach(0..<(PianoRollModel.stepCount / columnsPerGroup), id: \.self) { group in
                HStack(spacing: 2) {
                    ForEach(0..<columnsPerGroup, id: \.self) { col in
                        let step = group * columnsPerGroup + col
                        cell(row: row, step: step)
                    }
                }
                if group < PianoRollModel.stepCount / columnsPerGroup - 1 {
                    Spacer().frame(width: 5)
                }
            }
        }
    }

    @ViewBuilder
    private func cell(row: Int, step: Int) -> some View {
        let on = model.notes[row][step]
        let isCurrent = pattern.isPlaying && pattern.currentStep == step
        Button { model.toggle(row: row, step: step) } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(fill(on: on, isCurrent: isCurrent, sharp: model.isSharp(row: row)))
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isCurrent ? EchoelTheme.accent.opacity(0.7) : EchoelTheme.border, lineWidth: 1))
                .frame(height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.name(forRow: row)) step \(step + 1)")
        .accessibilityValue(on ? "on" : "off")
    }

    private func fill(on: Bool, isCurrent: Bool, sharp: Bool) -> Color {
        if on { return isCurrent ? .white : EchoelTheme.accent }
        if isCurrent { return EchoelTheme.text.opacity(0.18) }
        return sharp ? Color.white.opacity(0.03) : EchoelTheme.fill
    }
}
#endif
