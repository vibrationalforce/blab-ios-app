// TheFXRoutesSayWhoseBodyTests.swift
// Echoel — #635b: the FX "Live — body → sound" rows join the source-honesty law.
//
// WHAT THIS GUARDS. `BioModContributionRow` already knew one thing about its number —
// whether the body REPORTED that carrier (`measured`, rendered as "—" and "not measured").
// It did not know the other: whether the body was a body. The demo source reports every
// channel, so a simulated frame arrives `measured: true` and the row drew a confident signed
// offset and a FULL-STRENGTH accent bar that nothing on screen told apart from a real pulse.
// This is the seventh rendering surface to take the marker; the six before it are the bio
// strip, the header pill, the always-on channel rows, the Live-Colabo rows (and their wire
// payload), the Home-Screen widget and the watch glance.
//
// ⚠️ TWO EXCLUSIONS ARE THE POINT, NOT AN OVERSIGHT, and claims 4 and 5 are them:
//   · an **LFO** carrier is a real oscillator on its own clock. The bio source running in
//     demo does not make it simulated, and marking it would mint a fresh false claim of
//     exactly the kind this field exists to remove.
//   · an **unmeasured** row already renders "—" and says "not measured". It asserts nothing
//     about a body, so there is nothing to qualify; a "Demo" chip over a dash is noise.
//
// ⚠️ AND THE ONE THAT MATTERS MOST IS CLAIM 3 — the direction nobody notices. Labelling a
// REAL pulse as simulated is the worse of the two failures: the demo case is a missing
// qualifier, the real case is an active lie about the founder's own body, and no gate above
// this one can see it. It is a counterweight and it is green on both trees on purpose.
//
// KIND (§1): MIXED. Claims 1–5 are BEHAVIOURAL — they run `FXModulation.contributions`, a
// pure function, so they prove the producer rather than describing it. Claims 6–8 are a
// SOURCE-TEXT SCAN over `EchoelFXView.swift` and `FXModulation.swift`: no test here renders
// SwiftUI, so "the chip is on screen" is exactly as strong as "the file contains the branch"
// and no stronger. Device-verify is what closes that gap.
//
// GRADING (#433 / §3). The file does not exist on the parent (91d25ce), so NO assertion has
// a verdict there — §3's escape hatch, hand-transcribed instead. Hand-transcribed:
// **4 REGRESSIONS (claims 1, 6, 7, 9) · 1 FORWARD guard (claim 8) · 4 COUNTERWEIGHTS
// (claims 2–5)**. Claim 9 is its own regression, not a rider on 6: its needle
// (`let origin = contribution.synthetic`) does not exist on the parent either, so it takes
// the `guard … else { XCTFail }` path rather than an assertion.
//
// ⛔ THE FIRST DRAFT BOOKED CLAIM 8 AS A REGRESSION AND WAS WRONG IN THE FLATTERING
// DIRECTION — one sentence before citing #486 about the other direction. Claim 8 is
// `XCTAssertFalse(… contains("synthetic: Bool ="))`; on the parent that string does not occur
// at all, so `contains` is false and the assertion PASSES. A negative assertion over an absent
// needle is green BECAUSE of the absence and can never be red for it. §3 has a name for this
// exact shape — a FORWARD guard, driving a symbol this commit creates — and booking it as a
// regression is the defect §3 names by name.
//
// ⛔ AND THE SAME PARAGRAPH OVER-COLLAPSED IN THE HARSH DIRECTION. It said "the three needles"
// (there are FOUR positive ones across claims 6 and 7) and folded all of them into ONE absence
// under #486. They are TWO independent absences: `BioModContribution.synthetic` does not exist
// on the parent (claims 1, 6, 7's `synthetic` needles), and the CHIP does not exist either
// (`Text("Demo")`, red for its own reason — the row simply never rendered one). #486 collapses
// repeated reports of ONE missing thing; it does not merge two.
//
// ⚠️ WHAT A RED HERE MEANS AND DOES NOT FORBID (#364). Claims 6 and 7 pin a chip and an exact
// colour pair, which is ONE way to mark provenance and not the only correct one. A source cell
// naming "Demo" instead of a chip, or a held-style opacity composition instead of a colour
// swap, would honour the law and redden this file. That is the moment to REWRITE this guard
// against the new marking — never to delete it, and never to restore the old shape to get
// green. The law is "a demo reading must not look like a body"; the needles are only today's
// spelling of it.
//
// ⚠️ ONE RESIDUE IS REGISTERED AND DELIBERATELY NOT CLOSED. `FXBioModulator` feeds
// `bus.usableBio()`, and `.fallback`'s freshness window is 5 s, so for up to five seconds
// after switching Simulation → Camera these rows still draw the last SYNTHETIC frame and mark
// it "Demo" while the camera genuinely runs. That marking is CORRECT — the row is showing that
// frame's own value — and copying `BioStripView`'s `!cameraRPPG.isRunning` term across would
// make this row lie about the number it is actually drawing. `AlwaysOnBioRow` one Section
// below behaves identically. Claim 3's message should not be read as "that direction is fully
// closed at the pixel level"; it is closed at the FRAME level, which is what this file tests.

import XCTest
import Foundation
@testable import Echoelmusic

final class TheFXRoutesSayWhoseBodyTests: XCTestCase {

    private func frame(source: BioSource, coherence: Float = 0.6) -> BioSampleFrame {
        BioSampleFrame(timestamp: 0, heartRateBPM: 60, hrvNormalized: 0,
                       breathRate: 12, breathPhase: 0, coherence: coherence,
                       motionEnergy: 0, source: source)
    }

    private func bioRoute() -> FXModRoute {
        FXModRoute(carrier: .bio(.coherence), target: .reverbMix, depth: 0.5, bipolar: false)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Comments BLANKED, line count preserved. Not the raw file: this repo writes ⛔ blocks
    /// that quote the exact tokens its guards look for — this very header quotes
    /// `Text("Demo")` — so a raw scan can be satisfied by a retraction comment describing the
    /// code it is retracting. `OneDefinitionOfCodeNotProseTests` states that hazard verbatim.
    private func source(_ relative: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("""
                \(relative) is missing. A guard on a rendering surface that cannot find the \
                surface is a RED, never a skip — a skip would report an honest screen for a \
                screen it never looked at.
                """)
            throw CocoaError(.fileNoSuchFile)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    private func codeLines(_ relative: String) throws -> [String] {
        try source(relative).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    // MARK: - Claim 1 — a demo frame marks a contributing bio route

    func testADemoFrameMarksTheRoute() {
        let out = FXModulation.contributions(routes: [bioRoute()],
                                             frame: frame(source: .fallback), now: 0)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].measured,
                      "The demo source reports coherence, so this row IS measured — that is "
                      + "precisely why `measured` alone could never have carried this.")
        XCTAssertTrue(out[0].synthetic, """
            A contributing bio route driven by a `.fallback` frame is not marked as the demo. \
            The row then draws a signed offset and a full accent bar that nothing tells apart \
            from a real pulse — the exact impression six sibling surfaces already remove.
            """)
    }

    // MARK: - Claim 2 — the value is still the value

    func testTheMarkerDoesNotChangeTheNumbers() {
        let real = FXModulation.contributions(routes: [bioRoute()],
                                              frame: frame(source: .cameraPPG), now: 0)[0]
        let demo = FXModulation.contributions(routes: [bioRoute()],
                                              frame: frame(source: .fallback), now: 0)[0]
        XCTAssertEqual(real.signal01, demo.signal01, accuracy: 1e-6)
        XCTAssertEqual(real.offset, demo.offset, accuracy: 1e-6,
                       "Provenance labels the reading; it must not silently attenuate it. A "
                       + "demo route drives the effect exactly as hard as a real one, and the "
                       + "screen says whose it is — that is the whole design.")
    }

    // MARK: - Claim 3 — a real body must NEVER be labelled the demo (the worse failure)

    func testARealBodyIsNotCalledADemo() {
        // ⚠️ These four are transcribed from `BioSource` in `Core/EngineBus.swift`, not
        // remembered: the first draft wrote `.polarH10` and `.bleHRS`, neither of which
        // exists — the strap case is spelled `.ble`. A guard that names a case the enum does
        // not have does not fail, it refuses to compile, and takes the whole bundle with it.
        let realSources: [BioSource] = [.cameraPPG, .healthKit, .ble, .watch]
        for src in realSources {
            let out = FXModulation.contributions(routes: [bioRoute()],
                                                 frame: frame(source: src), now: 0)
            XCTAssertFalse(out[0].synthetic, """
                A `.\(src)` frame is being reported as the demo signal. This is the worse of \
                the two directions and the one nothing else catches: a missing marker omits a \
                qualifier, a wrong one tells the founder his own pulse is simulated.
                """)
        }
    }

    // MARK: - Claim 4 — an LFO is never simulated, whatever the bio source is doing

    func testAnLFOCarrierIsNeverTheDemo() {
        let lfo = FXModRoute(carrier: .lfo, target: .reverbMix, depth: 0.5, bipolar: false)
        let out = FXModulation.contributions(routes: [lfo], frame: frame(source: .fallback), now: 0)
        XCTAssertFalse(out[0].synthetic, """
            An LFO route is marked as the demo because the BIO source happens to be the demo. \
            The oscillator runs on its own clock and is exactly as real either way — this is a \
            fresh false claim of the same kind the marker exists to remove.
            """)
    }

    // MARK: - Claim 5 — an unmeasured row claims nothing, so it qualifies nothing

    func testAnUnmeasuredRowIsNotMarked() {
        // `.coherence` is unmeasured at exactly 0 (`ModSource.isMeasured`), demo source or not.
        let out = FXModulation.contributions(routes: [bioRoute()],
                                             frame: frame(source: .fallback, coherence: 0), now: 0)
        XCTAssertFalse(out[0].measured)
        XCTAssertFalse(out[0].synthetic, """
            An unmeasured row is marked "Demo". It already renders "—" and says "not \
            measured", so it asserts nothing about a body — a chip there is noise on the one \
            row that was already honest.
            """)

        let none = FXModulation.contributions(routes: [bioRoute()], frame: nil, now: 0)
        XCTAssertFalse(none[0].synthetic, "With no frame at all there is no provenance to report.")
    }

    // MARK: - Claim 6 — the row actually renders the chip and dims the bar

    func testTheRowRendersTheMarker() throws {
        let fx = try source("Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertTrue(fx.contains("if contribution.synthetic {"), """
            `EchoelFXView` no longer branches on `contribution.synthetic`. The producer would \
            keep computing an honest flag that never reaches a screen — the exact shape of a \
            wired value with no door.
            """)
        XCTAssertTrue(fx.contains("contribution.synthetic ? EchoelTheme.dim : EchoelTheme.accent"), """
            The signal bar fills a demo value in full `EchoelTheme.accent` again. The bar is \
            the loudest thing on the row; a chip beside a full-strength accent bar is a \
            footnote under a headline that contradicts it.
            """)
    }

    // MARK: - Claim 7 — the spelling is the established one, chosen by POSITION (#416/#634b)

    func testTheMarkerUsesTheEstablishedSpelling() throws {
        let fx = try source("Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertTrue(fx.contains("contribution.synthetic ? \"Simulated demo, \" : \"\""), """
            The VoiceOver origin is no longer the PREFIX spelling. There are three established \
            spellings and they differ by POSITION, not by taste: `"Bio source: simulated demo, \
            not your body"` labels a whole element, `"Simulated demo, "` prefixes a sentence \
            that continues, `"demo values, not your body"` heads a section. This string \
            continues into "Coherence moving Reverb Mix, 42 percent", so it takes the prefix \
            form. Minting a fourth spelling of one decision is what #634b had to retract.
            """)
        XCTAssertTrue(fx.contains("Text(\"Demo\")"),
                      "The chip text is no longer the bare `Demo` the six sibling surfaces use.")
    }

    // MARK: - Claim 8 — `synthetic` may not acquire a default (#431/#440/#443)

    func testSyntheticHasNoDefaultArgument() throws {
        let core = try source("Sources/Echoelmusic/Core/FXModulation.swift")
        XCTAssertFalse(core.contains("synthetic: Bool ="), """
            `BioModContribution.init` gave `synthetic` a default value. A defaulted argument \
            that no call site writes never appears in a diff, so the single construction site \
            would keep compiling while silently reporting every demo route as a real body — \
            which is the precise failure this whole slice removes. There is exactly one \
            construction site; the cost of no default is one edit.
            """)
    }

    // MARK: - Claim 9 — VoiceOver leads with the origin, on EVERY return path (#629b)

    /// The row's own doc says the origin must be computed ABOVE the `measured` guard, because
    /// a qualifier arriving after "42 percent" corrects a claim instead of preventing one.
    /// ⚠️ That law was PROSE and nothing asserted it — the sibling on the identical surface
    /// (`TheAlwaysOnRowsSayWhoseBodyTests`) pins the index order and the return-path count, and
    /// this file shipped its first draft without either. A refactor moving `let origin` inside
    /// the measured branch would have stayed green while the documented law broke.
    func testVoiceOverLeadsWithTheOrigin() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelFXView.swift")
        guard let originLine = lines.firstIndex(where: { $0.contains("let origin = contribution.synthetic") }),
              let guardLine = lines.firstIndex(where: { $0.contains("guard contribution.measured else") })
        else {
            return XCTFail("`origin` or the `measured` guard is gone from `accessibilityText`.")
        }
        XCTAssertLessThan(originLine, guardLine, """
            `origin` is computed AFTER the `measured` guard, so the unmeasured return path \
            speaks no origin while the chip can still be on screen. The row's own doc says \
            VoiceOver gets the same facts in the same order.
            """)
        // TWO paths, not three: this row has no "held" concept — FX routes RELEASE on a
        // dropout while the always-on timbre channels PARK, which is the deliberate
        // two-regimes split `stopsArrivingNote` explains to the player.
        XCTAssertEqual(lines.filter { $0.contains("return origin") }.count, 2, """
            Not both return paths of `accessibilityText` lead with `origin`. There are two \
            (unmeasured, measured) and each says something about a body.
            """)
    }
}
