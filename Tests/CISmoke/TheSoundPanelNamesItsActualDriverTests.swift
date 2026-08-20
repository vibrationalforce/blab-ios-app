// TheSoundPanelNamesItsActualDriverTests.swift
// Echoel — #640: the Sound panel said "your body" while the demo generator was driving.
//
// WHAT THIS GUARDS. One panel carries two sentences about why its numbers move by themselves,
// and until this slice both named the wrong subject under the demo source:
//   · top:    "Your body also shapes this sound while a session runs: Brightness … move around
//             the values you set here."                      (`BioShapedParameter`)
//   · bottom: "No automation recorded — nothing is replaying a curve. Anything moving on its
//             own RIGHT NOW is your body, not automation."   (`AutomationStatus`)
// Both are present-tense claims about the current frame, not descriptions of the wiring, and
// the second says so in the sentence. With `BioSimulator` driving, "your body" is false on the
// screen it ships on.
//
// ⭐ BOTH, IN ONE SLICE, AND THAT IS THE POINT RATHER THAN AN ACCIDENT OF SCOPE. Fixing only
// one leaves the panel saying "the simulated demo source, not automation" three inches under
// "Your body also shapes this sound" — a claim and its own refutation on a single screen,
// which is #425 arriving at the player. That exact collision on THIS panel is what #562 had to
// repair, one sentence at a time, and `TheTwoSelfMovingSourcesAgreeTests` exists because of
// it. Splitting this slice would have rebuilt it for a cycle.
//
// ⛔ THE REGISTER SAID THIS COULD NOT BE DONE THIS WAY, and the correction matters more than
// the copy. `TheAlwaysOnRowsSayWhoseBody` listed these sentences as fixable only "by changing
// the noun rather than adding a condition; a condition here would put a live bio read into a
// property `EchoelStudioView.body` evaluates (the 10.76.41/50 freeze law)". The premise is
// true of an INLINE condition; the conclusion silently assumed no leaf may exist — while the
// panel next door already mounts `AlwaysOnBioPanelStrip`, and `BioStripView` does the same,
// both reading live bio in their own bodies for exactly this reason. (⛔ The first draft also
// named `AutomationStatusStrip` as prior art. It is not: before THIS commit it read no bio at
// all. It is a leaf, which is why the read could be added to it cheaply — but it did not set
// the precedent, and citing it made the argument look better-supported than it was.) So a cheap, lawful option was booked as unavailable, and what it left standing was
// the expensive one: weaken "your body" for every real player to be correct about the demo.
// **A constraint recorded without its escape hatch reads as an impossibility** — the same
// shape as #639's "DMX cannot carry metadata", one slice earlier, in the same family.
//
// ⚠️ THE REAL-BODY WORDING IS BYTE-IDENTICAL to what shipped before #640, and claim 5 pins
// that. The ordinary path must not pay for the demo path's honesty — and if it changes, two
// other guards (`TheBodyShapedRowsAreNamedOnceTests`, `TheTwoSelfMovingSourcesAgreeTests`)
// that read this sentence character for character have to move in the same commit.
//
// ⚠️ `nil` READS AS NOT SYNTHETIC, deliberately, and it is the one place this slice could have
// over-corrected. Both leaves ask `usableBio()`, not `latestBio`: a frame past its source's
// freshness window is not driving anything, so naming a demo source that stopped a minute ago
// would be a fresh false claim pointing the other way. With nothing arriving, the sentences
// read exactly as they always have — which is also correct, because then they are describing
// the wiring rather than the frame.
//
// KIND (§1): claims 1–5 are **END-TO-END BEHAVIOUR** — both sentence builders are `public
// static` over Foundation-only types, so this bundle drives the shipped producers and reads
// their real output. Claims 6–9 are **SOURCE-TEXT SCANS**: the render sites are `private`
// members of `View` structs this bundle cannot RENDER (no environment, no host), so where the
// read SITS can only be read as text. ⛔ That word was "instantiate" in the first draft and it
// is wrong — `BodyShapesThisSoundLine` is `internal` with an implicit `init()`, so `@testable`
// reaches it fine. The reason for a text scan survives the correction; the word did not. What stays a DEVICE PROBE: that a player running the demo actually sees the
// changed subject, and that the panel still reads well.
//
// GRADING (#433 / §3) — and the honest headline first: **this file does not compile against
// the parent (c98b28d).** Claims 1–5 call `soundPanelSentence(synthetic:)` and
// `emptySentence(synthetic:)`, signatures this same commit creates; claim 8 reads a file that
// does not exist there. So NO assertion has a compiled verdict on the parent, and saying that
// plainly is the rule (#488 shipped a red gate for a cycle behind exactly this ambiguity).
// What follows is hand-transcription (§0), driven in Python against `git show c98b28d:` and
// the worktree for everything that is text, and reasoned — labelled as such — for the rest.
//   · **TEXT, DRIVEN, RED ON THE PARENT (3 assertions, 2 findings):** claim 6's mount check
//     (the parent renders a plain `Text`, so `BodyShapesThisSoundLine()` is absent) and claim
//     7's two (the parent's strip has no `EngineBus`, no `bus.usableBio()`, and passes no
//     subject). Those are the regressions this slice can actually demonstrate.
//   · **TEXT, DRIVEN, GREEN ON BOTH (3 assertions) — COUNTERWEIGHTS:** claim 6's three
//     negatives. `soundPanel` reads no bio on either tree, and that is the point: the slice
//     added a live read to the panel's TOP LINE without moving one into the host body. An
//     assertion that only went red on the parent would prove the feature; these prove the law
//     survived it.
//   · **FORWARD (claim 8):** it drives a struct this commit creates and could never have been
//     red. Booking it as a regression is §3's flattering direction.
//   · **REASONED, NOT DRIVEN (claims 1–5):** 1, 2, 3 and 4 would be red on the parent for the
//     same single reason — there is no demo variant to inspect, which is ONE finding (#486),
//     not four. Claim 5 would be GREEN there: it asserts the real-body strings are the
//     parent's strings, and that is its whole job.
//   · **Stripper: PROPHYLAKTISCH — 0 of 8 text verdicts flip** (counted raw vs. stripped on
//     both trees, §2). ⛔ THE FIRST DRAFT OF THIS LINE CLAIMED "TRAGEND, 2 of 3" AND HAD NOT
//     MEASURED IT — the reasoning was that claims 6 and 7 anchor on tokens this slice also put
//     into the ⛔ prose at those exact sites. They do not: the comments say `usableBio()` and
//     `latestBio` bare, while the needles carry their receivers (`bus.usableBio()`). Plausible
//     and wrong, which is the third time this bundle has had to retract an unmeasured
//     load-bearing claim. `SourceText.codeOnly` stays because the anchors sit in files whose
//     prose quotes them constantly — it is insurance, and insurance is worth naming as such.
//     ⚠️ AND THE STAKES ROSE AFTER THE REVIEW: claims 7 and 8 now scan a WHITESPACE-SQUEEZED
//     copy, so a needle can match prose that was merely line-wrapped around it. Re-measured
//     with the squeeze in place — still 0 of 6 squeezed verdicts flip (the near miss is this
//     slice's own header sentence "asks `EngineBus.usableBio()`", which squeezes to
//     `…Bus.usableBio()` and misses the lower-case needle by one character). Prophylactic
//     today, and the kind of prophylactic that earns its place.
//
// ⚠️ #364: a DIFFERENT honest shape is not forbidden. A per-row "Demo" chip, a marked panel
// header, or a redesign that drops one of the two sentences would all satisfy the law and turn
// these claims red — that is the moment to rewrite this file. What is forbidden silently is a
// panel that tells a player their body is moving a number a simulator is moving.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheSoundPanelNamesItsActualDriverTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let strip  = "Sources/Echoelmusic/Studio/AutomationStatusStrip.swift"
    private static let leaf   = "Sources/Echoelmusic/Studio/BodyShapesThisSoundLine.swift"

    // MARK: - 1–2  the subject follows the driver

    /// 1 — REGRESSION. The panel's top line stops attributing a simulator to the player.
    func testTheBodyShapedLineNamesTheDemoSourceWhenItDrives() {
        let demo = BioShapedParameter.soundPanelSentence(synthetic: true)
        XCTAssertTrue(demo.contains("simulated demo"), """
            The Sound panel's body-shaped line reads "\(demo)" while the demo generator drives. \
            It has to name the demo source: every other surface that draws a bio number has \
            said so since #627…#637, and this line makes a stronger claim than any of them — \
            it tells the player their own body is moving these controls.
            """)
        XCTAssertFalse(demo.hasPrefix("Your body"), """
            The demo variant still opens with "Your body". Naming the demo source LATER in the \
            sentence is not enough: this is the first line of the panel and a player scans its \
            opening, exactly as the metric sheet's per-row marking had to move out of the \
            section header (#637).
            """)
    }

    /// 2 — REGRESSION. The automation strip's empty line says "right now", so it is the more
    /// explicit of the two claims and the one a player consults when a number moves.
    func testTheEmptyAutomationLineNamesTheDemoSourceWhenItDrives() {
        let demo = AutomationStatus.emptySentence(synthetic: true)
        XCTAssertTrue(demo.contains("simulated demo"), """
            The empty-automation line reads "\(demo)" while the demo generator drives. Its \
            whole purpose (#562) is to answer "why is this moving?" — answering it with the \
            wrong source is worse than the silence #562 replaced, because the player now has a \
            confident wrong answer instead of an open question.
            """)
        // ⛔ THIS ANCHORED ON `contains("automation")` AND WAS GREEN FOR THE WRONG REASON
        // (#367): the string OPENS with "No automation recorded", so the assertion passed on
        // the first clause while its message was about the second. Rewriting the demo variant
        // to end "…is the simulated demo source." — dropping the scoping clause entirely, the
        // exact regression this case exists to catch — would have left it green.
        XCTAssertTrue(demo.contains("not automation"), """
            The demo variant dropped its "not automation" clause. #562's claim 1 is that a \
            strip reporting on curves must scope its denial to curves; the demo variant is not \
            exempt from the rule the real-body variant is bound by.
            """)
    }

    // MARK: - 3–4  what the two variants must keep sharing

    /// 3 — COUNTERWEIGHT, and the one that stops the two variants drifting apart. The row names
    /// are the checkable half of the sentence: `TheBodyShapedRowsAreNamedOnceTests` proves each
    /// one exists on the panel, but it reads the real-body variant only. Two independently
    /// written strings would let the demo variant name a control that is not there — the #496
    /// defect, reached by the honesty fix meant to prevent it.
    func testBothVariantsNameExactlyTheSameRows() {
        let real = BioShapedParameter.soundPanelSentence(synthetic: false)
        let demo = BioShapedParameter.soundPanelSentence(synthetic: true)
        let rows = BioShapedParameter.shapedByTheBody.flatMap(\.soundPanelRows)
        XCTAssertFalse(rows.isEmpty, """
            No parameter is reported as body-shaped, so this comparison has no content left. \
            That is a real change — see `TheBodyShapedRowsAreNamedOnceTests` — and this file \
            should be revisited in the same commit rather than left passing on nothing (#454).
            """)
        for row in rows {
            XCTAssertTrue(real.contains(row) && demo.contains(row), """
                "\(row)" is named by only one of the two variants. The row list is shared on \
                purpose: the mechanism is identical under both sources — the demo feeds the \
                same four channels through the same `bioBase*` anchors — so only the SUBJECT \
                may differ. A variant that names a different set is naming controls nothing \
                verified.
                """)
        }
    }

    /// 4 — COUNTERWEIGHT. The sentence's only actionable half is the pointer at the Bio panel,
    /// where the four channels are actually shown. A demo variant that dropped it would be
    /// honest and useless — and dropping it is the easiest way to shorten a sentence that just
    /// grew a clause.
    func testTheDemoVariantStillPointsAtTheBioPanel() {
        XCTAssertTrue(BioShapedParameter.soundPanelSentence(synthetic: true).contains("Open Bio"), """
            The demo variant no longer points at the Bio panel. The line deliberately shows no \
            live values (#553/#416); without the pointer it states a fact the player has no way \
            to check, which is exactly the objection `TheBodyShapedRowsAreNamedOnceTests` \
            raises against the real-body variant.
            """)
    }

    // MARK: - 5  the ordinary path pays nothing

    /// 5 — COUNTERWEIGHT, and the load-bearing one. Without it, the cheapest way to satisfy
    /// claims 1–2 is to reword both sentences for EVERY player — which is what the register's
    /// "change the noun rather than adding a condition" advice would have produced, and it
    /// would have cost the instrument its identity line to be correct about a demo mode.
    func testTheRealBodyWordingIsUnchanged() {
        XCTAssertTrue(BioShapedParameter.soundPanelSentence(synthetic: false)
            .hasPrefix("Your body also shapes this sound while a session runs:"), """
            The real-body variant's opening changed. This slice's whole shape — an argument \
            rather than a rewording — exists so the ordinary path is byte-identical. If the \
            copy genuinely needed to change, two other guards read this sentence character for \
            character and move in the SAME commit (#456).
            """)
        XCTAssertEqual(AutomationStatus.emptySentence(synthetic: false),
                       "No automation recorded — nothing is replaying a curve. Anything moving "
                       + "on its own right now is your body, not automation.", """
            The real-body empty-automation line changed. Same reasoning as above, plus \
            `TheTwoSelfMovingSourcesAgreeTests` drives this exact string for the #425 collision \
            it guards.
            """)
    }

    // MARK: - 6–8  where the read sits (the freeze law)

    /// 6 — REGRESSION. `soundPanel` is reached through `dropdownContent`, which
    /// `EchoelStudioView.body` evaluates permanently while hosting every `.menu` Picker of the
    /// instrument. The subject-choosing read must NOT be there (10.76.41/50).
    func testTheSoundPanelItselfStillReadsNoBio() throws {
        let body = try soundPanelBody()
        for needle in ["usableBio", "latestBio", "isSynthetic"] {
            XCTAssertFalse(body.contains(needle), """
                `soundPanel`'s own body contains `\(needle)`. `AnyView(...)` is not an \
                observation boundary, so a bio read here registers the ROOT as an observer of \
                the bio publisher and tears down any open Picker on every publish. The subject \
                belongs in `BodyShapesThisSoundLine`'s body, which is why that struct exists.
                """)
        }
        XCTAssertTrue(body.contains("BodyShapesThisSoundLine()"), """
            `soundPanel` no longer mounts the body-shaped line at all. The negative assertions \
            above are then satisfied by a panel that says nothing (#454).
            """)
    }

    /// 7 — REGRESSION. The strip may read bio — it is its own `View` struct — but it must ask
    /// `usableBio()`, not `latestBio`: the sentence says "right now", and a stale frame drives
    /// nothing.
    func testTheAutomationStripAsksTheFreshnessGate() throws {
        let code = try codeText(Self.strip)
        XCTAssertTrue(squeezed(code).contains("bus.usableBio()"), """
            `AutomationStatusStrip` does not ask `usableBio()`. Its sentence claims what is \
            moving RIGHT NOW; `latestBio` can be minutes old, and naming a demo source that \
            stopped long ago is a fresh false claim in the other direction.
            """)
        // ⛔ WHITESPACE-INSENSITIVE, AND THE FIRST DRAFT WAS NOT — it went RED on correct code
        // the moment the reviewer's fix wrapped the call across two lines to keep the read
        // inside the `rows.isEmpty` branch. A needle that a reformat can break is a needle that
        // forbids legitimate work (#364), and this one would have failed for a reason its
        // message does not mention (#367). Collapsing whitespace makes the assertion about the
        // CALL rather than about its line breaks.
        XCTAssertTrue(squeezed(code).contains("AutomationStatus.emptySentence(synthetic:"), """
            The strip no longer passes a subject to `emptySentence`. The argument is required \
            precisely so a forgetful call site cannot compile (#431/#440/#443) — if this went \
            green while the argument was dropped, the argument grew a default.
            """)
    }

    /// 8 — FORWARD. The leaf this commit creates asks the same gate the same way, so the two
    /// sentences on one panel can never disagree about whether the source is synthetic.
    func testTheBodyLineLeafAsksTheSameGateTheSameWay() throws {
        let code = try codeText(Self.leaf)
        XCTAssertTrue(squeezed(code).contains("bus.usableBio()?.source.isSynthetic"), """
            `BodyShapesThisSoundLine` no longer resolves the subject through \
            `usableBio()?.source.isSynthetic`. Both sentences share one screen; two spellings \
            of "is this synthetic" is #416, and here it would show up as one line marked and \
            the other not, in the same glance.
            """)
        // ⚠️ WHAT THIS PINS IS THE SPELLING, NOT THE INSTANT, and the difference is real
        // enough to write down. The two sentences live in two independent leaves: this one
        // observes `latestBio` alone, the strip also observes `player.lanes`/`enabled`. So the
        // strip can re-render while this leaf does not — and if a stopped demo has aged past
        // its window when someone touches the automation player, the strip flips to "your
        // body" while the line above still reads "the simulated demo source". One glance, two
        // evaluation instants. It needs a stopped demo AND an automation edit, and there is no
        // automation writer today (#473/#204), so it is registered rather than fixed; a shared
        // `TimelineView` or one hoisted leaf is the fix if a writer ever lands.
        XCTAssertTrue(code.contains("@Environment(EngineBus.self)"), """
            The leaf no longer takes the bus from the environment — so either it stopped \
            reading bio (and the subject is a constant again) or it acquired the value from a \
            parent body, which puts the observation back where the freeze law forbids it.
            """)
    }

    // MARK: - source access

    private struct SoundPanelAnchorMissing: Error { let reason: String }

    /// Every whitespace character removed, so a scan asserts on a CALL and not on the line
    /// breaks a formatter chose. `SourceText.codeOnly` preserves line count by design (several
    /// guards assert on `lines[i - 1]` relations), so it cannot do this itself — squeeze at the
    /// point of use, never in the shared stripper (#453).
    private func squeezed(_ code: String) -> String {
        code.filter { !$0.isWhitespace }
    }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SoundPanelAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// `soundPanel`'s body by brace matching from its declaration — never a fixed line window.
    /// This repo writes 30–40-line comment blocks and `SourceText.codeOnly` preserves line
    /// count, so any window is unsound by construction and rots as the prose grows (#408).
    private func soundPanelBody() throws -> String {
        let code = try codeText(Self.studio)
        guard let start = code.range(of: "private var soundPanel: some View {") else {
            throw SoundPanelAnchorMissing(reason: """
                `private var soundPanel: some View {` is gone from \(Self.studio). The panel was \
                renamed or restructured; re-anchor rather than letting the scan skip (#454).
                """)
        }
        var depth = 0
        var out = ""
        for ch in code[start.lowerBound...] {
            out.append(ch)
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth == 0 { break } }
        }
        guard depth == 0, out.count > 200 else {
            throw SoundPanelAnchorMissing(reason: """
                Brace matching over `soundPanel` returned \(out.count) characters — the \
                extraction failed, and every negative assertion above would pass over nothing \
                (#454).
                """)
        }
        return out
    }
}
