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
// SCOPE, stated so nobody reads more into a green bar than is here. This slice marks the
// two SwiftUI surfaces. It does NOT touch the network egress: `BioEgressPolicy` still
// allows `.fallback`, and no OSC / ADM-OSC / Art-Net / sACN address carries a source field,
// so a receiver on the LAN still cannot tell demo from body. That is a protocol change
// (an address or a tag), not a view change, and it is a separate decision. Apple Health is
// already clean and needs nothing: `HealthWritePolicy.isWritableSource` admits only `.ble`
// and `.cameraPPG`, so no synthetic value can ever be written.
//
// A THIRD surface renders these frames and is deliberately NOT marked: `AlwaysOnBioRow`
// (reachable twice — the Bio panel's `AlwaysOnBioPanelStrip` and the FX sheet's
// `AlwaysOnBioView`). It is left alone because its SUBJECT is different, and its own doc
// says so under #484: it reports what the SOUND path is being handed, never what a heart is
// doing — "not measured" / "no longer arriving" describe the reading, not the person. A
// synthetic 0.42 on the harmonicity channel is a true statement about the engine's input.
// Written down here rather than silently skipped so the next session can tell a decision
// from an oversight; if the founder reads that row as a body claim, it becomes #627b.
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
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED **PROPHYLAKTISCH** — all
// eighteen verdicts (nine assertions × two trees) are identical raw and stripped, because
// none of the prose added here spells a needle in its code form. It stays because the next
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
        XCTAssertEqual(lines.filter { $0.contains("reading?.source == .fallback") }.count, 1, """
            `isSynthetic` no longer reads `reading?.source`. `reading` is `usableBio()` — \
            the exact value every cell in this strip renders — so asking it is what keeps \
            the tag and the numbers appearing and expiring together. A separate UI flag can \
            drift from the bus, which is #503's defect one surface over.
            """)
    }

    /// 4 — COUNTERWEIGHT: green stays reserved for a real body. The cheap "fix" for the
    /// lying tag is to let `.fallback` into `hasLiveSignal`; that would paint the demo with
    /// the live-source colour and trade this bug for its mirror.
    func testTheLiveTagStillExcludesTheDemo() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/BioStripView.swift")
        XCTAssertEqual(lines.filter { $0.contains("bio.source != .fallback") }.count, 2, """
            `hasLiveSignal` / `sourceText` no longer exclude `.fallback`. The green tag and \
            the source name mean "a real body is on the wire"; admitting the simulator there \
            makes the demo indistinguishable from a strap — the same false claim #627 is \
            removing, moved into a nicer colour.
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
}
