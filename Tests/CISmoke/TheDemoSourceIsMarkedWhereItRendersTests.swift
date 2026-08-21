// TheDemoSourceIsMarkedWhereItRendersTests.swift
// Echoel — #627: where synthetic vitals are DRAWN, the surface must say they are synthetic.
//
// WHAT THIS GUARDS. `BioSimulator` publishes `BioSampleFrame`s stamped `.fallback` — the
// "Simulation" entry in the Pulse source dropdown. Two reachable surfaces render them:
//
//   · the header pill (`PulseMonitorMiniLive` → `PulseMonitorMini`), which prints the bus
//     BPM and paints the LOCK accent on any fresh frame. For a strap that is exactly right;
//     for the demo it was the app showing a heart rate the wearer does not have, in the one
//     tile that is on screen at all times.
//   · the Bio strip (`BioStripView`), whose HR / HRV / breath / coherence cells read
//     `usableBio()` — which INCLUDES `.fallback` — while `hasLiveSignal` deliberately
//     EXCLUDES it. With Simulation selected and a session running, every number was
//     confident and the tag beside them said "Connecting…" for the rest of the session:
//     `measuring` is `running`, and no branch above it could ever catch a synthetic frame.
//
// ⛔ #626 IS WHY THIS BECAME URGENT RATHER THAN COSMETIC. Before it, one real frame parked
// the simulator forever, so after any camera use the demo went quiet and the numbers
// blanked — the surface was honest BY ACCIDENT. #626 fixed the parking (correctly) and the
// accident went with it: the synthetic stream is now continuous. A fix that removes the
// thing that was hiding a lie owes the lie's repair, and #626's own commit message
// registered exactly this as the next slice.
//
// SCOPE. ⛔ #627 SAID "TWO reachable surfaces … A THIRD is deliberately NOT marked" AND THE
// ENUMERATION WAS FALSE — the review measured at least two more, and one of them opens FROM
// the strip #627 had just fixed. A confident count is what stops the next session from
// looking, so the count is replaced by a measured list with a verdict per entry:
//   · header pill (`PulseMonitorMini`) — MARKED (#627, corrected #627b).
//   · Bio strip (`BioStripView`) — MARKED (#627, corrected #627b).
//   · `BioMetricsGuideView` ("How your body shapes the sound") — SECTION HEADER marked in
//     #627b, ROWS marked in #637. Its door is `BioStripView`'s `.sheet(isPresented:
//     $showGuide)` (the ⓘ), so the #627 hole was one affordance from the #627 fix; and under
//     Simulation its `liveBio == nil` hint disappears, i.e. the sheet did not merely omit a
//     marker, it asserted a measured body. ⛔ THIS ENTRY READ `BioMetricInfoView` AND NAMED
//     `.sheet(item: $explain)` AS ITS DOOR — the wrong one of the file's two sheets, and the
//     wrong one of the strip's two sheet modifiers. `BioMetricInfoView` is the per-cell tap
//     and renders STATIC text with no bio read at all; it can neither mark nor over-claim.
//     Two other guards inherited the same wrong name (`TheAlwaysOnRowsSayWhoseBodyTests`,
//     `TheGlanceSaysWhetherItIsABodyTests`) and are corrected in the same commit as #637.
//     ⚠️ "MARKED" means provenance. The COPY half was open one cycle and is **CLOSED by
//     #638**: the HRV row's "more variability opens the reverb" was the mapping CLAUDE.md
//     struck at #546 — and the register understated it, because the same table was also
//     selling a heart-rate filter sweep deleted at #331 and a breath filter modulation whose
//     channel has no producer. All three rewritten; `BioSoundMapping.swift` is now scanned by
//     `DisabledReverbIsNotClaimedLiveTests` and compared against the audited
//     `AlwaysOnBioChannel.shapedParameters` by `TheGuideTableMatchesTheAuditedWritesTests`.
//   · `OwnBioRow` in `LiveColaboView` ("You", bpm + coherence from `usableBio()`) —
//     **MARKED (#629)**, together with the peer rows and the wire payload, exactly as the
//     deferral said it should be: one decision, not two cycles. ⛔ This entry read "DEFERRED"
//     until #629b and was false the moment #629 landed — the same class as the CRITICAL that
//     created this list. A per-entry list only beats a count if the entries get ticked off in
//     the commit that closes them.
//   · `AlwaysOnBioRow` — **MARKED (#634)**, both mounts, and the open question this entry
//     recorded is answered rather than left standing. The deferral's argument was that in the
//     FX sheet the subject is the SOUND path, so a synthetic 0.42 is a true statement about
//     the engine's input — and that is still true; it just does not decide the question,
//     because the rows are named "Heart rate" and "HRV" and speak "at 62 percent" to
//     VoiceOver. The Bio-panel mount was never covered by it at all. Marking costs the sound
//     reading nothing (the number is unchanged) and removes the body claim, so the trade the
//     deferral was weighing turned out to be one-sided.
//     ⛔ This entry sat as "DEFERRED / open question for the founder" while its own list
//     already carried the lesson two bullets up — *a per-entry list only beats a count if the
//     entries get ticked off in the commit that closes them.* Third occurrence in this family
//     (#629b, #632b, here), and the first where the correcting text was already in the file.
//   · `BioModContributionRow` (FX sheet, "Live — body → sound") — **CLOSED (#635b)**, ticked
//     off here. It needs a user-added route to render at all, which is why it sat unmeasured
//     in this list; it now carries `BioModContribution.synthetic` (no default), a "Demo" chip
//     and the prefix spelling. Guard `Tests/CISmoke/TheFXRoutesSayWhoseBodyTests.swift`.
//   · `BreathVoiceRow` and `AutoModeRow` (both in `bioPanel`) — **MARKED (#648)**, the two
//     rows that carry a spoken hint AND a caption each, so four strings. Both already
//     branched — on whether breath was measured, on whether a source was running — which is
//     why they read as carefully written and why this class survived five slices: **a row
//     that conditions on ONE thing reads as conditioned on everything.** The copy now lives
//     in `BioPanelRowCopy` (`Studio/AlwaysOnBioChannel.swift`), Foundation-only and driven
//     end-to-end (§1) rather than scanned. Guard:
//     `Tests/CISmoke/TheBioPanelRowsSayWhoseBodyTests.swift`.
//
// ⛔ THIS LIST STOPPED BEING TICKED AT #635b AND EIGHT SLICES LANDED WITHOUT AN ENTRY — the
// exact defect its own bullets name three times ("a per-entry list only beats a count if the
// entries get ticked off in the commit that closes them"), and the third-worst kind, because
// here the correcting text was not merely in the file, it was in the same list. Each of the
// eight carries its own guard and none is unregistered in the repo; what was missing is the
// ONE place a session looks to ask "which surfaces are marked?". They are, in order:
// **#639** OSC egress (below) · **#640** the sound panel's sentence · **#641/#642** the FX
// headers (`TheFXHeadersSayWhoseBodyTests`) · **#643** the always-on sentences
// (`TheAlwaysOnRowsSayWhoseBodyTests`) · **#644** the narration heading
// (`TheNarrationCannotClaimABodyItDidNotReadTests`) · **#645** the variation card
// (`TheVariationCardSaysWhoseTargetTests`) · **#646** the guide-sheet title
// (`TheGuideSheetTitleSaysWhoseBodyTests`) · **#647** the spoken tempo
// (`TheSpokenTempoSaysWhoseBodyTests`). Listed rather than re-argued: an entry per slice with
// its reasoning restated would double this header and is already in each guard.
//
// EGRESS splits in two, and #629 closed one half:
//   · **Peer payload — CLOSED (#629).** ⛔ This paragraph said `ColabPayload.egressible`
//     builds a `BioPeek` with NO source field, "so another performer sees your demo BPM
//     under your peer name". `BioPeek.synthetic` exists since #629 and the rows render it;
//     the sentence is retracted rather than deleted, because it is the sentence #627b wrote
//     to stop a session from concluding the peer path was fine. Guard:
//     `Tests/CISmoke/ThePeerSeesWhetherItIsABodyTests.swift`.
//   · **The four egress protocols — one of the four is now done.** `BioEgressPolicy` admits
//     `.fallback`, and #627 named these four while missing the peer payload. ⭐ #639 closed
//     **OSC**: `/echoelmusic/bio/synthetic` rides every non-empty bio batch. **ADM-OSC,
//     Art-Net/sACN and the discrete-event addresses stay open**, each for its own reason —
//     see `Tests/CISmoke/TheWireSaysWhoseBodyTests.swift`, which is also where the first
//     draft's false "DMX cannot carry metadata" is retracted (512 slots, four in use).
// Apple Health is clean and needs nothing: `HealthWritePolicy.isWritableSource` admits only
// `.ble` and `.cameraPPG`.
//
// KIND (§1): SOURCE-TEXT SCAN throughout. Both surfaces are SwiftUI leaves whose rendered
// output this bundle cannot inspect; what is checkable is that the branch exists, that it
// sits ahead of the branch that used to swallow it, and that the marker reaches the call
// site. That the founder SEES "Demo" is a device probe.
//
// GRADING (#433 / §3), measured against the parent (389e562), both trees, raw and stripped:
//   · claims 1, 2, 3, 5, 6, 7, 8 are REGRESSIONS — zero on the parent, and the parent's
//     rendered behaviour is the defect this file's name denies (an unmarked demo BPM under
//     a lock-green trace; "Connecting…" over live synthetic numbers). NOT "FORWARD": §3
//     reserves that for an assertion that could never have been red, and every one of these
//     is red on the parent. #625b carries the retraction of that exact mislabel.
//   · claims 4 and 9 are COUNTERWEIGHTS — identical on both trees. Claim 4 is the load
//     bearing one: the cheap way to make the tag stop lying is to let `.fallback` into
//     `hasLiveSignal`, which would paint the demo the GREEN reserved for a real body on the
//     wire. That trade is the mirror of the bug, so it is nailed shut.
//   · #627b added five things, graded against `2aa621f` (#627 itself) and MEASURED before
//     being written down — because the first draft of this very paragraph called all five
//     regressions and two of them are not:
//       – claim 3's hardened form (0 → 1) and claims 11 (0 → 1) and 12 (0 → 1) are
//         REGRESSIONS: `isSynthetic` had no camera term, the coherence cell was ungated, the
//         metric sheet was unmarked.
//       – claim 8's two new assertions are COUNTERWEIGHTS (1 and 2 on BOTH trees). #627
//         already built the marker as a prefix on both exits; what was missing was a GUARD
//         against moving it, not the ordering itself. The review's finding was vacuity, not
//         a defect, and calling it a regression would have been the flattering direction §3
//         warns about.
//       – claim 10 is a COUNTERWEIGHT too (0 and 0 on both trees): `demoTag` never used the
//         live or the warning colour. It nails a door shut that was never open.
//     Relative to that same parent, claims 1, 2, 4, 5, 6, 7 and 9 are green — they ARE #627's
//     fix. Two parents therefore appear in this file, named per claim rather than averaged
//     into one sentence that would be false for half of them.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH** twice —
// #627's eighteen verdicts (nine needles × two trees) and #627b's sixteen (eight needles ×
// two trees) are all identical raw and stripped, because none of the prose added here spells
// a needle in its code form. It stays because the next
// comment written near these branches is the one that would flip it, and because #623/#625
// each ASSERTED "TRAGEND" from the shape of a diff and measured otherwise (#626 was the
// first genuinely load-bearing one).
//
// ⚠️ #364: a DIFFERENT marking is not forbidden — a source cell that names "Demo" instead
// of a separate tag, or a distinct trace style, would satisfy the law and make claims 1-2
// red. That is the moment to rewrite this file, not to delete it. What is forbidden
// silently is a synthetic frame reaching either surface with nothing that says so.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheDemoSourceIsMarkedWhereItRendersTests: XCTestCase {

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func codeLines(_ relative: String) throws -> [String] {
        let path = sourceRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// A DOUBLE-ANCHORED window (#619b/#621b): a fixed line count ages as the comments
    /// around these branches grow, and this file adds several. Both anchors must be unique,
    /// so a rename fails LOUDLY here instead of silently selecting the wrong region.
    private func span(_ lines: [String], from: String, to: String,
                      _ what: String, file: StaticString = #filePath,
                      line: UInt = #line) -> [String] {
        let starts = lines.indices.filter { lines[$0].contains(from) }
        XCTAssertEqual(starts.count, 1, """
            \(what): the opening anchor "\(from)" matches \(starts.count) lines, not one — \
            every assertion over this span is measuring the wrong region. Re-anchor it.
            """, file: file, line: line)
        guard let a = starts.first else { return [] }
        guard let b = lines.indices.filter({ $0 > a && lines[$0].contains(to) }).first else {
            XCTFail("""
                \(what): the closing anchor "\(to)" never appears after the opening one — \
                the span is unbounded and would swallow the rest of the file.
                """, file: file, line: line)
            return []
        }
        return Array(lines[a...b])
    }

    // MARK: - The Bio strip

    /// 1 — REGRESSION: the strip has a branch for a synthetic frame at all.
    func testTheStripHasItsOwnBranchForASyntheticFrame() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        let control = span(lines,
                           from: "@ViewBuilder private var sourceControl: some View {",
                           to: "private var noSignalTag: some View {",
                           "sourceControl")
        XCTAssertEqual(control.filter { $0.contains("isSynthetic") }.count, 1, """
            `BioStripView.sourceControl` no longer asks whether the frame it is describing \
            is synthetic. Without that question a `.fallback` frame falls through to the \
            `measuring` branch and the corner reads "Connecting…" while HR, HRV, breath and \
            coherence print confident numbers beside it (#627).
            """)
        XCTAssertEqual(control.filter { $0.contains("demoTag") }.count, 1, """
            the demo branch no longer renders `demoTag`. The four older states cannot \
            describe a synthetic frame: `hasLiveSignal` excludes `.fallback` on purpose, so \
            the only alternatives are a green "live body" tag (a lie in the other direction) \
            or the amber "Connecting…" that this slice removed.
            """)
    }

    /// 2 — REGRESSION, and an ORDER check (#367): counts stay green if the branch is merely
    /// MOVED below `measuring`, which is exactly where it would be swallowed again.
    func testTheDemoBranchSitsAheadOfTheConnectingBranch() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        let control = span(lines,
                           from: "@ViewBuilder private var sourceControl: some View {",
                           to: "private var noSignalTag: some View {",
                           "sourceControl")
        guard let demo = control.firstIndex(where: { $0.contains("demoTag") }),
              let measuring = control.firstIndex(where: { $0.contains("measuringTag") }) else {
            return XCTFail("""
                `sourceControl` no longer names both `demoTag` and `measuringTag`; the \
                ordering this test exists to fix cannot be measured. See claim 1.
                """)
        }
        XCTAssertLessThan(demo, measuring, """
            the demo branch now sits BELOW the `measuring` branch, so it can never be \
            reached: the host passes `measuring: running`, which is true for the whole \
            session the demo runs in. That is the pre-#627 behaviour with an unreachable \
            tag added — worse than before, because the code looks fixed.
            """)
    }

    /// 3 — REGRESSION: the question is asked of the FRAME's own source, on the same
    /// freshness clock as the numbers beside it, not of some separate "is demo selected"
    /// flag that could disagree with what is actually on the bus.
    func testSyntheticIsDecidedByTheFramesOwnSource() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        // ⚠️ #627b: the first version counted the SUBSTRING file-wide while its failure
        // message warned about "a separate UI flag that can drift from the bus" — so
        // redefining `isSynthetic` as exactly such a flag kept this green as long as any
        // other line still carried the substring. The whole declaration is pinned instead.
        // ⛔ #678: this literal said `reading?.source == .fallback`, and #677 respelled that
        // comparison to `reading?.source.isSynthetic == true` — an identity-preserving change
        // that took this needle to ZERO while the property it protects was untouched. The
        // message below would then have said "`isSynthetic` is no longer exactly …" and the
        // cheapest way to make it green is to REVERT the migration. That is the #646 ⛔ block
        // at the bottom of this very file, arriving exactly as it predicted: "a needle naming
        // an inline expression dies the day somebody names that expression". The repair there
        // was applied to claim 12 only; claims 3, 4 and 11 kept literal spellings.
        // Kept as a whole-declaration pin rather than moved to a function anchor, because BOTH
        // halves of this line are the claim (the frame's own source AND the camera exclusion)
        // and a function anchor cannot see either.
        let declaration = "private var isSynthetic: Bool "
            + "{ reading?.source.isSynthetic == true && !cameraRPPG.isRunning }"
        XCTAssertEqual(lines.filter { $0.trimmingCharacters(in: .whitespaces) == declaration }.count, 1, """
            `isSynthetic` is no longer exactly `\(declaration)`. Two things are pinned here \
            and both are load-bearing: it must read the FRAME's own source through \
            `reading` (= `usableBio()`, the exact value every cell renders, so tag and \
            numbers appear and expire together — a separate UI flag drifts from the bus, \
            #503's defect one surface over), and it must exclude a running camera, or the \
            stale `.fallback` frame brands a real reading as a demo for up to five seconds \
            AND swallows the "Cover camera" coaching that sits below it (#627b).
            """)
    }

    /// 4 — COUNTERWEIGHT: green stays reserved for a real body. The cheap "fix" for the
    /// lying tag is to let `.fallback` into `hasLiveSignal`; that would paint the demo with
    /// the live-source colour and trade this bug for its mirror.
    func testTheLiveTagStillExcludesTheDemo() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        // ⛔ #678: this counted `bio.source != .fallback` and expected TWO. #677 respelled
        // BOTH of them to `!bio.source.isSynthetic`, so it dropped to zero in one step — the
        // worst of the five, because a count of 2 going to 0 reads as "both exclusions were
        // deleted" when neither was touched.
        XCTAssertEqual(lines.filter { $0.contains("!bio.source.isSynthetic") }.count, 2, """
            `hasLiveSignal` / `sourceText` no longer exclude the demo generator. The green tag \
            and the source name mean "a real body is on the wire"; admitting the simulator \
            there makes the demo indistinguishable from a strap — the same false claim #627 is \
            removing, moved into a nicer colour.
            ⚠️ The needle is the PREDICATE (`isSynthetic`), not the case (`.fallback`). Since \
            #677 those are one spelling; if you are respelling it again, respell it here in the \
            SAME commit (#456) — a needle that goes to zero on an identity-preserving change \
            tells the next session to undo correct work.
            """)
    }

    // MARK: - The header pill

    /// 5 — REGRESSION: the tile can be told its numbers are synthetic.
    func testThePillTakesASyntheticFlag() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        let decl = span(lines,
                        from: "struct PulseMonitorMini: View {",
                        to: "var body: some View {",
                        "PulseMonitorMini declaration")
        XCTAssertEqual(decl.filter { $0.contains("var synthetic: Bool") }.count, 1, """
            `PulseMonitorMini` no longer declares `synthetic`. This tile is on screen at all \
            times; without the flag it prints a heart rate and paints the lock accent for a \
            simulated frame exactly as it does for a strap (#627).
            """)
    }

    /// 6 — REGRESSION: the ONE live wrapper actually passes it. A defaulted parameter that
    /// no call site writes appears in no diff and does nothing (#431/#440/#443).
    func testTheLiveWrapperPassesIt() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        let call = span(lines,
                        from: "PulseMonitorMini(waveform: cameraRPPG.waveform,",
                        to: ".contentShape(Rectangle())",
                        "PulseMonitorMiniLive call site")
        XCTAssertEqual(call.filter { $0.contains("synthetic:") }.count, 1, """
            `PulseMonitorMiniLive` no longer passes `synthetic:`. The flag defaults to \
            `false`, so the tile silently returns to claiming every fresh bus frame as a \
            measured pulse — the defect, with the repair still visible in the type.
            """)
    }

    /// 7 — REGRESSION: the LOCK accent is the tile's strongest non-verbal claim, and a
    /// synthetic frame sets `locked`. The word alone would leave the colour lying.
    func testTheLockAccentIsGatedOnRealness() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        XCTAssertEqual(lines.filter { $0.contains("(locked && !synthetic)") }.count, 1, """
            the pulse trace is accent-coloured on `locked` alone again. A `.fallback` frame \
            is fresh, so it locks, so the demo lights the same green as a real strap — the \
            claim a glance actually reads, before any label (#627).
            """)
    }

    /// 8 — REGRESSION: VoiceOver hears it too. The visual marker is invisible to the user
    /// most likely to trust a spoken number as a measurement.
    func testVoiceOverIsToldItIsSimulated() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        let a11y = span(lines,
                        from: "private var accessibilityText: String {",
                        to: "#if canImport(AVFoundation)",
                        "accessibilityText")
        XCTAssertGreaterThanOrEqual(a11y.filter { $0.contains("synthetic") }.count, 1, """
            `accessibilityText` no longer mentions the synthetic source. It reads the BPM \
            straight out as a measurement, which is the one presentation where a visual \
            "Demo" chip does nothing at all.
            """)
        // ⚠️ #627b: presence alone was VACUOUS with respect to the property the source
        // comment calls load-bearing — appending ", simulated" AFTER the number is exactly
        // the presentation that comment argues against ("the marker goes FIRST"), and it
        // kept the assertion above green. The prefix and BOTH its uses are pinned.
        XCTAssertEqual(a11y.filter { $0.contains("let prefix = synthetic ?") }.count, 1, """
            the synthetic marker is no longer built as a PREFIX. A trailing footnote is \
            heard as a measurement with an addendum; "Simulated demo, 142 beats per minute" \
            cannot be. That ordering is the whole reason this string is touched.
            """)
        XCTAssertEqual(a11y.filter { $0.contains("return \"\\(prefix)") }.count, 2, """
            not both return paths lead with the prefix. `accessibilityText` has TWO exits \
            (with and without coherence); a marker on one of them leaves the other reading \
            a synthetic pulse out as a plain measurement.
            """)
    }

    /// 9 — COUNTERWEIGHT: there is exactly ONE construction site IN THE WHOLE TREE, so
    /// claim 6 covers every place this tile can render. ⚠️ The first draft of this counted
    /// inside `HeaderMonitors.swift` alone while its failure message spoke about the app —
    /// a second mount in any other file would have left every assertion here green. The
    /// scan therefore walks `Sources/`; `PulseMonitorMiniLive(` does not match, the
    /// trailing paren is what separates the wrapper from the tile.
    func testThePillHasExactlyOneConstructionSite() throws {
        let sources = sourceRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path)")
        }
        var sites: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in SourceText.codeOnly(text).split(separator: "\n") where line.contains("PulseMonitorMini(") {
                sites.append("\(relative): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(sites.count, 1, """
            `PulseMonitorMini` is constructed \(sites.count) times, not once: \(sites). \
            Claim 6 pins a single call site by name; a second mount can render synthetic \
            numbers unmarked while every assertion in this file stays green.
            """)
    }

    /// 10 — COUNTERWEIGHT (#627b, measured 0/0 on both trees): the demo tag's COLOUR. The whole argument for a fifth branch
    /// is that neither existing colour can describe a synthetic frame; nothing pinned that,
    /// so a later "make it more visible" edit to `EchoelTheme.success` would reproduce the
    /// exact mirror bug claim 4 exists to prevent, with every assertion still green.
    func testTheDemoTagBorrowsNeitherTheLiveNorTheWarningColour() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        let tag = span(lines,
                       from: "private var demoTag: some View {",
                       to: "private var liveTag: some View {",
                       "demoTag")
        XCTAssertEqual(tag.filter { $0.contains("EchoelTheme.success") }.count, 0, """
            `demoTag` now paints itself in `EchoelTheme.success` — the colour this file \
            reserves for a real body on the wire. That is the same false claim #627 removed, \
            moved into a nicer shade; claim 4 would not see it.
            """)
        XCTAssertEqual(tag.filter { $0.contains("EchoelTheme.warning") }.count, 0, """
            `demoTag` now paints itself amber. Amber in this strip means "something is \
            pending or wrong" (`measuringTag`, `openSettingsButton`); the demo is neither — \
            the user chose it, and nothing is being awaited.
            """)
    }

    /// 11 — REGRESSION (#627b): the pill's coherence cell must not carry a stale synthetic
    /// frame while the camera owns the display. It is the ONE value in that call which reads
    /// the bus in BOTH branches, so `synthetic:`'s `!cameraLive` term deliberately does not
    /// cover it — and #627 did not notice.
    func testTheCoherenceCellDropsAStaleSyntheticFrame() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/HeaderMonitors.swift")
        // ⛔ #678: respelled by #677 (`== .fallback` → `.isSynthetic == true`). Same
        // whole-line pin, new spelling — the line IS the claim here, both the `cameraLive`
        // term and the `? nil :` are load-bearing and no function anchor sees them.
        let guardLine = "let coherenceFrame = (cameraLive && fresh?.source.isSynthetic == true) ? nil : fresh"
        XCTAssertEqual(lines.filter { $0.contains(guardLine) }.count, 1, """
            the coherence cell reads `fresh` unconditionally again. Switching source stops \
            the simulator but nothing clears `EngineBus.latestBio`, and `.fallback`'s window \
            is 5 s — so just after Simulation → Camera the pill prints the SIMULATOR's \
            coherence with the demo marker deliberately off, because `synthetic:` is gated \
            on `!cameraLive` (#627b).
            """)
        XCTAssertEqual(lines.filter { $0.contains("coherence: coherenceFrame.flatMap") }.count, 1, """
            the guarded frame is computed but not used for the coherence argument — the \
            repair would then be present in the source and absent from the render.
            """)
    }

    /// 12 — REGRESSION (#627b): the sheet the fixed strip OPENS is marked too. This was the
    /// hole in #627 — one tap from the "Demo" tag, live percentages with no marker, and the
    /// "read your pulse" hint GONE because `liveBio` is non-nil under Simulation, i.e. an
    /// assertion of a measured body rather than a missing footnote.
    ///
    /// ⛔ TWO REPAIRS FROM #637, both of which this assertion needed rather than deserved.
    ///
    /// (a) IT WAS A COUNT PIN AND CORRECT WORK BROKE IT (#364). It demanded EXACTLY ONE
    /// `liveBio?.source == .fallback`. #637 marked the mapping rows themselves and added a
    /// second — `private var isSyntheticBio` — so a commit that made the sheet MORE honest
    /// turned this red. Zero is the hazard here, never "more than one": a second reader of
    /// the same test is how a marking gets applied per row. The pin is now `>= 1` and the
    /// per-row facts are pinned where they belong, in
    /// `TheMetricSheetRowsSayWhoseBodyTests`.
    ///
    /// (b) IT NAMED THE WRONG TYPE AND THE WRONG DOOR. `BioMetricInfo.swift` holds two
    /// sheets: `BioMetricInfoView` (`.sheet(item: $explain)`, the per-cell tap) renders
    /// STATIC explanation text and reads no bio at all, so it can neither mark nor
    /// over-claim; the marking lives in `BioMetricsGuideView` (`.sheet(isPresented:
    /// $showGuide)`, the ⓘ). A message naming the wrong type sends the next session to a
    /// file that is already correct.
    /// ⛔ (c) A THIRD REPAIR, AND THE NEEDLE BROKE THE SAME WAY TWICE (#646). Repair (a) fixed
    /// the COUNT and left the needle a literal SPELLING — `liveBio?.source == .fallback`. #646
    /// hoisted that comparison out of the view into `BioMetric.originNote(for:)` so a second
    /// heading could ask it, and the spelling went to ZERO occurrences: correct work, red gate,
    /// and a failure message that would have said the sheet "no longer distinguishes a
    /// synthetic frame anywhere" while it distinguishes at three sites. That is the #367 mirror
    /// — green or red for a reason other than the one stated. **The lesson repair (a) did not
    /// draw: loosening `==` to `>=` fixes the arithmetic and leaves the FRAGILITY, because the
    /// fragile part was never the number.** A needle naming an inline expression dies the day
    /// somebody names that expression, which is the ordinary direction of improvement. The
    /// anchor is now the FUNCTION the decision lives in; it survives a caller being added, a
    /// caller being moved, and the comparison being respelled inside it.
    func testTheMetricSheetMarksTheDemoToo() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioMetricInfo.swift")
        let hits = lines.filter { $0.contains("BioMetric.originNote(") }.count
        XCTAssertGreaterThanOrEqual(hits, 1, """
            `BioMetricsGuideView` no longer distinguishes a synthetic frame anywhere. Its \
            door is `BioStripView`'s `.sheet(isPresented: $showGuide)`, one affordance from \
            the "Demo" tag, so an unmarked sheet directly contradicts the tag beside it. \
            `>= 1`, never `== n`: a THIRD heading asking the same question is this sheet \
            getting more honest, and repair (a) already paid for pinning that as a defect.
            """)
    }
}
