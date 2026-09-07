// TheAutotuneCharacterIsDerivedNotStoredTests.swift
// Echoel — #681. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS GUARDS. The founder asked for "Autotune (Charakter Einstellungen)". The
// monitor already had the maths (VL1/VL3, #599) and two raw 0…1 fields; what it did not
// have was a NAME for a setting. `VoiceTuneCharacter` supplies four, and the whole risk
// of that slice is in ONE design decision:
//
//   THE SELECTION IS DERIVED FROM THE LIVE VALUES, NEVER STORED.
//
// A stored `@State` character is the obvious implementation and it rots on the first
// drag of either field: the picker keeps claiming "Tight" while the numbers say
// something else. That is the ownership failure `DiatonicHarmonyFollower` already paid
// for ("a control that lies is worse than none"), and nothing in a compiler notices it.
// Claims 5–7 are the ones that go red if a later cycle "simplifies" the binding into a
// stored property; claims 1–4 are the algebra underneath.
//
// ⭐ IT IS A LABEL OVER SHIPPED BEHAVIOUR, NOT A NEW TASTE, and claim 2 is what keeps it
// that way. `AudioEngine` has launched with `voiceTuneStrength = 1` / `voiceTuneRetune =
// 0.8` since #599; `.tight` names that exact pair. Move either literal — on the engine
// side or the character side — and claim 2 goes red, because that is the moment a user
// starts hearing a different monitor than the one they shipped with.
//
// ⚠️ HONEST LIMITS. 7 tests, 26 assertion statements (6+3+4+3+3+3+4; counted in Python
// over lines whose first token is XCTAssert, NOT `grep -c`, which also catches the prose
// mentions around it — the header-counts-itself trap this repo has paid for twice). The
// number has now been wrong TWICE in one file, in both directions: the first draft wrote
// 26 from memory when it was 27, and the review fix (#682) folded claim 5's two name-tied
// negatives into one regex, taking it back to 26. Recount, never adjust by memory of the
// delta. Claims 1–4 are executed behaviour on the shipped pure type (no mocks, no host). Claims 5–7 are SOURCE-TEXT JOINS — the
// picker lives in a SwiftUI view this bundle cannot build, the house pattern
// (`SoundPanelPresetBarTests`, `TheVoiceTuneSnapsToTheSessionKeyTests`). What no test
// here can prove: that four characters are the RIGHT four, that `.natural` sounds
// natural, or that a segmented picker with nothing highlighted reads as "custom" to a
// performer mid-take. That is a device probe (NEEDS-FOUNDER-VERIFY BLOCKED-BY-#1024: monitoring on, Tune
// to key on, step through the four while singing; then drag Amount and check the
// highlight clears and the caption appears).
//
// ⭐ GRADING (§3). Transcribed in Python against BOTH trees. Worktree: all needles
// reproduce. Against the parent: claims 1–4 cannot even compile there (the type is new),
// so this file is FORWARD in full — red at the parent by absence, reported once (#486).
//
// ⛔ Stripper: NOT load-bearing here, and I expected the opposite. The picker carries a
// long ⭐ note that says "@State" and "Custom" in prose, so the obvious reading is that a
// raw scan would trip claims 5 and 7. Measured (raw vs stripped counts, both trees): every
// verdict is identical — the needles are the LONGER strings (`@State private var
// voiceTuneCharacter`, `VoiceTuneCharacter?.none`), which the prose never spells. The
// stripper still runs, because the day someone quotes one of those in a comment is the day
// it starts mattering. Recording it as "TRAGEND" without the count would have been the
// same defect this file's claim 2 exists to prevent: a number carried over from what I
// assumed rather than what I measured.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutotuneCharacterIsDerivedNotStoredTests: XCTestCase {

    // MARK: - 1: the four are distinct, in range, and ordered

    /// A character list that is not ordered reads as arbitrary — a performer expects the
    /// row to go from least to most correction, left to right. Both numbers must be
    /// non-decreasing across `allCases`, and no two characters may share a pair (two
    /// segments that produce the same sound is a menu that lies about having four).
    func testTheFourCharactersAreDistinctInRangeAndOrdered() {
        let all = VoiceTuneCharacter.allCases
        XCTAssertEqual(all, [.natural, .smooth, .tight, .hard],
                       "The declared order IS the on-screen order — ForEach walks allCases.")
        for c in all {
            XCTAssertTrue((0...1).contains(c.strength),
                          "\(c.label) strength \(c.strength) is outside the corrector's 0…1.")
            XCTAssertTrue((0...1).contains(c.retuneSpeed),
                          "\(c.label) retuneSpeed \(c.retuneSpeed) is outside the corrector's 0…1.")
        }
        for (a, b) in zip(all, all.dropFirst()) {
            XCTAssertLessThanOrEqual(a.strength, b.strength,
                                     "\(a.label) → \(b.label) walks BACK on strength.")
            XCTAssertLessThanOrEqual(a.retuneSpeed, b.retuneSpeed,
                                     "\(a.label) → \(b.label) walks BACK on retune speed.")
        }
        let pairs = Set(all.map { "\($0.strength)/\($0.retuneSpeed)" })
        XCTAssertEqual(pairs.count, all.count,
                       "Two characters share a pair — one segment is a duplicate of another.")
    }

    // MARK: - 2: the shipped default is a NAMED character, not a custom value

    /// ⭐ THE CLAIM THAT KEEPS THIS SLICE A LABEL. If `.tight` stops naming the engine's
    /// launch pair, every existing user's monitor either changes or shows "Custom" on a
    /// setting they never chose. It reads the literals out of `AudioEngine.swift` rather
    /// than hard-coding 1 / 0.8 twice, so moving them on EITHER side is caught (#416).
    ///
    /// ⛔ THE NEEDLES CARRY A TRAILING NEWLINE AND THAT IS THE WHOLE POINT. Without it
    /// `contains("… Float = 0.8")` also matches `= 0.85`, `= 0.82`, `= 0.8123` — so the
    /// one drift this claim exists to catch would pass it green. Both lines are verified
    /// newline-terminated with no trailing whitespace (`cat -A`), and `codeOnly` preserves
    /// line structure, so anchoring on the newline is safe. A needle that is a PREFIX of
    /// the failure it forbids fails open, and nothing about the green tick says so.
    func testTheShippedDefaultIsExactlyTheTightCharacter() throws {
        let engine = try source("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertTrue(engine.contains("var voiceTuneStrength: Float = 1\n"), """
            The engine's default correction amount is no longer `Float = 1`. If that was \
            deliberate, `VoiceTuneCharacter.tight` must move with it — otherwise the app \
            launches on a setting the picker calls Custom.
            """)
        XCTAssertTrue(engine.contains("var voiceTuneRetune: Float = 0.8\n"), """
            The engine's default retune speed is no longer `Float = 0.8`. Same rule as \
            above: the named character and the launch value are ONE decision.
            """)
        XCTAssertEqual(VoiceTuneCharacter.matching(strength: 1, retuneSpeed: 0.8), .tight,
                       "The launch pair must land on a named character, not on Custom.")
    }

    // MARK: - 3: derived matching, including the Float → Double widening at the door

    /// The door stores `Float` and the corrector speaks `Double`. `Float(0.8)` widens to
    /// 0.800000011920929, so an exact `==` here would report Custom on a freshly launched
    /// app. The tolerance exists for exactly this and is pinned by the second assertion.
    func testMatchingSurvivesTheFloatWideningAndStillRejectsOffPoints() {
        XCTAssertEqual(VoiceTuneCharacter.matching(strength: Double(Float(1.0)),
                                                   retuneSpeed: Double(Float(0.8))), .tight,
                       "Float → Double widening must not push the launch pair off its name.")
        XCTAssertEqual(VoiceTuneCharacter.matching(strength: Double(Float(0.55)),
                                                   retuneSpeed: Double(Float(0.15))), .natural)
        XCTAssertNil(VoiceTuneCharacter.matching(strength: 0.67, retuneSpeed: 0.30),
                     "A pair between two characters is Custom — the picker must clear.")
        XCTAssertNil(VoiceTuneCharacter.matching(strength: 1.0, retuneSpeed: 0.15), """
            Both numbers must match. A pair that borrows one half from `.tight` and the \
            other from `.natural` is the performer's own setting, not a named one.
            """)
    }

    // MARK: - 4: a non-finite value can never read as a named character

    /// The engine sanitises before handing values to the corrector, but this type is read
    /// straight off the control-plane properties by the view. A NaN that answered "Tight"
    /// would put a confident label on a broken number.
    func testNonFiniteValuesReadAsCustomNeverAsACharacter() {
        XCTAssertNil(VoiceTuneCharacter.matching(strength: .nan, retuneSpeed: 0.8))
        XCTAssertNil(VoiceTuneCharacter.matching(strength: 1, retuneSpeed: .nan))
        XCTAssertNil(VoiceTuneCharacter.matching(strength: .infinity, retuneSpeed: 1))
    }

    // MARK: - 5: the door stores no selection

    /// The whole point of the slice. `@State` of this type anywhere in the sheet means a
    /// selection that can disagree with the numbers it claims to describe.
    func testTheDoorHoldsNoStoredCharacterSelection() throws {
        let view = try source("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        XCTAssertTrue(view.contains("selection: voiceTuneCharacterBinding"), """
            The character picker is gone or renamed. Re-anchor this scan rather than \
            letting it pass vacuously (#454) — the negative below proves nothing without it.
            """)
        // ⛔ NAME-INDEPENDENT ON PURPOSE (#646/#673). The first version forbade two exact
        // spellings, `@State private var voiceTuneCharacter` and the one without
        // `private` — the IDENTIFIER, not the defect. A later cycle adding
        // `@State private var selectedCharacter: VoiceTuneCharacter?` for the picker while
        // leaving `matching(` in place for the caption would pass every assertion here with
        // the stored-selection defect fully present. The prose above the picker does say
        // "@State", but `source(_:)` returns `SourceText.codeOnly`, so a comment cannot
        // trip this.
        XCTAssertNil(view.range(of: #"@State[^\n]*VoiceTuneCharacter"#, options: .regularExpression), """
            A STORED character selection is back, under whatever name. It goes stale the \
            first time a finger moves Amount or Tune, and then the picker claims a setting \
            that is not active. Derive it from the live values \
            (`VoiceTuneCharacter.matching`) instead.
            """)
        XCTAssertTrue(view.contains("VoiceTuneCharacter.matching("), """
            The derived read is gone. Whatever feeds the picker now, it is no longer the \
            live values, which is the one thing this file exists to keep true.
            """)
    }

    // MARK: - 6: picking a character writes BOTH numbers

    /// Half an application is worse than none: writing only `strength` would leave the
    /// glide of whatever was selected before, so "Hard" would not snap.
    func testPickingACharacterWritesBothFields() throws {
        let view = try source("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        XCTAssertTrue(view.contains("audioEngine.voiceTuneStrength = Float("),
                      "The picker no longer writes the correction amount.")
        XCTAssertTrue(view.contains("audioEngine.voiceTuneRetune = Float("),
                      "The picker no longer writes the retune speed — `Hard` would not snap.")
        XCTAssertTrue(view.contains("guard let choice else { return }"), """
            The nil branch is gone. A nil selection is the Custom state being REPORTED, \
            never a value to apply — writing on nil would make the caption unreachable.
            """)
    }

    // MARK: - 7: the preset sits ON its parameters, and offers no inert segment

    /// ⚠️ THIS CLAIM FORBIDS A "SIMPLIFICATION", NOT WORK (#364). Two failure shapes, and
    /// both look like tidying: deleting the numeric fields because a picker now covers
    /// them (the fields are the fine control — the sound panel keeps both too), and adding
    /// a "Custom" segment for symmetry (selecting it could only be a no-op, which is the
    /// inert control this design avoids; Custom is REPORTED by the caption, never offered).
    func testTheNumericFieldsSurviveAndCustomIsNotASegment() throws {
        let view = try source("Sources/Echoelmusic/Studio/AudioInputPickerView.swift")
        XCTAssertTrue(view.contains("label: \"Amount\""), """
            The Amount field is gone. A character picker REPLACES neither field — it is a \
            preset over them, the `presetRow` shape the sound panel uses.
            """)
        XCTAssertTrue(view.contains("label: \"Tune\""),
                      "The Tune field is gone — see the message above.")
        // ⛔ FOUR SPELLINGS, NOT ONE. The first version forbade only
        // `VoiceTuneCharacter?.none` and missed `.tag(nil as …)`,
        // `.tag(Optional<VoiceTuneCharacter>.none)` — and this file's OTHER picker uses the
        // opposite house spelling (`.tag(Optional(option))`), so the author most likely to
        // add a nil tag is the one following the neighbour.
        XCTAssertNil(view.range(of: #"\.tag\((nil|Optional<VoiceTuneCharacter>\.none|VoiceTuneCharacter\?\.none)"#,
                                options: .regularExpression), """
            A `nil` tag is a "Custom" segment. Selecting it cannot change either number, \
            so it is an inert control; the caption under the picker reports Custom instead.
            """)
        XCTAssertTrue(view.contains("if voiceTuneCharacter == nil {"), """
            The Custom caption is gone. Without it a cleared picker is indistinguishable \
            from a broken one.
            """)
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DiagAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
