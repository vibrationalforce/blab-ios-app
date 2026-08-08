//
//  MoodStorage.swift
//  Echoelmusic — Sequencer
//
//  ⭐ THE EIGHT MOOD KNOBS WERE THE ONLY COMPOSER INPUT WITH NO PERSISTENCE AT ALL (#275 slice 1).
//
//  `EchoelStudioView` holds them as `@State private var mood = MoodProfile()`. Every one of
//  their siblings on the way into `BioComposer.Input` is `@AppStorage`-backed and survives a
//  relaunch — genre, scale, root, lockBPM, lockedBPM, bassRhythm, padRhythm, articulation,
//  preset, and (via `SessionContext`) tuning and A4. Mood was not. Eight dials that shape
//  density, register, dissonance, chord colour, leaps, ornaments, placement and velocity feel
//  reset to factory on every cold start, silently, with no control showing that it happened.
//
//  ⭐ AND IT WAS INVISIBLE TO THE ONE LINE BUILT TO ANSWER "WHAT DID I WAKE UP WITH".
//  `EchoelStudioView.logLaunchMusicalIdentity` (#401) reports twelve values and never reported
//  mood, because there was nothing persisted to report. `SoundReset` (#400) likewise could not
//  list it. So a founder reading the launch breadcrumb after a session that sounded different
//  got a complete-looking line that omitted eight of the knobs that made it sound that way.
//
//  ⚠️ WHY A STRING AND NOT EIGHT KEYS. `@AppStorage` binds one scalar per key, so the direct
//  shape is eight new `StudioDefaultKeys` entries and eight declarations. The tempting shortcut
//  — conforming `MoodProfile` to `RawRepresentable<String>` so `@AppStorage` takes it whole — is
//  a trap this file will not set: the standard library provides Codable conformance FOR
//  RawRepresentable types via their rawValue, which would silently change how `TimelineLane.mood`
//  already encodes on disk. One key holding this type's own JSON keeps the storage decision here,
//  in one place (#416), and touches no existing persisted shape.
//
//  ⚠️ TOLERANT BY CONSTRUCTION, and deliberately NOT by extending `MoodProfile`'s own Codable.
//  Decoding into `[String: Float]` and reading field by field means an absent, malformed or
//  non-finite entry costs exactly that ONE field its stored value and nothing else — the
//  Persistence-Steward `decodeIfPresent` rule, obtained without changing a type that
//  `TimelineLane` already persists. A synthesized `MoodProfile` decode would throw on a single
//  missing key and reset all eight.
//
//  ⚠️ NON-FINITE FALLS BACK TO THE FIELD'S DEFAULT, IT IS NOT CLAMPED — and the shared
//  `clamped(to:)` is the wrong tool here on purpose. That one maps NaN to the range's LOWER
//  bound, which for these fields is 0, and 0 is a real, meaningful mood setting ("no tension",
//  "machine-exact"). Turning "this value is unreadable" into "the user asked for none of it"
//  is the fabricated-number class (#424/#426/#433/#461). A finite value outside 0…1 IS clamped:
//  the knobs only produce 0…1, so out-of-range can only be corruption, and every reader treats
//  the fields as unit-range anyway.
//
//  ⚠️ HONEST LIMIT: an OLDER build reading a string written by a NEWER one that has a ninth mood
//  field will drop that field on the next write-back. That is true of every scalar key in
//  `StudioDefaultKeys` too and is not worth a version tag here; it is written down so the next
//  person adding a mood dimension knows the downgrade cost rather than discovering it.
//

import Foundation

/// The one definition of how a `MoodProfile` is stored in `UserDefaults` — see the header for
/// why it is a single JSON string rather than eight keys or a `RawRepresentable` conformance.
public enum MoodStorage {

    /// The storage keys, one per `MoodProfile` field. Deliberately the property names: a
    /// stored blob is read by humans in a diagnostics dump, and an index-based scheme would
    /// re-point every field the moment a dimension is inserted.
    private enum Field {
        static let liveliness = "liveliness"
        static let darkness = "darkness"
        static let tension = "tension"
        static let romance = "romance"
        static let weird = "weird"
        static let virtuosity = "virtuosity"
        static let syncopation = "syncopation"
        static let humanize = "humanize"
    }

    /// The unit range every mood field lives in.
    private static let range: ClosedRange<Float> = 0...1

    /// Encode for `UserDefaults`. Sorted keys so a stored value is stable and diffable —
    /// two identical moods must produce identical strings, or a launch restore would look
    /// like a change to anything comparing the raw text.
    public static func encode(_ mood: MoodProfile) -> String {
        let fields: [String: Float] = [
            Field.liveliness: mood.liveliness,
            Field.darkness: mood.darkness,
            Field.tension: mood.tension,
            Field.romance: mood.romance,
            Field.weird: mood.weird,
            Field.virtuosity: mood.virtuosity,
            Field.syncopation: mood.syncopation,
            Field.humanize: mood.humanize
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(fields),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Decode a stored string. An empty string, unreadable text, a missing field or a
    /// non-finite number each fall back to THAT field's factory default — never to zero,
    /// and never taking the other seven fields with it.
    public static func decode(_ raw: String) -> MoodProfile {
        guard let data = raw.data(using: .utf8),
              let fields = try? JSONDecoder().decode([String: Float].self, from: data)
        else { return MoodProfile() }
        return profile(from: fields)
    }

    /// The field-by-field decision, split out from `decode` so a guard can drive it directly.
    ///
    /// ⚠️ THAT SPLIT IS NOT COSMETIC, AND THE REASON IS AN HONEST LIMIT: **JSON cannot carry a
    /// non-finite number.** `NaN` is not valid JSON at all, and a magnitude past `Float`'s range
    /// makes `JSONDecoder` throw for the whole document rather than for one field. So the
    /// `isFinite` branch below is UNREACHABLE through `decode` today — a guard that fed `"NaN"` as
    /// text would be green because the parse failed, not because the branch worked (#367). It is
    /// kept because this transform is the one place the rule lives and a future non-JSON caller
    /// (a peer payload, a migration) would reach it, and it is testable only because it is public.
    public static func profile(from fields: [String: Float]) -> MoodProfile {
        var mood = MoodProfile()

        func value(_ key: String) -> Float? {
            guard let v = fields[key], v.isFinite else { return nil }
            return min(max(v, range.lowerBound), range.upperBound)
        }

        if let v = value(Field.liveliness) { mood.liveliness = v }
        if let v = value(Field.darkness) { mood.darkness = v }
        if let v = value(Field.tension) { mood.tension = v }
        if let v = value(Field.romance) { mood.romance = v }
        if let v = value(Field.weird) { mood.weird = v }
        if let v = value(Field.virtuosity) { mood.virtuosity = v }
        if let v = value(Field.syncopation) { mood.syncopation = v }
        if let v = value(Field.humanize) { mood.humanize = v }
        return mood
    }
}
