// TheAlwaysOnRowsReachTheBioPanelTests.swift
// Echoel — #553. The four always-on channels are now READABLE where the promise is made.
//
// WHAT CHANGED. #542 put the four channel NAMES into `bioPanel` as a sentence and left the live
// numbers behind Effects › All parameters › scroll to the bottom. A player who asks "is my body
// reaching the engine right now?" asks it in the Bio panel, and the honest answer — a value plus
// whether that value is a measurement — already existed; only its address was wrong. This slice
// hoists `AlwaysOnBioRow` out of `EchoelFXView` into its own file and mounts the same rows under
// the sentence via `AlwaysOnBioPanelStrip`.
//
// ⭐ ONE ROW, TWO CONTAINERS — that is the whole design and claim 1 is what protects it. The
// tempting shape was a second, hand-built readout in the panel: four `Text`s and a bar, half an
// hour's work, no file moved. It is also #416 with a sharper edge than usual, because a readout
// copy drifts in what it CLAIMS ABOUT THE BODY, not merely in how it looks — one surface would
// keep saying "measured" after the other learned to say "held". The model was already shared
// (`AlwaysOnBioChannel`); the ROW was not, and that was the actual gap.
//
// ⚠️ THE FREEZE LAW IS THE RISK THIS SLICE CARRIES, so claim 4 is the assertion that matters
// most. `bioPanel` is reached through `dropdownContent`, which `EchoelStudioView.body` evaluates
// PERMANENTLY, and that body hosts every `.menu` Picker of the instrument. A `bus.latestBio` read
// inlined into the panel would register the ROOT as an observer of the bio publisher and tear an
// open Picker down on every publish — 10.76.41/50, not a hypothetical. `AnyView(...)` is not an
// observation boundary; a `View` struct is, which is why the strip is one, exactly like the two
// leaves already in that panel (`BioStripView`, `BreathCoachStrip`).
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN throughout. It proves the row is declared once, that the panel
// mounts the strip, and that the read sits in the strip's own body. It cannot prove the rows
// RENDER, that the 1 Hz ticker fires on device, that the panel still fits at accessibility text
// sizes with four more rows in it, or — the one that matters — that an open Picker survives a
// running camera with this mounted. All four are device probes and all four stay open.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (`d8858ea`) and this tree:
//   · TWO REGRESSIONS, and they are separate findings rather than one absence (#486): claim 1 is
//     red on the parent because the row is declared in `EchoelFXView` instead of its own file;
//     claim 2 because nothing mounts the strip. Different facts, different repairs.
//   · ONE FORWARD guard: claim 3 names `AlwaysOnBioPanelStrip`, which this commit creates, so it
//     could never have been red for its stated reason. Booking it as a regression would be the
//     flattering-direction defect (#433).
//   · TWO COUNTERWEIGHTS green on both trees, and they are the point of the file: claim 4 (the
//     panel's own body still reads no bio value) and claim 5 (the FX sheet still shows the rows).
//     Without claim 5 this file stays green on a tree that MOVED the readout instead of widening
//     its reach — which would be a regression for every player already using the FX surface.
//   · STRIPPER: TRAGEND, 2 of 10 verdicts flip — claim 4 on BOTH trees. Raw, the panel body
//     contains the phrase `bus.latestBio` in the prose explaining why the read is NOT there, and
//     the parent had its own such sentence. A raw scan would call the freeze law broken on the
//     very commit that obeys it. (A flip count is per (claim, TREE); this session corrected that
//     three times, so it is written out rather than counted a fourth way.)

import Foundation
import XCTest

final class TheAlwaysOnRowsReachTheBioPanelTests: XCTestCase {

    private static let row = "Sources/Echoelmusic/Studio/AlwaysOnBioRow.swift"
    private static let fx = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - claim 1 (REGRESSION) — the row is declared exactly once, in its own file

    func testTheRowHasExactlyOneDeclarationAndItIsTheSharedFile() throws {
        var sites: [String] = []
        for rel in try swiftFiles() where try codeText(rel).contains("struct AlwaysOnBioRow") {
            sites.append(rel)
        }
        XCTAssertEqual(sites, [Self.row], """
            `AlwaysOnBioRow` is declared at \(sites.isEmpty ? "no site" : sites.joined(separator: ", ")) \
            — it must be declared exactly once, in `\(Self.row)`. Two declarations means the FX \
            sheet and the Bio panel each render their own idea of what the body is doing, and the \
            drift will not be cosmetic: these rows say whether a value is a MEASUREMENT, is HELD, \
            or is the engine's neutral. One surface learning a new state and the other not is the \
            failure this move exists to make impossible (#416).
            """)
    }

    // MARK: - claim 2 (REGRESSION) — the Bio panel mounts it

    func testTheBioPanelMountsTheStrip() throws {
        let code = try codeText(Self.studio)
        XCTAssertTrue(code.contains("AlwaysOnBioPanelStrip()"), """
            Nothing in `\(Self.studio)` mounts `AlwaysOnBioPanelStrip()`. The panel's sentence \
            (`AlwaysOnBioChannel.bioPanelSentence`) promises that the body drives the sound and \
            then names four channels; without the strip the numbers are three levels away again \
            (Effects › All parameters › scroll), which is the state #542 had to leave behind and \
            #553 closed. If the mount was removed on purpose, the ⛔ block above that sentence \
            says the opposite and moves in the same commit.
            """)
    }

    // MARK: - claim 3 (FORWARD) — the strip is a leaf that reads bio in its OWN body

    func testTheStripIsItsOwnViewAndReadsTheBusItself() throws {
        let code = try codeText(Self.row)
        guard let body = bracedBody(after: "struct AlwaysOnBioPanelStrip: View", in: code) else {
            return XCTFail("""
                `struct AlwaysOnBioPanelStrip: View` is not declared in `\(Self.row)`. It is the \
                observation boundary the whole slice rests on — see claim 4.
                """)
        }
        XCTAssertTrue(body.contains("bus.latestBio"), """
            The strip no longer reads `bus.latestBio` in its own body. Either it stopped showing \
            live values, or — the dangerous case — the read moved UP into a parent. The parent \
            here is `bioPanel`, evaluated by `EchoelStudioView.body`, which hosts the instrument's \
            `.menu` Pickers: that is the 10.76.41/50 freeze, arriving by refactor.
            """)
        XCTAssertTrue(body.contains("AlwaysOnBioRow(channel:"), """
            The strip no longer renders `AlwaysOnBioRow`. If the panel now builds its own rows, \
            claim 1 is about to be true in letter and false in spirit — the two surfaces would be \
            free to disagree about whether a channel is measured, held, or neutral.
            """)
        XCTAssertFalse(body.contains("Section {"), """
            The strip wraps its rows in a `Section`. It lives in a `VStack` inside `bioPanel`, \
            not in a `List`; `Section`/`.listRowBackground` belong to `AlwaysOnBioView` in the FX \
            sheet and render as a stray inset here.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the panel's own body still reads no bio value

    /// #343, and the sharpest assertion in the file. Claims 1–3 all stay green on a tree that
    /// "simplified" the strip away by inlining its four rows into the panel — which is precisely
    /// the edit that reinstates the menu freeze, and precisely the edit a later reader is most
    /// likely to think is tidy.
    func testTheBioPanelBodyItselfObservesNoBioValue() throws {
        let code = try codeText(Self.studio)
        guard let body = bracedBody(after: "private var bioPanel: some View", in: code) else {
            return XCTFail("""
                `private var bioPanel: some View` was not found in `\(Self.studio)` — re-anchor \
                this scan rather than letting it pass on nothing (#454).
                """)
        }
        XCTAssertFalse(body.contains("latestBio"), """
            `bioPanel`'s own body reads a bio value. `bioPanel` is reached through \
            `dropdownContent`, which `EchoelStudioView.body` evaluates PERMANENTLY, and that body \
            hosts every `.menu` Picker of the instrument — so this read makes the ROOT an observer \
            of the bio publisher and tears an open Picker down on every publish (10.76.41/50). \
            `AnyView(bioPanel)` is not an observation boundary. Put the read in a `View` struct, \
            the way `AlwaysOnBioPanelStrip`, `BioStripView` and `BreathCoachStrip` all do.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the FX sheet did not LOSE the readout

    func testTheFXSheetStillShowsTheSameRows() throws {
        let code = try codeText(Self.fx)
        XCTAssertTrue(code.contains("AlwaysOnBioView()"), """
            `\(Self.fx)` no longer mounts `AlwaysOnBioView()`. #553 WIDENS the readout's reach; it \
            does not relocate it. A player working in the FX sheet — where the bio-mod routes are \
            edited and where the always-on channels are the baseline those routes add to — must \
            still see them there.
            """)
    }

    // MARK: - source access

    private struct RowAnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    private func codeText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw RowAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw RowAnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw RowAnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so a "declared exactly once" result here would be vacuous.
                """)
        }
        return out.sorted()
    }

    /// Brace-matched body after `anchor` (#408): a fixed line window is unsound in this repo,
    /// where a member can carry a forty-line comment block and `SourceText.codeOnly` preserves
    /// the line count.
    private func bracedBody(after anchor: String, in text: String) -> String? {
        guard let a = text.range(of: anchor),
              let open = text.range(of: "{", range: a.upperBound..<text.endIndex) else { return nil }
        var depth = 0
        var i = open.lowerBound
        while i < text.endIndex {
            if text[i] == "{" { depth += 1 }
            if text[i] == "}" {
                depth -= 1
                if depth == 0 { return String(text[open.lowerBound...i]) }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
