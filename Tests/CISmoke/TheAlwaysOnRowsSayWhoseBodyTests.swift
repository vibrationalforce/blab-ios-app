// TheAlwaysOnRowsSayWhoseBodyTests.swift
// Echoel — #634: the always-on channel rows printed the demo generator as a measured body,
// in the Bio panel, a few dozen lines under a strip that already said "Demo".
//
// WHAT THIS GUARDS. `AlwaysOnBioRow` renders four bio channels — coherence, HRV, heart rate,
// breath phase — as a two-decimal value plus a filled accent bar, and tells VoiceOver
// "Coherence at 62 percent, shaping …". Two reachable hosts: `AlwaysOnBioPanelStrip` in
// `bioPanel` (reached by a TAP on the pulse pill) and `AlwaysOnBioView` in the FX "All
// parameters" sheet. ⛔ THIS LINE SAID "(Bio chip)" — no chip OPENS the panel; `.bio` is absent from the
// standing strip and appears there only as the selected tab once it is open (#705/#706).
//
// ⛔ WHY `isMeasured` COULD NOT CATCH IT, and this is the whole finding. `isMeasured` asks the
// frame's own `hasMeasuredCoherence` / `hasMeasuredHRV` / `hasMeasuredHeartRate` /
// `hasMeasuredBreath` gates. Every one of those is a test on the NUMBER, never on its origin —
// and `BioSimulator` satisfies all four by construction (heart rate 58…92, HRV 0.2…0.9,
// coherence 0.2…0.9, breath rate 12, a moving phase). So under Simulation the rows reported
// four confident measurements, full-opacity accent bars, and a VoiceOver sentence about the
// listener's body.
//
// ⛔ AND `isHeld` IS NOT A NEAR-MISS FOR IT EITHER — claim 3 proves that rather than asserting
// it. A demo frame is FRESH: it arrives about once a second, well inside `.fallback`'s
// freshness window, so `isHeld` is false the entire time. The one existing fact that could
// have hinted at something is the one the demo never trips.
//
// ⚠️ THE SHARP PART IS THE PLACEMENT, not the row in isolation. `bioPanel` mounts
// `BioStripView` — which HAS marked the demo since #627 — and then, further down, the static
// sentence "Four BODY channels shape the instrument's own timbre while a session runs",
// and then these four rows. A player read "Demo" at the top of the panel and, immediately
// under a sentence that says *body*, four unmarked measurements of a body that is not there.
//
// KIND (§1): claims 1–3 and 8 are **END-TO-END BEHAVIOUR** — `AlwaysOnBioReading`,
// `AlwaysOnBioChannel.reading(in:now:)` and `BioSampleFrame` are public Foundation-only value
// types, so this bundle drives the real producer. Claims 4–7 are SOURCE-TEXT SCANS: the row is
// a SwiftUI leaf whose rendered output no test bundle here can inspect. That the founder SEES
// the chip and hears the sentence is a DEVICE PROBE and stays open.
//
// GRADING (#433 / §3), measured against the parent (86625fd), both trees, raw and stripped:
//   · This file does not COMPILE against the parent — `AlwaysOnBioReading.isSynthetic` does
//     not exist there. Per §3 that is ONE absence (#486), not five findings, and no assertion
//     has a verdict on the parent tree; it is hand-transcribed instead (§0). Explicitly NOT
//     "green against its own tree" dressed as gradable (#488).
//   · claims 4 and 6 are REGRESSIONS by transcription: the chip needles go 0 → 1 and the
//     `origin` binding does not exist on the parent (claim 6 lands in its `XCTFail`).
//     `isSynthetic` occurs ZERO times in `AlwaysOnBioRow.swift` there, and the parent's
//     rendered behaviour is exactly what this file's name denies.
//   · claim 5 is MIXED and is written down per assertion rather than averaged (the #632b
//     lesson, one cycle old): the accent line carries the `isSynthetic` ternary 0 → 1, a
//     REGRESSION; the `.opacity(reading.isHeld ?` half is 1 and 1, a COUNTERWEIGHT — the held
//     dimming predates this slice and the assertion exists so marking does not eat it.
//   · claim 2 is a COUNTERWEIGHT (7 declared cases, both anchors unique, on both trees).
//   · claims 3, 7 and 8 are COUNTERWEIGHTS, identical on both trees, and they carry the file:
//     3 shows the new fact was genuinely unreachable from the old ones; 7 keeps the #498/#500
//     laws ("—" for unmeasured, "held" for aged-out) from being traded away while marking; 8
//     keeps `reading(in:now:)` ASKING `BioSource.freshnessWindow` and
//     `BioSource.futureSkewTolerance` instead of restating them (#416) — adding a second
//     `frame.source` read to that method is exactly when someone inlines the first.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). No assertion's VERDICT flips raw vs
// stripped, so the file is green either way — but the headline "PROPHYLAKTISCH" was too
// generous and is corrected here (#634b): the bare `"—"` needle really does change COUNT in
// the row file (2 raw → 1 stripped; the second hit is a doc comment), so the stripper is
// load-bearing for that one and the count I published (11 needles) was two short — there are
// 13 on the row file plus 2 anchors on `EngineBus.swift`. Verdicts unchanged, arithmetic wrong,
// and #623/#625 are in this file's ancestry precisely for asserting a stripper verdict from
// the shape of a diff instead of measuring it.
//
// ⚠️ #364: a DIFFERENT marking is not forbidden — a fifth row reading "source: demo", or the
// panel sentence itself turning conditional, would satisfy the law and turn claims 4–6 red.
// That is the moment to rewrite this file. What is forbidden silently is a `.fallback` frame
// reaching these rows with nothing that says so.
//
// ⚠️ STILL OPEN after this slice. ⛔ THE FIRST VERSION OF THIS LIST NAMED THREE COPY SITES AND
// WAS SHORT BY SIX ENTRIES, INCLUDING TWO WHOLE RENDERING SURFACES — the #632/#627b defect for
// the third time in this family, and the reason a register gets MEASURED and not recalled:
//   · **`BioModContributionRow` — CLOSED (#635b), ticked off here in the commit that noticed
//     it was still listed as open.** It was RENDERING in the SAME SHEET, one `Section` ABOVE
//     the rows #634 marked (`EchoelFXView`: `BioModLiveView` then `AlwaysOnBioView`), drawing
//     a signed offset and speaking "…moving <target>, N percent" while `BioModContribution`
//     carried `measured` and NO origin field at all — one sheet, one frame, two provenance
//     stories about forty points apart. #635b added `public var synthetic: Bool` with no
//     default (`Core/FXModulation.swift`), a "Demo" chip and a dimmed bar in the row, and the
//     prefix spelling in its label (`Studio/EchoelFXView.swift`); guard
//     `Tests/CISmoke/TheFXRoutesSayWhoseBodyTests.swift`. ⛔ Two cycles passed with this bullet
//     reading "Next slice" AFTER the slice had landed — which is the failure this list's own
//     rule names: a per-entry register only beats a count if the entries get ticked off in the
//     commit that closes them.
//   · **CLOSED by #637 — and this entry named the WRONG TYPE, which is why it is corrected
//     here rather than deleted.** The half-marked sheet is `BioMetricsGuideView` (the ⓘ,
//     `.sheet(isPresented: $showGuide)`), NOT `BioMetricInfoView` (the per-cell tap, static
//     text, no bio read at all). #627b had put "demo values, not your body" in the SECTION
//     HEADER only, while each mapping row — its own accessibility element, so the header is
//     unreachable by rotor — ended "Currently N percent." with no prefix and filled its
//     `liveBar` in full `EchoelTheme.accent`. #637 dims the number and the bar and prefixes
//     the label; guard `Tests/CISmoke/TheMetricSheetRowsSayWhoseBodyTests.swift`.
//   · ⭐ **`AlwaysOnBioChannel.soundPanelSentence`: "Your body also shapes this sound…"** —
//     possessive, second person, rendered in the Sound panel. Stronger than the
//     `bioPanelSentence` the first version of this list named, and it was missing.
//     **CLOSED by #640**, together with `AutomationStatus.emptySentence` on the same panel —
//     guard `Tests/CISmoke/TheSoundPanelNamesItsActualDriverTests.swift`.
//   · ⭐ **`bioPanelSentence` and `alwaysOnSentence` — the same noun ("body") in two more
//     places. CLOSED by #643**, both from the same conditional subject and both taking the flag
//     from the RAW frame their own rows answer from. The Bio panel's sentence MOVED one level
//     down into `AlwaysOnBioPanelStrip` to get it: `bioPanel` is a body that may not read live
//     bio (10.76.41/50), and the strip already binds that frame for the rows — so the claim and
//     the numbers under it are now one read by construction. ⛔ NOT "one bio read fewer in the
//     panel body" — the string that moved was a `static let`, so that body went zero → zero. The
//     gain is that the flag never had to be read there. Guard: claim 6 of this file.
//     ⛔ **THIS BULLET NAMED `EchoelFXView.stopsArrivingNote` AS A THIRD AND
//     ITS STRING CONTAINS NO SUCH NOUN** ("When a channel stops arriving, its routes here
//     release…"). The error travelled into two other registers verbatim; the count "four" was
//     right and one of the four was the wrong file, which is worse than a wrong count because
//     nothing ever contradicts it.
//   · ⛔ **AND THE FIRST CORRECTION OVERSHOT INTO SOMETHING WORSE — IT EXONERATED THE WHOLE
//     FILE.** It read: "Grep the FILE and you find one 'body' — `var body: some View`, forty
//     lines down and part of no sentence". Measured: `grep -c body` on `EchoelFXView.swift`
//     returns **48** lines, `var body: some View` occurs **seven** times, and the nearest one
//     after `stopsArrivingNote` is **six** lines down, not forty. Retracting a wrong SYMBOL was
//     right; the sentence I replaced it with quietly closed a whole file, and closing is the
//     direction that costs — a wrong entry gets found by the next reader, a missing one never
//     does. THREE unmarked user-facing strings lived there. #641 triaged all three and closed
//     the one that needed closing — the split is the useful part of the entry:
//       · ⭐ **CLOSED (#641, and the Live half re-opened and re-closed by #642):** the section
//         headers `Text("Live — body → sound")` and `Text("Always on — body → timbre")`.
//         ⛔ THE FIRST LITERAL IS NO LONGER IN THE VIEW. #642 moved the Live heading's four
//         states and THREE strings into `LiveModOrigin.heading` (`Core/FXModulation.swift`), so
//         the view renders `modulator.liveOrigin.heading`. ⛔ THE FIRST DRAFT SAID THE QUOTATION
//         IS "no longer a line one can grep for" — false: `"Live — body → sound"` is still
//         greppable, at its new home in `FXModulation.swift`. The narrower TRUE claim is that
//         `Text("Live — body → sound")` is gone from the VIEW. The reason was a state
//         #641 closed this entry without: a section of only LFO routes still said "body →
//         sound" over an oscillator, which #641's review registered and left. Both are rendered
//         WHILE their rows are live, and
//         every row under them has said "Demo" since #635b / #498 — a heading asserting a body
//         over rows that say otherwise is the #640 collision on a second panel. Each now
//         derives from a value that adds no observation. (⛔ THIS SENTENCE SAID "from the SAME
//         value its own rows use" and it is FALSE for the Live half — the rows' `synthetic` comes
//         through `usableBio()`, the heading through raw `latestBio`, deliberately since #641's
//         review pass. #642 copied the stale summary into this register before retracting it in
//         `TheFXHeadersSayWhoseBodyTests` claim 6, where the whole argument lives.) The
//         held-state footer clause went with them, reworded rather than branched: "your body
//         has stopped sending it" → "the signal has stopped arriving" (#484's precedent — a
//         MECHANISM sentence takes the signal as its subject, and is then true under both
//         sources). Guard: `Tests/CISmoke/TheFXHeadersSayWhoseBodyTests.swift`.
//       · ⚠️ **DELIBERATELY NOT MARKED, and this is a decision, not a leftover:** "Let the body
//         shape the effects: e.g. coherence → reverb…" renders when there are NO routes, and
//         "Start a session to watch the body move these parameters." renders when the modulator
//         is NOT running. Both are INSTRUCTIONS about what the instrument does, on screens where
//         nothing is claimed about a current reading; marking them would imply a demo is running
//         when none is. Claim 5 of that guard pins both, so a later "sweep the file for `body`"
//         cannot quietly take them. **The family's remaining risk is over-correction.**
//     (Line numbers are a date, not a fact — re-grep `"body` in that file.)
//   · ⛔ **AND THE ADVICE ATTACHED HERE WAS AN IMPOSSIBILITY CLAIM THAT IS NOT TRUE.** It read:
//     "All four collapse into ONE edit by changing the noun rather than adding a condition; a
//     condition here would put a live bio read into a property `EchoelStudioView.body`
//     evaluates (the 10.76.41/50 freeze law)." The premise holds for an INLINE condition; the
//     conclusion assumed no leaf may exist — while this very panel already mounts
//     `AutomationStatusStrip` and the panel next door mounts `AlwaysOnBioPanelStrip`, both
//     reading live state in their own bodies for exactly this reason. #640 took the leaf route.
//     What the discarded advice would have bought instead is worth naming: rewording the noun
//     for EVERY player, so the instrument's identity line pays for the demo mode's honesty.
//     A constraint recorded without its escape hatch reads as an impossibility.
//   · ⭐ **CLOSED (#648)** — the two `EchoelStudioView` captions ("your measured coherence…",
//     "your inhale opens it"), plus the two SPOKEN hints beside them that no register held:
//     `BreathVoiceRow`'s "Sounds a held tone whose colour follows your body" and `AutoModeRow`'s
//     "Slowly steers the mood dials toward your measured body state". All four now come from
//     `BioPanelRowCopy`. The shape is the finding: each row already branched — on breath
//     measured, on source running — so each LOOKED conditioned, and **a row that conditions on
//     one thing reads as conditioned on everything**. That is why this class survived five
//     slices. Guard: `TheBioPanelRowsSayWhoseBodyTests`.
//   · ⭐ **THRESHOLD MET (#648)** — the shared SUBJECT-PHRASE helper this list asked for is
//     `BioPanelRowCopy.subject(synthetic:)`. It shares the NOUN only, never a sentence (#634b).
//     The seven existing inline sites are NOT migrated: guards pin those literals verbatim, so
//     a migration must move them in the same commit (#456).
//   · ⭐ **CLOSED (#647)** — `BodyTempoField`'s `.accessibilityLabel`, which was the fixed string
//     `"Tempo, driven by your body"` at both sites. Now `TempoFollowLabel.spoken(for:)`, keyed on
//     `bus.usableBio()`. Ticked in the commit that closes it, in BOTH registers — #642 updated
//     one and not the other, and that is the failure this list's own rule names.
//     ⛔ #647 ALSO CALLED THIS "the last registered entry of the #632/#627b pattern" AND THAT
//     WAS FALSE — the very next bullet in this list is spoken and still open. Retracted at the
//     guard too. Declaring a pattern closed is how the next session stops looking for it.
//     ⭐ #647's REVIEW then found a SECOND spoken claim in the same file that no register held:
//     the lock button's "tap to let your body drive it again", false under Simulation because
//     unlocking hands the clock to the demo generator. Now `TempoFollowLabel.unlockHint(for:)`.
//     The lesson is the register's, not the reviewer's: a per-entry list finds what somebody
//     already wrote down, and a file-wide sweep for the PHRASE finds what nobody did.
//   · ⭐ **CLOSED (#649).** This stood as "WATCH, not a defect yet: spelled inline at SEVEN
//     sites", and the helper it called for is now `BioProvenanceCopy.demoSubject`. Its analysis
//     was right and its COUNT was wrong: a driven census found TEN, and one of the ten was
//     invisible to the very grep the entry was written from — `autoModeHint` split the phrase
//     mid-phrase across two literals. It also listed `AutomationStatus` as an inline site; that
//     one is a permanent NON-site (three-way contrast, see `BioProvenanceCopy`).
//     ⛔ THE FAMILY CARRIED THREE REGISTERS WITH THREE DIFFERENT WRONG COUNTS — six in
//     `AlwaysOnBioChannel`, seven here, and the ten that was true. #649 retracted the first and
//     left this one standing, so a reviewer found an open WATCH item for work that had already
//     shipped, with a threshold ("the eighth copy") that no longer exists. **The register that
//     records a threshold has to be ticked by the commit that crosses it** — the same rule the
//     surfaces register states three times about itself, now paid for a fourth time.
//   · ADM-OSC and Art-Net still carry no provenance (#462, second half) — ⛔ **sACN STOOD IN
//     THIS LIST ONE CYCLE AGO AND IS CLOSED (#789)**: E1.31 puts a 64-byte Source Name in the
//     framing layer of every data packet, `SACNSender` was already filling it with a hardcoded
//     name, and a demo session now reads "Echoelmusic (DEMO)" in a console's source list.
//     Art-Net stays open for a PRECISE reason: `ArtDMX` carries no name and `ArtPollReply`,
//     which does, is not implemented — a build, not a decision. ⭐ OSC itself is
//     DONE since #639 (`/echoelmusic/bio/synthetic`) — this line said "OSC" first and would
//     otherwise send the next session to re-do it — and the DISCRETE EVENTS are done since
//     #785, which is why they are struck from this bullet here rather than only in
//     `TheWireSaysWhoseBodyTests`. Exactly the rule stated two bullets up: **the register that
//     records a threshold has to be ticked by the commit that crosses it**, and a register
//     entry lives in as many files as somebody wrote it into (#456).
//
// ⚠️ AND ONE ASYMMETRY TO WRITE DOWN RATHER THAN "HARMONISE": `AlwaysOnBioChannel` tests bare
// `frame.source == .fallback`, while `BioStripView` and `HeaderMonitors` add `&& !isRunning`
// on the camera (#627b — switching Simulation → Camera stops the simulator but nothing clears
// `latestBio`, and `.fallback`'s window is 5 s, so the last synthetic frame stays usable while
// the camera is genuinely running). BOTH ARE RIGHT ABOUT THEIR OWN NUMBER: the strip prefers
// `cameraRPPG.displayBPM` during that window, so marking it would lie; these rows draw the
// fallback frame's own value, so marking it is accurate. Copying the camera term across would
// make THIS row lie. The visible residue is that for ≤5 s an unmarked strip sits above marked
// rows in one panel — registered, not a defect to paper over.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAlwaysOnRowsSayWhoseBodyTests: XCTestCase {

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

    private let row = "Sources/Echoelmusic/Studio/AlwaysOnBioRow.swift"

    /// A frame every channel reports as measured, stamped `now` so it is never held.
    private func frame(_ source: BioSource, at t: TimeInterval = 1000) -> BioSampleFrame {
        BioSampleFrame(timestamp: t, heartRateBPM: 64, hrvNormalized: 0.45,
                       breathRate: 12, breathPhase: 0.3, coherence: 0.62,
                       motionEnergy: 0, source: source)
    }

    // MARK: - 1–3, 8  END-TO-END BEHAVIOUR

    /// 1. Only the demo generator's source sets the flag, and every real source clears it.
    ///    Enumerated rather than sampled: `BioSource` is not `CaseIterable`, so claim 2 pins
    ///    the case count and this list stays exhaustive by construction (#367).
    func testOnlyTheFallbackSourceIsSynthetic() {
        for channel in AlwaysOnBioChannel.allCases {
            XCTAssertTrue(channel.reading(in: frame(.fallback), now: 1000).isSynthetic,
                          "\(channel.name): a .fallback frame is the demo generator's")
            for real in [BioSource.healthKit, .oura, .ble, .watch, .cameraPPG, .faceCam] {
                XCTAssertFalse(channel.reading(in: frame(real), now: 1000).isSynthetic, """
                    \(channel.name) marked a \(real) frame as the demo. Every one of these is a \
                    real signal off a real body; branding one fake is the mirror of the bug \
                    this file is about.
                    """)
            }
        }
    }

    /// 2. The premise claim 1 rests on (#343), and it is a SOURCE SCAN on purpose. The
    ///    obvious behavioural form — comparing my hardcoded list against a hardcoded
    ///    `Set(0...6)` — cannot fail for its named reason (#367): adding `case emg = 7` leaves
    ///    both sides untouched and the test green. `BioSource` is not `CaseIterable`, so the
    ///    only thing that actually sees a new case is the declaration itself.
    func testTheSourceSetIsStillTheSevenClaimOneEnumerates() throws {
        let lines = try codeLines("Sources/Echoelmusic/Core/EngineBus.swift")
        // Double-anchored (#619b/#621b): both must be unique, so a rename fails loudly here
        // instead of silently selecting the wrong region.
        let opens = lines.indices.filter { lines[$0].contains("public enum BioSource: UInt8") }
        let closes = lines.indices.filter { lines[$0].contains("public var providesTrustedHRV") }
        XCTAssertEqual(opens.count, 1, "the BioSource declaration anchor is no longer unique")
        XCTAssertEqual(closes.count, 1, "the closing anchor is no longer unique")
        guard let a = opens.first, let b = closes.first, b > a else {
            return XCTFail("could not bracket the BioSource case list")
        }
        // Only DECLARATIONS. ⛔ THE FIRST DRAFT REQUIRED AN EXPLICIT `= N` AND FAILED OPEN ON
        // THE ONE SHAPE IT IS NAMED FOR (#634b): `BioSource: UInt8` permits IMPLICIT raw
        // values, so `case emg` with no `= 7` left the count at seven, this guard green, and
        // claim 1's hand-written six-source list silently one short — exactly the miss it
        // exists to prevent. A predicate that only sees the spelling the author happened to
        // use is not a census.
        //
        // The `switch` arms further down in the same type (`case .ble, .cameraPPG: return 6`)
        // are excluded twice over: they are outside the bracketed span, and they carry a `:`.
        let declared = lines[a..<b].filter {
            let s = $0.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("case ") else { return false }
            if s.contains(":") { return false }             // a switch arm, not a declaration
            guard let eq = s.firstIndex(of: "=") else { return true }   // implicit raw value
            return Int(s[s.index(after: eq)...].trimmingCharacters(in: .whitespaces)) != nil
        }
        XCTAssertEqual(declared.count, 7, """
            `BioSource` declares \(declared.count) cases, not the seven claim 1 enumerates: \
            \(declared.map { $0.trimmingCharacters(in: .whitespaces) }). A new source must be \
            added to that list AND decided — is it a body, or is it generated? Nothing else in \
            this bundle would notice, because `BioSource` is not CaseIterable.
            """)
    }

    /// 3. COUNTERWEIGHT, and the reason this slice was needed at all: the demo trips NEITHER
    ///    existing fact. All four channels read as measured, and none reads as held.
    func testTheDemoFrameLooksExactlyLikeAMeasuredBodyToTheOldFacts() {
        for channel in AlwaysOnBioChannel.allCases {
            let r = channel.reading(in: frame(.fallback), now: 1000)
            XCTAssertTrue(r.isMeasured, """
                \(channel.name): the demo satisfies the frame's own hasMeasured… gate. If this \
                ever goes false, `isSynthetic` stopped being load-bearing for that channel — \
                re-read this whole file rather than deleting the assertion.
                """)
            XCTAssertFalse(r.isHeld, """
                \(channel.name): a demo frame is FRESH, so `isHeld` cannot stand in for \
                provenance. This is the assertion that proves claim 1 is not redundant.
                """)
        }
    }

    /// 8. COUNTERWEIGHT (#416). `reading(in:now:)` now reads `frame.source` twice — once for the
    ///    freshness window, once for provenance. That is exactly the moment someone "simplifies"
    ///    the first into a literal. Driven, not scanned: real behaviour at both windows.
    func testTheFreshnessWindowIsStillAskedOfTheSource() {
        // `.fallback` and `.healthKit` have deliberately different windows (5 s vs 90 s).
        let old = 1000 - (BioSource.fallback.freshnessWindow + 1)
        XCTAssertTrue(AlwaysOnBioChannel.heartRate
            .reading(in: frame(.fallback, at: old), now: 1000).isHeld,
            "past its own window, a demo frame must read as held — the window is per-source")
        XCTAssertFalse(AlwaysOnBioChannel.heartRate
            .reading(in: frame(.healthKit, at: old), now: 1000).isHeld, """
            a HealthKit frame at the same age must NOT be held: its window is far longer. If \
            this fails, the per-source window was replaced by one number for everyone.
            """)
        XCTAssertTrue(AlwaysOnBioChannel.heartRate
            .reading(in: frame(.fallback, at: 1000 + BioSource.futureSkewTolerance + 1),
                     now: 1000).isHeld,
            "and the future-skew half is still asked of `BioSource`, not restated here")
    }

    // MARK: - 4–7  SOURCE-TEXT SCANS (the row)

    /// 4. The chip is rendered, and gated on the new fact rather than on measuredness.
    func testTheRowRendersTheDemoChip() throws {
        let lines = try codeLines(row)
        XCTAssertEqual(lines.filter { $0.contains("if reading.isSynthetic {") }.count, 1)
        XCTAssertEqual(lines.filter { $0.contains("Text(\"Demo\")") }.count, 1, """
            the always-on row no longer renders the marker. Five sibling surfaces render the \
            same word; if this one changed its form, say so here in the same commit.
            """)
    }

    /// 5. The BAR is the loudest thing on the row, and it must not paint a fabrication in the
    ///    colour this app reserves for a live body — the over-claim #627 removed from the pill.
    func testTheBarDoesNotPaintADemoInTheLiveAccent() throws {
        let lines = try codeLines(row)
        let fills = lines.filter { $0.contains("EchoelTheme.accent") }
        XCTAssertEqual(fills.count, 1, "one accent site, so this assertion measures all of them")
        XCTAssertTrue(fills.first?.contains("reading.isSynthetic ?") ?? false, """
            the signal bar fills with `EchoelTheme.accent` unconditionally again. Accent is \
            the live-body colour here (`BioStripView.demoTag` states the reservation); a demo \
            value must draw in `EchoelTheme.dim`. The held dimming composes ON TOP — check \
            that `.opacity(reading.isHeld ? …)` survived alongside it.
            """)
        // ⚠️ SCANNED FILE-WIDE, NOT ON THE ACCENT LINE. The tint ternary and the held opacity
        // sit on two source lines (the one-liner is past the line-length limit), and the first
        // draft of this assertion looked for both on one — it was RED on a correct tree and my
        // §0 transcription caught it before the commit. A needle that assumes a formatting
        // choice is a needle that breaks on `swiftformat`, not on a defect.
        XCTAssertEqual(lines.filter { $0.contains(".opacity(reading.isHeld ?") }.count, 1, """
            marking the demo swallowed the #500 held dimming, or moved it somewhere this scan \
            cannot see. Both facts compose on this bar: demo decides the COLOUR, held decides \
            the OPACITY.
            """)
    }

    /// 6. VoiceOver leads with it, on EVERY return path — a qualifier that arrives after
    ///    "at 62 percent" corrects a claim instead of preventing one (the #629b ordering law).
    func testVoiceOverLeadsWithTheOrigin() throws {
        let lines = try codeLines(row)
        guard let originLine = lines.firstIndex(where: { $0.contains("let origin = reading.isSynthetic") }),
              let guardLine = lines.firstIndex(where: { $0.contains("guard reading.isMeasured else") })
        else {
            return XCTFail("`origin` or the isMeasured guard is gone from `accessibilityText`")
        }
        XCTAssertLessThan(originLine, guardLine, """
            `origin` is computed AFTER the isMeasured guard, so the unmeasured return path \
            speaks no origin while the chip is still on screen — the row's own doc says \
            VoiceOver gets the same facts in the same order.
            """)
        XCTAssertEqual(lines.filter { $0.contains("return origin") || $0.contains("origin +") }.count, 3, """
            not all three return paths of `accessibilityText` lead with `origin`. There are \
            three (unmeasured, measured, measured+held) and each states something about a body.
            """)
    }

    /// 7. COUNTERWEIGHT. Marking the demo must not be paid for by dropping the two facts that
    ///    were already right: "—" for an unmeasured channel (#498) and "held" for an aged-out
    ///    one (#500). Both are one-line deletions away and both would look like tidying.
    func testTheOlderHonestyStillRenders() throws {
        let lines = try codeLines(row)
        XCTAssertEqual(lines.filter { $0.contains("Text(\"held\")") }.count, 1,
                       "#500's held word is gone")
        XCTAssertTrue(lines.contains { $0.contains("reading.isMeasured") && $0.contains("\"—\"") }
                      || lines.contains { $0.contains(": \"—\"") },
                      "#498's em dash for an unmeasured channel is gone")
    }

    // MARK: - 6  the two sentences above the rows (#643) — END-TO-END

    /// 6a/6b — REGRESSION, and the strong kind (§1): both sentences are pure `static func`s on a
    /// public enum, so this drives them and reads what a player would see. Until #643 both said
    /// "Four body channels shape the instrument's own timbre while a session runs" over rows
    /// that had marked themselves "Demo" since #635b — a present-tense claim about a current
    /// reading, false whenever the demo generator drives, on the two surfaces that make the
    /// promise most plainly.
    ///
    /// ⚠️ THE COUNTERWEIGHT IS THE INTERESTING HALF, and it is why this is not four assertions.
    /// Only the SUBJECT is allowed to differ: the channel list, the tail and each surface's
    /// deictic half ("these routes" / "open Effects › All parameters") must be byte-identical
    /// across the two branches, or a copy edit lands in one branch and a player sees a different
    /// sentence depending on which source happens to be running. Asserting the shared SUFFIX
    /// pins that without re-spelling it here (#416).
    func testBothAlwaysOnSentencesNameWhoseChannelsTheyAre() {
        for (label, real, demo) in [
            ("FX footer",
             AlwaysOnBioChannel.alwaysOnSentence(synthetic: false),
             AlwaysOnBioChannel.alwaysOnSentence(synthetic: true)),
            ("Bio panel",
             AlwaysOnBioChannel.bioPanelSentence(synthetic: false),
             AlwaysOnBioChannel.bioPanelSentence(synthetic: true)),
        ] {
            XCTAssertTrue(real.contains("body channels"), """
                \(label): the measured-source wording no longer says whose channels these are. \
                This slice adds a second subject for one case; it does not rewrite the sentence.
                """)
            XCTAssertFalse(real.contains("simulated demo"), """
                \(label): a REAL body is being told it is the demo generator. That is the \
                over-correction this family has already had to retract twice — marking is only \
                honest when it is conditional.
                """)
            XCTAssertTrue(demo.contains("simulated demo") && demo.contains("not your body"), """
                \(label): while the demo generator drives, the sentence still claims the \
                player's body. Every row beneath it says "Demo"; the sentence above them is the \
                half a scanning reader takes.
                """)
            // Only the subject differs — everything from the shared tail on must match.
            let tail = "the instrument's own timbre while a session runs: coherence, HRV, "
            XCTAssertTrue(real.contains(tail) && demo.contains(tail), """
                \(label): the two branches diverge before the channel list. Only the SUBJECT may \
                differ — a player must not read a different sentence depending on which source \
                is running, and the four channel names have exactly one spelling (#416).
                """)
        }
    }
}
