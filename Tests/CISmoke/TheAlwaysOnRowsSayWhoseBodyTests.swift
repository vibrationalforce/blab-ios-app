// TheAlwaysOnRowsSayWhoseBodyTests.swift
// Echoel — #634: the always-on channel rows printed the demo generator as a measured body,
// in the Bio panel, a few dozen lines under a strip that already said "Demo".
//
// WHAT THIS GUARDS. `AlwaysOnBioRow` renders four bio channels — coherence, HRV, heart rate,
// breath phase — as a two-decimal value plus a filled accent bar, and tells VoiceOver
// "Coherence at 62 percent, shaping …". Two reachable hosts: `AlwaysOnBioPanelStrip` in
// `bioPanel` (Bio chip) and `AlwaysOnBioView` in the FX "All parameters" sheet.
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
//   · **`BioModContributionRow` — RENDERING, and it is in the SAME SHEET, one `Section` ABOVE
//     the rows this slice just marked** (`EchoelFXView`: `BioModLiveView` then
//     `AlwaysOnBioView`). It draws a signed offset and speaks "…moving <target>, N percent",
//     and `BioModContribution` carries `measured` and NO origin field at all. Its producer
//     reads `usableBio()`, which admits `.fallback`. So one sheet, one frame, two provenance
//     stories about forty points apart. Next slice.
//   · **`BioMetricInfoView` is HALF marked and is on this family's "already marks" list** —
//     #627b put "demo values, not your body" in the SECTION HEADER, but each mapping row is
//     its own accessibility element whose label ends "Currently N percent." with no prefix,
//     and its `liveBar` fills a demo value in full `EchoelTheme.accent` — the exact over-claim
//     claim 5 above removes from this row. A VoiceOver user rotoring through rows never hears
//     the header.
//   · **`AlwaysOnBioChannel.soundPanelSentence`: "Your body also shapes this sound…"** —
//     possessive, second person, rendered in the Sound panel. Stronger than the `bioPanelSentence`
//     the first version of this list named, and it was missing.
//   · `bioPanelSentence`, `alwaysOnSentence` and `EchoelFXView.stopsArrivingNote` — the same
//     noun ("body") in three more places. All four collapse into ONE edit by changing the
//     noun rather than adding a condition; a condition here would put a live bio read into a
//     property `EchoelStudioView.body` evaluates (the 10.76.41/50 freeze law).
//   · Two `EchoelStudioView` captions ("your measured coherence…", "your inhale opens it") and
//     `BodyTempoField`'s unconditional `.accessibilityLabel("Tempo, driven by your body")`.
//   · OSC / ADM-OSC / Art-Net / sACN still carry no provenance (#462, second half).
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
}
