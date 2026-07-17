// Note.swift
// Echoel — the one note model shared by the piano roll, melody clips, and MIDI
// export. A note has a pitch, a start time, a length, and a per-note velocity.
//
// PRECISION: the underlying time unit is PPQ TICKS (pulses-per-quarter, the MIDI
// standard), NOT steps. `ticksPerQuarter = 480` and the 16-step/bar grid means
// `ticksPerStep = 120`. Ticks are the source of truth so notes can sit OFF the
// step grid (unquantized capture, nudge, swing) and export sample-tight. The
// familiar `startStep`/`lengthSteps` remain as computed views over the ticks, so
// every existing call site (and the step-grid UI) keeps working unchanged.

import Foundation

/// Which arrangement layer a note belongs to — the routing key for the multitimbral
/// engine (each role can play through its own instrument voice/timbre). Defaults to
/// `.harmony`; legacy clips without a role decode as `.harmony` (unchanged behaviour).
public enum NoteRole: String, Codable, Sendable {
    case harmony   // chords / pad / inner pulse
    case lead      // the melody line
    case bass      // the low root line
}

/// Per-note MPE expression OVERRIDES (#58 Slice 6 — the "MPE station" seam):
/// fixed, user-drawn 5D values that take precedence over the live bio-derived
/// dimension WHERE SET. Every dimension is optional — an unset one falls through
/// to the body (or the neutral base). `nil` on the note ⇒ byte-identical JSON to
/// pre-S6 builds (same contract as `NoteOperators`). Values are stored normalized
/// (bend −1…+1, slide/pressure 0…1) and converted to wire units at merge time.
public struct NoteMPE: Codable, Sendable, Equatable {
    /// Per-note pitch bend, normalized −1…+1 (maps onto the MPE bend range).
    public var bend: Float?
    /// Slide / brightness (CC74), normalized 0…1.
    public var slide: Float?
    /// Press / channel pressure, normalized 0…1.
    public var pressure: Float?

    public init(bend: Float? = nil, slide: Float? = nil, pressure: Float? = nil) {
        self.bend = bend.map { Swift.max(-1, Swift.min(1, $0)) }
        self.slide = slide.map { Swift.max(0, Swift.min(1, $0)) }
        self.pressure = pressure.map { Swift.max(0, Swift.min(1, $0)) }
    }

    /// True when no dimension is set — merging a transparent override is a no-op.
    public var isTransparent: Bool { bend == nil && slide == nil && pressure == nil }

    /// Decode through the clamping init so a corrupt/hand-edited clip can never
    /// round-trip out-of-range values through persistence (the synthesized
    /// Decodable would bypass the init's clamps).
    private enum CodingKeys: String, CodingKey { case bend, slide, pressure }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bend: try c.decodeIfPresent(Float.self, forKey: .bend),
                  slide: try c.decodeIfPresent(Float.self, forKey: .slide),
                  pressure: try c.decodeIfPresent(Float.self, forKey: .pressure))
    }
}

/// A single melodic note, timed in PPQ ticks.
///
/// `startTick` is the 0-based tick it begins on; `lengthTicks` is how long it
/// sounds (clamped to ≥1 tick). `velocity` is normalized [0...1] and is carried
/// straight into `ControllerEvent.value` when the note is triggered. The
/// `startStep`/`lengthSteps` accessors quantize to/from the 16th-note grid.
public struct Note: Codable, Sendable, Equatable, Identifiable {

    /// PPQ resolution — ticks per quarter note (MIDI standard 480).
    public static let ticksPerQuarter = 480
    /// 16 steps per 4/4 bar → 4 steps per quarter → 120 ticks per step.
    public static let ticksPerStep = ticksPerQuarter / 4   // = 120

    public var id: UUID
    public var pitch: Int
    /// Start time in PPQ ticks (≥0). Source of truth.
    public var startTick: Int
    /// Length in PPQ ticks (≥1). Source of truth.
    public var lengthTicks: Int
    public var velocity: Float
    /// Arrangement layer for multitimbral routing (default `.harmony`).
    public var role: NoteRole
    /// Per-note play operators (chance / repeats / occurrence — "Ableton 20"
    /// track). `nil` = plain note, plays every loop (identical to a default
    /// `NoteOperators()`); legacy clips decode as `nil`. Encoded only when set,
    /// so older builds keep reading new clips unchanged.
    public var operators: NoteOperators?
    /// Per-note MPE overrides (#58 S6). `nil` = today's behaviour: the live
    /// bio-derived expression (or none) drives all dimensions. Encoded only
    /// when set — same backward-compat contract as `operators`.
    public var mpe: NoteMPE?

    // MARK: Init

    /// Step-grid init (back-compatible). Steps are converted to ticks.
    public init(
        id: UUID = UUID(),
        pitch: Int,
        startStep: Int,
        lengthSteps: Int = 1,
        velocity: Float = 0.8,
        role: NoteRole = .harmony,
        operators: NoteOperators? = nil
    ) {
        self.id = id
        self.pitch = min(max(pitch, 0), 127)               // defensive: MIDI range
        self.startTick = max(0, startStep) * Note.ticksPerStep
        self.lengthTicks = max(1, lengthSteps) * Note.ticksPerStep
        self.velocity = min(max(velocity, 0), 1)
        self.role = role
        self.operators = operators
    }

    /// Tick-precise init — for unquantized capture / sub-step editing.
    public init(
        id: UUID = UUID(),
        pitch: Int,
        startTick: Int,
        lengthTicks: Int,
        velocity: Float = 0.8,
        role: NoteRole = .harmony,
        operators: NoteOperators? = nil
    ) {
        self.id = id
        self.pitch = min(max(pitch, 0), 127)
        self.startTick = max(0, startTick)
        self.lengthTicks = max(1, lengthTicks)
        self.velocity = min(max(velocity, 0), 1)
        self.role = role
        self.operators = operators
    }

    // MARK: Step views (quantized to the 16th grid)

    /// Start step on the 16th-note grid (rounds to the nearest step).
    public var startStep: Int {
        get { (startTick + Note.ticksPerStep / 2) / Note.ticksPerStep }
        set { startTick = max(0, newValue) * Note.ticksPerStep }
    }

    /// Length in steps (≥1, rounds UP so a sub-step note still reads as one step).
    public var lengthSteps: Int {
        get { max(1, (lengthTicks + Note.ticksPerStep - 1) / Note.ticksPerStep) }
        set { lengthTicks = max(1, newValue) * Note.ticksPerStep }
    }

    /// Exclusive end step: the first step at which the note is no longer held.
    public var endStep: Int { startStep + lengthSteps }

    /// Exclusive end tick.
    public var endTick: Int { startTick + lengthTicks }

    // MARK: Queries / editing

    /// True if this note is sounding during `step` (start inclusive, end exclusive).
    public func covers(step: Int) -> Bool {
        step >= startStep && step < endStep
    }

    /// Nudge the start by a tick delta (clamped to ≥0). Returns a new note.
    public func nudged(byTicks delta: Int) -> Note {
        var n = self
        n.startTick = max(0, startTick + delta)
        return n
    }

    /// Snap the start to the nearest multiple of `division` ticks (e.g. a 16th =
    /// `ticksPerStep`, a triplet 8th = `ticksPerQuarter/3`). Returns a new note.
    public func quantizedStart(toTicks division: Int) -> Note {
        guard division > 0 else { return self }
        var n = self
        n.startTick = ((startTick + division / 2) / division) * division
        return n
    }

    // MARK: Codable (ticks primary; falls back to legacy steps)

    private enum CodingKeys: String, CodingKey {
        case id, pitch, startTick, lengthTicks, velocity, role, operators, mpe
        case startStep, lengthSteps   // legacy fallback (pre-PPQ clips)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.pitch = min(max(try c.decode(Int.self, forKey: .pitch), 0), 127)
        self.velocity = min(max(try c.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.8, 0), 1)
        if let t = try c.decodeIfPresent(Int.self, forKey: .startTick) {
            self.startTick = max(0, t)
        } else {
            let s = try c.decodeIfPresent(Int.self, forKey: .startStep) ?? 0
            self.startTick = max(0, s) * Note.ticksPerStep
        }
        if let lt = try c.decodeIfPresent(Int.self, forKey: .lengthTicks) {
            self.lengthTicks = max(1, lt)
        } else {
            let ls = try c.decodeIfPresent(Int.self, forKey: .lengthSteps) ?? 1
            self.lengthTicks = max(1, ls) * Note.ticksPerStep
        }
        self.role = try c.decodeIfPresent(NoteRole.self, forKey: .role) ?? .harmony
        self.operators = try c.decodeIfPresent(NoteOperators.self, forKey: .operators)
        self.mpe = try c.decodeIfPresent(NoteMPE.self, forKey: .mpe)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pitch, forKey: .pitch)
        try c.encode(startTick, forKey: .startTick)
        try c.encode(lengthTicks, forKey: .lengthTicks)
        try c.encode(velocity, forKey: .velocity)
        try c.encode(role, forKey: .role)
        // Only when set — a plain note's JSON is byte-identical to pre-operator
        // builds, and older builds simply ignore the key when it is present.
        try c.encodeIfPresent(operators, forKey: .operators)
        try c.encodeIfPresent(mpe, forKey: .mpe)
        // Legacy mirror so an older build can still read the clip.
        try c.encode(startStep, forKey: .startStep)
        try c.encode(lengthSteps, forKey: .lengthSteps)
    }
}
