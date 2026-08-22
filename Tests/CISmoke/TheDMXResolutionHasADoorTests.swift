// TheDMXResolutionHasADoorTests.swift
// Echoel — the light senders offered a mode nothing could select. #730.
//
// WHAT WAS WRONG. `ArtNetSender.resolution` and `SACNSender.resolution` are `public var`
// properties of a `String`-backed `CaseIterable` enum — the shape a `Picker` is built from —
// and their docs called 8-bit "the legacy mode for simple fixtures". Measured across the
// WHOLE tracked repository, not one directory (the #728 lesson):
//
//     git grep -nw resolution -- .            # every mention, any file kind
//     git grep -n "resolution *=" -- .        # only `resolution == .sixteenBit`, a READ
//
// ZERO writers. Not in `Sources/`, not in `Tests/` (`ArtNetSenderTests` passes `.eightBit`
// as a function ARGUMENT to the static encoders, which is a different thing from setting the
// property), not anywhere. The `.eightBit` branch of `dmxChannels`, `applyDimmer` and
// `applySlewedColour` could not be reached from the running app at all, and neither property
// is persisted, so not even a document written by an older build could set it.
//
// ⭐ WHY THIS ONE IS A DOOR AND NOT A THIRD "NO DOOR" GUARD. #724 and #727 found flags whose
// surface did not exist and wrote the absence down. Here the surface DOES exist and is
// reachable: `PatchbayView`'s `lichtSection` already drives BOTH senders together for Grand
// Master and Blackout, and `PatchbayView` is mounted behind the routing sheet. The property,
// the enum, the encoder branches and the unit tests for both branches were all already
// shipped. The only missing piece was one row. Writing "this promise is false" a third time
// would have been cheaper and worse: the honest repair was to make the sentence true.
//
// ⚠️ NO NEW MODAL. The row goes into an EXISTING panel; the presentation-modifier chain in
// `EchoelStudioView` is untouched (the 10.76.34 black-screen law).
//
// ⚠️ IT FORBIDS NOTHING (#364). Claim 7 does not forbid persisting the choice — it requires
// that the doc saying "live state, not persisted" moves in the SAME commit that adds
// persistence (#456). Nothing here pins `.sixteenBit` as the default: that is a design value
// a founder may change, and #364 forbids pinning it.
//
// ⚠️ HONEST GRADING (#433/#464/#486). Hand-transcribed against `git show 8af1934:` and the
// worktree — a CI round trip is a lottery ticket, not a check (#686):
//   · **1 REGRESSION** on the parent `8af1934`: the door does not exist there. Claims 1, 2
//     and 7 all go red for that ONE reason and are counted ONCE (#486), not as three.
//     Claim 2 and claim 7 fail by ANCHOR ABSENCE (the member and its doc are not there);
//     claim 1's needle is simply absent.
//   · **4 COUNTERWEIGHTS** green on both trees: both senders still declare a writable
//     `resolution` (3), the encoder still branches on both cases (4), the routing sheet still
//     has a producer and still builds `PatchbayView` (5), `lichtSection` is still mounted (6).
//     Without them, deleting the enum, the encoder branch or the panel would leave claims 1
//     and 2 green over a row that selects nothing.
//
// ⚠️ STRIPPER LOAD-BEARING MEASUREMENT (#453/#477): **PROPHYLAKTISCH (0 of 7 verdicts flip)**.
// Every needle was counted raw and comment-stripped on both trees; nothing flips today. Two
// measured counterfactuals say why it is kept, rather than the usual assertion that it might
// matter one day:
//   · Comment out the `artNet.resolution = r` line and claim 2 is RED stripped and GREEN raw —
//     driven on a deliberately broken copy of the file. The two prose blocks this slice added
//     discuss the very strings the scan hunts for, so this is not hypothetical.
//   · `lichtSection` already occurs THREE times raw and TWICE in code (line 108 names it in a
//     comment about card grammar). Claim 6 wants at least two CODE occurrences; read raw, a
//     section that had been declared and demounted would still count two and pass.
//
// LIMIT (§1): SOURCE-TEXT SCAN. It proves the row and the binding are written; it cannot prove
// the segmented control renders, that a fixture reads 8-bit correctly, or that the fade looks
// right. Those are DEVICE PROBES and stay open.

import XCTest

private struct DMXAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { "anchor missing: \(reason)" }
}

final class TheDMXResolutionHasADoorTests: XCTestCase {

    private static let patchbay = "Sources/Echoelmusic/Studio/PatchbayView.swift"
    private static let artNet = "Sources/Echoelmusic/Sync/ArtNetSender.swift"
    private static let sacn = "Sources/Echoelmusic/Sync/SACNSender.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - 1 · the selector exists

    func testTheLightSectionOffersBothResolutions() throws {
        let code = try codeOf(Self.patchbay)
        XCTAssertTrue(code.contains("selection: dmxResolutionBinding"), """
            The Light section no longer binds a Picker to `dmxResolutionBinding`. Before #730 \
            `resolution` had ZERO writers in the whole repository while its own doc offered \
            8-bit as a choice. If the control moved, move this claim with it; if it was \
            removed, the sender docs in ArtNetSender.swift and SACNSender.swift promise a mode \
            nobody can pick again and must be corrected in the SAME commit (#456).
            """)
        XCTAssertTrue(code.contains("ArtNetSender.DMXResolution.sixteenBit"), """
            The 16-bit option is gone from the Picker. Both cases must be offered — a selector \
            with one case is the doorless state this guard exists to end.
            """)
        XCTAssertTrue(code.contains("ArtNetSender.DMXResolution.eightBit"), """
            The 8-bit option is gone from the Picker, which puts the `.eightBit` encoder branch \
            back out of reach of the running app.
            """)
    }

    // MARK: - 2 · one choice, both protocols

    func testTheChoiceDrivesBothSenders() throws {
        let body = try memberBody(startingWith: "private var dmxResolutionBinding",
                                  in: Self.patchbay)
        XCTAssertTrue(body.contains { $0.contains("artNet.resolution = ") }, """
            `dmxResolutionBinding` no longer writes `artNet.resolution`. The Light section's \
            law is one control, both protocols — the same shape as `grandMasterBinding` and \
            the Blackout button. A picker that moves only one sender puts a rig into two \
            different DMX resolutions with no indication on screen.
            """)
        XCTAssertTrue(body.contains { $0.contains("sacn.resolution = ") }, """
            `dmxResolutionBinding` no longer writes `sacn.resolution` — see above. sACN and \
            Art-Net share `ArtNetSender.DMXResolution` precisely so one choice can drive both.
            """)
    }

    // MARK: - 3 · counterweight: the property is still writable

    func testBothSendersStillDeclareAWritableResolution() throws {
        for path in [Self.artNet, Self.sacn] {
            let code = try codeOf(path)
            XCTAssertTrue(code.contains("public var resolution"), """
                \(path) no longer declares `public var resolution`. If it became a `let`, or \
                moved, the Picker in the Light section writes nothing and claims 1 and 2 stay \
                green over a control with no effect. This pins that it is WRITABLE, never its \
                default value (#364 — the default is a design choice).
                """)
        }
    }

    // MARK: - 4 · counterweight: both branches still encode

    func testTheEncoderStillBranchesOnBothResolutions() throws {
        let code = try codeOf(Self.artNet)
        XCTAssertTrue(code.contains("case .eightBit"), """
            `ArtNetSender` no longer has an `.eightBit` encoder branch. The Picker would then \
            offer a mode that produces nothing, which is worse than the doorless state it \
            replaced — the operator would believe the rig was switched.
            """)
        XCTAssertTrue(code.contains("case .sixteenBit"), """
            `ArtNetSender` no longer has a `.sixteenBit` encoder branch — the default mode of \
            every launch.
            """)
    }

    // MARK: - 5 · counterweight: the panel is still reachable

    func testTheRoutingSheetStillHasAProducerAndStillBuildsThePanel() throws {
        let code = try codeOf(Self.studio)
        XCTAssertTrue(code.contains("showRouting = true"), """
            Nothing sets `showRouting` to true any more, so `PatchbayView` — and with it the \
            whole Light section — is unreachable. The row this guard protects would then be a \
            control behind no door, the exact state #724/#727 had to write down twice.
            """)
        XCTAssertTrue(code.contains("PatchbayView("), """
            The routing sheet no longer builds `PatchbayView`. Reaching the flag that opens a \
            sheet is not the same as the sheet still presenting the panel.
            """)
    }

    // MARK: - 6 · counterweight: the section is still mounted

    func testTheLightSectionIsStillMounted() throws {
        let code = try codeOf(Self.patchbay)
        let mounts = code.components(separatedBy: "lichtSection").count - 1
        XCTAssertGreaterThanOrEqual(mounts, 2, """
            `lichtSection` appears \(mounts) time(s) in the code of \(Self.patchbay). It needs \
            at least two — its declaration and at least one mount in the body. One occurrence \
            means it is declared and never rendered, and every claim above would still pass \
            over a section nobody can see.
            """)
    }

    // MARK: - 7 · the live-only record moves with the behaviour

    func testTheRowRecordsThatTheChoiceIsNotPersisted() throws {
        let raw = try rawText(Self.patchbay)
        XCTAssertNotNil(raw.range(of: "LIVE STATE, NOT PERSISTED"), """
            The note recording that the DMX resolution is NOT persisted is gone from \
            \(Self.patchbay). This does not forbid persisting it (#364) — it requires that if \
            you add a key and a decode default, this prose moves in the SAME commit (#456), so \
            no later reader has to guess whether a fixed installation keeps its setting.
            """)
    }

    // MARK: - helpers

    /// Lines of a member, from the line containing `prefix` to the closing `}` at that line's
    /// OWN indentation. Structural, not a fixed window — this repo writes 30-line comment
    /// blocks and `SourceText.codeOnly` preserves line count, so any window is unsound (#408).
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeOf(path)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            throw DMXAnchorMissing(reason: """
                `\(prefix)` is gone from \(path). A missing ANCHOR fails rather than skips \
                (#454) — otherwise a rename would leave this claim silent about a binding that \
                no longer drives both senders.
                """)
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[(start + 1)..<close])
    }

    private func codeOf(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawText(relativePath))
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DMXAnchorMissing(reason: """
                \(relativePath) is not present while `Sources/` is — the anchor moved. A \
                missing TREE skips (see `repoRoot`); a missing ANCHOR fails (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

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
}
