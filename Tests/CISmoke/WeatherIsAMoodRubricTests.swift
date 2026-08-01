// WeatherIsAMoodRubricTests.swift
// Echoel — das Wetter steht bei den Reglern, die es verstellt.
//
// WHAT THIS GUARDS (#359, Founder 2026-08-01: "Weather könnte auch eine Rubrik mit slidern
// in mood, Sound und Field sein oder?"). Weather in Echoel is not a naming gimmick and the
// chip copy already said so before this change: the fetched condition blends into
// darkness / liveliness / tension in the composer, and into hue / saturation / glow / motion
// in the live visual. It nevertheless lived behind a chip labelled "Session", next to the
// one toggle that really is about naming. A control whose ONLY door is a word that does not
// describe it is unfindable — which is exactly what filed task #59 concluded about this
// feature: "es fehlt die Auffindbarkeit, nicht die Synthese".
//
// So `weatherRow` now sits inside `moodPanel`, among the mood knobs it modulates, and the
// panel it left is titled after the one thing left in it: `placeRow` → "Place". That second
// half also settles filed task #284 — a chip called "Session" that saves no session, sitting
// one chip away from a "Save & Export" panel that does.
//
// ⚠️ WHAT THIS FILE CANNOT SEE, said plainly because a guard that oversells itself is worse
// than none: this is a SOURCE-TEXT scan. It proves `weatherRow` is a child of `moodPanel`'s
// builder and is no longer a child of `sessionPanel`'s. It cannot prove the row RENDERS, that
// the panel opens, or that the founder can find it. That is a device check and it stays open.
//
// ⭐ STEP 2 (2026-08-01) SPLIT THE ROW BY DOMAIN. `WeatherMood.Param` has always declared a
// `Domain` — four influences touch the SOUND (structure · warmth · energy · drama, i.e.
// darkness/liveliness/tension) and four touch the PICTURE (hue · saturation · glow · movement,
// read by `FloatingVisualWindow`). The code knew which half was which long before the UI did:
// all eight sat in Mood, where the picture is not visible. So the image half moved to
// `visualPanel` (the Field chip) as `weatherImageRow`, and Mood keeps the toggle, the sound
// mixers and a ONE-TAP pointer to Field. That is the founder's "in mood, Sound und Field"
// read literally — the sound-domain params ARE the mood params.
//
// ⚠️ THREE LIMITS THAT ARE NOT OBVIOUS FROM THE TEST NAMES.
// (a) Both rows are behind an opt-in. `weatherEnabled` defaults to OFF and every mixer sits
//     behind `if weatherEnabled`, so a founder opening Mood sees ONE TOGGLE, not "eine Rubrik
//     mit slidern", until he flips it — and opening Field sees nothing at all. Step 1's whole
//     justification is findability, so this is the honest gap in it, and no source-text guard
//     can close it. It is a deliberate trade: a standing "turn weather on" line in Field would
//     be permanent chrome for every user, on the panel #365/#369 just trimmed.
// (b) These do NOT all survive #359 step 3. That step deletes `sessionPanel` and the
//     `.session` chip. `testThePlacePanelNoLongerCarriesWeather` will then FAIL (its window
//     opening is gone) — it used to SKIP silently, which the step-2 Nachlese fixed in
//     `window(_:opening:closing:)`; that is a deliberate improvement, because a quiet green
//     is exactly what this note was warning about — while `testThePlaceChipSaysPlace` and
//     `testTheVoiceOverNameFollowsTheChip` will hard-FAIL (their windows survive, the case
//     does not). Whoever ships step 3 must delete those three deliberately, in the same
//     commit, and say so; two of them going quiet is not the same as them passing.
// (c) Step 2 already had to do that once: `testTheWeatherRowStillCarriesItsTwoMixerGroups`
//     demanded both groups in one row, which is precisely what step 2 undid. It was rewritten
//     in the same commit, not deleted. A guard written for step N that would go red on the
//     planned step N+1 is not a bug in the guard — but shipping N+1 without touching it IS.
//
// ⚠️ WHY BOTH DIRECTIONS ARE ASSERTED. Asserting only "moodPanel contains weatherRow" would
// stay green if a future edit re-added the row to `sessionPanel` as well — two weather
// surfaces writing the same `@AppStorage` keys, which is the `visualVJOverlay` defect (open
// task #270) reproduced on a second feature. The pair "in Mood AND not in Place" is the
// claim; either half alone is not.
//
// No simulator; `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree
// is not at this file's compile-time path — a green it did not earn is the failure mode this
// whole bundle exists to avoid.

import Foundation
import XCTest
@testable import Echoelmusic

final class WeatherIsAMoodRubricTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// What ends a `window(...)` over a declaration in `EchoelStudioView.swift`.
    ///
    /// ⛔ `"private func "` WAS MISSING FROM THE `weatherRow` WINDOWS UNTIL THE #359-STEP-2
    /// NACHLESE, and the omission got dangerous in the very commit that introduced its
    /// danger. `weatherRow` ends well before the next `private var`, so the window ran 22
    /// lines past it — through `turnLocationOnForWeather()` and into `weatherImageRow`'s doc
    /// block. That was harmless while every assertion was POSITIVE ("this token appears").
    /// Step 2 made two of them NEGATIVE ("this token does NOT appear"), so an
    /// `AdaptiveCardGrid` placed in any `private func` down there would redden the only
    /// blocking bundle with a failure message naming `weatherRow` — sending its reader to a
    /// declaration that is innocent. Step 2's own NEW test already passed the three-element
    /// list, so the asymmetry sat inside a single changeset.
    ///
    /// Hoisted to one constant rather than repeated: the two call sites that needed it had
    /// drifted apart precisely because the list was written out by hand each time.
    private static let declarationClosing = ["private var ", "private func ", "// MARK:"]

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func lines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The declaration's own lines, from the line that opens it up to (not including) the
    /// line that opens the next one. Deliberately a WINDOW and not a whole-file grep: the
    /// claim here is about which builder a row belongs to, and a file-wide match would be
    /// satisfied by the row existing anywhere at all.
    private func window(_ source: [String],
                        opening: String,
                        closing: [String]) throws -> [String] {
        guard let start = source.firstIndex(where: { $0.contains(opening) }) else {
            // ⛔ THIS WAS `XCTSkip`, AND THAT MADE EVERY TEST HERE SELF-DISARMING. Delete
            // `weatherImageRow` outright and `testTheImageRowStillBuildsTheVisualMixers` went
            // silently GREEN. Same lesson the #367 Nachlese applied to its own helper hours
            // earlier, in this same bundle: a source-text guard may SKIP when the TREE is
            // absent — it has nothing to read — but never because the THING IT GUARDS moved.
            // Deliberate consequence for #359 step 3, and an improvement: the three tests this
            // file's header says will "go quiet" now FAIL instead, which is what the header
            // already demanded ("two of them going quiet is not the same as them passing").
            XCTFail("""
                declaration '\(opening)' not found — it was renamed, reformatted or deleted. \
                If that was deliberate, delete this test in the SAME commit and say so. Until \
                then the surface it pins has no guard at all.
                """)
            return []
        }
        var end = source.count
        var i = start + 1
        while i < source.count {
            if closing.contains(where: { source[i].contains($0) }) {
                end = i
                break
            }
            i += 1
        }
        return Array(source[start..<end])
    }

    /// Comment lines are stripped before matching. This file's own header talks about
    /// `weatherRow` and `sessionPanel`; so does the prose inside those declarations. A guard
    /// that matches its own explanation proves nothing — `ScrubNotifiesOnlyOnRealChangeTests`
    /// paid for that lesson by going red for a comment someone added to a pinned block.
    private func code(_ source: [String]) -> [String] {
        source.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && !t.isEmpty
        }
    }

    // MARK: - The Mood half

    func testTheMoodPanelCarriesTheWeatherRow() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: Self.declarationClosing))
        let hits = mood.filter { $0.contains("weatherRow") }
        XCTAssertEqual(hits.count, 1, """
            #359: moodPanel must build `weatherRow` exactly once. Found \(hits.count). \
            Weather blends into darkness/liveliness/tension — it belongs among the knobs it \
            modulates, not behind a chip about session names.
            """)
    }

    func testTheWeatherRowStaysBehindItsFrameworkGuard() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: Self.declarationClosing))
        guard let at = mood.firstIndex(where: { $0.contains("weatherRow") }) else {
            return XCTFail("no weatherRow in moodPanel — see the sibling test")
        }
        let guardLine = at > 0 ? mood[at - 1] : ""
        XCTAssertTrue(guardLine.contains("#if canImport(WeatherKit)")
                      && guardLine.contains("canImport(CoreLocation)"), """
            #359: the line above `weatherRow` must still be its \
            `#if canImport(WeatherKit) && canImport(CoreLocation)` guard, because \
            `weatherRow` itself is declared inside that same guard. Found: '\(guardLine)'. \
            Without it the Mood panel stops compiling wherever WeatherKit is absent.
            """)
    }

    /// ⛔ An earlier version of this asserted only `weatherAt < captionAt` — "weather comes
    /// BEFORE the caption" — while calling itself "stays the LAST child" and saying so in its
    /// message. A 14th row appended after the caption would have passed. #359 steps 2 and 3
    /// add rows to sibling panels, so a guard that misses exactly that is worse than none.
    func testTheCaptionStaysTheLastChildOfTheMoodPanel() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: Self.declarationClosing))
        let weatherAt = mood.firstIndex { $0.contains("weatherRow") }
        let captionAt = mood.firstIndex { $0.contains("Friendly ↔ scary (tension)") }
        guard let weatherAt, let captionAt else {
            return XCTFail("moodPanel lost either `weatherRow` or its explanatory caption")
        }
        XCTAssertLessThan(weatherAt, captionAt, """
            #359: the caption is the panel's closing sentence and the house rule keeps \
            headers and captions OUTSIDE the reflow grid, i.e. last. `weatherRow` was \
            inserted after it.
            """)
        // And it really is last: everything after the caption is one of its own modifiers or
        // a closing brace — no further child.
        let after = mood[(captionAt + 1)...].map { $0.trimmingCharacters(in: .whitespaces) }
        let strays = after.filter { !$0.hasPrefix(".") && !$0.hasPrefix("}") }
        XCTAssertTrue(strays.isEmpty, """
            #359: a child was added AFTER the panel's closing caption: \(strays). The caption \
            reads as the panel's last word; a row below it reads as an afterthought.
            """)
    }

    /// ⛔ WITHOUT THIS TEST THE WHOLE FILE COULD BE SATISFIED BY A NAME. Every other
    /// assertion here is about the token `weatherRow` appearing in `moodPanel`'s builder.
    /// Empty that row to `EmptyView()` — delete the mixers, the Apple-required attribution —
    /// and the bundle stays green while the founder's ask is gone. Nothing else in
    /// `Tests/CISmoke` asserts the mixers exist. Step 3 of #359 will be editing exactly this
    /// code, so the gutting is not hypothetical.
    ///
    /// ⚠️ THIS TEST CHANGED SHAPE IN STEP 2 AND THAT IS THE POINT. It used to demand BOTH
    /// mixer groups plus the `AdaptiveCardGrid` that held them side by side. Step 2 moved the
    /// Image group to `visualPanel`, so the old form would have gone red on the intended
    /// change. It is REWRITTEN rather than deleted: the anti-gutting claim survives, it just
    /// now names one group here and the other in the sibling test below.
    func testTheWeatherRowStillCarriesItsSoundMixerGroup() throws {
        let row = code(try window(try lines(Self.studio),
                                  opening: "private var weatherRow: some View {",
                                  closing: Self.declarationClosing))
        XCTAssertTrue(row.contains(where: { $0.contains("weatherMixGroup(\"Sound\"") }), """
            #359: `weatherRow` no longer builds `weatherMixGroup("Sound"…)`. The founder asked \
            for weather as a rubric WITH SLIDERS; a row that only carries its on/off toggle \
            satisfies every other test in this file and none of the request.
            """)
        XCTAssertFalse(row.contains(where: { $0.contains("weatherMixGroup(\"Image\"") }), """
            #359 step 2: the Image mixers are back in `weatherRow`. They belong in \
            `visualPanel` — they tint the picture, and Mood shows none of it. Two surfaces \
            writing the same @AppStorage weather keys is the `visualVJOverlay` defect (open \
            task #270) reproduced on a third feature.
            """)
        XCTAssertFalse(row.contains(where: { $0.contains("AdaptiveCardGrid") }), """
            #359 step 2: `weatherRow` has an `AdaptiveCardGrid` again. A grid arranges CARDS \
            and only the Sound card is left here — one card has nothing to arrange. If a \
            second card genuinely returns, restore the grid AND correct CLAUDE.md's #292 \
            reflow count and `AdaptiveCardGrid`'s own doc block, which both now say \
            `mixerPanel` is the single bare caller.
            """)
    }

    /// ⛔ THE MOVE ITSELF CREATES THE HAZARD THIS PINS. Anyone who used the Image mixers
    /// before step 2 opens Mood and finds four of the eight gone, with nothing saying where.
    /// This row's own history is the precedent: its location prerequisite used to be a
    /// sentence naming another toggle, and the fix was to make it a tap. A pointer that
    /// merely describes the destination is the defect, not the fix.
    func testTheMoodPanelCarriesAOneTapPointerToField() throws {
        let row = code(try window(try lines(Self.studio),
                                  opening: "private var weatherRow: some View {",
                                  closing: Self.declarationClosing))
        XCTAssertTrue(row.contains(where: { $0.contains("activeMenu = .field") }), """
            #359 step 2: nothing in `weatherRow` carries the reader to the Field panel. The \
            four image mixers moved there; without a one-tap pointer this is exactly the \
            dead end filed task #59 diagnosed about this same feature — "es fehlt die \
            Auffindbarkeit, nicht die Synthese".
            """)
    }

    // MARK: - The Field half (#359 step 2)

    func testTheFieldPanelCarriesTheWeatherImageRow() throws {
        let source = try lines(Self.studio)
        let field = code(try window(source,
                                    opening: "private var visualPanel: some View {",
                                    closing: Self.declarationClosing))
        let hits = field.filter { $0.contains("weatherImageRow") }
        XCTAssertEqual(hits.count, 1, """
            #359 step 2: `visualPanel` (the Field chip) must build `weatherImageRow` exactly \
            once. Found \(hits.count). Hue, Saturation, Glow and Movement are read by \
            `FloatingVisualWindow` — they change the PICTURE, and this is the panel that \
            governs it.
            """)
        guard let at = field.firstIndex(where: { $0.contains("weatherImageRow") }) else { return }
        let guardLine = at > 0 ? field[at - 1] : ""
        XCTAssertTrue(guardLine.contains("#if canImport(WeatherKit)")
                      && guardLine.contains("canImport(CoreLocation)"), """
            #359 step 2: the line above `weatherImageRow` must be its \
            `#if canImport(WeatherKit) && canImport(CoreLocation)` guard, because the row \
            itself is declared inside that same guard. Found: '\(guardLine)'. Without it the \
            Field panel stops compiling wherever WeatherKit is absent.
            """)
    }

    /// The same anti-gutting claim as the Sound side, on the half that moved. Without it
    /// `weatherImageRow` could be reduced to `EmptyView()` and every other test here stays
    /// green — the row's NAME is what the panel test matches on.
    func testTheImageRowStillBuildsTheVisualMixers() throws {
        let row = code(try window(try lines(Self.studio),
                                  opening: "private var weatherImageRow: some View {",
                                  closing: Self.declarationClosing))
        XCTAssertTrue(row.contains(where: { $0.contains("weatherMixGroup(") }), """
            #359 step 2: `weatherImageRow` no longer builds a `weatherMixGroup(…)`. An empty \
            row satisfies `testTheFieldPanelCarriesTheWeatherImageRow`, which matches the \
            NAME, and the founder's four sliders are gone.
            """)
        XCTAssertTrue(row.contains(where: { $0.contains("domain == .visual") }), """
            #359 step 2: `weatherImageRow` no longer filters on `domain == .visual`. That \
            filter is what keeps the split honest — `WeatherMood.Param.Domain` is the one \
            place that knows which influence touches sound and which touches picture, and \
            hand-listing the cases here would let the two halves drift apart silently.
            """)
        XCTAssertTrue(row.contains(where: { $0.contains("weatherEnabled") }), """
            #359 step 2: `weatherImageRow` renders unconditionally. Weather is opt-in and \
            default OFF; four sliders that do nothing until a toggle two panels away is \
            flipped are a lying control, and the Field panel is already under a chrome \
            budget (#365, #369).
            """)
    }

    // MARK: - The Place half (this is also filed task #284)

    func testThePlacePanelNoLongerCarriesWeather() throws {
        let source = try lines(Self.studio)
        let place = code(try window(source,
                                    opening: "private var sessionPanel: some View {",
                                    closing: Self.declarationClosing))
        let hits = place.filter { $0.contains("weatherRow") }
        XCTAssertTrue(hits.isEmpty, """
            #359: `weatherRow` is back in the Place panel as well. Two surfaces writing the \
            same @AppStorage weather keys is the `visualVJOverlay` defect (open task #270) \
            on a second feature — the row has ONE home, and it is moodPanel.
            """)
    }

    func testThePlaceChipSaysPlace() throws {
        let source = try lines(Self.studio)
        let labels = code(try window(source,
                                     opening: "var label: String {",
                                     closing: ["var fullName: String {"]))
        guard let line = labels.first(where: { $0.contains("case .session:") }) else {
            return XCTFail("the `.session` chip lost its label case")
        }
        XCTAssertTrue(line.contains("\"Place\""), """
            #284/#359: the chip must read "Place". Found: '\(line.trimmingCharacters(in: .whitespaces))'. \
            "Session" named nothing this panel does — it holds one toggle about the city in \
            the session NAME — and it collided with the "Save & Export" panel two chips over, \
            which is where a user reasonably looks to save a session.
            """)
    }

    func testTheVoiceOverNameFollowsTheChip() throws {
        let source = try lines(Self.studio)
        // ⛔ These terminators used to be ["private ", "func ", "static "] — three ordinary
        // words that appear in ordinary prose. They are matched on RAW lines, so ONE doc
        // comment mentioning a `func` anywhere inside this switch would truncate the window
        // before `case .session:` and turn the blocking gate red for a sentence. Same shape
        // as the trap `ScrubNotifiesOnlyOnRealChangeTests` already paid for. Narrowed to the
        // declaration form the other three windows in this file already use.
        let names = code(try window(source,
                                    opening: "var fullName: String {",
                                    closing: Self.declarationClosing))
        guard let line = names.first(where: { $0.contains("case .session:") }) else {
            return XCTFail("the `.session` chip lost its VoiceOver name")
        }
        XCTAssertFalse(line.lowercased().contains("weather"), """
            #359: the spoken name still promises weather behind a chip that no longer holds \
            it. Found: '\(line.trimmingCharacters(in: .whitespaces))'. A VoiceOver user \
            following that sentence lands on a panel with one location toggle in it.
            """)
        XCTAssertTrue(line.contains("Place"), """
            #359: the spoken name must start from the same word the chip shows, or the \
            sighted and the spoken app disagree about what the door is.
            """)
    }
}
