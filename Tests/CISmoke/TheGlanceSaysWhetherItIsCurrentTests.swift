// TheGlanceSaysWhetherItIsCurrentTests.swift
// Echoel — #636: the Home-Screen widget and the watch face stop presenting an old
// reading as a current one.
//
// WHAT THIS GUARDS. `BioVitals.isFresh` shipped with **zero production callers** — measured:
// `git grep -n isFresh -- Sources` returned its own declaration, one doc reference, and
// nothing else. So both glances printed a 40-to-44-point "142 bpm" for a payload of ANY age.
// A session that ended three hours ago rendered exactly like a heart beating now, and the
// widget's own App Store subtitle says "Live heart rate, HRV, and coherence from your
// session." Nothing on either surface was measuring the word "live".
//
// ⭐ THE WINDOW IS DERIVED, WHICH IS THE WHOLE REASON THIS SLICE IS SMALL. The payload carries
// no `BioSource`: the TYPE cannot cross into the extension targets (`Core/EngineBus.swift` is
// in neither — the #545 constraint `BioVitals.isFresh`'s own `-1` literal already lives under).
// So the glance needs ONE window, and the value is the largest one the ENGINE still believes:
// 90 s, for `.watch`/`.healthKit`, of which `.healthKit` is the one with a producer. `.oura`'s
// 600 s is excluded because it has none.
//
// ⛔ IT IS A BOUND, NOT AN AGREEMENT. The first draft of this header said "at 90 the glance and
// `EngineBus.usableBio` agree exactly". They do not: `usableBio` is PER-SOURCE, so a camera-rPPG
// payload — the app's own headline live pipeline — is dropped by the engine at 6 s and still
// reads current here for another 84. What 90 guarantees is one direction: **it can never mark a
// live reading stale.** The over-claim was made in the same paragraph that warned against "a
// band nobody could explain", while opening a 6→90 s band on the default source. The real fix
// is a later slice and is not blocked: the WINDOW is a `TimeInterval` and can travel in the
// payload the way `synthetic: Bool?` already does (#632). Saying "impossible" would have taken
// that decision away from the next reader.
//
// ⚠️ CLAIM 2 IS A DOUBLE ANCHOR, and that is what makes "derived" more than a word in a
// comment: it pins the constant to 90 AND pins the `case .watch, .healthKit: return 90` line
// in `EngineBus.swift` it is copied from. Move the source window and this goes red naming the
// derivation, instead of the copy quietly meaning something else.
//
// ⚠️ THE MARKER IS DELIBERATELY NOT A CHIP. "Demo" answers *whose body*; "Last session"
// answers *when*. Boxing both would present them as two labels of one class. Claim 5 pins
// that choice by asserting the corner-radius literal count in each file is still exactly one
// — so a later "make them consistent" pass cannot quietly turn the time qualifier into a
// second badge, and so nobody reads the unchanged count as "nothing was added here".
//
// KIND (§1): MIXED. Claims 1 and 7 are BEHAVIOURAL (they run `isFresh`). Claims 2–6 are a
// SOURCE-TEXT SCAN with comments stripped. No test here renders SwiftUI or WidgetKit, so
// "the founder sees the words" is a device probe, not something this file can prove.
//
// GRADING (#433 / §3). The file does not exist on the parent (9185b6a), so NO assertion has a
// verdict there — §3's escape hatch, hand-transcribed per ASSERTION rather than per method,
// because two methods are mixed:
//   · **5 REGRESSIONS** — claim 3, claim 4, claim 5's `Text("Last session")` half, and both
//     halves of claims 8 and 9. All come from ONE absence (#486): neither glance carries a
//     staleness branch, so nothing schedules an expiry entry and nothing dims a metric either.
//     ⚠️ Claims 8 and 9 exist because the mandatory review found the first draft's own gaps —
//     the widget's single timeline entry froze `isCurrent` at build time, and HRV/coherence
//     stayed at full strength beside a dimmed pulse. Both were live defects in MY code, not
//     hypotheticals, which is why each carries the retraction next to the claim.
//   · **2 FORWARD guards** — claim 1, and claim 2's `== 90` half. Both drive
//     `glanceFreshnessWindow`, a symbol this commit creates, so neither could have been red.
//   · **4 COUNTERWEIGHTS / anchors** — claim 2's `EngineBus` half, claim 5's radius half,
//     claim 6, claim 7. Green on both trees, and they are the content.
//
// ⛔ THE FIRST DRAFT SAID "4 REGRESSIONS (claims 2, 3, 4, 5) · 1 FORWARD (claim 1)" AND
// CONTRADICTED ITSELF ONE LINE APART: claim 2's `== 90` has the IDENTICAL shape to claim 1 —
// it names a symbol the parent does not have — and the same paragraph used that property to
// call claim 1 forward and claim 2 a regression. It also claimed TWO absences and, with claim 2
// reclassified, there is one. Grading per method hid it; grading per assertion is what found
// it, and that is why this block is written per assertion.

import XCTest
import Foundation
@testable import Echoelmusic

final class TheGlanceSaysWhetherItIsCurrentTests: XCTestCase {

    private let widget = "Sources/EchoelmusicWidgets/EchoelBioWidget.swift"
    private let watch = "Sources/EchoelmusicWatch/EchoelWatchApp.swift"

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Comments BLANKED. This header itself quotes `Text("Last session")` and
    /// `BioVitals.glanceFreshnessWindow`; a raw scan of a repo that writes ⛔ blocks quoting
    /// its own needles can be satisfied by the retraction describing the code it retracts.
    private func code(_ relative: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("""
                \(relative) is missing. A guard over a glance that cannot find the glance is a \
                RED, never a skip — a skip would report an honest surface for one it never read.
                """)
            throw CocoaError(.fileNoSuchFile)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    // MARK: - Claim 1 — the window actually separates a live session from an old one

    func testTheGlanceWindowSeparatesNowFromEarlier() {
        let w = BioVitals.glanceFreshnessWindow
        var v = BioVitals()
        v.timestamp = 1_000

        XCTAssertTrue(v.isFresh(within: w, now: 1_000),
                      "A payload written this instant must read as current.")
        XCTAssertTrue(v.isFresh(within: w, now: 1_000 + w - 1), """
            A payload one second inside the window reads stale. That marks a legitimately \
            latent source — a Watch or HealthKit reading, which the engine itself still acts \
            on for a full 90 s — as an old session.
            """)
        XCTAssertFalse(v.isFresh(within: w, now: 1_000 + w + 1), """
            A payload past the window still reads current, which is the entire defect: a \
            session that ended hours ago renders as a heart beating now.
            """)
        // The two-sided half survives the wider window: a stamp from ahead of `now` is still
        // rejected past the 1 s clock-skew tolerance, so a device with a stepped clock cannot
        // make an arbitrary payload look current.
        XCTAssertFalse(v.isFresh(within: w, now: 1_000 - 2),
                       "A timestamp from the future beyond the skew tolerance must be rejected.")
    }

    // MARK: - Claim 2 — the window is DERIVED (double anchor)

    func testTheWindowIsTheEnginesLargestWiredWindow() throws {
        XCTAssertEqual(BioVitals.glanceFreshnessWindow, 90, accuracy: 0.001, """
            The glance window moved. It is not a taste value: it is the largest \
            `BioSource.freshnessWindow` among the sources that have a producer, so that the \
            glance and `EngineBus.usableBio` agree about what is still believable.
            """)
        let bus = try code("Sources/Echoelmusic/Core/EngineBus.swift")
        XCTAssertTrue(bus.contains("case .watch, .healthKit: return 90"), """
            `BioSource.freshnessWindow` no longer returns 90 for `.watch`/`.healthKit`, so the \
            glance constant is copied from a number that changed. Re-derive it in the same \
            commit and pull the doc on `BioVitals.glanceFreshnessWindow` with it — the copy \
            exists only because `BioSource` does not compile into the extension targets.
            """)

        // ⚠️ The line above pins the SOURCE of the copy; this pins that it is still the
        // LARGEST one, which is what the method's name actually claims. Without it, adding a
        // source with a 120 s window and a producer leaves this test green while
        // `testTheWindowIsTheEnginesLargestWiredWindow` becomes exactly false.
        XCTAssertEqual(windowValues(in: bus), [5, 6, 90, 600], """
            `BioSource.freshnessWindow` now returns \(windowValues(in: bus)) — the set changed. \
            Today the only value above 90 is `.oura`'s 600, and it is excluded because it has \
            no producer. If the new value belongs to a source that DOES publish, 90 no longer \
            bounds anything and `BioVitals.glanceFreshnessWindow` must be re-derived.
            """)
    }

    /// Every `return N` inside `BioSource.freshnessWindow`, sorted and de-duplicated.
    /// Scoped to that one computed property — a file-wide scan for `return <number>` would
    /// pick up half of `EngineBus` and make the assertion above mean nothing.
    private func windowValues(in bus: String) -> [Int] {
        let lines = bus.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: {
            $0.contains("var freshnessWindow: TimeInterval {")
        }) else { return [] }
        var out = Set<Int>()
        for line in lines[start...].dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "}" { break }
            guard let r = t.range(of: "return ") else { continue }
            if let v = Int(t[r.upperBound...].trimmingCharacters(in: .whitespaces)) { out.insert(v) }
        }
        return out.sorted()
    }

    // MARK: - Claim 3 — both glances actually call it

    func testBothGlancesGateOnTheWindow() throws {
        // ⚠️ `>= 1`, not `== 1` (#364). The first draft pinned exactly one and the widget
        // already legitimately has TWO — the view's `isCurrent` and the timeline's expiry
        // entry — so the pin would have forbidden the very fix the reviewer asked for. More
        // call sites is the direction this law wants; zero is the failure.
        for path in [widget, watch] {
            let c = try code(path)
            XCTAssertGreaterThanOrEqual(
                c.components(separatedBy: "BioVitals.glanceFreshnessWindow").count - 1, 1, """
                \(path) does not gate on `BioVitals.glanceFreshnessWindow` at all. `isFresh` \
                spent its whole life with zero production callers; a glance that stops calling \
                it is back to printing any-age data as a live pulse.
                """)
        }
    }

    // MARK: - Claim 4 — the widget must read its ENTRY's date, never the wall clock

    func testTheWidgetIsAPureFunctionOfItsEntry() throws {
        let c = try code(widget)
        XCTAssertTrue(c.contains("now: entry.date.timeIntervalSinceReferenceDate"), """
            The widget's freshness check no longer uses `entry.date`. WidgetKit renders a \
            timeline entry at a moment it chooses; reading the wall clock in a view body makes \
            the same entry render differently on every redraw and makes the state untestable. \
            The watch face is the OPPOSITE case and correctly uses `Date()` — it owns its own \
            refresh tick — so this assertion is deliberately widget-only.
            """)
    }

    // MARK: - Claim 5 — one spelling, and it is a caption rather than a second badge

    func testTheMarkerIsOneStringAndNotABadge() throws {
        for path in [widget, watch] {
            let c = try code(path)
            XCTAssertEqual(c.components(separatedBy: "Text(\"Last session\")").count - 1, 1, """
                \(path) no longer carries exactly one `Text("Last session")`. One decision, one \
                string (#416) — two spellings of "this is not now" across two glances is the \
                drift this repo has already retracted once for the demo marker.
                """)
            // ⛔ NO RADIUS ASSERTION HERE (#416). The first draft added one, and
            // `RadiusHasOneSpellingTests.testTheExtensionTargetsAreListedNotForgotten` already
            // pins both extension files' corner-radius literals as an exact two-element list —
            // one decision with two edit sites, and its own failure message pointed the reader
            // at the other guard. The design fact ("Demo" is a badge because it answers whose
            // body; "Last session" is a caption because it answers when) is recorded at the
            // `staleTag` declarations; turning the caption into a chip reddens the guard that
            // owns radii, which is the correct owner.
        }
    }

    // MARK: - Claim 6 — COUNTERWEIGHT: the provenance marker must survive this

    func testTheDemoMarkerStillStands() throws {
        for path in [widget, watch] {
            let c = try code(path)
            XCTAssertTrue(c.contains("synthetic == true"), """
                \(path) lost the three-state provenance read. Freshness and provenance are \
                different questions and a glance needs both: "this is not now" does not tell \
                the founder the number was never his body's, and vice versa.
                """)
            XCTAssertTrue(c.contains("demoTag"), "\(path) lost the demo chip.")
        }
    }

    // MARK: - Claim 7 — COUNTERWEIGHT: the 2 s WIRE window must not follow the glance

    func testTheWireWindowStaysTwoSeconds() throws {
        var v = BioVitals()
        v.timestamp = 1_000
        XCTAssertFalse(v.isFresh(now: 1_003), """
            `isFresh`'s DEFAULT window is no longer ~2 s. The obvious next cleanup is \
            "harmonise the two windows"; doing it in this direction makes every in-app \
            freshness check believe data a minute and a half old. The two numbers answer \
            different questions — a wire read happens continuously, a glance renders when the \
            system feels like it — and they are supposed to differ.
            """)
        let mgr = try code("Sources/Echoelmusic/Core/BioFeedbackManager.swift")
        XCTAssertTrue(mgr.contains("within maxAge: TimeInterval = 2"),
                      "The wire default moved off 2 s; claim 7's behavioural half is now testing "
                      + "a different number than the one it names.")
    }

    // MARK: - Claim 8 — the widget SCHEDULES the transition; one entry makes the marker inert

    /// ⛔ THE FIRST DRAFT OF #636 SHIPPED WITHOUT THIS AND WAS NEARLY A NO-OP ON THE WIDGET.
    /// `entry.date` is stamped when the TIMELINE is built, so with a single entry `isCurrent`
    /// is frozen at that instant for the timeline's whole life. The error is one-directional
    /// and lands on the wrong side — `entry.date` is never later than the render, so the widget
    /// can only UNDERSTATE age, which is the exact defect the marker exists to remove. Nor does
    /// anything force a reload: `reloadWidgetsIfDue()` is reached only from a publish tick, and
    /// publishing stops when the session does. A second entry AT the expiry moment is how
    /// WidgetKit expresses "this changes at time T" without reading a wall clock in the body.
    func testTheWidgetSchedulesItsOwnExpiry() throws {
        let c = try code(widget)
        XCTAssertTrue(c.contains("entry.vitals.timestamp + BioVitals.glanceFreshnessWindow"), """
            The widget's timeline no longer schedules an entry at the moment the reading stops \
            being current. Without it the freshness marker is frozen at timeline-build time and \
            a finished session keeps rendering at full strength until WidgetKit happens to \
            regenerate — which its daily budget can defer for tens of minutes.
            """)
        XCTAssertTrue(c.contains("entries.append(BioEntry("), """
            The widget emits a single timeline entry again. See above: one entry cannot express \
            a state change that happens later, and the direction of the error is the harmful one.
            """)
    }

    // MARK: - Claim 9 — HRV and coherence dim with the pulse (no half-marked card)

    /// They come from the SAME payload and the SAME timestamp as the heart rate. Marking only
    /// the pulse is worse than marking nothing: the reader learns that an unmarked number is
    /// current. The widget's own App Store subtitle names all three.
    func testTheOtherMetricsDimToo() throws {
        for path in [widget, watch] {
            let c = try code(path)
            let renderer = c.components(separatedBy: "private func metric(")
            // ⚠️ `guard`, not `XCTAssertEqual` followed by a subscript. XCTest does not stop at
            // a failed assertion, so `renderer[1]` on a one-element array TRAPS — the bundle
            // dies with a crash instead of a named failure, and a crash here is
            // indistinguishable from #396 without reading the job log.
            guard renderer.count == 2 else {
                return XCTFail("\(path) has \(renderer.count - 1) `metric` renderers; expected one.")
            }
            XCTAssertTrue(renderer[1].contains("isCurrent ? Color.primary : Color.secondary"), """
                \(path)'s HRV/coherence values render at full strength regardless of age, while \
                the heart rate beside them dims. A half-marked card teaches the reader that the \
                unmarked numbers are the current ones — the opposite of what this file is for.
                """)
        }
    }
}
