#if canImport(SwiftUI)
import SwiftUI
import Foundation

// PianoRollView.swift
// Echoel — polyphonic melodic piano roll driving the live PolySynthVoice.
//
// A real roll, not a step grid: notes have a pitch, a start step, a length in
// steps (legato/sustain across boundaries), and a per-note velocity. Editing is
// tap-to-place / drag-to-stretch on a scrollable, zoomable canvas; the selected
// note gets a velocity + length inspector. Notes drive PolySynthVoice directly
// (chords), and note-offs fire at note END (length), scheduled on the ONE shared
// PatternEngine clock via `pattern.onTick` — drums + melody stay on one transport.

/// Editable polyphonic melodic pattern + its trigger logic.
@MainActor
@Observable
public final class PianoRollModel {

    public static let stepCount = 16
    /// Lowest displayed pitch (C2) and how many semitone rows are shown (→ C6).
    public static let lowPitch = 36
    public static let pitchCount = 49
    public static var highPitch: Int { lowPitch + pitchCount - 1 }

    /// All notes in the pattern (absolute MIDI pitch).
    public private(set) var notes: [Note] = []

    @ObservationIgnored private weak var voice: PolySynthVoice?
    /// Optional sub-bass voice — the lowest notes of each take also drive this an
    /// octave down so the bass can be FELT (sub/headphones/haptics). nil = no sub.
    @ObservationIgnored private weak var subVoice: SubBassVoice?
    /// Notes currently sounding → so we can fire their note-off at end step.
    @ObservationIgnored private var active: [UUID: Note] = [:]
    /// Staged next pattern, swapped in seamlessly at the loop boundary (step 0)
    /// so a live re-seed never cuts a sustaining note mid-bar (no click/gap).
    @ObservationIgnored private var pendingNotes: [Note]?

    public init() {}

    // MARK: - Editing

    /// The note (if any) sounding at `pitch` during `step`.
    public func note(atPitch pitch: Int, step: Int) -> Note? {
        notes.first { $0.pitch == pitch && $0.covers(step: step) }
    }

    /// Add a note, clamping its length so it never crosses the loop boundary.
    @discardableResult
    public func add(pitch: Int, startStep: Int, lengthSteps: Int = 1, velocity: Float = 0.8) -> Note {
        let maxLen = max(1, Self.stepCount - startStep)
        let note = Note(
            pitch: pitch, startStep: startStep,
            lengthSteps: min(max(1, lengthSteps), maxLen), velocity: velocity
        )
        notes.append(note)
        return note
    }

    public func remove(id: UUID) { notes.removeAll { $0.id == id } }

    public func setLength(id: UUID, lengthSteps: Int) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        let maxLen = max(1, Self.stepCount - notes[i].startStep)
        notes[i].lengthSteps = min(max(1, lengthSteps), maxLen)
    }

    public func setVelocity(id: UUID, _ velocity: Float) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[i].velocity = min(max(velocity, 0), 1)
    }

    public func clear() {
        notes.removeAll()
        pendingNotes = nil   // else a staged bar would resurrect what was just cleared
        allNotesOff()        // release anything sounding so clearing never hangs a note
    }

    /// Replace all notes (used when launching a melody clip). Flush any notes
    /// currently sounding first, otherwise regenerating mid-playback leaves the
    /// old notes' entries in `active` → stuck/lingering notes.
    public func load(_ newNotes: [Note]) {
        allNotesOff()
        pendingNotes = nil
        notes = newNotes
    }

    /// Stage a new pattern to swap in seamlessly at the next loop boundary.
    /// Unlike `load`, this does NOT cut sounding notes — held notes ring to their
    /// natural end and the new bar layers in on the downbeat (step 0). This is the
    /// path the live evolution uses while playing, so re-seeding never clicks.
    public func loadAtBoundary(_ newNotes: [Note]) {
        pendingNotes = newNotes
    }

    // MARK: - Transport (shared clock)

    public func start(pattern: PatternEngine, voice: PolySynthVoice, subVoice: SubBassVoice? = nil) {
        self.voice = voice
        self.subVoice = subVoice
        pattern.onTick = { [weak self] step in self?.trigger(step) }
        // Any stop (from any view) flushes held notes — no caller can forget.
        pattern.onStop = { [weak self] in self?.allNotesOff() }
    }

    public func stop(pattern: PatternEngine) {
        pattern.onTick = nil
        pendingNotes = nil
        allNotesOff()
    }

    public func allNotesOff() {
        for note in active.values { voice?.noteOff(pitch: note.pitch) }
        active.removeAll()
        voice?.allNotesOff()
        subVoice?.allNotesOff()
    }

    /// Each tick: release notes ending now, then start notes beginning now.
    /// `endStep % stepCount` so a note ending on the bar line releases at the
    /// loop wrap (step 0), giving correct sustain + retrigger.
    nonisolated(unsafe) private static var triggerTraced = false
    private func trigger(_ step: Int) {
        if !Self.triggerTraced {
            Self.triggerTraced = true
            EchoelCrashLog.breadcrumb("trigger#1 step=\(step) notes=\(notes.count)")
        }
        // Seamless morph: at the loop boundary, swap in the staged pattern WITHOUT
        // an allNotesOff cut. Sustaining notes from the previous bar keep their
        // entries in `active` and release naturally at their own endStep below; the
        // new pattern's notes start via the normal startStep==step path. No gap.
        if step == 0, let pending = pendingNotes {
            notes = pending
            pendingNotes = nil
        }
        // Release notes ending now. The engine's noteOff(pitch:) releases EVERY
        // voice of that pitch, so when two notes share a pitch (voice-leading can
        // produce this) we must only release a pitch once no surviving note still
        // holds it — otherwise a short note would cut off a sustained same-pitch one.
        // Bass register = within a major third of the take's lowest note. Those
        // notes also drive the sub-bass voice an octave down (the "felt" dimension),
        // adapting per take regardless of the genre's octave.
        let bassCeiling = (notes.map { $0.pitch }.min() ?? 0) + 4
        let ending = active.filter { $0.value.endStep % Self.stepCount == step }
        for id in ending.keys { active[id] = nil }
        for note in ending.values where !active.values.contains(where: { $0.pitch == note.pitch }) {
            voice?.noteOff(pitch: note.pitch)
            if note.pitch <= bassCeiling { subVoice?.noteOff(pitch: note.pitch - 12) }
        }
        for note in notes where note.startStep == step {
            voice?.noteOn(pitch: note.pitch, velocity: note.velocity)
            active[note.id] = note
            if note.pitch <= bassCeiling { subVoice?.noteOn(pitch: note.pitch - 12) }
        }
    }

    // MARK: - Labels

    public func name(forPitch pitch: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = pitch / 12 - 1
        return "\(names[((pitch % 12) + 12) % 12])\(octave)"
    }

    public func isSharp(pitch: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
    }

    public func isC(pitch: Int) -> Bool { ((pitch % 12) + 12) % 12 == 0 }
}

/// Drag anchor captured at the start of a create/select gesture.
private struct RollDragAnchor { let pitch: Int; let startStep: Int }

/// Piano-roll editor surface. Presented from the Tools tab; drives the synth.
@MainActor
struct PianoRollView: View {

    let pattern: PatternEngine
    @Bindable var model: PianoRollModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID?
    @State private var drawLength: Int = 1
    @State private var stepW: CGFloat = 26
    @State private var rowH: CGFloat = 22

    // Live drag state
    @State private var anchor: RollDragAnchor?
    @State private var dragStep: Int?

    private let gutterW: CGFloat = 42
    private let minStepW: CGFloat = 16
    private let maxStepW: CGFloat = 56
    private let minRowH: CGFloat = 14
    private let maxRowH: CGFloat = 34

    private var canvasW: CGFloat { stepW * CGFloat(PianoRollModel.stepCount) }
    private var canvasH: CGFloat { rowH * CGFloat(PianoRollModel.pitchCount) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                transport.padding(.horizontal, 16).padding(.top, 8)
                inspector.padding(.horizontal, 16)
                rollScroller
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Piano Roll")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            // One dismiss control only — a single "Done". "Clear" used to sit in the
            // cancellation slot, where it read as "Cancel/back" but silently destroyed
            // every note; it now lives in the transport row as an explicit destructive
            // button (see `transport`).
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: - Transport + tools

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

            // Draw length (steps a new tapped note spans).
            Picker("Length", selection: $drawLength) {
                Text("1").tag(1); Text("2").tag(2); Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)

            Spacer(minLength: 0)
            Button(role: .destructive) { model.clear(); selectedID = nil } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(EchoelTheme.danger)
                    .frame(width: 34, height: 34)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear all notes")
            zoomButton(systemName: "minus.magnifyingglass") { zoom(-1) }
            zoomButton(systemName: "plus.magnifyingglass") { zoom(1) }
        }
    }

    private func zoomButton(systemName: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EchoelTheme.text)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func zoom(_ direction: Int) {
        let f: CGFloat = direction > 0 ? 1.2 : 1 / 1.2
        stepW = min(max(stepW * f, minStepW), maxStepW)
        rowH = min(max(rowH * f, minRowH), maxRowH)
    }

    // MARK: - Selected-note inspector

    @ViewBuilder
    private var inspector: some View {
        if let id = selectedID, let note = model.notes.first(where: { $0.id == id }) {
            HStack(spacing: 12) {
                Text(model.name(forPitch: note.pitch))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 46, alignment: .leading)

                Text("Len").font(.caption2).foregroundStyle(EchoelTheme.dim)
                Stepper(value: Binding(
                    get: { note.lengthSteps },
                    set: { model.setLength(id: id, lengthSteps: $0) }
                ), in: 1...PianoRollModel.stepCount) {
                    Text("\(note.lengthSteps)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(EchoelTheme.text)
                }
                .frame(width: 110)

                Text("Vel").font(.caption2).foregroundStyle(EchoelTheme.dim)
                Slider(value: Binding(
                    get: { Double(note.velocity) },
                    set: { model.setVelocity(id: id, Float($0)) }
                ), in: 0...1)

                Button {
                    model.remove(id: id); selectedID = nil
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EchoelTheme.danger)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 30)
        } else {
            Text("Tap to add a note · drag to stretch · tap a note to edit")
                .font(.caption2)
                .foregroundStyle(EchoelTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 30)
        }
    }

    // MARK: - Scrollable roll (pinned pitch gutter + horizontally-scrolling canvas)

    private var rollScroller: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                gutter
                ScrollView(.horizontal, showsIndicators: true) {
                    canvas
                }
            }
        }
    }

    private var gutter: some View {
        VStack(spacing: 0) {
            ForEach(rowsTopDown, id: \.self) { pitch in
                Text(model.isC(pitch: pitch) ? model.name(forPitch: pitch) : "")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(EchoelTheme.dim)
                    .frame(width: gutterW, height: rowH, alignment: .trailing)
                    .padding(.trailing, 3)
                    .background(model.isSharp(pitch: pitch)
                        ? Color.white.opacity(0.02) : EchoelTheme.fill)
                    .overlay(Rectangle().frame(height: 0.5)
                        .foregroundStyle(EchoelTheme.border), alignment: .bottom)
            }
        }
        .frame(width: gutterW)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            gridBackground
            ForEach(model.notes) { note in noteRect(note) }
            if pattern.isPlaying { playhead }
        }
        .frame(width: canvasW, height: canvasH, alignment: .topLeading)
        .contentShape(Rectangle())
        .coordinateSpace(name: "roll")
        .gesture(canvasDrag)
    }

    private var gridBackground: some View {
        Canvas { ctx, size in
            // Row stripes (sharps darker).
            for (i, pitch) in rowsTopDown.enumerated() {
                let y = CGFloat(i) * rowH
                let rect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                let shade = model.isSharp(pitch: pitch) ? 0.03 : 0.06
                ctx.fill(Path(rect), with: .color(EchoelTheme.text.opacity(shade)))
                if model.isC(pitch: pitch) {
                    ctx.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                               with: .color(EchoelTheme.border), lineWidth: 0.5)
                }
            }
            // Bar/beat lines every 4 steps.
            for step in 0...PianoRollModel.stepCount {
                let x = CGFloat(step) * stepW
                let strong = step % 4 == 0
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                           with: .color(EchoelTheme.text.opacity(strong ? 0.16 : 0.06)),
                           lineWidth: strong ? 1 : 0.5)
            }
        }
        .frame(width: canvasW, height: canvasH)
    }

    private func noteRect(_ note: Note) -> some View {
        let x = CGFloat(note.startStep) * stepW
        let w = CGFloat(note.lengthSteps) * stepW
        let y = yForPitch(note.pitch)
        let selected = note.id == selectedID
        return RoundedRectangle(cornerRadius: 3)
            .fill(EchoelTheme.accent.opacity(0.35 + 0.6 * Double(note.velocity)))
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(selected ? Color.white : EchoelTheme.accent, lineWidth: selected ? 1.5 : 0.5))
            .frame(width: max(4, w - 2), height: max(6, rowH - 2))
            .offset(x: x + 1, y: y + 1)
    }

    private var playhead: some View {
        Rectangle()
            .fill(Color.white.opacity(0.5))
            .frame(width: 1.5, height: canvasH)
            .offset(x: CGFloat(pattern.currentStep) * stepW)
    }

    // MARK: - Geometry helpers

    /// Pitches from highest (top) to lowest (bottom) for top-down layout.
    private var rowsTopDown: [Int] {
        Array(stride(from: PianoRollModel.highPitch, through: PianoRollModel.lowPitch, by: -1))
    }

    private func yForPitch(_ pitch: Int) -> CGFloat {
        CGFloat(PianoRollModel.highPitch - pitch) * rowH
    }

    private func pitch(atY y: CGFloat) -> Int {
        let row = Int(y / rowH)
        return min(max(PianoRollModel.highPitch - row, PianoRollModel.lowPitch), PianoRollModel.highPitch)
    }

    private func step(atX x: CGFloat) -> Int {
        min(max(Int(x / stepW), 0), PianoRollModel.stepCount - 1)
    }

    // MARK: - Gesture

    private var canvasDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("roll"))
            .onChanged { value in
                if anchor == nil {
                    anchor = RollDragAnchor(
                        pitch: pitch(atY: value.startLocation.y),
                        startStep: step(atX: value.startLocation.x)
                    )
                }
                dragStep = step(atX: value.location.x)
            }
            .onEnded { value in
                defer { anchor = nil; dragStep = nil }
                guard let anchor else { return }
                let endStep = step(atX: value.location.x)
                let s0 = min(anchor.startStep, endStep)
                let s1 = max(anchor.startStep, endStep)
                let span = s1 - s0 + 1
                if span <= 1 {
                    if let existing = model.note(atPitch: anchor.pitch, step: s0) {
                        selectedID = existing.id
                    } else {
                        let note = model.add(pitch: anchor.pitch, startStep: s0,
                                             lengthSteps: drawLength)
                        selectedID = note.id
                    }
                } else {
                    let note = model.add(pitch: anchor.pitch, startStep: s0, lengthSteps: span)
                    selectedID = note.id
                }
            }
    }
}
#endif
