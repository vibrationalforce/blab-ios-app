// TheMoodKnobsSurviveARelaunchTests.swift
// Echoel — #275 slice 1. The eight mood dials were the ONLY composer input with no persistence
// at all, and therefore the only one the launch breadcrumb could not report and the sound reset
// could not clear.
//
// ⚠️ THE LIMIT FIRST. The STORAGE half is real behaviour driven end to end — `MoodStorage` is a
// `public enum` of pure Foundation functions and `MoodProfile` is a `public` `Equatable`
// value type, so those cases exercise shipped code rather than describing it. The WIRING half is
// a SOURCE-TEXT SCAN: `moodRaw` is an `@AppStorage` on a view this bundle cannot construct, and
// `resetSoundToDefaults()` / `logLaunchMusicalIdentity()` are `private` members of it. **That the
// dials come back on a real cold start, and that a restored mood sounds like the one that was
// dialled in, are two device trials and both are OPEN.**
//
// ⭐ WHAT WAS WRONG. `EchoelStudioView` holds them as `@State private var mood = MoodProfile()`.
// Every sibling on the way into `BioComposer.Input` is `@AppStorage`-backed and survives a cold
// start — genre, scale, root, lockBPM, lockedBPM, bassRhythm, padRhythm, articulation, preset,
// and via `SessionContext` the tone system and A4. Mood was not. Density, register, dissonance,
// chord colour, leaps, ornaments, placement and velocity feel silently returned to factory on
// every launch, with no control showing that it had happened — and #401's launch line, built to
// answer "what did I wake up with", reported twelve values and could not report these eight
// because nothing stored them. #400's reset could not list them for the same reason.
//
// ⭐ THE COUNTERWEIGHTS ARE THE CONTENT (#343). A guard that only asserted "a key exists" would
// stay green on a tree that kept the key and lost every property that makes it safe: the
// per-field tolerance (one bad entry must not reset the other seven), the non-finite fallback
// (which must be the FIELD's default and never zero — `clamped(to:)` maps NaN to the lower bound,
// and 0 is a real mood setting: "no tension", "machine-exact"), the empty-string default (any
// literal there would be a SECOND declaration of `MoodProfile()`'s defaults), and the single
// encode site (three writers — knobs, pad drag, `MoodPreset` — would be three copies of one
// storage decision, #416).
//
// ⚠️ HONEST GRADING (#433/#464), stated plainly rather than disguised: this file **cannot be
// graded against the parent tree at all** — every behaviour case names `MoodStorage`, and claim 2
// names `StudioDefaultKeys.mood`, neither of which exists there, so the bundle does not compile
// and NO claim has a verdict. Transcribed by hand instead (a Python rebuild of
// `SourceText.codeOnly` plus the brace matcher, run against `git show HEAD:` and the working
// tree, every needle driven individually): **all 8 source needles flip — red on the parent, green
// here — and NONE is an anchor-absence artefact**, because `.onAppear`,
// `logLaunchMusicalIdentity()`, `resetSoundToDefaults()` and `SoundReset.entries` all exist there
// and fail on CONTENT. They are **SIX findings, not eight** (#486): the storage declaration, the
// restore-before-the-line, the single write-back, the breadcrumb, the reset push-back and the
// reset entry — the count needle is the same finding as the closure needle (on the parent it
// reads 0, not 2), and the two breadcrumb needles are one line. The eight behaviour cases drive a
// type this same commit creates and could never have been red; booking them as regressions would
// be the #433 defect in the flattering direction.
//
// ⚠️ `SourceText.codeOnly` is **LOAD-BEARING here, and that is MEASURED** rather than assumed
// (#484/#485 each had to retract the stronger claim once, #486 twice): raw versus stripped differ
// on **1 of 16** needle verdicts across both trees — the ORDERING needle, and it fails on the RAW
// text of the CORRECT tree. The restore's own ⚠️ comment writes "MUST PRECEDE
// `logLaunchMusicalIdentity()`" nine lines ABOVE the assignment it guards, so a raw scan finds the
// prose mention first and concludes the order is wrong. The #486/#491 collision again: this repo
// writes down the rule beside the line, and a positional scan reads the note as the code.
//

import XCTest
@testable import Echoelmusic

final class TheMoodKnobsSurviveARelaunchTests: XCTestCase {

    private static let view = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let reset = "Sources/Echoelmusic/Core/SoundReset.swift"

    // MARK: - behaviour: the storage decision, driven end to end

    /// Claim 1 — a dialled-in mood comes back exactly. All eight fields, not "close enough":
    /// `Float` round-trips through JSON without loss at these magnitudes, and a lossy restore
    /// would be a silent drift on every relaunch rather than a visible failure.
    func testAMoodSurvivesTheRoundTrip() {
        let m = MoodProfile(liveliness: 0.82, darkness: 0.11, tension: 0.44, romance: 0.97,
                            weird: 0.05, virtuosity: 0.63, syncopation: 0.28, humanize: 0.71)
        XCTAssertEqual(MoodStorage.decode(MoodStorage.encode(m)), m,
                       "a stored mood must come back field for field — a lossy restore drifts a "
                       + "little on every launch, which is worse than not persisting at all")
    }

    /// Claim 2 — the key's default. `StudioDefaultKeys.mood.value` is `""`, so THIS is the value
    /// a fresh install decodes, and it must resolve to the factory profile rather than to zeros.
    func testAnEmptyStringIsTheFactoryProfile() {
        XCTAssertEqual(MoodStorage.decode(""), MoodProfile(),
                       "a fresh install stores nothing; decoding that must be the factory mood, "
                       + "not eight zeros")
        XCTAssertEqual(StudioDefaultKeys.mood.value, "",
                       "the key default must stay empty — any literal profile there would be a "
                       + "SECOND declaration of MoodProfile()'s defaults and the two would drift")
    }

    /// Claim 3 — unreadable text costs the stored value and nothing else.
    func testUnreadableTextIsTheFactoryProfile() {
        XCTAssertEqual(MoodStorage.decode("not json at all"), MoodProfile())
        XCTAssertEqual(MoodStorage.decode("{"), MoodProfile())
        XCTAssertEqual(MoodStorage.decode("[1,2,3]"), MoodProfile(),
                       "valid JSON of the wrong shape must fall back too, not trap")
    }

    /// Claim 4 — a missing field costs ONLY that field (the `decodeIfPresent` law). A synthesized
    /// `MoodProfile` decode would throw on one absent key and reset all eight; that is exactly why
    /// this decodes into `[String: Float]` and reads field by field.
    func testAMissingFieldCostsOnlyThatField() {
        let stored = "{\"darkness\":0.9,\"humanize\":0.8,\"liveliness\":0.1,\"romance\":0.7,"
                   + "\"syncopation\":0.6,\"tension\":0.5,\"virtuosity\":0.4}"   // no "weird"
        let m = MoodStorage.decode(stored)
        XCTAssertEqual(m.weird, MoodProfile().weird, accuracy: 1e-6,
                       "the absent field falls back to ITS default")
        XCTAssertEqual(m.liveliness, 0.1, accuracy: 1e-6,
                       "and the seven present fields keep their stored values — one gap must not "
                       + "reset the whole profile")
        XCTAssertEqual(m.darkness, 0.9, accuracy: 1e-6)
        XCTAssertEqual(m.humanize, 0.8, accuracy: 1e-6)
    }

    /// Claim 5 — THE COUNTERWEIGHT AGAINST `clamped(to:)`. A non-finite entry falls back to that
    /// field's DEFAULT, explicitly not to zero. The shared clamp maps NaN to the range's lower
    /// bound, which here is 0, and 0 is a real setting — turning "unreadable" into "the user asked
    /// for none of it" is the fabricated-number class (#424/#426/#433/#461). Witnessed on fields
    /// whose defaults are NOT zero, or the assertion could not tell the two policies apart.
    ///
    /// ⚠️ DRIVEN THROUGH `profile(from:)`, NOT THROUGH `decode`, and that is an honest limit
    /// rather than convenience: JSON cannot carry a non-finite number, so feeding `"NaN"` as text
    /// would pass because the PARSE failed — a guard green for a reason other than its named one
    /// (#367). Through the JSON door this branch is unreachable today; through this transform it
    /// is the rule, and the rule is what a future non-JSON caller would reach.
    func testANonFiniteFieldFallsBackToItsDefaultAndNotToZero() {
        for bad in [Float.nan, .infinity, -.infinity] {
            let m = MoodStorage.profile(from: ["liveliness": bad, "romance": bad])
            XCTAssertEqual(m.liveliness, MoodProfile().liveliness, accuracy: 1e-6,
                           "\(bad) must read as ABSENT, not as the bottom of the range")
            XCTAssertEqual(m.romance, MoodProfile().romance, accuracy: 1e-6)
            XCTAssertNotEqual(m.liveliness, 0,
                              "if this ever reads 0 the fallback became clamped(to:) and every "
                              + "unreadable field now claims the user asked for none of it")
        }
    }

    /// Claim 5b — and the two doors agree on everything JSON CAN carry: `decode` must be
    /// `profile(from:)` over the parsed dictionary, not a second copy of the field logic (#416).
    func testDecodeDelegatesToTheSameTransform() {
        let fields: [String: Float] = ["liveliness": 0.11, "darkness": 0.22, "tension": 0.33,
                                       "romance": 0.44, "weird": 0.55, "virtuosity": 0.66,
                                       "syncopation": 0.77, "humanize": 0.88]
        let direct = MoodStorage.profile(from: fields)
        let viaText = MoodStorage.decode(MoodStorage.encode(direct))
        XCTAssertEqual(direct, viaText,
                       "the dictionary door and the string door must resolve identically")
    }

    /// Claim 6 — a FINITE value outside the unit range IS clamped, and the two policies stay
    /// distinguishable: -3 on `romance` clamps to 0, which is not its default.
    func testAFiniteValueOutsideTheUnitRangeIsClamped() {
        let m = MoodStorage.decode("{\"liveliness\":5.0,\"romance\":-3.0}")
        XCTAssertEqual(m.liveliness, 1.0, accuracy: 1e-6)
        XCTAssertEqual(m.romance, 0.0, accuracy: 1e-6,
                       "a finite out-of-range value is corruption of a known direction and is "
                       + "clamped — unlike a non-finite one, which is not a direction at all")
        XCTAssertNotEqual(m.romance, MoodProfile().romance,
                          "clamped and default must not coincide here, or claim 5 proves nothing")
    }

    /// Claim 7 — the encoding is stable. `.sortedKeys` is not cosmetic: two identical moods must
    /// produce identical strings, or a launch restore writes a "different" value back and anything
    /// comparing the raw text sees a change that did not happen.
    func testTheEncodingIsStable() {
        let a = MoodProfile(liveliness: 0.3, darkness: 0.4, tension: 0.5, romance: 0.6,
                            weird: 0.7, virtuosity: 0.8, syncopation: 0.9, humanize: 1.0)
        let b = MoodProfile(liveliness: 0.3, darkness: 0.4, tension: 0.5, romance: 0.6,
                            weird: 0.7, virtuosity: 0.8, syncopation: 0.9, humanize: 1.0)
        XCTAssertEqual(MoodStorage.encode(a), MoodStorage.encode(b))
        let text = MoodStorage.encode(a)
        let names = text.split(separator: "\"").enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
        XCTAssertEqual(names, names.sorted(),
                       "field order must be sorted, or the same mood serialises differently run "
                       + "to run: \(text)")
        XCTAssertEqual(names.count, 8, "all eight dials must be written: \(text)")
    }

    /// Claim 8 — the reset lists mood, keyed exactly to the one storage key. Without this the
    /// dials would persist and be unclearable, which is precisely the state `SoundReset` exists to
    /// stop needing a reinstall for.
    func testTheResetClearsTheMoodKey() {
        let entry = SoundReset.entries.first { $0.label == "mood" }
        XCTAssertNotNil(entry, "SoundReset must list mood — a value that persists and cannot be "
                        + "reset is the #400 defect returning")
        XCTAssertEqual(entry?.keys, [StudioDefaultKeys.mood.key])
        XCTAssertTrue(SoundReset.keys.contains(StudioDefaultKeys.mood.key))
    }

    // MARK: - wiring: source-text scans

    /// Claim 9 — the view declares the storage AND restores it BEFORE the launch line. The
    /// ordering is the substance: `logLaunchMusicalIdentity()` reports `mood=` now, and reporting
    /// the value the view was CONSTRUCTED with instead of the one it woke up with would make the
    /// breadcrumb lie about exactly the class of state it exists to expose.
    func testTheViewRestoresTheMoodBeforeItReportsIt() throws {
        let src = try code(Self.view)
        XCTAssertTrue(src.contains("private var moodRaw = StudioDefaultKeys.mood.value"),
                      "the storage half of the eight dials is gone")
        let appear = try block(startingAt: ".onAppear", in: src)
        guard let decode = appear.range(of: "mood = MoodStorage.decode(moodRaw)"),
              let line = appear.range(of: "logLaunchMusicalIdentity()") else {
            return XCTFail("onAppear no longer both restores the mood and logs the launch line")
        }
        XCTAssertTrue(decode.lowerBound < line.lowerBound,
                      "the restore must precede the launch line, or the breadcrumb reports the "
                      + "constructed mood instead of the woken-up one")
    }

    /// Claim 10 — exactly ONE encode site (#416). Persisting at each of the three writers (the
    /// eight knobs, the mood pad's drag, applying a `MoodPreset`) would be three copies of one
    /// storage decision, and the pad is the one that would be forgotten: it writes two fields from
    /// inside a drag gesture.
    func testThereIsExactlyOneEncodeSite() throws {
        let src = try code(Self.view)
        XCTAssertTrue(src.contains(".onChange(of: mood) { _, m in moodRaw = MoodStorage.encode(m) }"),
                      "the single write-back is gone or reshaped")
        XCTAssertEqual(src.components(separatedBy: "MoodStorage.encode").count - 1, 1,
                       "mood must be encoded in exactly one place — a second site is a second "
                       + "copy of the storage decision (#416)")
    }

    /// Claim 11 — the launch line reports it. `ResetSoundClearsWhatTheLaunchLineReportsTests`
    /// already requires every reset label to appear as `<label>=` on that line; this pins the
    /// VALUE side, so a tree that emits the label with a placeholder goes red.
    func testTheLaunchLineReportsTheEightNumbers() throws {
        let src = try code(Self.view)
        let fn = try block(startingAt: "private func logLaunchMusicalIdentity()", in: src)
        XCTAssertTrue(fn.contains("mood=\\(moodText)"),
                      "the launch breadcrumb must carry the mood values")
        XCTAssertTrue(fn.contains("mood.liveliness, mood.darkness, mood.tension, mood.romance"),
                      "it must report the NUMBERS, not merely that a mood exists — these are "
                      + "eight settings the player chose, unlike the inferred fingerprint")
    }

    /// Claim 12 — the reset pushes the factory profile back into the live `@State`. Removing a key
    /// is not the same as applying its default when a live object holds the value: without this
    /// the eight dials in memory keep shaping every take until the next launch, and the reset
    /// visibly does nothing — the "it needed a reinstall" experience returning through the button
    /// built to end it.
    func testTheResetPushesTheProfileBackIntoTheLiveState() throws {
        let src = try code(Self.view)
        let fn = try block(startingAt: "private func resetSoundToDefaults()", in: src)
        XCTAssertTrue(fn.contains("mood = MoodProfile()"),
                      "SoundReset.clear removes the key, but `mood` is @State — the live dials "
                      + "must be pushed back to factory in the same call")
    }

    /// Claim 13 — the reset file names the key through its owner, not through a repeated literal.
    func testTheResetEntryReadsTheKeyFromItsOwner() throws {
        let src = try code(Self.reset)
        XCTAssertTrue(src.contains("Entry(label: \"mood\", keys: [StudioDefaultKeys.mood.key])"),
                      "the reset must read the key from StudioDefaultKeys, not repeat a literal")
    }

    // MARK: - helpers

    /// Reads a repo source file as CODE, never prose (#453). Skips on the DIRECTORY, never on the
    /// individual file: a `fileExists` bracket around each read turns a deletion — the exact
    /// catastrophe this bundle stands against — into a green skip (#475).
    private func code(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "Sources/ not present in this checkout")
        let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "\(relative) is empty — the scans below would pass on nothing")
        return SourceText.codeOnly(text)
    }

    /// The text of one declaration: from `anchor` to the matching close of its FIRST `{`. Brace
    /// counted rather than line counted, and it THROWS on a missing anchor rather than returning
    /// "" — a scan that passes on an empty slice is the #367 defect.
    private func block(startingAt anchor: String, in source: String) throws -> String {
        guard let start = source.range(of: anchor) else {
            throw ScanFailure("anchor '\(anchor)' is missing — fix the anchor, not the assertions")
        }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else {
            throw ScanFailure("anchor '\(anchor)' has no opening brace to bound the scan")
        }
        var depth = 0
        var i = open
        while i < source.endIndex {
            if source[i] == "{" { depth += 1 }
            if source[i] == "}" {
                depth -= 1
                if depth == 0 { return String(source[start.lowerBound...i]) }
            }
            i = source.index(after: i)
        }
        throw ScanFailure("anchor '\(anchor)' never closes — unbalanced braces in the scanned text")
    }

    private struct ScanFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
