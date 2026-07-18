// Arrangement.swift
// Echoel — the linear song timeline (Arrangement view). Where the Session grid
// (ClipStore) is a palette of launchable clips, an Arrangement is an ORDERED
// chain of sections that plays clips back over song time: section 1 for N bars,
// then section 2, and so on. Pure value types so the whole song persists as JSON
// and round-trips cleanly; the play cursor is a separate pure struct so the
// bar-advance logic is unit-testable without any audio engine.

import Foundation

/// One block on the arrangement timeline: a reference to a Session clip that
/// plays for `lengthBars` bars. `clipID == nil` is a deliberate silent gap.
public struct ArrangementSection: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Reference into `ClipStore` (matched by `Clip.id`). `nil` = silent gap.
    public var clipID: UUID?
    public var name: String
    public var colorIndex: Int
    /// How many bars this section plays before the song advances. Always >= 1.
    public var lengthBars: Int

    public init(
        id: UUID = UUID(),
        clipID: UUID? = nil,
        name: String,
        colorIndex: Int = 0,
        lengthBars: Int = 1
    ) {
        self.id = id
        self.clipID = clipID
        self.name = name
        self.colorIndex = colorIndex
        self.lengthBars = max(1, lengthBars)
    }

    private enum CodingKeys: String, CodingKey {
        case id, clipID, name, colorIndex, lengthBars
    }

    /// Forward/backward-compatible decode (law 9, mirroring `Clip.init(from:)`):
    /// a section saved before a field existed — or a future field added later —
    /// decodes to its default instead of THROWING. Without this, the synthesized
    /// decoder makes every field required, so one new field fails the whole
    /// `Arrangement` decode and `ArrangementStore` silently drops the entire song
    /// (`?? Arrangement()`). Encode stays synthesized (the CodingKeys match).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        clipID = try? c.decode(UUID.self, forKey: .clipID)   // nil = silent gap
        name = (try? c.decode(String.self, forKey: .name)) ?? "Section"
        colorIndex = (try? c.decode(Int.self, forKey: .colorIndex)) ?? 0
        lengthBars = max(1, (try? c.decode(Int.self, forKey: .lengthBars)) ?? 1)
    }
}

/// The full song: an ordered list of sections.
public struct Arrangement: Codable, Sendable, Equatable {
    public var sections: [ArrangementSection]

    public init(sections: [ArrangementSection] = []) {
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey { case sections }

    /// Additive decode (law 9): a document missing `sections` (or a future added
    /// field) loads as an empty song instead of throwing and losing everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sections = (try? c.decode([ArrangementSection].self, forKey: .sections)) ?? []
    }

    /// Total length of the song in bars.
    public var totalBars: Int { sections.reduce(0) { $0 + max(1, $1.lengthBars) } }

    /// The per-section bar lengths, in order — the only input the cursor needs.
    public var sectionLengths: [Int] { sections.map { max(1, $0.lengthBars) } }
}

/// Pure play-head over an arrangement. Tracks which section is sounding and how
/// many of its bars have elapsed. Advancing happens one completed bar at a time
/// so the logic is deterministic and fully unit-testable (no clock, no audio).
public struct ArrangementCursor: Equatable, Sendable {
    /// Index of the section currently sounding.
    public private(set) var index: Int
    /// Bars elapsed within the current section (0 ..< section.lengthBars).
    public private(set) var barsIntoSection: Int

    public init(index: Int = 0, barsIntoSection: Int = 0) {
        self.index = index
        self.barsIntoSection = barsIntoSection
    }

    /// Outcome of completing one bar of playback.
    public struct Advance: Equatable, Sendable {
        /// `true` when the play-head crossed into a different section (or looped
        /// back to the start) and the host should LOAD that section's clip.
        public var enteredNewSection: Bool
        /// `true` when a non-looping song ran past its last section — the host
        /// should stop the transport.
        public var finished: Bool
    }

    /// Jump straight to a section, restarting it from its first bar. Used by
    /// tap-to-seek on the timeline. Out-of-range indices are ignored (no-op).
    public mutating func seek(to newIndex: Int, sectionCount: Int) {
        guard newIndex >= 0, newIndex < sectionCount else { return }
        index = newIndex
        barsIntoSection = 0
    }

    /// Advance the cursor by one completed bar.
    ///
    /// - Parameters:
    ///   - sectionLengths: bar length of every section, in order.
    ///   - loop: when the last section ends, restart from section 0 (`true`) or
    ///     finish (`false`).
    /// - Returns: whether a new section was entered (→ load its clip) and whether
    ///   the song finished (→ stop).
    public mutating func completeBar(sectionLengths: [Int], loop: Bool) -> Advance {
        guard !sectionLengths.isEmpty else {
            return Advance(enteredNewSection: false, finished: true)
        }
        // Clamp a stale index (e.g. a section was deleted mid-play).
        if index >= sectionLengths.count {
            index = 0
            barsIntoSection = 0
            return Advance(enteredNewSection: true, finished: false)
        }

        let currentLength = max(1, sectionLengths[index])
        let nextBars = barsIntoSection + 1

        if nextBars < currentLength {
            // Still inside the current section — keep playing the same clip.
            barsIntoSection = nextBars
            return Advance(enteredNewSection: false, finished: false)
        }

        // Current section is done — move to the next.
        let nextIndex = index + 1
        if nextIndex < sectionLengths.count {
            index = nextIndex
            barsIntoSection = 0
            return Advance(enteredNewSection: true, finished: false)
        }

        // Past the last section.
        if loop {
            index = 0
            barsIntoSection = 0
            return Advance(enteredNewSection: true, finished: false)
        }
        return Advance(enteredNewSection: false, finished: true)
    }
}
