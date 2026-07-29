// MoodPreset.swift
// Echoel — a named, saveable "mood": the 8 MoodProfile dimensions that shape the
// CHARACTER of the composition (not the timbre — that's SynthPatch). Mirrors the
// FXPreset / SynthPatch pattern so the whole app saves/recalls/shares the same way:
// Codable JSON, stable ids, curated factory set, a community submission URL.
//
// Lives in Sequencer/ (not DSP/) because it references MoodProfile — the AUv3
// plugin target compiles DSP/ only and must stay self-contained.

import Foundation

/// A named snapshot of a `MoodProfile` (the 8 composition-character dimensions),
/// plus curation tags. `Codable` so it round-trips to disk and to the community.
public struct MoodPreset: Codable, Identifiable, Sendable, Equatable {

    /// 1 = the shape as of 2026-07-29 (#189 slice 5). Same shape as `Clip`/`TrackFX`/
    /// `SynthPatch`: never decoded, never assigned, so the SYNTHESIZED encoder writes the
    /// current version by construction. `MoodPresetStore` persists a bare `[MoodPreset]`,
    /// so the stamp is PER MOOD — nothing versions the array itself.
    ///
    /// Note the deliberate inconsistency with its sibling `FXPreset`, which carries its own
    /// older `schema: Int` (assigned by callers, factory presets ship `3`). That one is NOT
    /// renamed to match: it is persisted and its values are meaningful, so a rename would
    /// be the exact silent-loss move this whole task exists to prevent.
    public static let currentSchemaVersion = 1

    /// ⚠️ Deliberately never read by `init(from:)` — the key exists so the ENCODER writes
    /// it; a migration reads the file's own value into a local inside the decoder.
    public private(set) var schemaVersion: Int = MoodPreset.currentSchemaVersion

    public var id: UUID
    public var name: String
    public var tags: [String]

    public var liveliness: Float
    public var darkness: Float
    public var tension: Float
    public var romance: Float
    public var weird: Float
    public var virtuosity: Float
    public var syncopation: Float
    public var humanize: Float

    public init(id: UUID = UUID(), name: String, tags: [String] = [],
                liveliness: Float = 0.5, darkness: Float = 0.5, tension: Float = 0.0,
                romance: Float = 0.3, weird: Float = 0.0,
                virtuosity: Float = 0.3, syncopation: Float = 0.15, humanize: Float = 0.25) {
        self.id = id
        self.name = name
        self.tags = tags
        self.liveliness = liveliness
        self.darkness = darkness
        self.tension = tension
        self.romance = romance
        self.weird = weird
        self.virtuosity = virtuosity
        self.syncopation = syncopation
        self.humanize = humanize
    }

    /// Capture a live `MoodProfile` under a name (and optional tags).
    public init(name: String, tags: [String] = [], from profile: MoodProfile) {
        self.init(name: name, tags: tags,
                  liveliness: profile.liveliness, darkness: profile.darkness,
                  tension: profile.tension, romance: profile.romance,
                  weird: profile.weird, virtuosity: profile.virtuosity,
                  syncopation: profile.syncopation, humanize: profile.humanize)
    }

    /// The recallable profile this preset represents.
    public var profile: MoodProfile {
        MoodProfile(liveliness: liveliness, darkness: darkness, tension: tension,
                    romance: romance, weird: weird, virtuosity: virtuosity,
                    syncopation: syncopation, humanize: humanize)
    }

    /// Case-insensitive search over name + tags. Empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if name.lowercased().contains(q) { return true }
        return tags.contains { $0.lowercased().contains(q) }
    }

    // Forward/backward-compatible decode: any missing field falls back to the
    // neutral default, so older/newer JSON never fails to load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MoodPreset(name: "")
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        liveliness = (try? c.decode(Float.self, forKey: .liveliness)) ?? d.liveliness
        darkness = (try? c.decode(Float.self, forKey: .darkness)) ?? d.darkness
        tension = (try? c.decode(Float.self, forKey: .tension)) ?? d.tension
        romance = (try? c.decode(Float.self, forKey: .romance)) ?? d.romance
        weird = (try? c.decode(Float.self, forKey: .weird)) ?? d.weird
        virtuosity = (try? c.decode(Float.self, forKey: .virtuosity)) ?? d.virtuosity
        syncopation = (try? c.decode(Float.self, forKey: .syncopation)) ?? d.syncopation
        humanize = (try? c.decode(Float.self, forKey: .humanize)) ?? d.humanize
    }
}

public extension MoodPreset {

    /// Decode a stable factory UUID literal without force-unwrapping. Every literal
    /// below is valid; the deterministic all-zero fallback only guards a future typo
    /// (it never hands out a random id), so favorites/recents stay stable.
    private static func uid(_ s: String) -> UUID {
        UUID(uuidString: s) ?? UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    }

    /// Curated factory moods — pick a feeling without dialing 8 knobs. Stable ids
    /// so favorites/recents survive relaunch and updates.
    static let factory: [MoodPreset] = [
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C1"),
                   name: "Calm", tags: ["ambient", "still", "gentle"],
                   liveliness: 0.20, darkness: 0.45, tension: 0.0, romance: 0.35,
                   weird: 0.0, virtuosity: 0.15, syncopation: 0.05, humanize: 0.35),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C2"),
                   name: "Dreamy", tags: ["ambient", "soft", "float"],
                   liveliness: 0.30, darkness: 0.55, tension: 0.05, romance: 0.60,
                   weird: 0.20, virtuosity: 0.20, syncopation: 0.10, humanize: 0.55),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C3"),
                   name: "Romantic", tags: ["warm", "lush", "tender"],
                   liveliness: 0.40, darkness: 0.40, tension: 0.05, romance: 0.90,
                   weird: 0.05, virtuosity: 0.35, syncopation: 0.12, humanize: 0.45),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C4"),
                   name: "Playful", tags: ["bright", "bouncy", "light"],
                   liveliness: 0.75, darkness: 0.25, tension: 0.05, romance: 0.30,
                   weird: 0.35, virtuosity: 0.45, syncopation: 0.55, humanize: 0.40),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C5"),
                   name: "Epic", tags: ["cinematic", "grand", "soar"],
                   liveliness: 0.80, darkness: 0.45, tension: 0.40, romance: 0.70,
                   weird: 0.15, virtuosity: 0.80, syncopation: 0.25, humanize: 0.30),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C6"),
                   name: "Dark & Tense", tags: ["dark", "scary", "dissonant"],
                   liveliness: 0.55, darkness: 0.85, tension: 0.85, romance: 0.10,
                   weird: 0.55, virtuosity: 0.40, syncopation: 0.30, humanize: 0.25),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C7"),
                   name: "Hypnotic", tags: ["minimal", "machine", "loop"],
                   liveliness: 0.45, darkness: 0.55, tension: 0.10, romance: 0.20,
                   weird: 0.10, virtuosity: 0.20, syncopation: 0.20, humanize: 0.05),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C8"),
                   name: "Virtuoso", tags: ["busy", "showy", "fast"],
                   liveliness: 0.85, darkness: 0.40, tension: 0.30, romance: 0.45,
                   weird: 0.40, virtuosity: 0.95, syncopation: 0.45, humanize: 0.35),

        // ── Added 2026-07-29 (founder: "Macht es Sinn bei mood noch mehr optionen
        // einzubauen? ARP, eclectic, Space, meditativ, trippy, etc sei creativ").
        //
        // WHAT A MOOD CAN AND CANNOT DO, because the names below promise things and
        // half a promise is worse than none: these 8 dimensions shape the NOTES —
        // how many, how high, how consonant, how ornamented, how far off the beat,
        // how evenly struck. They do not touch timbre (that is `SynthPatch`) and they
        // do not touch space (that is the FX chain). So "Space" here means a sparse,
        // low, wide-interval line that LEAVES room — not reverb. Reverb is one panel
        // over, and deliberately still the user's to dial.
        //
        // TWO NAMES FROM THE ASK ARE MISSING ON PURPOSE:
        //  • "ARP" is not a mood. An arpeggiator is a note GENERATOR with rate,
        //    direction, octave span and gate; there is no dimension here that could
        //    produce one, so a mood called Arp would be a control that lies about
        //    what it does — the exact class of defect this repo spent #164 removing.
        //    The founder reached the same conclusion unprompted ("Vielleicht ist der
        //    arp auch eine eigene Kategorie und könnte ein komplexes bedienelement
        //    werden"), and `BreathArp` already exists to be that surface.
        //  • Nothing was added CLOSER TOGETHER THAN THE SET ALREADY WAS. That is the
        //    exact claim, and it took two corrections to make it true. The first draft
        //    said "nothing was added near an existing mood" and measured plain distance
        //    over all 8 dimensions — which was wrong twice over:
        //      (a) The number was false. Eclectic landed 0.4110 from Virtuoso, TIGHTER
        //          than the shipped set's own tightest pair (Calm ↔ Dreamy, 0.4123).
        //      (b) Worse, the measure itself was decorative. `darkness` and `romance`
        //          are NOT read continuously by the composer — they are thresholds, and
        //          the ONLY reads in the whole engine are `mood.darkness > 0.6`
        //          (`BioComposer.composeHarmonic`, octave shift) and `mood.romance > 0.5`
        //          (adds the 7th). Two moods can therefore differ by 0.43 of darkness and
        //          produce the SAME notes. Measured that way, the first "Glass" was a
        //          clone of "Hypnotic" — the near-duplicate the test existed to catch,
        //          sailing through it.
        //    So the test now measures BOTH: raw spread, and spread with those two axes
        //    collapsed to what the engine actually acts on. On both measures the tightest
        //    pair in the library is a pre-existing one. See `MoodCharacterSmokeTests`.
        //
        // "Vast" and not "Space", which is the word the founder used: in THIS app "space"
        // is an occupied namespace — the spatial output stage (ADM-OSC `/adm/obj/{n}/*`,
        // `ImmersiveStageView`), and the founder's own next ask names "space" as a
        // character of the coming sample engine. A mood by that name would be read as one
        // of those. "Vast" says the same thing about the NOTES, which is all a mood can do.
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000C9"),
                   name: "Vast", tags: ["sparse", "wide", "open", "slow", "space"],
                   liveliness: 0.08, darkness: 0.72, tension: 0.12, romance: 0.40,
                   weird: 0.45, virtuosity: 0.08, syncopation: 0.02, humanize: 0.55),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CA"),
                   name: "Meditative", tags: ["still", "breath", "sustained", "warm"],
                   liveliness: 0.05, darkness: 0.30, tension: 0.00, romance: 0.20,
                   weird: 0.00, virtuosity: 0.00, syncopation: 0.00, humanize: 0.70),
        // 0.65 and 0.58 below, not 0.60 for both: `darkness` is compared with a STRICT
        // `> 0.6`, so a mood parked exactly on 0.60 sits on the edge of an audible cliff
        // (a whole octave). Written as 0.60 the intent is unreadable — did the author mean
        // "just under" or did they not know there was an edge? — and the day someone
        // changes `>` to `>=` both moods silently drop an octave. Off the edge on purpose.
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CB"),
                   name: "Trippy", tags: ["psychedelic", "off-kilter", "chromatic"],
                   liveliness: 0.62, darkness: 0.65, tension: 0.35, romance: 0.30,
                   weird: 0.95, virtuosity: 0.55, syncopation: 0.75, humanize: 0.60),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CC"),
                   name: "Eclectic", tags: ["restive", "mixed", "unpredictable"],
                   liveliness: 0.58, darkness: 0.52, tension: 0.30, romance: 0.62,
                   weird: 0.72, virtuosity: 0.72, syncopation: 0.52, humanize: 0.52),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CD"),
                   name: "Nocturne", tags: ["night", "dark", "lush", "expressive"],
                   liveliness: 0.25, darkness: 0.78, tension: 0.15, romance: 0.85,
                   weird: 0.10, virtuosity: 0.42, syncopation: 0.08, humanize: 0.62),
        // THE ONE THAT HAD TO BE REBUILT. Glass first read
        // (0.50, 0.12, 0, 0.12, 0.05, 0.25, 0, 0.02) — which looked distinct from Hypnotic
        // (0.45, 0.55, …) only because of a 0.43 gap in `darkness`, and darkness below 0.6
        // does nothing at all. On the axes the composer reads, that Glass was 0.24 from
        // Hypnotic: the same take with a different name. It is now what the name actually
        // means — minimalism: RELENTLESSLY busy, dead on the beat, machine-exact, with the
        // running figures that implies. That is a character no other mood here has.
        // The tags dropped "bright" for the same reason: at darkness 0.10 it is in the
        // identical register as half the library, and tags are searchable user-facing copy.
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CE"),
                   name: "Glass", tags: ["repeating", "exact", "running", "machine"],
                   liveliness: 0.88, darkness: 0.10, tension: 0.00, romance: 0.10,
                   weird: 0.02, virtuosity: 0.55, syncopation: 0.00, humanize: 0.00),
        MoodPreset(id: Self.uid("A1000000-0000-0000-0000-0000000000CF"),
                   name: "Restless", tags: ["driving", "urgent", "off-beat"],
                   liveliness: 0.92, darkness: 0.58, tension: 0.65, romance: 0.12,
                   weird: 0.50, virtuosity: 0.60, syncopation: 0.88, humanize: 0.50)
    ]

    /// Bundled community moods (`Resources/Community/moods/*.json`), best-effort —
    /// missing/corrupt files degrade to none. Reuses the shared loader so the
    /// community loop (submit → triage PR → bundle) works the same as FX/patches.
    static let community: [MoodPreset] = CommunityLibrary.load("Community/moods", as: MoodPreset.self)

    /// A pre-filled GitHub "new issue" URL carrying this mood's JSON, for the
    /// in-app "Submit to community" flow — mirrors FXPreset/SynthPatch. No backend.
    func communityIssueURL(owner: String = "vibrationalforce",
                           repo: String = "Echoelmusic") -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let body = """
        Thanks for sharing an Echoel mood!

        **Name:** \(name)

        The mood JSON is below — a maintainer will review it and, if curated, add \
        it to the mood library.

        ```json
        \(json)
        ```
        """
        var comps = URLComponents(string: "https://github.com/\(owner)/\(repo)/issues/new")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: "Mood submission: \(name)"),
            URLQueryItem(name: "labels", value: "mood-submission"),
            URLQueryItem(name: "body", value: body)
        ]
        return comps?.url
    }

    /// A pre-addressed email carrying this mood's JSON, for the in-app "Submit to
    /// community" flow. Composes a mail to the Echoel curator with the preset
    /// embedded — no GitHub account or app needed, works on any device with Mail.
    /// Curated submissions are bundled into the mood library. Foundation-only.
    func communityMailtoURL(to address: String = "echoel@tropicaldrones.com") -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        let body = """
        Sharing an Echoel mood for the community library.

        Name: \(name)

        Mood JSON below:

        \(json)
        """
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = address
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "Echoelmusic mood: \(name)"),
            URLQueryItem(name: "body", value: body)
        ]
        return comps.url
    }
}
