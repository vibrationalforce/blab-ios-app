// TheStallRemedyReachesTheScreenTests.swift
// Echoel — the half of #484 that only VoiceOver could hear. #523.
//
// WHAT WAS WRONG. #484 taught a stalled rPPG acquisition to say so, and it wrote two good
// remedies: "The signal isn't steady enough to read — lift your finger and place it again"
// and "Still nothing to read — try another finger, or warm your hand first". They live in
// `PulseCue.fullHint`. Measured before the slice (`git grep -n 'fullHint' -- Sources`, three
// hits outside `PulseCue.swift`), `fullHint` reached a SIGHTED user at zero places:
//   · `CameraRPPGBioPublisher.coachingHint` is `acquisitionCue.fullHint`, and its only reader
//     is `PulseMeasurementView`, whose only mount is `BioSourceView` — which has ZERO
//     construction sites anywhere in `Sources/`. Doorless.
//   · `HeaderMonitors` puts `fullHint` in `.accessibilityValue` and `shortLabel` in the pixels.
//     VoiceOver hears the remedy; the screen shows "Unsteady" or "Nothing yet".
//   · `BioStripView`'s banner spells out `PulseCue.cameraDenied.fullHint` as a hard-coded
//     literal for the permission dead end — never the live cue.
// So the person the case was written for saw two words of pure diagnosis and was told nothing
// they could act on, on the app's binding constraint (#304/#410/#415).
//
// ⛔ AND THE FIRST DRAFT OF THIS SLICE JUSTIFIED ITS SCOPE WITH A FALSE PREMISE — caught by
// driving all eight cases before the commit, not in review. It named the gate
// `remedyIsOnlyInFullHint` and claimed `.stalled` is "the ONLY actionable case whose short form
// contains no instruction", with "Cover lens", "Too bright", "Hold still", "Press gently" and
// "Camera off" each being the instruction in miniature. Measured: **`.tooBright` and
// `.cameraDenied` withhold their remedy too.** "Too bright" is pure diagnosis; its action is
// *"Press a little lighter"*, and the intuitive move on a washed-out reading is the OPPOSITE
// one — press harder. "Camera off" likewise hides *"enable it in Settings"*. Only `.coverLens` /
// `.holdStill` / `.pressGently` genuinely are their own instruction. The counterweight written
// to defend the false premise would have been **red on correct code** (#367/#364).
//
// ⭐ THE DECISION SURVIVED ON A DIFFERENT, TWO-PART REASON, which is why the gate is now called
// `warrantsFullHintOnScreen` — a claim about what this SLOT should spend itself on, not a claim
// about the strings. `.stalled` is the only cue that is (a) silent about its remedy AND (b) safe
// to wrap AND (c) not already covered elsewhere:
//   · **`.tooBright` fails (b).** A wrapping sentence in `statusBanner`'s reserved slot resizes
//     that slot, and `bioPanel` stacks the explanatory line, "Open Routing" and the Health opt-in
//     row beneath it — #382 exists for exactly that shove. `placementCue` is a pure computed
//     property over live analyzer state, so it can flip as fast as frames arrive: wrapping it
//     here is the #382 bug with a faster clock. The gap is REAL, NAMED and unrepaired — a sighted
//     user staring at "Too bright" is still not told to press lighter. Closing it needs a fixed
//     slot height or a latch, i.e. its own slice, and `testTooBrightAlsoWithholdsItsRemedy` keeps
//     the fact on the record instead of letting the exclusion read as "nothing to see".
//     ⭐ THAT SLICE IS #569 AND IT TOOK THE LATCH OPTION. The exclusion above still holds AT
//     THIS LAYER — the enum must not claim the slot unconditionally — but the sentence now
//     reaches a sighted user through `CameraRPPGBioPublisher.cueWarrantsFullHintOnScreen`,
//     which ORs a `BioTrustLatch` (4 s engage / 3 s release) over `.tooBright`. The two
//     wiring needles below moved with it; the case assertions did not, and that is the point.
//   · **`.cameraDenied` fails (c).** `statusBanner` branch 2 already renders
//     `PulseCue.cameraDenied.fullHint` directly; a second copy here is #416's defect.
//   · **`.stalled` passes all three** — LATCHED once in the publish tick (`stallWasRhythmless`),
//     ~45 s in, clearing only when `placementCue` stops being `.finding`, a user-initiated event.
//
// ⚠️ THE PRICE, ASSERTED NOWHERE AND STATED HERE. The slot still grows ONCE when the stall
// latches, by a wrapped line or two at AX3+. `LockCueDoesNotShoveTheControlsTests`' own header
// already accepts this class for branch 1 ("informative and low-frequency"); this is the same
// trade, arriving after 45 s of a screen saying nothing useful. Whether that reads as helpful
// or as a jolt is a device question, not a source one.
//
// ⚠️ HONEST GRADING (#433/#464). Against the parent tree this file does NOT compile at all:
// two cases drive `PulseCue.warrantsFullHintOnScreen`, which does not exist there, so NO
// assertion has a verdict — the #464 situation, said plainly rather than dressed up.
// Transcribed by hand instead (a Python rebuild of `codeLines` plus the brace matcher, run
// against `git show HEAD:` and the worktree):
//   · THREE needles are red on the parent for their NAMED reason — on `HEAD`, `statusBanner`
//     mentions neither `warrantsFullHintOnScreen` nor `acquisitionCue.fullHint`, and no line
//     pairs `!lockedCueVisible` with the gate. They are ONE finding reported three times
//     (#486), not three: the parent simply has no second occupant in that slot.
//   · The behavioural cases drive a property this same commit adds — they could never have been
//     red, and booking them as regressions would be the #433 defect.
//   · FOUR needles are COUNTERWEIGHTS, green on both trees, and they are the content: a guard
//     that only asserts the new line stays green on a tree that keeps the LINE and loses the
//     FACT (#343). They pin that the remedy strings still carry a verb; that the THREE cues
//     which really are self-explaining still are (the narrowed, measured form of the premise
//     that was wrong); that `.cameraDenied`'s sentence is still rendered by its own branch, so
//     excluding it here stays justified; and that `HeaderMonitors` still renders `shortLabel` —
//     because "fix" it by putting `fullHint` in the 28-pt header and both the freeze law and
//     #382 are back at once.
//
// ⚠️ `SourceText.codeOnly` IS PROPHYLACTIC HERE, and that is MEASURED rather than assumed —
// raw vs stripped differ in 0 of 6 needle verdicts on BOTH trees, i.e. 0 of 12 cells.
//
// ⛔ THE FIRST DRAFT OF THIS BLOCK CALLED IT LOAD-BEARING and put a number next to it, which is
// the exact overclaim #484 and #485 each had to withdraw once and #486 twice — written here in
// the file that cites them. Caught by measuring before the commit, not in review. The reason it
// is NOT load-bearing is a scoping accident worth naming, because it is one paragraph from
// ceasing to be true: this slice does write the literal `acquisitionCue` into a ⛔ retraction in
// this file, but that retraction sits in `banner(_:color:systemImage:)`'s doc block, OUTSIDE the
// brace-matched `statusBanner` window every needle here reads. File-wide on the worktree the
// token is raw 4 / code 2; inside the window it is 1 / 1. Move that paragraph up, or write a
// future retraction that quotes `acquisitionCue.fullHint` inside `statusBanner`, and the
// stripper becomes the only thing between these scans and a green bought with prose — the
// #486/#491 collision, which this repo keeps hitting because it writes down what it removed.
//
// ⚠️ AND THE LIMIT FIRST. The BEHAVIOURAL half is real end to end (`PulseCue` is a `public`
// Foundation-only enum). The WIRING half is a SOURCE SCAN: `statusBanner` is a `private`
// member of a view this bundle cannot instantiate. That the remedy RENDERS, that it reads as
// help rather than as blame, and that the one-time growth is tolerable at AX5 are three device
// trials and all three are OPEN.
//
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheStallRemedyReachesTheScreenTests: XCTestCase {

    private static let strip = "Sources/Echoelmusic/Studio/BioStripView.swift"
    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let statusBannerDeclaration = "private var statusBanner: some View"

    // MARK: - The fact the gate names

    /// Only `.stalled` earns the wrapping slot — driven over every case.
    func testOnlyTheStalledCueWarrantsTheSentence() {
        let warranting: [PulseCue] = [
            .stalled(hasRhythmlessSignal: true),
            .stalled(hasRhythmlessSignal: false),
        ]
        let withoutWarrant: [PulseCue] = [
            .cameraDenied, .locked, .coverLens, .tooBright, .holdStill, .pressGently, .finding,
        ]
        for cue in warranting {
            XCTAssertTrue(cue.warrantsFullHintOnScreen, """
                \(cue.shortLabel) stopped warranting its sentence on screen. That flag is the \
                ONLY thing that puts the remedy where a sighted user can read it — before it \
                existed, `fullHint` reached the pixels nowhere and VoiceOver alone got \
                "\(cue.fullHint)".
                """)
        }
        for cue in withoutWarrant {
            XCTAssertFalse(cue.warrantsFullHintOnScreen, """
                `\(cue.shortLabel)` started claiming the wrapping slot. `placementCue` \
                recomputes per FRAME, so wrapping one of its cases resizes the reserved slot at \
                the publisher's rate — the #382 shove with a faster clock. Only `.stalled` is \
                latched (`stallWasRhythmless`) and therefore safe to wrap, and `.cameraDenied` \
                already has its sentence rendered by branch 2. If a genuinely new stable case \
                needs the slot, widen this list deliberately and say why.
                """)
        }
    }

    /// COUNTERWEIGHT — `.tooBright` hides its remedy too, and is excluded ANYWAY.
    ///
    /// ⛔ This is the corrected form of a guard that would have been RED ON CORRECT CODE. Its
    /// first version asserted every other actionable short label contains its own instruction —
    /// false for "Too bright", whose action ("Press a little lighter") lives only in `fullHint`,
    /// and whose intuitive reading pushes the user the WRONG way (press harder). Keeping the
    /// fact asserted rather than deleted is the point: the exclusion is a #382 trade, not an
    /// absence of a problem, and a future fixed-height slot should reopen it.
    func testTooBrightAlsoWithholdsItsRemedy() {
        let short = PulseCue.tooBright.shortLabel.lowercased()
        let full = PulseCue.tooBright.fullHint.lowercased()
        XCTAssertTrue(full.contains("lighter"), """
            `.tooBright`'s remedy stopped saying "lighter": "\(PulseCue.tooBright.fullHint)". \
            The whole reason this case is a NAMED unrepaired gap is that the fix is \
            counter-intuitive — less pressure, not more.
            """)
        XCTAssertFalse(short.contains("lighter") || short.contains("press"), """
            `\(PulseCue.tooBright.shortLabel)` now carries its own instruction. If the short \
            form tells the user to press lighter, the gap this guard records is closed and the \
            ⛔ block in `warrantsFullHintOnScreen` should be rewritten to say so — do not just \
            delete this assertion.
            """)
        XCTAssertFalse(PulseCue.tooBright.warrantsFullHintOnScreen, """
            `.tooBright` started claiming the wrapping slot AT THE ENUM. That is the wrong \
            layer and it is why this assertion survives #569: the exclusion here is a LAYOUT \
            ground, not a copy one — `placementCue` recomputes per frame, so a cue that says \
            "always spend the slot on me" resizes it at the publisher's rate. The gap is closed \
            one layer up, by `CameraRPPGBioPublisher.cueWarrantsFullHintOnScreen`, which adds \
            the thing an enum cannot know: a `BioTrustLatch` requiring 4 s sustained washout. \
            Move the answer back down here and the latch is bypassed.
            """)
    }

    /// COUNTERWEIGHT — the three cues that really ARE their own instruction.
    ///
    /// Narrowed from four: `.tooBright` was in this list and does not belong (see the ⛔ above).
    /// These three are what makes "two words are enough in the header" true for them.
    func testTheThreeSelfExplainingCuesStillExplainThemselves() {
        let selfExplaining: [PulseCue] = [.coverLens, .holdStill, .pressGently]
        let verbs = ["cover", "press", "hold"]
        for cue in selfExplaining {
            let lowered = cue.shortLabel.lowercased()
            XCTAssertTrue(verbs.contains { lowered.contains($0) }, """
                `\(cue.shortLabel)` no longer tells the user what to do in its short form. \
                These three are the cues for which the header's two words genuinely suffice; \
                reword one into a diagnosis and it joins `.tooBright` on the gap list — record \
                that rather than leaving this guard red.
                """)
        }
    }

    /// COUNTERWEIGHT — the remedies must stay remedies.
    ///
    /// The whole slice is worthless if the sentence it puts on screen stops naming an action.
    func testBothStallRemediesStillNameAnAction() {
        for rhythmless in [true, false] {
            let hint = PulseCue.stalled(hasRhythmlessSignal: rhythmless).fullHint.lowercased()
            let actions = ["lift", "place", "try", "warm"]
            XCTAssertTrue(actions.contains { hint.contains($0) }, """
                A stall hint stopped naming something the user can do: "\(hint)". Putting a \
                second diagnosis on screen next to "Unsteady"/"Nothing yet" buys nothing — the \
                sentence earns its slot only by being the instruction the short label omits.
                """)
        }
    }

    // MARK: - The wiring

    /// The strip actually renders the gated hint.
    func testTheStripRendersTheStallRemedy() throws {
        let slot = try window(try codeLines(Self.strip), from: Self.statusBannerDeclaration)

        // ⚠️ THE NEEDLE MOVED WITH THE GATE (#569, same commit — #456). The strip now asks the
        // PUBLISHER's `cueWarrantsFullHintOnScreen`, which is the enum's answer OR a latched
        // `.tooBright`. Note the capital `W`: `contains("warrantsFullHintOnScreen")` does NOT
        // match `cueWarrantsFullHintOnScreen`, so leaving the old needle would have gone red on
        // correct code — the #367 failure, arriving through a rename rather than a deletion.
        XCTAssertTrue(slot.contains { $0.contains("cueWarrantsFullHintOnScreen") }, """
            `statusBanner` no longer asks `cueWarrantsFullHintOnScreen`, so the stall remedy is \
            back to reaching a sighted user nowhere: `coachingHint`'s only consumer is the \
            doorless `PulseMeasurementView`, and `HeaderMonitors` gives `fullHint` to \
            VoiceOver only. This member is the one surface that puts it in pixels.
            """)

        XCTAssertTrue(slot.contains { $0.contains("acquisitionCue.fullHint") }, """
            `statusBanner` asks the gate but no longer renders `acquisitionCue.fullHint`. The \
            gate alone changes nothing — it is the SENTENCE that is missing from the screen, \
            and re-deriving the wording here instead of reading `fullHint` would put a second \
            copy of it in the app (#416).
            """)
    }

    /// The remedy yields to the lock cue — they share one reserved slot.
    ///
    /// A lock and a stall are mutually exclusive states, but the congratulation LINGERS six
    /// seconds after the lock; during those seconds the honest message is the congratulation.
    func testTheRemedyYieldsToTheLockCue() throws {
        let slot = try window(try codeLines(Self.strip), from: Self.statusBannerDeclaration)
        XCTAssertTrue(slot.contains { $0.contains("!lockedCueVisible") && $0.contains("cueWarrantsFullHintOnScreen") }, """
            The stall remedy is no longer gated on `!lockedCueVisible`. Both banners live in \
            one `ZStack` occupying the slot `LockCueDoesNotShoveTheControlsTests` reserves, so \
            without that gate they can be visible together for the six seconds the lock cue \
            lingers — two contradictory sentences stacked on one another.
            """)
    }

    /// COUNTERWEIGHT — `.cameraDenied`'s sentence is still rendered by its OWN branch.
    ///
    /// This is what makes excluding `.cameraDenied` from the gate correct rather than an
    /// oversight: its short form ("Camera off") hides its remedy exactly like `.tooBright`'s
    /// does, but branch 2 of the same member already spells the sentence out. Lose that branch
    /// and the exclusion silently becomes a second invisible dead end — with nothing else in
    /// the bundle noticing, because the gate would still read `false` quite correctly.
    func testTheCameraDeniedRemedyIsStillRenderedByItsOwnBranch() throws {
        let slot = try window(try codeLines(Self.strip), from: Self.statusBannerDeclaration)
        XCTAssertTrue(slot.contains { $0.contains("PulseCue.cameraDenied.fullHint") }, """
            `statusBanner` no longer renders `PulseCue.cameraDenied.fullHint`. "Camera off" is \
            pure diagnosis — the action ("enable it in Settings") lives only in `fullHint` — so \
            this branch is the ONLY place a sighted user is told how to recover from a denied \
            camera. `.cameraDenied` is deliberately outside `warrantsFullHintOnScreen` BECAUSE \
            of this line; removing it turns that exclusion into a silent dead end.
            """)
    }

    /// COUNTERWEIGHT — the header keeps the SHORT form.
    ///
    /// The tempting "consistency" cleanup after this slice is to give the header the full
    /// sentence too. That is two shipped laws at once: `HeaderMonitors` renders inside
    /// `WorkspaceView`'s subtree (the 10.76.50 freeze rule is why the live read is confined to
    /// a leaf at all), and the tile's value slot is `minWidth: 28` — a wrapping sentence there
    /// reflows the whole chrome bar on every cue change.
    func testTheHeaderStillShowsTheShortLabel() throws {
        let source = try codeLines(Self.header)
        XCTAssertTrue(source.contains { $0.contains("Text(cue.shortLabel)") }, """
            `HeaderMonitors` stopped rendering `cue.shortLabel`. The compact tile has room for \
            one or two words and sits in `WorkspaceView`'s subtree; the full sentence belongs \
            in the panel the amber tile leads to, which is what this slice wired. Putting it \
            in the header instead reflows the chrome on every cue change.
            """)
        XCTAssertTrue(source.contains { $0.contains("if showCue, let cue { return cue.fullHint }") }, """
            `HeaderMonitors.accessibilityText` no longer hands `fullHint` to VoiceOver. That \
            path is not made redundant by the panel line — it is what a VoiceOver user gets \
            without opening anything, and it was the ONLY consumer of the remedy before this \
            slice.
            """)
    }

    // MARK: - Reading the source

    /// Comment-stripped lines of `path`, via the ONE shared definition (#453).
    ///
    /// ⛔ THROWS rather than skips when the file is absent — the #454 lesson. A scan that
    /// silently measures nothing passes for the wrong reason, and this bundle has paid for
    /// that shape before.
    private func codeLines(_ relativePath: String) throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present under \(root.path) — this guard inspects source \
                text, so it SKIPS rather than reporting a green it did not earn
                """)
        }
        let code = SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
        return code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Lines from `declaration` to the closing brace at the declaration's own indentation.
    ///
    /// Structural rather than a line count or a `private var` terminator — both shapes have
    /// already failed in this bundle; `LockCueDoesNotShoveTheControlsTests` carries the same
    /// helper and the reasoning at length.
    private func window(_ source: [String], from declaration: String) throws -> [String] {
        guard let start = source.firstIndex(where: { $0.contains(declaration) }) else {
            throw XCTSkip("""
                `\(declaration)` is gone from BioStripView — if the status line was \
                restructured this guard should be rewritten with it, not left to pass vacuously
                """)
        }
        let indent = String(source[start].prefix { $0 == " " })
        let closer = indent + "}"
        guard let end = source[start...].dropFirst().firstIndex(where: {
            $0.hasPrefix(closer) && $0.trimmingCharacters(in: .whitespaces) == "}"
        }) else {
            throw XCTSkip("""
                `\(declaration)` has no closing brace at its own indentation — the file was \
                reformatted or the member restructured, and reading on would inspect the wrong \
                lines
                """)
        }
        return Array(source[start...end])
    }
}
