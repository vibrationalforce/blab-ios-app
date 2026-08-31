// TheMetronomeAccentHasADoorTests.swift
// Echoel — the one metronome option whose three siblings all had a row. #924.
//
// WHAT WAS WRONG. `MetronomeVoice` exposes FIVE settable observed properties, and four of them
// have a writer: `enabled`, `beatsPerBar` and `level` from `metronomeRow` (the Tempo panel), and
// `bpm` from the transport relay in `EchoelmusicApp`. The fifth, `accentDownbeat`, had **no
// writer anywhere under `Sources/`** — found by `scripts/doorless-state.py`, which flags settable
// class state with no door. ⛔ The first draft of this line said "four settable options"; `bpm`
// is the one it forgot, and it is the one that matters most for the freeze law below.
//
// ⭐ WHY THIS ONE IS DIFFERENT FROM THE OTHER ENTRIES ON THAT LIST. The tool's own rule sorts
// them: *a tuning constant with no writer is fine, a knob whose doc names a user who cannot turn
// it is the defect.* `accentDownbeat` is neither exactly — its doc names no user — but it is a
// third thing the rule implies: **an option sitting beside siblings that all have rows, in a
// panel the player can open.** Absence there reads as a decision nobody made.
//
// ⛔ THE SURVEY THAT STOOD HERE WAS ASSERTED, NOT RUN, and the mandatory review measured it
// false. It said the non-guarded remainder were "DSP tuning constants … in files like
// `EchoelCellular` and `EchoelModalBank`, which are TEST-ONLY", and named `inharmonicity` and
// `onsetNoiseDecay` as examples — both of which live in `EchoelDDSP`, the LIVE synth. Measured
// 2026-08-31 on the tool's own output (32 entries after this slice doored one; the tool
// reports 31 since #925 removed `CameraAnalyzer.dominantHue` — the breakdown below is the
// measurement of that day and is left as it was taken, with the delta named):
//   · **11 are not in `DSP/` at all** — `MemoryPressureHandler` · `ResourceGovernor` ×2 ·
//     `CrashSafeStatePersistence` ×2 · `TimelineStore` · `ADMOSCSender` · `Transport` ·
//     `PolarH10BioPublisher` · `CameraAnalyzer` · `BioReactiveSynthVoice`.
//   · **9 are in `EchoelDDSP`**, which 30 other files under `Sources/` consume.
//   · Only **9** are in the two test-only files (`EchoelCellular` 7, `EchoelModalBank` 2), and
//     even there the label means "no INSTANTIATION site", not "unmentioned" — CLAUDE.md makes
//     that exact distinction after a `grep` recipe aged badly.
// So the list still holds real production knobs and is NOT triaged. Writing an untested survey
// into a guard header is the failure this bundle exists to prevent: **the check is the
// measurement, the survey is a memory of one.** Kept as a ⛔ rather than deleted because the same
// false sentence went out in the commit message and in `decisions.csv`, and this is the copy a
// later session will actually read.
//
// ⭐ AND IT IS THE ONE THAT MAKES A SIBLING AUDIBLE. `beatsPerBar` only means something because
// beat 0 sounds different; the render block's test is
// `let isDownbeat = (beatIndex == 0) && audioAccent`. With the accent off, the bar-length row
// becomes an invisible setting — so the two rows belong together, and shipping the number
// without the switch was the asymmetry. (That row was labelled "Beats per bar" until #930
// measured it CLICK-local — `Transport.beatsPerBar` is a hard `static let 4` — and renamed it
// to "Accent every", which is what the render test above actually decides.)
//
// ⚠️ NOT A NEW FEATURE. Every layer already existed and was already reachable-by-default: the
// property, its `didSet` mirror to the `nonisolated(unsafe)` audio value, and the render-block
// read. This slice adds a door to built behaviour, which is why it is a Ralph-sized change and
// not a product question.
//
// ⚠️ A `Bool` IS A `Toggle`, NOT AN `EchoelValueField`, and that is the UI law read correctly.
// CLAUDE.md's parameter rule says every adjustable NUMERIC parameter uses `EchoelValueField`,
// and warns in the same breath: read the word "numeric" — a parameter whose values have names
// is a Picker, and by the same logic an on/off is a Toggle. The sibling `enabled` row is a
// `Toggle`; this matches it rather than inventing a 0/1 number field.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree, so every
// claim has a verdict there.
//
// ⭐ A SIXTH CLAIM ARRIVED WITH #927 and it is graded against ITS OWN parent, not #924's:
// `testExactlyOneMetronomeVoiceIsEverBuilt` is a COUNTERWEIGHT, green on both trees. Booking it
// as a finding would be the flattering direction (#433). It pins the premise the Mix board's
// Click strip asserts in a comment and nothing checked — that exactly one `MetronomeVoice` is
// ever built, so that strip is a second DOOR and not a second CLICK.
//
// Against the #924 parent: **Two are red** — the row and its placement, which is the finding.
// **Three are counterweights** (#343), green on both: they catch a tree that
// adds the row but breaks the chain that makes it audible, or that converts the Bool into a
// number field, or that moves the row outside the `enabled` block where it would be the
// "adjustable but inaudible" control this repo keeps removing (#135/#164/#227).
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether a player wants the accent off. The switch is offered,
// the default is unchanged (on), and nothing about the shipped sound moves until someone taps.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMetronomeAccentHasADoorTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let voice = "Sources/Echoelmusic/Audio/MetronomeVoice.swift"

    // MARK: - the door

    func testTheAccentRowExistsAndBindsTheVoice() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        XCTAssertTrue(code.contains("Toggle(isOn: $metronome.accentDownbeat"), """
            No control writes `accentDownbeat`. It is the only one of MetronomeVoice's five \
            settable observed properties without a writer: `enabled`, `beatsPerBar` and `level` \
            all have a row in this same panel, and `bpm` is written by the transport relay — and \
            it is the option that makes `beatsPerBar` audible at all.
            """)
    }

    func testTheAccentRowSitsInsideTheEnabledBlock() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        guard let rowStart = code.range(of: "if metronome.enabled {") else {
            return XCTFail("`metronomeRow` no longer gates its detail rows on `metronome.enabled`.")
        }
        let after = code[rowStart.upperBound...]
        // The accent row must appear in the gated block, before that block's closing depth.
        var depth = 1
        var index = after.startIndex
        var body = ""
        while index < after.endIndex, depth > 0 {
            let ch = after[index]
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth == 0 { break } }
            body.append(ch)
            index = after.index(after: index)
        }
        // ⚠️ REFUSE TO ANSWER RATHER THAN ANSWER FROM THE REST OF THE FILE. If the braces never
        // balance the loop reaches `endIndex` with `depth > 0`, and `body` is then everything
        // after the `if` — a match found anywhere later in this 10k-line file would read as a
        // green this walk did not earn (#454). Also honest about the walker's one blind spot:
        // `SourceText.codeOnly` strips comments but deliberately leaves STRING LITERALS, so a
        // future row whose label contains a brace would miscount. No such label exists today.
        guard depth == 0 else {
            throw XCTSkip("unbalanced braces after `if metronome.enabled` — refusing to guess the block")
        }
        XCTAssertTrue(body.contains("$metronome.accentDownbeat"), """
            The accent control is ABSENT FROM, or sits outside, the `if metronome.enabled` \
            block. (On the parent tree it is absent — that is this claim's #367 reason there, and \
            the first draft of this message named only the misplacement.) Outside the block it \
            would be offered while the click is silent: the "adjustable but inaudible" control \
            this repo keeps removing (#135/#164/#227), which is why the sibling rows are inside.
            """)
    }

    // MARK: - counterweights: the row must move sound, and stay a switch

    func testTheAccentStillMirrorsToTheAudioValue() throws {
        let code = SourceText.codeOnly(try rawText(Self.voice))
        XCTAssertTrue(code.contains("didSet { audioAccent = accentDownbeat }"), """
            `accentDownbeat` no longer mirrors into `audioAccent`. The property is `@MainActor` \
            observable state and the render block cannot read it directly, so without this \
            `didSet` the new control is decorative — a switch that changes a number nobody hears.
            """)
    }

    func testTheRenderBlockStillReadsTheAudioValue() throws {
        let code = SourceText.codeOnly(try rawText(Self.voice))
        XCTAssertTrue(code.contains("(beatIndex == 0) && audioAccent"), """
            The click no longer decides its downbeat from `audioAccent`. That single expression \
            is what connects the new switch to sound AND what makes `beatsPerBar` meaningful; \
            without it both rows are settings with no consequence.
            """)
    }

    /// ⛔ THIS CLAIM'S NEEDLE WAS WRONG TWICE, IN OPPOSITE DIRECTIONS, AND BOTH WERE MINE.
    ///
    /// FIRST it was `EchoelValueField(label: "Accent"` — RED ON A CORRECT TREE, because
    /// `EchoelStudioView` already has TWO of those (field-arp accent, pad accent), both genuinely
    /// numeric and both unrelated to the click. **A needle taken from a LABEL collides with every
    /// other row using that word.** Caught by driving the claim before the fix.
    ///
    /// THEN it became `value: $metronome.accentDownbeat` — UNFALSIFIABLE, which the mandatory
    /// review caught and driving could not. `EchoelValueField` is generic over
    /// `V: BinaryFloatingPoint`, so a `Bool` binding cannot be passed to it at all: that needle
    /// only matches a tree the COMPILER already rejects. Worse, the violation the message
    /// describes — a 0/1 bridge — would be written `Binding(get: { … ? 1.0 : 0.0 }, set: …)` and
    /// match nothing here. A green earned by a needle that cannot fail is the shape #679/#738
    /// are both about.
    ///
    /// ⚠️ WHAT IT PINS NOW, STATED WITH ITS LIMIT: the label THIS row would carry if someone
    /// rebuilt it as a number field. That is reachable by compiling code and specific enough not
    /// to collide (the two existing rows are labelled "Accent", not "Accent downbeat"). It does
    /// NOT catch a bridge under a different label — no negative needle would. The real pin is the
    /// POSITIVE one in `testTheAccentRowExistsAndBindsTheVoice`, which requires the `Toggle`
    /// form; this claim is the cheap second opinion, not the guarantee.
    func testTheSwitchIsAToggleAndNotANumberField() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        XCTAssertFalse(code.contains("EchoelValueField(label: \"Accent downbeat\""), """
            The accent was rebuilt as a value field rather than a switch. CLAUDE.md's parameter \
            rule covers adjustable NUMERIC parameters and says in the same breath to read that \
            word: a named choice is a Picker, and an on/off is a Toggle — its sibling `enabled` \
            row is one. A 0/1 number field here would obey the rule's letter against its purpose.
            """)
    }

    // MARK: - the premise the second door rests on

    /// ⭐ THE MIX BOARD IS A SECOND DOOR, NOT A SECOND CLICK — and until #927 nothing checked
    /// it. `mixStripCard("Click")` carries its own on/off and level rows and asserts in a
    /// comment that they "read and write the one `MetronomeVoice` instance". That is true only
    /// while exactly one is ever built. A second construction site would give the board its own
    /// voice: two clicks, started at different moments, drifting apart — and **nothing on
    /// screen would say so**, because both doors would keep looking right while editing
    /// different objects. That is the worst shape a UI defect can take here.
    ///
    /// ⚠️ PINNED AS ONE, DELIBERATELY, AND THAT IS NOT A ROTTING COUNT (#903). The number is a
    /// LAW, not a date: a second metronome is a product decision, never an incidental edit, so
    /// the day this goes red is the day someone should have to say out loud that they meant it.
    /// The message says what to do if they did.
    ///
    /// ⚠️ `SourceText.codeOnly` HERE IS **PROPHYLAKTISCH (0 of 370 files flip)** — §2 requires
    /// this label and #927 shipped without it, one commit after #926b was told the same thing.
    /// Measured: raw and stripped both find exactly one site; no string literal in `Sources/`
    /// contains the type name. The stripper stays because it costs nothing and is the one
    /// stripper (#453), not because it is doing work here.
    ///
    /// ⚠️ WHAT THE NEEDLE DOES NOT SEE, stated because a coverage limit no one wrote is how a
    /// guard reads as protection it does not give (#927b, all three found by the reviewer):
    ///   · `let x: MetronomeVoice = .init()` scores ZERO. That idiom is LIVE in this repo twice
    ///     (`MultiTrackRecorder.swift:42`, `LaneLaunchLatch.swift:247`), so it is the realistic
    ///     way a second instance would actually be written. Not covered.
    ///   · A suffix collision (`SilentMetronomeVoice(`) would count as a site and red this
    ///     claim on a tree that is fine.
    ///   · A construction in `EchoelmusicWatch` or `EchoelmusicWidgets` — separate targets,
    ///     separate PROCESSES — would red it with a message about "two clicks drifting apart"
    ///     that does not describe that case at all. Only `Sources/` is scanned; that is right
    ///     for the hazard and wrong for the wording, so the wording says `Sources/`.
    ///
    /// ⚠️ AND `count-pins.py` CANNOT SEE THIS PIN. It reads two syntactic shapes and
    /// `XCTAssertEqual(sites.count, 1, …)` is neither, so "count-pins 0 RED" in any status
    /// delta is true and says nothing about this claim. Drive it by hand or by mutation.
    func testExactlyOneMetronomeVoiceIsEverBuilt() throws {
        var sites: [String] = []
        for file in try sourcePathsRelativeToRepo() {
            let code = SourceText.codeOnly(try rawText(file))
            let count = code.components(separatedBy: "MetronomeVoice(").count - 1
            for _ in 0..<count { sites.append(file) }
        }
        XCTAssertEqual(sites.count, 1, """
            `MetronomeVoice(` is constructed \(sites.count) time(s) under `Sources/`: \
            \(sites.joined(separator: ", ")). Exactly one instance is what makes the Mix \
            board's Click strip a second DOOR onto the Tempo panel's click rather than a \
            second click. Two instances would sound twice and drift apart, with both surfaces \
            still looking correct. If a second metronome is genuinely wanted, say so here and \
            in the two comments that assert the single-instance premise \
            (`metronomeRow` and the `mixStripCard(\"Click\")` strip in `EchoelStudioView`).
            """)
    }

    // MARK: - helpers

    // MARK: - The label is not a claim about the project (#930)

    func testTheClicksBarRowIsNamedForWhatItDoes() throws {
        let studio = SourceText.codeOnly(try rawText(Self.studio))
        // ⛔ PLAIN ESCAPED STRINGS, NOT `"""` LITERALS. The first draft of this claim wrote
        // both needles as multi-line literals — and `"""` followed by content on the SAME line
        // does not compile in Swift. Caught by reading before CI did; noted because the needle
        // itself carries quotes and reaching for `"""` is the natural reflex.
        XCTAssertTrue(studio.contains("EchoelValueField(label: \"Accent every\", value: Binding("), """
            The click's bar row is no longer labelled "Accent every".
            It was called "Beats per bar" until #930, and that was a claim about the PROJECT: \
            it is the phrase a musician reads as the time signature. Measured, the row is \
            CLICK-LOCAL — see the next claim — so the old label promised a setting the app \
            does not have. If you are renaming it again, rename it to something that describes \
            the render block (`isDownbeat = (beatIndex == 0) && audioAccent`), not the score, \
            and pull the SIX prose homes named in the #930 commit with it (#456).
            """)
        XCTAssertTrue(studio.contains("range: 1...12, unit: \"beats\", decimals: 0"), """
            The unit is what carries the honesty: "Accent every … 4" is ambiguous, \
            "Accent every … 4 beats" is not. `EchoelValueField`'s VoiceOver path reads \
            `"\\(n) \\(unit)"` for any unit it does not special-case, so this is also what a \
            non-sighted performer hears.
            """)
    }

    func testTheProjectsMeterIsAHardFourTheClickCannotReach() throws {
        // ⛔ THE LAW BEHIND THE RENAME, and it is stronger than the one sentence that started
        // it. The reviewer measured ONE constant (`Transport.beatsPerBar`); measured again for
        // #930 there are THREE independent hard fours — `Transport`, `AutomationPlayer` and
        // `TimelineTime` each declare their own. The click's 1…12 reaches none of them.
        // Each is a `static let`, so the compiler already forbids assignment; what this claim
        // adds is that they stay `let` and stay 4, and that the click has no bridge to them.
        let owners = [
            ("Sources/Echoelmusic/Core/Transport.swift", "public nonisolated static let beatsPerBar = 4"),
            ("Sources/Echoelmusic/Core/AutomationPlayer.swift", "public static let beatsPerBar = 4"),
            ("Sources/Echoelmusic/Sequencer/Timeline.swift", "public static let beatsPerBar = 4"),
        ]
        for (path, declaration) in owners {
            XCTAssertTrue(SourceText.codeOnly(try rawText(path)).contains(declaration), """
                `\(path)` no longer declares `\(declaration)`.
                ⚠️ THIS IS NOT A REQUEST TO PUT IT BACK (#364). A settable project meter is a \
                real feature and someone may be building it. But the moment the project's bar \
                becomes settable AND the click follows it, "Accent every" is the WRONG name — \
                "Beats per bar" becomes true — so rename the row back and pull the prose in the \
                SAME commit. Until then the two bars diverge silently and the label must say so.
                """)
        }
        let voice = SourceText.codeOnly(try rawText(Self.voice))
        for owner in ["Transport", "TimelineTime", "AutomationPlayer"] {
            XCTAssertFalse(voice.contains(owner), """
                `\(Self.voice)` now references `\(owner)`. The click has grown a bridge to the \
                project's clock structure. That may be the feature above — if so, see its \
                message. If it is not, it is a coupling the click does not need: the render \
                block only wraps `beatIndex` and owes nothing to the arrangement.
                """)
        }
    }

    /// Every Swift file under `Sources/`, repo-relative.
    ///
    /// ⛔ NAMED `sourcePathsRelativeToRepo`, NOT the name the first draft used (#927b), because
    /// `EveryIconOnlyControlSpeaksTests` already declares a helper of THAT name with DIFFERENT
    /// semantics: `[URL]` absolute, rooted at `Sources/Echoelmusic` rather than `Sources`,
    /// throwing `XCTSkip` rather than failing. One name, two meanings — the defect
    /// `03e335f`/#926 registered for `slice(…)` and wrote into `Tests/CISmoke/CLAUDE.md` §2
    /// **one commit earlier**, reintroduced by the session that wrote it. No CI catches it:
    /// `TheSliceHelperHasTwoSemanticsTests` scans `func slice` only. The rule that file states
    /// — *read the neighbour's BODY, not its name* — is the whole lesson, and the cheapest way
    /// to obey it is to give a different thing a different name.
    private func sourcePathsRelativeToRepo() throws -> [String] {
        let root = try repoRoot().appendingPathComponent("Sources")
        // ⛔ THE FLOOR USED TO SIT AFTER THIS GUARD AND THEREFORE COULD NOT DO ITS JOB (#927b).
        // On the enumerator-nil path the old code returned `[]` BEFORE the floor ran, so
        // claim 6 went red reading "constructed 0 time(s) under Sources/: ." — the wrong
        // reason, plus a dangling separator from joining an empty array. That is exactly the
        // #367 shape the floor was written to prevent. Throwing ends the test at the real
        // cause, the way both cited precedents do.
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("Sources/ could not be enumerated — this claim cannot be answered, "
                          + "and answering it from an empty list would blame the wrong thing.")
        }
        var files: [String] = []
        for case let name as String in walker where name.hasSuffix(".swift") {
            files.append("Sources/" + name)
        }
        // #367: an enumeration that finds too little would make claim 6 red for a reason its
        // message does not state. 200 follows the neighbour's floor rather than a rounder
        // number — the tree holds well over three hundred.
        XCTAssertGreaterThan(files.count, 200, """
            Only \(files.count) Swift file(s) found under Sources/ — the enumeration is \
            looking at the wrong tree, so any verdict below is about nothing.
            """)
        return files.sorted()
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
