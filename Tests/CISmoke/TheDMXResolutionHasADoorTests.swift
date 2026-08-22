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
// ⚠️ HONEST GRADING (#433/#464/#486). Hand-transcribed against `git show 548ecb3:` and the
// worktree — a CI round trip is a lottery ticket, not a check (#686):
//   · **1 REGRESSION** on the parent `548ecb3`: the door does not exist there. Claims 1, 2
//     and 7 all go red for that ONE reason and are counted ONCE (#486), not as three.
//     Claim 2 and claim 7 fail by ANCHOR ABSENCE (the member and its doc are not there);
//     claim 1's needle is simply absent.
//   · **4 COUNTERWEIGHTS** green on both trees: both senders still declare a writable
//     `resolution` (3), the encoders still branch on both cases (4), the routing sheet still
//     has a producer and still builds `PatchbayView` (5), `lichtSection` is still mounted (6).
//
// ⛔ AND THE FIRST VERSION OVER-SOLD ALL FOUR EQUALLY (#731). It said "without them, deleting
// the enum, the encoder branch or the panel would leave claims 1 and 2 green" — measured, the
// COMPILER shadows most of that. `project.yml:355-361` gives `EchoelmusicTests` a
// `dependencies: [target: Echoelmusic]`, so `Sources/` must build before any assertion has a
// verdict at all:
//   · delete `DMXResolution`, or make `resolution` a `let` (claim 3's named reason) → the
//     Picker and the binding stop compiling → NO verdict, not "green";
//   · delete `case .eightBit:` from a two-case `switch` → non-exhaustive → the same.
// Claim 4 therefore bites only on the narrower edit that replaces a case with `default:`, and
// claim 3 only on a rename that keeps everything compiling. **Claims 5 and 6 are the genuinely
// load-bearing pair** — demounting `lichtSection` or removing the sheet's producer compiles
// perfectly and would leave a row nobody can reach. Keeping 3 and 4 is still right (they name
// the premise in the failure message a compile error never states), but this file will not
// pretend they carry the weight the panel checks do.
//
// ⚠️ STRIPPER LOAD-BEARING MEASUREMENT (#453/#477): **six claims read stripped text and 0 of
// those 6 flip; claim 7 reads RAW on purpose and DOES flip** — its needle lives only in a
// `///` block, so stripped it reads 0 and the claim would be red on a correct tree.
//
// ⛔ THE FIRST VERSION WROTE "PROPHYLAKTISCH (0 of 7 verdicts flip) … nothing flips today"
// (#731), which counted a raw-reading claim in a stripped-reading measurement and was false by
// its own arithmetic — one commit after #729 was spent on exactly that error, in the opposite
// direction. The label must name WHICH reading each claim uses before it counts flips. Two
// measured counterfactuals say why it is kept, rather than the usual assertion that it might
// matter one day:
//   · Comment out the `artNet.resolution = r` line and claim 2 is RED stripped and GREEN raw —
//     driven on a deliberately broken copy of the file. The two prose blocks this slice added
//     discuss the very strings the scan hunts for, so this is not hypothetical.
//   · `lichtSection` already occurs THREE times raw and TWICE in code — the third is the
//     comment `"same grammar as \`lichtSection\`"` above `learnCard`. Claim 6 wants at least
//     two CODE occurrences; read raw, a section that had been declared and demounted would
//     still count two and pass. (A quoted phrase survives an insertion; a line number does
//     not, and the first version cited one — #731.)
//
// ⭐ THE DOOR MADE A LATENT BRANCH REACHABLE — REGISTERED BY #731, **FIXED BY #732**, and this
// paragraph is rewritten by #733 because #732 shipped without moving it (#456, in the file
// whose own #731 repair was about that very failure two bullets up). `ArtNetSender.sendIfFresh`
// has a HOLD branch: with no allowed source it reuses `lastChannels` and keeps running
// master/blackout/slew, so a Blackout is honoured with bio stopped. That array is sized for
// the resolution in force when it was built; until #730 the property had no writer, so the
// sizes could never disagree. The repair is a `didSet` on `resolution` in BOTH senders that
// **RE-ENCODES** the held array (`ArtNetSender.reencode`), guarded by
// `TheHeldFrameSurvivesAResolutionFlipTests`.
//
// ⛔ AND THE THREE THINGS THIS PARAGRAPH ORIGINALLY SAID ARE ALL WRONG, WHICH IS WHY IT IS
// REWRITTEN RATHER THAN TICKED OFF:
//   · it prescribed **CLEARING** the held state. Measured, that is worse than the defect: the
//     hold branch would fall to `else { return }` and the blackout would stop working — the
//     exact L1 failure the branch exists to prevent.
//   · "ONE tick" — the hold branch stores its own input back, so without the fix the
//     wrongly-sized array is re-stored every 33 ms, not once.
//   · "the next fresh frame (~1 Hz) rebuilds the array" — there is no clock in it. The bio
//     branch reads `bus.latestBio`, the raw snapshot, with no freshness window and no reset,
//     and `BioEgressPolicy` gates wrist/ring sources by SOURCE, permanently. On such a source
//     the hold branch is where the sender lives, and "the next fresh frame" never comes.
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
    private static let musicMap = "Sources/Echoelmusic/Sync/MusicMediaMapping.swift"

    // MARK: - 1 · the selector exists

    /// ⛔ SCOPED TO `lichtSection`, NOT TO THE FILE (#731). The first version read the whole
    /// file while its failure message said "the LIGHT SECTION no longer binds a Picker" —
    /// moving the row into `networkOutSection` would have kept it green while the message
    /// asserted something untested. That is #367 in its mirror form: green for a reason other
    /// than the one the message states.
    func testTheLightSectionOffersBothResolutions() throws {
        let section: [String] = try memberBody(startingWith: "private var lichtSection",
                                               in: Self.patchbay)
        let code: String = section.joined(separator: "\n")
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

    /// ⛔ IT SCANS TWO FILES, NOT ONE (#731). The first version read `ArtNetSender.swift`
    /// alone, but the resolution the new binding writes also selects a branch in
    /// `MusicMediaMapping.swift:43-44`, reached from `ArtNetSender.swift` and `SACNSender.swift`
    /// on the music-driven path — removing THAT branch was invisible.
    /// ⚠️ AND THE MESSAGE READS STRONGER THAN THE ASSERTION: `case .eightBit` occurs three
    /// times in `ArtNetSender.swift`, so this reds only when ALL of them are gone. It is a
    /// premise-holder, not an exhaustiveness check — the compiler is the exhaustiveness check.
    func testTheEncoderStillBranchesOnBothResolutions() throws {
        for path in [Self.artNet, Self.musicMap] {
            let code: String = try codeOf(path)
            XCTAssertTrue(code.contains("case .eightBit"), """
                \(path) no longer has an `.eightBit` encoder branch. The Picker would then \
                offer a mode that produces nothing on that path, which is worse than the \
                doorless state it replaced — the operator would believe the rig was switched.
                """)
            XCTAssertTrue(code.contains("case .sixteenBit"), """
                \(path) no longer has a `.sixteenBit` encoder branch — the default mode of \
                every launch.
                """)
        }
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
    /// ⛔ WRITTEN WITH `components(separatedBy:)` AND A PLAIN LOOP ON PURPOSE (#731). The
    /// first version used `split(separator:omittingEmptySubsequences:).map(String.init)` plus
    /// two inferred `prefix { … }.count` closures inside a `firstIndex { … }` — the exact
    /// four-stage generic chain #726 had spent a cycle removing from the sibling guard one
    /// commit earlier ("took 550ms to type-check, limit 200ms"). It is a warning, not an
    /// error, so nothing would have turned red; it would simply have been re-paid.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines: [String] = try codeOf(path).components(separatedBy: "\n")
        var start: Int = -1
        for i in 0..<lines.count where lines[i].contains(prefix) {
            start = i
            break
        }
        guard start >= 0 else {
            throw DMXAnchorMissing(reason: """
                `\(prefix)` is gone from \(path). A missing ANCHOR fails rather than skips \
                (#454) — otherwise a rename would leave this claim silent about a binding that \
                no longer drives both senders.
                """)
        }
        let indent: Int = Self.leadingSpaces(lines[start])
        var close: Int = lines.count
        for i in (start + 1)..<lines.count {
            let trimmed: String = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "}" && Self.leadingSpaces(lines[i]) == indent {
                close = i
                break
            }
        }
        return Array(lines[(start + 1)..<close])
    }

    private static func leadingSpaces(_ line: String) -> Int {
        var n: Int = 0
        for c in line {
            if c == " " { n += 1 } else { break }
        }
        return n
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
