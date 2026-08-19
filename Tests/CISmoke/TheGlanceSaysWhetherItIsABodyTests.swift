// TheGlanceSaysWhetherItIsABodyTests.swift
// Echoel — #632: the fourth chamber of the #627 law. The Home-Screen widget and the Watch
// glance print heart rate, HRV and coherence as a measurement. Nothing in the payload they
// read said whether a body produced them.
//
// WHAT THIS GUARDS. `BioFeedbackPublisher.publishTick()` takes the bus's freshest USABLE
// frame — which INCLUDES `.fallback`, the "Simulation" entry in the Pulse source dropdown —
// maps it through `vitals(from:)` into `BioVitals`, and writes it to the App Group. Two
// first-party surfaces read that payload and render it big:
//
//   · `EchoelBioWidget` (`EchoelmusicWidgets`), on the Home and Lock Screen, where it is
//     glanceable with the app closed and no context at all around it.
//   · `WatchBioView` (`EchoelmusicWatch`).
//
// `BioVitals` carried `egressAllowed` and no provenance. That bit is NOT a substitute and
// the confusion is the trap this file exists to nail shut: `BioEgressPolicy.allowsEgress`
// returns **true** for `.fallback` — correctly, because a demo walk is nobody's pulse and
// therefore cannot leak one. So the one flag that did travel says "safe to show" and reads,
// to anyone skimming, like "measured". The provenance has to travel separately.
//
// ⛔ WHY `Bool?` AND NOT `Bool`. `egressAllowed` fails CLOSED: absent ⇒ `false` ⇒ refuse.
// This field has no safe `false`. Reading silence as "measured" prints a demo pulse as the
// user's; reading it as "demo" brands a real reading fake. A payload written by a build
// older than #632 has no such key, so it decodes to `nil` and both surfaces leave it
// unmarked — the status quo, not a new claim. Same three-state encoding as
// `ColabPayload.BioPeek.synthetic` (#629), for the same reason, one convention for
// cross-process provenance.
//
// ⛔ AND IT CANNOT BE A `BioSource`. `Core/BioFeedbackManager.swift` is compiled STANDALONE
// into `EchoelmusicWidgets` and `EchoelmusicWatch` (`project.yml` lists the single path
// under both); `Core/EngineBus.swift` is in neither, so `BioSource` does not exist there.
// The same structural fact that forces `isFresh` to keep a literal skew tolerance forces
// this field to be a plain optional. The source is read exactly once, app-side, in
// `BioFeedbackPublisher.vitals(from:)`.
//
// KIND (§1): claims 1–5 are **END-TO-END BEHAVIOUR** — `BioVitals` is a public Foundation-only
// value type and `vitals(from:)` is a public nonisolated static pure mapping, so this bundle
// drives the payload and the producer for real. Claims 6–10 are SOURCE-TEXT SCANS: both
// renderers are SwiftUI leaves in targets this bundle cannot instantiate. That the founder
// SEES "Demo" on the Home Screen is a DEVICE PROBE and stays open.
//
// ⚠️ THE WATCH SURFACE IS UNREACHABLE TODAY and this file does not pretend otherwise. The
// watch target is not embedded (`project.yml` keeps `- target: EchoelmusicWatch` commented
// out under the app's dependencies) and there is no transport between wrist and phone at
// all (#549 — an App Group container is per DEVICE). Claim 9 pins the marker anyway,
// because the day the transport lands is the day nobody will re-derive this law.
//
// GRADING (#433 / §3), measured against the parent (3372f74), both trees, raw and stripped:
//   · This file does not COMPILE against the parent: `BioVitals.synthetic` does not exist
//     there, so claims 1–5 name a symbol that is absent. Per §3 that is **one absence**
//     (#486), not five findings, and no assertion in this file has a verdict on the parent
//     tree. It is hand-transcribed instead (§0) — see the Python note in the commit body.
//     Explicitly NOT "green against its own tree" dressed up as gradable (#488).
//   · claims 6, 7 and 9 are REGRESSIONS by transcription: the needles `demoTag` and
//     `isDemo` occur ZERO times in both renderer files on the parent, and the parent's
//     rendered behaviour is exactly what this file's name denies.
//   · claim 11 is MIXED by construction: three of its five files marked already (#627/#629)
//     and two are this slice's, so its per-file assertions are 3 COUNTERWEIGHTS and 2
//     REGRESSIONS, and its total assertion is a REGRESSION (3 on the parent, 5 here).
//   · claim 8 is a COUNTERWEIGHT (2 and 2 on both trees) — it pins that `hrvText` and
//     `coherenceText` still treat 0 as "not measured" and print "—". That rule predates
//     this slice; the cheap way to "fix" an unmarked demo is to blank the numbers instead
//     of marking them, which would destroy the honest-zero rule and mark nothing.
//   · claim 10 is MIXED and is written down per assertion rather than averaged, because the
//     first draft of this paragraph called it one counterweight and the transcription said
//     otherwise: 10a (`egressAllowed` still decodes `?? false`) is a COUNTERWEIGHT, 1 and 1;
//     10c (the provenance decode carries no default) is a COUNTERWEIGHT, 0 and 0; 10b (that
//     decode line exists at all) is a REGRESSION, 0 → 1. The obvious tidy-up after this slice
//     is to "harmonise" the two flags into one shape; doing it in the direction that reads
//     tidier turns the fail-closed neighbour into a fail-open one.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH**: all
// **eleven** source needles count identically raw and stripped on both trees, because no
// comment added by this slice spells one in its code form. It stays because the next comment
// written near these branches is the one that would flip it. (⛔ #632b: this said "ten" and
// "claims 6–10" while claim 11 was already in the file — the grading paragraph WAS updated
// for it and these two lines were not. A count and a range are two places, and a slice that
// adds an assertion has to move both.)
//
// ⚠️ #364: a DIFFERENT marking is not forbidden — a widget that writes "Demo" into the "HR"
// label itself, or a distinct numeral style, would satisfy the law and turn claims 6/7/9
// red. That is the moment to rewrite this file. What is forbidden silently is a synthetic
// payload reaching either glance with nothing that says so.
//
// ⚠️ STILL OPEN after this slice, named so no session concludes the family is closed:
//   · **OSC / ADM-OSC / Art-Net / sACN** — `/echoelmusic/bio/*` carries no provenance, so an
//     integrator cannot tell a demo walk from a measured pulse. Named by #627 and #629 too.
//   · ⛔ **AN AUv3 ITEM STOOD HERE AND THE TARGET DOES NOT EXIST.** It read "the AUv3's
//     host-visible AUParameters (`pullSharedVitals`) now receive a payload that KNOWS".
//     `project.yml` declares five targets and records the removal at 2026-07-24;
//     `git grep -n pullSharedVitals -- Sources` returns TWO COMMENTS AND NO CODE. Nothing
//     "now receives" anything. Booking a phantom into the STILL-OPEN list of a brand-new
//     guard is the expensive kind of stale — it is the line a future session triages from,
//     so it costs a budgeted slice for a surface that cannot be built. Both reviewers found
//     it independently, which is how a phantom this fresh gets caught at all.
//   · **`AlwaysOnBioRow` (#633, the next slice)** — four bio channels rendered as decimals
//     plus filled bars, in `bioPanel` a few dozen lines UNDER the marked `BioStripView` and
//     directly beneath the sentence "Four body channels shape the instrument's own timbre".
//     It reads `frame.source` only for the freshness window, never for provenance, and the
//     simulator satisfies every `isMeasured` gate. Second host: the FX "All parameters" sheet.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGlanceSaysWhetherItIsABodyTests: XCTestCase {

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

    private let widget = "Sources/EchoelmusicWidgets/EchoelBioWidget.swift"
    private let watch = "Sources/EchoelmusicWatch/EchoelWatchApp.swift"

    private func frame(_ source: BioSource, bpm: Float = 64) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000, heartRateBPM: bpm, hrvNormalized: 0.4,
                       breathRate: 6, breathPhase: 0.25, coherence: 0.6,
                       motionEnergy: 0, source: source)
    }

    // MARK: - 1–5  END-TO-END BEHAVIOUR (the payload and its producer)

    /// 1. The demo source is what sets the flag, and a measured one clears it.
    func testTheProducerReadsTheFrameSource() {
        XCTAssertEqual(BioFeedbackPublisher.vitals(from: frame(.fallback)).synthetic, true,
                       "a .fallback frame must reach the glance marked as the demo")
        XCTAssertEqual(BioFeedbackPublisher.vitals(from: frame(.cameraPPG)).synthetic, false,
                       """
                       a measured frame must be marked NOT synthetic — nil there would be a \
                       second "unknown" invented by the one place that actually knows.
                       """)
        XCTAssertEqual(BioFeedbackPublisher.vitals(from: frame(.ble)).synthetic, false)
        XCTAssertEqual(BioFeedbackPublisher.vitals(from: frame(.healthKit)).synthetic, false)
    }

    /// 2. `egressAllowed` is NOT the provenance. This is the trap in one assertion: the demo
    ///    frame is allowed OUT and is still not a body.
    func testEgressPermissionIsNotProvenance() {
        let demo = BioFeedbackPublisher.vitals(from: frame(.fallback))
        XCTAssertTrue(demo.egressAllowed,
                      """
                      a demo walk is nobody's pulse, so it may egress — this is correct, and it \
                      is precisely why the flag cannot double as "measured".
                      """)
        XCTAssertEqual(demo.synthetic, true)
        let health = BioFeedbackPublisher.vitals(from: frame(.healthKit))
        XCTAssertFalse(health.egressAllowed, "5.1.3: HealthKit-store data never egresses")
        XCTAssertEqual(health.synthetic, false, "…and it is still a real body")
    }

    /// 3. Round-trips through the App Group's JSON encoding, both states.
    func testTheFlagSurvivesTheAppGroupEncoding() throws {
        for value in [true, false] {
            let sent = BioVitals(heartRateBPM: 70, timestamp: 5, synthetic: value)
            let back = try JSONDecoder().decode(BioVitals.self, from: JSONEncoder().encode(sent))
            XCTAssertEqual(back.synthetic, value,
                           """
                           the flag must cross the process boundary — the reader is a different \
                           target and has nothing else to go on.
                           """)
        }
    }

    /// 4. A payload written before this field existed decodes to nil, NOT false. Non-destructive
    ///    migration (`decodeIfPresent`), and the three-state semantics in one assertion.
    func testAnOlderPayloadDecodesToUnknownNotToMeasured() throws {
        let v1 = #"{"heartRateBPM":72,"hrvNormalized":0.3,"breathPhase":0,"coherence":0.5,"timestamp":9}"#
        let back = try JSONDecoder().decode(BioVitals.self, from: Data(v1.utf8))
        XCTAssertNil(back.synthetic,
                     """
                     absent must mean UNKNOWN. Defaulting to false would print an old build's \
                     demo payload as measured; defaulting to true would brand an old build's \
                     real reading fake. Neither direction is safe.
                     """)
        XCTAssertEqual(back.heartRateBPM, 72, "the rest of the v1 payload must still decode")
    }

    /// 5. A nil flag is OMITTED, so a reader older than this field is unaffected.
    func testAnUnsetFlagIsNotWritten() throws {
        let data = try JSONEncoder().encode(BioVitals(heartRateBPM: 60, timestamp: 1))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("synthetic"),
                       """
                       an unset optional must not be written as null — a reader that does \
                       `decodeIfPresent` would then see a present key with no value.
                       """)
        XCTAssertTrue(json.contains("egressAllowed"), "the neighbouring flag is still written")
    }

    // MARK: - 6–9  SOURCE-TEXT SCANS (the two renderers)

    /// 6. The widget marks it, in BOTH families — the small one is the tight layout and is
    ///    the one a "make it fit" edit drops first.
    func testTheWidgetMarksItInBothFamilies() throws {
        let lines = try codeLines(widget)
        XCTAssertEqual(lines.filter { $0.contains("if isDemo { demoTag }") }.count, 2, """
            the Home-Screen widget must render the marker in the small AND the medium \
            layout — both print a heart rate as a measurement.
            """)
        XCTAssertEqual(lines.filter { $0.contains("private var demoTag: some View") }.count, 1)
    }

    /// 7. Three-state at the READ site too. `entry.vitals.synthetic == true` and nothing else:
    ///    a `?? false` here would be indistinguishable in a diff and would silently re-fold
    ///    "unknown" into "measured", undoing claim 4 at the only place it is observed.
    func testTheWidgetReadsTheFlagAsThreeState() throws {
        let lines = try codeLines(widget)
        let reads = lines.filter { $0.contains("entry.vitals.synthetic") }
        XCTAssertEqual(reads.count, 1, "one read site, so this assertion measures all of them")
        XCTAssertTrue(reads.first?.contains("== true") ?? false, """
            the widget must mark ONLY on an explicit true. `synthetic ?? false` reads the \
            same and means "an old payload's demo values are measured".
            """)
    }

    /// 8. COUNTERWEIGHT. The honest-zero rule stays: 0 means "not measured" and prints "—".
    ///    Blanking the numbers is the cheap alternative to marking them, and it destroys this.
    func testTheHonestZeroRuleSurvives() throws {
        for file in [widget, watch] {
            let lines = try codeLines(file)
            let dashes = lines.filter { $0.contains("> 0 ?") && $0.contains("\"—\"") }
            XCTAssertEqual(dashes.count, 2, """
                \(file): HRV and coherence must still render "—" when they were not \
                measured. Marking the demo must not become an excuse to blank real zeros.
                """)
        }
    }

    /// 9. The Watch marks it too — pinned although the surface is unreachable today (#549).
    func testTheWatchMarksItAsWell() throws {
        let lines = try codeLines(watch)
        XCTAssertEqual(lines.filter { $0.contains("if isDemo { demoTag }") }.count, 1)
        let reads = lines.filter { $0.contains("vitals.synthetic") }
        XCTAssertEqual(reads.count, 1)
        XCTAssertTrue(reads.first?.contains("== true") ?? false,
                      "same three-state read as the widget — one law, two surfaces")
    }

    /// 10. COUNTERWEIGHT. The fail-closed neighbour must not be "harmonised" into an optional.
    func testTheEgressFlagStillFailsClosed() throws {
        let lines = try codeLines("Sources/Echoelmusic/Core/BioFeedbackManager.swift")
        let egress = lines.filter {
            $0.contains("decodeIfPresent(Bool.self, forKey: .egressAllowed)")
        }
        XCTAssertEqual(egress.count, 1)
        XCTAssertTrue(egress.first?.contains("?? false") ?? false, """
            `egressAllowed` must keep defaulting to false. The two flags look alike and the \
            obvious tidy-up is to give them one shape; doing it in THIS direction turns a \
            5.1.3 fail-closed guard into a fail-open one.
            """)
        let prov = lines.filter { $0.contains("decodeIfPresent(Bool.self, forKey: .synthetic)") }
        XCTAssertEqual(prov.count, 1)
        XCTAssertFalse(prov.first?.contains("??") ?? true, """
            …and the provenance flag must keep NO default, for the mirror reason.
            """)
    }

    /// 11. The RENDERER COUNT, because this slice falsified prose in two files that this
    ///     bundle cannot scan negatively. `Bio/BioSimulator.swift` and `EchoelmusicApp.swift`
    ///     each carried "there is no user-facing \"Demo\" string in `Sources/`" — true when
    ///     written, false since #627, and two renderers *more* false since #632. Both are
    ///     corrected in the same commit.
    ///
    ///     ⚠️ A NEGATIVE SCAN IS THE WRONG SHAPE HERE and that is why this is a count: those
    ///     two files now QUOTE the retracted sentence in order to retract it, so a guard
    ///     forbidding the phrase would fail on its own correction — the #491 collision, in a
    ///     source file instead of CLAUDE.md.
    ///
    ///     ⚠️ `>=` and not `==` (#364): a SIXTH surface that learns to mark its demo is
    ///     exactly the work this law wants, and an equality test would paint it red. What
    ///     this catches is a renderer LOSING its marker.
    func testEveryMarkedSurfaceStillMarks() throws {
        var total = 0
        for file in [widget, watch,
                     "Sources/Echoelmusic/Studio/BioStripView.swift",
                     "Sources/Echoelmusic/Studio/HeaderMonitors.swift",
                     "Sources/Echoelmusic/Studio/LiveColaboView.swift"] {
            // ⚠️ EXISTENCE FIRST, and this is not ceremony. `codeLines` throws `XCTSkip`
            // when a file is absent, so deleting a renderer would turn every assertion
            // over it GREEN — the failure mode the 2026-08-19 audit found in dozens of
            // guards in this bundle. For a law whose whole subject is "this surface must
            // still say something", a silent skip is the one verdict that must not exist.
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: sourceRoot().appendingPathComponent(file).path),
                "\(file) is gone — this law's guard must go RED on that, never quietly skip")
            let hits = try codeLines(file).filter { $0.contains("Text(\"Demo\")") }.count
            XCTAssertGreaterThanOrEqual(hits, 1, """
                \(file) rendered the demo marker and no longer does. If that removal is \
                deliberate, the prose in `Bio/BioSimulator.swift` and `EchoelmusicApp.swift` \
                has to move in the SAME commit — both files describe how many surfaces mark.
                """)
            total += hits
        }
        XCTAssertGreaterThanOrEqual(total, 5, """
            five surfaces mark synthetic vitals as of #632 — bio strip, header pill, \
            Live-Colabo rows, Home-Screen widget, Watch glance. Fewer means one went quiet.
            """)
    }
}
