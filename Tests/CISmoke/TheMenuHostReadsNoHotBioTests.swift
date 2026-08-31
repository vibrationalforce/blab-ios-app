// TheMenuHostReadsNoHotBioTests.swift
// Echoel — #918. The freeze that cost five device builds has no guard.
//
// THE DEFECT CLASS, in the founder's words each time: "Sobald Biofeedback läuft kann ich nicht
// mehr auswählen." An open `.menu` Picker popover is torn down whenever its host's body
// rebuilds, and a `@Observable` property read DURING BODY EVALUATION registers that whole body
// as an observer. `CameraRPPGBioPublisher` writes its readouts on a ~10 Hz tick, so ONE such
// read anywhere in an ancestor rebuilds the entire subtree ten times a second.
//
// It was diagnosed and fixed FIVE times — 10.76.41, .43, .47, .48, .50 — and the last of those
// is the reason this file exists: every previous audit scoped itself to `EchoelStudioView`,
// found it genuinely clean, and the read was one level UP, in `WorkspaceView.topBar` feeding
// the header pulse tile. A law that is only written in prose gets re-broken by the next person
// who audits the obvious view.
//
// ⛔ THIS GUARD WAS WRONG THREE TIMES BEFORE IT WAS RIGHT, and every one was found by DRIVING
// it as a mutation, not by reading it — the discipline this session has had to learn four
// times. (1) It was RED ON A CORRECT TREE: the "is this computed?" step gave a STORED property
// to a brace matcher, which then ran to the end of the class, so every stored property
// "contained" every hot name — `isRunning` was swept in and the shipped 10.76.50 repair was
// reported as the violation. (2) It was falsely GREEN for a ONE-LINE member, whose whole body
// sits on the declaration line the extraction starts after. (3) It was file-scoped, so it
// flagged a small leaf `View` struct declared in the same file — which is the DOCUMENTED
// REPAIR for this defect, i.e. the guard forbade the fix it exists to teach (#364).
// Seven mutants are driven now: a hot read added to the root, to a multi-line member and to a
// one-line member all go red; a new leaf struct in the same file, a read inside a `private
// func`, and the untouched tree all stay green; a renamed type fails loudly instead of
// scanning nothing.
//
// WHAT THIS IS: a SOURCE-TEXT SCAN (§1). It proves where text sits — never that the app does
// not churn. Three limits, stated before the claim rather than after:
//   · It reads `some View` members only. A read inside a `private func` or a `.task {}` closure
//     is NOT body evaluation and is correctly out of scope — `EchoelStudioView` has three such
//     reads today (`bodyTempoTrustworthy`, the settle-wait, the start/stop breadcrumbs) and
//     they are fine.
//   · A `.task {}` or `.onAppear {}` closure written INSIDE a `some View` member would be
//     scanned and would read as a violation although it is safe. None exists today; if one
//     appears, narrow the extraction rather than deleting the claim.
//   · It anchors on the spelling `cameraRPPG.`. A view reaching the publisher under another
//     binding is invisible to it.
//
// ⭐ THE HOT SET IS DERIVED, NOT LISTED. A hard-coded list would name today's properties and
// silently miss tomorrow's — the shape this repo calls a stale number. It is computed here from
// the publisher itself: every externally readable, OBSERVATION-TRACKED property that the ~10 Hz
// publish task assigns, plus every computed property that exposes one. Measured at the time of
// writing it selects nine (`waveform`, `confidence`, `detectedBPM`, `displayBPM`,
// `fingerDetected`, `isSettled`, `signalQuality`, `recoveryState`, `brightHintLatched`), and
// correctly does NOT select `isRunning` — which changes on start/stop only and is exactly what
// #50's repair left `WorkspaceView` reading.
//
// ⚠️ HONEST GRADING (#433/#464) — the parent is `eaffc74`. This file is NEW there, so no
// assertion has a verdict on it; hand-transcribed over its checks:
//   · REGRESSIONS: 0. The tree is CLEAN today — that is the point. This is a recurrence guard
//     for a class that has recurred five times, not a bug report.
//   · FORWARD guards: 0. It names no symbol this commit creates.
//   · COUNTERWEIGHTS: all of them. Per §343 that is the content, and three of them exist
//     specifically so the two negative claims cannot pass by finding nothing (#367): the
//     derivation must select `waveform`, the leaves must still read hot properties, and
//     `WorkspaceView` must still read `isRunning`.
//   · ANCHOR ABSENCE: 0 — every anchor is asserted present before it is used.
//
// ⚠️ NOT COMPILE-VERIFIED by the cheap gate: `Xcode Compile Check` builds `Sources/` alone.
// This file builds only in the CI/CD `Build for Testing` step.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMenuHostReadsNoHotBioTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let root = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let host = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let leaves = [
        "Sources/Echoelmusic/Studio/HeaderMonitors.swift",
        "Sources/Echoelmusic/Studio/PulseMeasurementView.swift",
        "Sources/Echoelmusic/Studio/BioStripView.swift",
    ]

    // MARK: - 1. The derivation itself

    func testTheHotSetIsDerivedAndSelectsTheOneThatCausedTheFreeze() throws {
        let hot = try hotProperties()
        XCTAssertTrue(hot.contains("waveform"), """
            `waveform` is THE property of the 10.76.50 finding — `WorkspaceView.topBar` read it \
            to feed the header pulse tile, and it updates ~10 Hz while biofeedback runs. If the \
            derivation stops selecting it, the two scans below go green by selecting nothing, \
            which is the #367 failure mode this claim exists to block. Selected: \
            \(hot.sorted().joined(separator: ", "))
            """)
        XCTAssertGreaterThanOrEqual(hot.count, 5, """
            The derivation collapsed to \(hot.count) propert(ies). It reads the publisher's own \
            declarations and its publish task; if either anchor moved, re-derive it rather than \
            lowering this floor — a scan over an empty set proves nothing at all.
            """)
    }

    func testTheStartStopFlagIsNotTreatedAsHot() throws {
        let hot = try hotProperties()
        XCTAssertFalse(hot.contains("isRunning"), """
            COUNTERWEIGHT, and it is the one that keeps this guard from forbidding correct work \
            (#364). `isRunning` changes on start and on stop — not on a tick — and reading it in \
            an ancestor is exactly what the 10.76.50 repair LEFT in place. A derivation that \
            swept it up would redden the shipped fix.
            """)
    }

    // MARK: - 2. The two ancestors

    func testTheRootBuildsNoViewFromAHotReadout() throws {
        try assertNoHotRead(in: Self.root, of: "WorkspaceView", why: """
            `WorkspaceView` is the ROOT. A ~10 Hz read in any of its view-building members \
            rebuilds every surface below it ten times a second and tears down whatever Picker \
            popover the player has open — the founder's "kann ich nicht mehr auswählen", \
            reported five times. The repair is never to throttle: confine the read to its own \
            small leaf `View` struct (`PulseMonitorMiniLive` is the worked example) so only that \
            leaf churns.
            """)
    }

    func testTheMenuHostBuildsNoViewFromAHotReadout() throws {
        try assertNoHotRead(in: Self.host, of: "EchoelStudioView", why: """
            `EchoelStudioView` hosts the Picker menus themselves. `AnyView(...)` is NOT an \
            observation boundary, so a read in ANY member this body evaluates — including a \
            dropdown panel — registers the whole body as a 10 Hz observer. Reads inside \
            `private func` bodies and `.task {}` closures are deliberately out of scope: they \
            are not body evaluation, and three of them exist here on purpose.
            """)
    }

    // MARK: - 3. The needle must be able to match

    func testTheLeavesStillReadTheHotReadouts() throws {
        let hot = try hotProperties()
        var found: [String] = []
        for path in Self.leaves {
            let text = SourceText.codeOnly(try read(path))
            for name in hot where text.contains("cameraRPPG.\(name)") {
                found.append("\(path.split(separator: "/").last ?? ""):\(name)")
            }
        }
        XCTAssertFalse(found.isEmpty, """
            COUNTERWEIGHT AND SELF-TEST IN ONE. The two scans above are NEGATIVE claims, and a \
            negative claim with a needle that cannot match is green forever while proving \
            nothing (#367). The leaves are where these reads BELONG — the law is "in a leaf", \
            not "nowhere" — so at least one of them must still contain one. If this is empty, \
            either the leaves were emptied or the `cameraRPPG.` spelling changed, and the two \
            scans above are worthless until it is fixed.
            """)
    }

    func testTheRootStillReadsTheStartStopFlag() throws {
        let text = SourceText.codeOnly(try read(Self.root))
        XCTAssertTrue(text.contains("cameraRPPG.isRunning"), """
            COUNTERWEIGHT: proves the root scan is reading the right file with the right \
            spelling. `WorkspaceView` reads the publisher — just not a ticking property. \
            Without this, `testTheRootBuildsNoViewFromAHotReadout` would also pass on a file \
            that mentions the publisher nowhere at all.
            """)
    }

    // MARK: - Derivation

    /// Externally readable, observation-TRACKED properties the ~10 Hz publish task writes,
    /// plus computed properties that expose one.
    private func hotProperties() throws -> Set<String> {
        let code = SourceText.codeOnly(try read(Self.publisher))
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var readable: [String: Bool] = [:]     // name -> is tracked (not @ObservationIgnored)
        for line in lines {
            guard let name = declaredVarName(in: line) else { continue }
            // A `private` GETTER hides it from every view. `private(set)` does not — it is the
            // publisher's normal shape (`public private(set) var waveform`), and treating it as
            // private is the mistake that made the first derivation return an empty set.
            let privateGetter = line.contains("private var ") || line.contains("fileprivate var ")
            guard !privateGetter else { continue }
            readable[name] = !line.contains("@ObservationIgnored")
        }

        guard let taskStart = code.range(of: "publishTask = Task") else {
            XCTFail("the publish-task anchor `publishTask = Task` is gone — re-derive the scan")
            return []
        }
        let tick = String(code[taskStart.lowerBound...])

        var hot = Set<String>()
        for (name, tracked) in readable where tracked {
            if tick.contains("self.\(name) = ") { hot.insert(name) }
        }
        // A COMPUTED property that exposes a hot one is just as hot to read: the body
        // evaluating it registers on whatever the getter touches.
        //
        // ⛔ THE FIRST DRAFT ASKED EVERY DECLARATION FOR A BODY AND WAS RED ON A CORRECT TREE —
        // caught by driving it, not by reading it. A STORED property has no braces, so the
        // brace matcher ran from its line to the next `}` at that indentation, i.e. to the end
        // of the class, and every stored property "contained" every hot name. It swept up
        // `isRunning`, `tick`, `tickSeconds` and `rrWindowMs`, and the root scan then reported
        // `WorkspaceView.topBar` — the SHIPPED 10.76.50 repair — as a violation. A guard that
        // reddens correct work gets deleted and takes the law with it (#364). The gate is that
        // the declaration line must actually OPEN a body.
        for (name, tracked) in readable where tracked && !hot.contains(name) {
            guard let line = lines.first(where: { declaredVarName(in: $0) == name }),
                  line.trimmingCharacters(in: .whitespaces).hasSuffix("{") else { continue }
            let body = memberBody(startingWith: "var \(name)", in: lines)
            if hot.contains(where: { body.contains("\($0)") }) { hot.insert(name) }
        }
        return hot
    }

    private func declaredVarName(in line: String) -> String? {
        guard let r = line.range(of: "var ") else { return nil }
        let rest = line[r.upperBound...]
        let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !name.isEmpty else { return nil }
        let after = rest.dropFirst(name.count).first
        guard after == ":" || after == " " || after == "=" else { return nil }
        return String(name)
    }

    // MARK: - The scan

    private func assertNoHotRead(in path: String, of type: String, why: String) throws {
        let hot = try hotProperties()
        let lines = SourceText.codeOnly(try read(path))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // ⛔ SCOPED TO THE TYPE, NOT TO THE FILE — a driven mutant forced this. A file-wide
        // scan flags a small leaf `View` struct declared in the same file, and declaring one is
        // the DOCUMENTED REPAIR for this very defect. Forbidding the fix in the guard that
        // teaches it is #364 in its purest form.
        // ⛔ The colon is not cosmetic: without it `struct EchoelStudioView` also matches
        // `struct EchoelStudioView2`, so a RENAME would leave the guard silently scanning a
        // different type instead of failing. A driven mutant caught that too.
        guard let open = lines.firstIndex(where: { $0.contains("struct \(type):") && $0.contains(": View {") }) else {
            XCTFail("`struct \(type): View` is gone from \(path) — move this guard with it")
            return
        }
        let outer = lines[open].prefix { $0 == " " }.count
        let end = lines[(open + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == outer
        } ?? lines.endIndex

        var offences: [String] = []
        for index in open..<end where lines[index].contains(": some View {") {
            // ⛔ THE DECLARATION LINE IS PART OF THE MEMBER, and leaving it out was a second
            // false GREEN the same mutant run exposed: a one-line member
            // `var x: some View { Text("\(cameraRPPG.waveform.count)") }` keeps its whole body
            // on the declaration line, which `memberBody` starts AFTER.
            let member = lines[index] + "\n"
                + memberBody(startingWith: lines[index], in: lines, from: index)
            for name in hot where member.contains("cameraRPPG.\(name)") {
                offences.append("line \(index + 1): \(lines[index].trimmingCharacters(in: .whitespaces)) reads cameraRPPG.\(name)")
            }
        }
        XCTAssertTrue(offences.isEmpty, """
            \(path) builds a view from a ~10 Hz readout:
            \(offences.joined(separator: "\n"))

            \(why)
            """)
    }

    // MARK: - Helpers

    /// Lines of a member, from the line containing `prefix` to the closing `}` at that line's
    /// OWN indentation. Structural, not a line count — this repo writes 30-line comment blocks,
    /// so any fixed window is unsound by construction (§2, #408).
    private func memberBody(startingWith prefix: String, in lines: [String], from: Int? = nil) -> String {
        guard let start = from ?? lines.firstIndex(where: { $0.contains(prefix) }) else { return "" }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return lines[(start + 1)..<close].joined(separator: "\n")
    }

    private func read(_ relative: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                Sources/ is not reachable from this file's path — the checkout layout changed. \
                Skipping rather than failing: this guard reads source text, and an unreadable \
                tree is not evidence that the code is wrong.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}
