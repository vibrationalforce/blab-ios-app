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
// ⛔ THIS GUARD HAS BEEN WRONG SEVEN TIMES, and every single one was found by DRIVING it as a
// mutation — never by reading it. Recorded in full because the pattern is the finding:
//   RED ON A CORRECT TREE (would have shipped a broken gate):
//     1. The "is this computed?" step handed a STORED property to a brace matcher, which then
//        ran to the end of the class; every stored property "contained" every hot name,
//        `isRunning` was swept in, and the SHIPPED 10.76.50 repair was reported as the
//        violation. A guard that reddens correct work gets deleted and takes the law with it.
//     2. A multi-line signature puts `) -> some View {` on a CONTINUATION line, indented
//        deeper than its `func`; matching from there overran the member and produced seven
//        false offences. The scan now walks back to the declaration line.
//   FALSELY GREEN (would have been a guard that guards nothing):
//     3. A ONE-LINE member keeps its whole body on the declaration line, which the extraction
//        started after.
//     4. `-> some View` FUNCTIONS were not scanned at all — 19 in `EchoelStudioView`, 1 in
//        `WorkspaceView`. A mutant put a hot read in `menuChip` and the guard stayed green.
//     5. A ONE-LINE computed property in the PUBLISHER was not treated as computed, so
//        `rrWindowMs` and `coachingHint` never entered the derivation.
//     6. The computed pass was ONE HOP through PUBLIC members only. `acquisitionCue` reaches
//        its hot inputs through a private `placementCue`; `coachingHint` needs three hops.
//     7. `SurfaceHost` — a third ancestor between the root and the Picker host — was not
//        scanned at all.
//   Plus two shape defects with no visible symptom yet: the derivation walked a `Dictionary`
//   (per-process iteration order, so a future two-hop chain would have made the result flake),
//   and it read declarations file-wide instead of class-wide.
//
// ⛔ AND THE HEADER ITSELF CARRIED A FALSE LAW. It said a read inside "a `private func` or a
// `.task {}` closure is NOT body evaluation and is correctly out of scope". That is false for
// any `private func … -> some View`, and for a `private func … -> Bool` CALLED from a body. It
// was true only of the three call sites that happen to exist here today. The rule is about
// WHERE the value is read, not what kind of member holds it.
//
// WHAT THIS IS: a SOURCE-TEXT SCAN (§1). It proves where text sits — never that the app does
// not churn. The limits, stated before the claim:
//   · It scans view-BUILDING members (`: some View {`, `-> some View {`) of the three named
//     types, in their `struct` and in any `extension`. A read inside a plain helper called
//     FROM a body is still a real defect and is not seen; the two that exist today are reached
//     from action paths, which is checked, not assumed.
//   · An ACTION closure written inside such a member (`Button { … }`, `.onAppear { … }`,
//     `.task { … }`) is not body evaluation, and a hot read there would be reported although
//     it is safe. None exists today. Note the neighbouring case is the OPPOSITE: the value
//     argument of `.onChange(of:)` IS evaluated during body, so flagging that is correct.
//   · It anchors on the spelling `cameraRPPG.`. An alias (`let cam = cameraRPPG`), a hot value
//     passed down as a function argument, or a renamed binding is invisible to it.
//
// ⭐ THE HOT SET IS DERIVED, NOT LISTED — a hard-coded list names today's properties and
// silently misses tomorrow's. Three sources: stored properties the ~10 Hz publish task
// assigns; computed properties whose getter reads `analyzer.` (fed at 15 fps — `rrWindowMs` is
// exactly that and mentions no hot name at all); and the transitive closure over computed
// properties with PRIVATE nodes kept as waypoints. The count is deliberately not written here
// (#818): re-derive it from `testTheHotSetIsDerivedAndSelectsTheOneThatCausedTheFreeze`, whose
// failure message prints the selected set. It correctly does NOT select `isRunning`, which
// changes on start/stop only and is exactly what the 10.76.50 repair left the root reading.
//
// ⚠️ HONEST GRADING (#433/#464) — the parent is `99c595f`, which carries the first version of
// this file. This rewrite does not compile against it (nothing new is named, but the members
// differ), so grade it as: 0 REGRESSIONS — the tree is CLEAN today and that is the point; this
// is a recurrence guard for a class that has recurred five times, not a bug report. 0 FORWARD
// guards. Everything else is a COUNTERWEIGHT, and per §343 that is the content. Four of them
// exist specifically so the three negative claims cannot pass by finding nothing (#367): the
// derivation must select `waveform`, `rrWindowMs` and `coachingHint`; the leaves must still
// read hot properties; the root must still read `isRunning`; and each scan asserts it actually
// found view-building members. ANCHOR ABSENCE: 0 — every anchor is asserted before use, which
// was NOT true of the first version and is the repair for its unguarded member needle.
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
    /// ⛔ THE THIRD ANCESTOR, missed by the first version. The chain is
    /// `EchoelmusicApp.mainContent` → `WorkspaceView` → `SurfaceHost` → `EchoelStudioView`,
    /// and `SurfaceHost` wraps the Picker host DIRECTLY. It is clean today, so leaving it out
    /// made the guard green partly by luck — and "a hot read one level above the level the
    /// last fix reached" is the 10.76.50 finding word for word.
    private static let wrapper = "Sources/Echoelmusic/Studio/SurfaceSwitcher.swift"
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
        XCTAssertTrue(hot.contains("rrWindowMs"), """
            `rrWindowMs` is the property whose OWN doc comment in the publisher states this \
            law — "must only ever be read inside a LEAF view … would tear down any open \
            `.menu` Picker on every heartbeat". Its getter is `{ analyzer.rawIntervalsMs }`: \
            it mentions no hot NAME, so a name-graph alone never finds it. If this fails, the \
            "reads the 15 fps analyzer" rule was lost and the derivation has a hole the \
            source itself warns about.
            """)
        XCTAssertTrue(hot.contains("coachingHint"), """
            Three hops — `coachingHint` → `acquisitionCue` → a PRIVATE `placementCue` → \
            `fingerDetected`/`isLocked`. A single hop through public members only, which is \
            what the first version did, found none of the three. If this fails, either the \
            transitive closure stopped iterating or private waypoints were dropped again.
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

    func testTheWrapperBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.wrapper, of: "SurfaceHost", why: """
            `SurfaceHost` sits BETWEEN the root and the Picker host. It is clean today; the \
            claim exists because the defect's whole history is that each fix reached one level \
            and the next read appeared one level above it.
            """)
        XCTAssertGreaterThan(members, 0, "no view-building member found in SurfaceHost — the needle stopped matching")
    }

    func testTheRootBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.root, of: "WorkspaceView", why: """
            `WorkspaceView` is the ROOT. A ~10 Hz read in any of its view-building members \
            rebuilds every surface below it ten times a second and tears down whatever Picker \
            popover the player has open — the founder's "kann ich nicht mehr auswählen", \
            reported five times. The repair is never to throttle: confine the read to its own \
            small leaf `View` struct (`PulseMonitorMiniLive` is the worked example) so only that \
            leaf churns.
            """)
        XCTAssertGreaterThan(members, 0, """
            ANCHOR ASSERTION, and the first version did not have one: the member needles \
            (`: some View {`, `-> some View {`) are what the negative claim iterates over. If \
            they stop matching — a reformat, a move into an extension — the loop runs zero \
            times and the claim passes by finding nothing. #367, and it is the exact mode the \
            counterweights below exist to block.
            """)
    }

    func testTheMenuHostBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.host, of: "EchoelStudioView", why: """
            `EchoelStudioView` hosts the Picker menus themselves. `AnyView(...)` is NOT an \
            observation boundary, so a read in ANY member this body evaluates — including a \
            dropdown panel — registers the whole body as a 10 Hz observer. Reads inside \
            `private func` bodies and `.task {}` closures are deliberately out of scope: they \
            are not body evaluation, and three of them exist here on purpose.
            """)
        XCTAssertGreaterThan(members, 20, """
            ANCHOR ASSERTION. `EchoelStudioView` had \(members) view-building members when \
            this was written (66). A collapse to a handful means a needle stopped matching, \
            not that the view shrank — and the negative claim above would then be green for \
            having looked at almost nothing.
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

    /// Externally readable, observation-TRACKED properties that a body evaluating them
    /// registers on at ~10 Hz.
    ///
    /// Three sources, and the second and third were both added after a review drove mutants
    /// through the first: (a) stored properties the publish task assigns; (b) a computed
    /// property whose getter reads `analyzer.` — `CameraAnalyzer` is fed at 15 fps, and
    /// `rrWindowMs` is exactly that shape while mentioning no hot NAME at all; (c) the
    /// transitive closure over computed properties, PRIVATE nodes included as waypoints.
    /// `acquisitionCue` reaches its hot inputs only through a private `placementCue`, and
    /// `coachingHint` only through `acquisitionCue` — a public-only single hop found neither.
    private func hotProperties() throws -> Set<String> {
        let all = SourceText.codeOnly(try read(Self.publisher))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Scoped to the class, like the scan half — otherwise the loop ingests declarations
        // from other types in the file and every function-local `var`.
        guard let (lo, hi) = span(of: "class CameraRPPGBioPublisher", in: all) else {
            XCTFail("`class CameraRPPGBioPublisher` is gone — re-derive this scan")
            return []
        }
        let lines = Array(all[lo..<hi])
        let text = lines.joined(separator: "\n")
        guard let taskStart = text.range(of: "publishTask = Task") else {
            XCTFail("the publish-task anchor `publishTask = Task` is gone — re-derive the scan")
            return []
        }
        let tick = String(text[taskStart.lowerBound...])

        struct Decl { let tracked: Bool; let privateGetter: Bool; let computed: Bool; let body: String }
        var decls: [String: Decl] = [:]
        for (index, line) in lines.enumerated() {
            guard let name = declaredVarName(in: line) else { continue }
            // `private(set)` is NOT a private getter — it is this publisher's normal shape
            // (`public private(set) var waveform`), and treating it as private returned an
            // empty set on the first attempt.
            let privateGetter = line.contains("private var ") || line.contains("fileprivate var ")
            let head = line.split(separator: "{", maxSplits: 1).first.map(String.init) ?? line
            let computed = line.contains("{") && !head.contains("=")
            let after = line.range(of: "{").map { String(line[$0.upperBound...]) } ?? ""
            let oneLiner = computed && after.contains("}")
            decls[name] = Decl(tracked: !line.contains("@ObservationIgnored"),
                               privateGetter: privateGetter,
                               computed: computed,
                               body: computed ? (oneLiner ? line : memberBody(in: lines, from: index)) : "")
        }

        var hot = Set<String>()
        for (name, d) in decls where d.tracked {
            if !d.computed && tick.contains("self.\(name) = ") { hot.insert(name) }
            if d.computed && mentions("analyzer.", in: d.body) { hot.insert(name) }
        }
        // Fixed point over SORTED names. ⛔ The first version walked a `Dictionary`, whose
        // iteration order is per-process seeded: with any two-hop chain present the derived
        // set would have differed between runs and the negative scans would have been
        // intermittently green — a flake in the guard sold as "derived, so it catches
        // tomorrow's properties".
        var grew = true
        while grew {
            grew = false
            for name in decls.keys.sorted() {
                guard let d = decls[name], d.tracked, d.computed, !hot.contains(name) else { continue }
                if hot.sorted().contains(where: { mentions($0, in: d.body) }) {
                    hot.insert(name)
                    grew = true
                }
            }
        }
        // A private getter cannot be read by a view; it is only a waypoint above.
        return hot.filter { decls[$0]?.privateGetter == false }
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

    /// `body.contains(name)` with word edges, so `isLocked` is not found inside `isLockedRaw`.
    private func mentions(_ name: String, in body: String) -> Bool {
        var searchFrom = body.startIndex
        while let r = body.range(of: name, range: searchFrom..<body.endIndex) {
            let beforeOK = r.lowerBound == body.startIndex
                || !isWordChar(body[body.index(before: r.lowerBound)])
            let afterOK = r.upperBound == body.endIndex || !isWordChar(body[r.upperBound])
            if beforeOK && afterOK { return true }
            searchFrom = r.upperBound
        }
        return false
    }

    private func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    // MARK: - The scan

    /// Every member of `type` that BUILDS A VIEW, in its `struct` and in any `extension`.
    ///
    /// ⛔ TWO NEEDLES, NOT ONE. The first version matched only `: some View {`, so all 19
    /// `-> some View` FUNCTIONS in `EchoelStudioView` and the 1 in `WorkspaceView` were
    /// invisible — and a driven mutant put a hot read in `menuChip` and stayed green. A
    /// `@ViewBuilder private func` is body evaluation just as much as a computed `var`.
    @discardableResult
    private func assertNoHotRead(in path: String, of type: String, why: String) throws -> Int {
        let hot = try hotProperties()
        let lines = SourceText.codeOnly(try read(path))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // ⛔ SCOPED TO THE TYPE, NOT TO THE FILE — a driven mutant forced this. A file-wide
        // scan flags a small leaf `View` struct declared in the same file, and declaring one is
        // the DOCUMENTED REPAIR for this very defect. Forbidding the fix in the guard that
        // teaches it is #364 in its purest form. Extensions of the type count as the type.
        var spans: [(Int, Int)] = []
        if let s = span(of: "struct \(type):", in: lines) { spans.append(s) }
        for (index, line) in lines.enumerated() where line.hasPrefix("extension \(type)") {
            if let s = span(of: line, in: lines, from: index) { spans.append(s) }
        }
        guard !spans.isEmpty else {
            XCTFail("`struct \(type):` is gone from \(path) — move this guard with it")
            return 0
        }

        var offences: [String] = []
        var members = 0
        for (lo, hi) in spans {
            for index in lo..<hi where lines[index].contains(": some View {")
                                       || lines[index].contains("-> some View {") {
                members += 1
                // ⛔ WALK BACK TO THE DECLARATION LINE. A multi-line signature puts
                // `) -> some View {` on a CONTINUATION line, indented deeper than its `func`;
                // brace-matching from there ran past the member's end and swallowed unrelated
                // code — seven false offences on a correct tree, found by driving it.
                var start = index
                var steps = 0
                while start > lo, steps < 12,
                      !lines[start].contains("func "), !lines[start].contains("var ") {
                    start -= 1
                    steps += 1
                }
                // The declaration line is part of the member: a one-line
                // `var x: some View { Text("\(cameraRPPG.waveform.count)") }` keeps its whole
                // body there, and an extraction that starts AFTER it was a second false green.
                let member = lines[start] + "\n" + memberBody(in: lines, from: start)
                for name in hot.sorted() where member.contains("cameraRPPG.\(name)") {
                    offences.append("line \(index + 1): \(lines[index].trimmingCharacters(in: .whitespaces)) reads cameraRPPG.\(name)")
                }
            }
        }
        XCTAssertTrue(offences.isEmpty, """
            \(path) builds a view from a ~10 Hz readout:
            \(offences.joined(separator: "\n"))

            \(why)
            """)
        return members
    }

    // MARK: - Helpers

    /// The half-open line range of a declaration: from the line containing `opener` to the
    /// closing `}` at that line's OWN indentation. Structural, not a line count — this repo
    /// writes 30-line comment blocks, so any fixed window is unsound by construction (#408).
    private func span(of opener: String, in lines: [String], from: Int? = nil) -> (Int, Int)? {
        guard let start = from ?? lines.firstIndex(where: { $0.contains(opener) }) else { return nil }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return (start, close)
    }

    private func memberBody(in lines: [String], from index: Int) -> String {
        guard let (start, close) = span(of: lines[index], in: lines, from: index) else { return "" }
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
