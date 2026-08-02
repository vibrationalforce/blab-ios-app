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
// (b) ⭐ THAT PREDICTION CAME TRUE AND WAS ACTED ON — kept, not deleted, because it is the
//     only record that the deletion was planned rather than convenient. It read: "These do
//     NOT all survive #359 step 3. That step deletes `sessionPanel` and the `.session` chip.
//     `testThePlacePanelNoLongerCarriesWeather` will then FAIL (its window opening is gone)
//     — it used to SKIP silently, which the step-2 Nachlese fixed in
//     `window(_:opening:closing:)` … while `testThePlaceChipSaysPlace` and
//     `testTheVoiceOverNameFollowsTheChip` will hard-FAIL (their windows survive, the case
//     does not). Whoever ships step 3 must delete those three deliberately, in the same
//     commit, and say so; two of them going quiet is not the same as them passing."
//     Step 3 deleted all three in its own commit and said so, and put three NEW tests on the
//     surface the control moved to (see the "Place half" MARK below). The Nachlese's
//     `XCTFail`-instead-of-`XCTSkip` change is what made this a forced decision rather than
//     a silent one — which is the whole reason it was made.
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
    ///
    /// ⚠️ FOUR WINDOWS USE THIS NOW, NOT SEVEN. The three `moodPanel` windows moved to
    /// `memberClosing` in the #292-Slice-3 Nachlese — see that constant's own note for why.
    /// The four that remain are short and comment-light, which is the only condition under
    /// which ending on `"// MARK:"` is a convenience rather than a trap.
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
                                   closing: Self.memberClosing))
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
                                   closing: Self.memberClosing))
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
                                   closing: Self.memberClosing))
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
    //
    // ⭐ THREE TESTS STOOD HERE AND STEP 3 DELETED THEM, WHICH IS THE OUTCOME THIS FILE'S
    // HEADER ORDERED — `testThePlacePanelNoLongerCarriesWeather`, `testThePlaceChipSaysPlace`
    // and `testTheVoiceOverNameFollowsTheChip`. All three pinned a surface that no longer
    // exists: `sessionPanel` is deleted and `StudioMenu.session` with it. Note (b) in the
    // header predicted exactly this and demanded the deletion be deliberate and stated,
    // because the step-2 Nachlese had already turned the "window not found" path from
    // `XCTSkip` into `XCTFail` — so leaving them would have reddened the only blocking
    // bundle, and the reader would have been sent to a declaration that is innocent.
    //
    // What replaces them is NOT another test here. The claim "the place control still has a
    // door" now belongs to the panel that holds it: `SaveDoorNamingTests` already guards
    // `.export`'s presence in `studioChips`, its chip label and its `fullName`. A second
    // file asserting the same door would be the two-surfaces defect in guard form.

    /// ⛔ SIX WINDOWS NOW USE THIS INSTEAD OF `Self.declarationClosing`, and the exception is
    /// the point. That list ends a window on `"// MARK:"` as well, matched on RAW lines. It is
    /// right for the four short windows above; it is a trap in a long, heavily-commented
    /// declaration.
    ///
    /// ⛔ THE THREE `moodPanel` WINDOWS JOINED THIS LIST IN THE #292-SLICE-3 NACHLESE, and the
    /// reason is that Slice 3 itself created the hazard: it added 23 comment lines inside
    /// `moodPanel`, including a paragraph that argues about the `soundPanel` Tone grid. One
    /// future sentence containing the literal `// MARK:` — say, a pointer to the
    /// `// MARK: Mood presets` heading that already sits ~90 lines below — would truncate the
    /// window, and `testTheCaptionStaysTheLastChildOfTheMoodPanel` would then report
    /// "moodPanel lost either `weatherRow` or its explanatory caption" about a panel where
    /// both are present. Same trap, third declaration; the fix was already sitting here.
    ///
    /// The original occasion (kept, because it is the worked example): `utilityRow` is ten
    /// children over ~170 lines with four multi-paragraph ⛔ blocks in it — a strong candidate
    /// to acquire an internal `// MARK: - Naming` sub-heading. That
    /// edit would truncate the window and, depending on where it landed, either drop
    /// `placeRow` (accusing someone of deleting a row that is still there) or drop the Save
    /// button (`XCTFail("utilityRow lost either …")`). Both messages send their reader to an
    /// innocent line — the exact failure this file's own header documents at the `weatherRow`
    /// window, ONE COMMIT before this one. Terminating only on the next member declaration
    /// costs a few trailing comment lines in the window.
    ///
    /// ⚠️ AND IT IS NOT PROSE-PROOF — the first version of this paragraph said "cannot be
    /// tripped by prose", which is one claim too strong. `window(_:opening:closing:)` matches
    /// `.contains` on RAW lines, so a comment reading "…the `private var placeRow` below…"
    /// truncates a window just as surely as a `// MARK:` did. The difference is probability,
    /// not impossibility: a sub-heading is a thing people ADD to a long declaration, while
    /// spelling out `private var ` inside prose is rare (this file names members as
    /// `` `placeRow` ``, never with the keyword). Say the smaller true thing.
    private static let memberClosing = ["private var ", "private func "]

    /// The one claim from that group worth keeping, re-aimed at where the control went.
    /// Without it, `placeRow` could be dropped from `utilityRow` and every surviving test
    /// here stays green — the Mood/Field halves say nothing about Place.
    func testTheSaveExportPanelCarriesThePlaceRow() throws {
        let source = try lines(Self.studio)
        let utility = code(try window(source,
                                      opening: "private var utilityRow: some View {",
                                      closing: Self.memberClosing))
        let hits = utility.filter { $0.contains("placeRow") }
        XCTAssertEqual(hits.count, 1, """
            #359 step 3 / #284: `utilityRow` must build `placeRow` exactly once. Found \
            \(hits.count). The Place panel and its chip were deleted in that step, so this \
            is now the ONLY door to the toggle that puts your city into the session and \
            export file names. Zero here does not hide a row — it makes the control \
            unreachable, which is the #272 defect the same panel already paid for once.
            """)
        guard let at = utility.firstIndex(where: { $0.contains("placeRow") }) else { return }
        let guardLine = at > 0 ? utility[at - 1] : ""
        XCTAssertTrue(guardLine.contains("#if canImport(CoreLocation)"), """
            #359 step 3: the line above `placeRow` must be its `#if canImport(CoreLocation)` \
            guard, because `placeRow` itself is declared inside that same guard. Found: \
            '\(guardLine)'. Without it "Save & Export" stops compiling wherever CoreLocation \
            is absent — and unlike the weather rows, this panel has no other reason to be \
            platform-conditional, so nothing else would catch it.
            """)
    }

    /// The place toggle shapes the name the Save button writes, so it must sit ABOVE that
    /// button. Ordering is the entire argument for choosing this panel over any other, and
    /// a source-text guard can check it where it cannot check that the panel looks right.
    func testThePlaceRowSitsAboveSave() throws {
        let source = try lines(Self.studio)
        let utility = code(try window(source,
                                      opening: "private var utilityRow: some View {",
                                      closing: Self.memberClosing))
        let placeAt = utility.firstIndex { $0.contains("placeRow") }
        let saveAt = utility.firstIndex { $0.contains("saveName = session.sessionName(") }
        guard let placeAt, let saveAt else {
            return XCTFail("""
                `utilityRow` lost either `placeRow` or the Save button's \
                `saveName = session.sessionName(` action — see the sibling test.
                """)
        }
        XCTAssertLessThan(placeAt, saveAt, """
            #359 step 3: `placeRow` moved BELOW the Save button. It is the control that puts \
            the city into `session.sessionName(bpm:)`, which is literally what that button \
            reads — a user scanning down stops at the first button that does what they came \
            for, so a naming control underneath it is never seen before the file is written.
            """)
    }

    /// And the door has to say so. The subtitle is the only text visible before the panel is
    /// opened; a control that moved into a panel whose description does not mention it is
    /// the exact defect #359 exists to undo (filed task #59: "es fehlt die Auffindbarkeit").
    ///
    /// ⛔ ANCHORED TO THE `panel(…)` CALL, not to the window. The first version joined every
    /// code line in `utilityRow` and asked whether the phrase appeared ANYWHERE — which an
    /// `accessibilityHint` on `placeRow`'s new position would satisfy just as well, keeping
    /// this green after the subtitle had been shortened back to its pre-#359 form. The claim
    /// is about the SUBTITLE; the assertion has to be about the subtitle.
    /// `SaveDoorNamingTests.testThePanelTitleAgreesWithTheDoor` anchors the same way, and its
    /// doc explains why the trailing `}   // panel("Save & Export")` marker cannot match: the
    /// call carries a comma after the title, the marker does not.
    func testTheSaveExportSubtitleNamesTheCity() throws {
        let source = try lines(Self.studio)
        let utility = code(try window(source,
                                      opening: "private var utilityRow: some View {",
                                      closing: Self.memberClosing))
        guard let at = utility.firstIndex(where: { $0.contains("panel(\"Save & Export\",") }) else {
            return XCTFail("""
                `utilityRow` no longer opens with `panel("Save & Export", …)`. If the panel was \
                retitled, move this guard and `SaveDoorNamingTests` in the SAME commit — a door \
                and its panel disagreeing about their own name is #272 verbatim.
                """)
        }
        // The subtitle is the SECOND argument and sits on its own continuation line.
        let call = utility[at...].prefix(3).joined(separator: " ")
        XCTAssertTrue(call.contains("city in the name"), """
            #359 step 3: the "Save & Export" subtitle no longer names the city. Found: \
            '\(call.trimmingCharacters(in: .whitespaces))'. The place toggle now lives inside \
            this panel and nothing else advertises it — the chip that used to say "Place" is \
            deleted. #272 is the precedent: the founder reported controls "missing" that were \
            in this very panel, behind a title and subtitle that did not name them.
            """)
    }
}
