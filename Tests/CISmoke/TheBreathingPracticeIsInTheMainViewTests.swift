// TheBreathingPracticeIsInTheMainViewTests.swift
// Echoel — #486. Blocking bundle.
//
// ⭐ THE ASK AND ITS SHAPE. Founder 2026-08-07 asked for "Training für kohärentes Atmen"
// alongside the chanting / humming / toning / singing half that #485 put on the mix board.
// As with #485, the CAPABILITY was already built — twice over: `BreathGuideView` (a paced
// circle with contraindications and a hold-acknowledgement gate) and `MeditationView`
// (duration, session recording, history). BOTH are doorless (#276), so none of it is
// reachable.
//
// ⭐ AND THE REASON IT STAYED DOORLESS IS A FOUNDER RULING, NOT AN OVERSIGHT — which is why
// this slice adds a strip and not a door. decisions.csv 2026-07-12, verbatim: *"Meditation
// View nicht extra. Alles findet in der Main View statt und ist Teil des
// Produktionsprozesses."* Giving the guide a chip or a sheet would obey the ask by breaking
// the ruling. The practice comes INTO `bioPanel`, directly under `BioStripView` — the
// measured half and the active half in one panel.
//
// ⚠️ HONEST GRADING — and the first draft of this paragraph got it wrong in the flattering
// direction, which is the #433 defect committed in the paragraph headed "honest grading".
// It claimed "FOUR red by absence, ONE real mount finding, THREE green on both sides". The
// three it called green each open by extracting `BreathCoachStrip`, which does not exist on
// the parent tree, so their non-empty assertion fires first and they are red too — for the
// cheap reason, not their stated one.
//
// Counted rather than remembered, against the pre-#486 tree: ALL of the strip-reading
// methods are red for the SAME single absence — the strip is not there, so `block()` returns
// "" — which is one absence reported many times, not many findings. ONE is a real mount
// finding: `testTheStripIsMountedInTheBioPanel` extracts `bioPanel`, which exists on the
// parent, PASSES its non-empty assertion, and goes red on `.contains("BreathCoachStrip()")`
// — for exactly the reason its name states.
//
// ⛔ AND THE "COUNTED RATHER THAN REMEMBERED" PARAGRAPH WAS ITSELF WRONG IN THREE PLACES,
// found by two independent reviewers who re-implemented the scanner and ran every assertion
// against both trees. Each correction is worth more than the number it replaces:
// · It cited the panel as "6849 chars raw, 2280 stripped" as EVIDENCE ABOUT THE PARENT. Those
//   are the POST-change numbers; the parent is 5255/1987. The conclusion (the parent is
//   non-empty, so this really is a mount finding) survives — the figures quoted to support it
//   described the tree the commit had already produced. A number attached to the wrong object,
//   the class CLAUDE.md logs more than any other.
// · It said "exactly TWO are green on both sides". It is THREE — the third is method 1's own
//   non-empty guard, and the sentence two lines above SAYS SO ("PASSES its non-empty
//   assertion"). One paragraph, one fact, asserted and then omitted from its own count, in the
//   flattering direction: it credited this file with one more regression than it has.
// · It stated the mechanism as "the non-empty assertion fires" for all seven. True of five.
//   `testTheThirtyHertzReadStaysInItsOwnLeafView` fires EARLIER, on the struct-declaration
//   scan, and `testThePacerStaysTimerFreeAndIsDrivenByItsHost` had no non-empty assertion at
//   all — it does now, because it was the one strip-reading method missing the #367 bracket
//   its siblings carry.
// Exact per-assertion counts are deliberately NOT restated here: this file has now been
// edited twice after being graded, and a per-assertion tally is a number that expires on the
// next edit. What does not expire is the SHAPE — one absence, many reports, one mount finding.
//
// So the backward-facing value of this file is one mount finding. Its worth is FORWARD, and
// each method names the specific, plausible, well-intentioned next edit it stands against.
//
// ⭐ THE COUNTERWEIGHT THAT MATTERS MOST IS THE LEAF-VIEW ONE, and it is the reason this
// file exists at all rather than the mount. `pacer.guidance` is rewritten ~30×/s. The
// obvious later simplification — "it is only a strip, fold it into `bioPanel` as a
// `@ViewBuilder` fragment and drop the struct" — is the 10.76.41/50 freeze at THREE TIMES
// the rate that caused it.
//
// ⛔ THE FIRST DRAFT OF THIS PARAGRAPH GOT THE MECHANISM WRONG, in the direction that makes
// the rule sound SOFTER than it is. It said `panel(_:_:)`'s builder is `@escaping` and is
// invoked inside `EchoelPanel`'s own body, so an inlined read would only land on
// `EchoelPanel`. Measured instead of asserted: `bioPanel` has NO `panel(...)` wrapper at
// its top level — the only `panel(` inside that whole declaration was that sentence itself,
// written into the mount comment. Its `VStack` reaches the screen through
// `dropdownContent`, whose own FREEZE RULE note states it plainly: evaluated in the ROOT
// body PERMANENTLY. So inlining this fragment puts a 30 Hz read directly on
// `EchoelStudioView.body` — the body that hosts every `.menu` Picker of the instrument.
// Not one hop from the freeze; the freeze.
//
// Note also the argument that does NOT work: `bioPanel` hosts no `Picker` today, so "it
// cannot tear down a menu" is true of the current tree and useless as a rule — the read
// would be on the ROOT body, not on this panel. `AnyView(bioPanel)` is not a boundary
// either (10.76.50). A separate `View` struct is one, which is why the pin is on the struct
// and not on the absence of a Picker.
//
// ⭐ THE SECOND COUNTERWEIGHT IS THE SAFETY ONE, and it is deliberately TWO assertions
// rather than one. `BreathPattern` states its own law: the UI must keep resonance
// preselected and never auto-select a hold pattern. This surface has no pattern picker, so
// (a) it must force `.resonance` when the shared pacer was left on a hold pattern by the
// doorless full-screen guide, and (b) it must render `BreathPacer.contraindications` — the
// SHARED constant, never a local copy, so the wording cannot drift from the guide above.
// A single assertion on either half would leave the other free to be "simplified" away.
//
// ⚠️ WHAT THIS FILE CANNOT DO, first, because it is most of the file. Every assertion is a
// SOURCE-TEXT SCAN. `BreathCoachStrip` is a SwiftUI `View` behind `#if canImport(SwiftUI)`
// and `pacer` is `@Environment`-injected; there is no way to render it from here. That the
// strip appears on the device, that the circle reads as a breath, that ~6/min feels right,
// and that a user can follow it are ALL device checks and all open. Nothing here says the
// practice works — only that it is present, paced by the shared pacer, and safe-by-source.
//
// ⚠️ AND AN HONEST LIMIT OF THE FEATURE ITSELF, pinned so it cannot be forgotten rather
// than fixed: the guide stops on `onDisappear`, so you cannot breathe along with the panel
// collapsed. That is the safe direction — a pacer running invisibly is a state the user can
// neither see nor stop — but it IS a limit. `testTheGuideCannotRunInvisibly` makes removing
// it a decision instead of a side effect.
//
// ⛔ `SourceText.codeOnly` WAS CALLED PROPHYLACTIC IN THE FIRST DRAFT — the exact overclaim
// #484 had to retract one slice earlier, and then the same word went the OTHER way. Three
// gradings of one fact, each measured at the time and each true only then:
// 1. First draft: "the mount comment names `BreathCoachStrip` in prose" — false. Raw
//    `bioPanel` contained the type name exactly ONCE, and it was the real call.
// 2. Retraction: "prophylactic, stripped vs raw differ on 0" — true when written.
// 3. Now: LOAD-BEARING, and measured. `testTheStripCannotInheritAHoldPattern` asserts the
//    ABSENCE of `if pacer.pattern.hasHolds`, and this slice writes exactly that string into
//    a retraction comment in `BreathGuideView.swift` explaining why the conditional form was
//    replaced. Raw text: present. Stripped: absent. Without the stripper that assertion is
//    RED on correct code.
// The lesson is the one CLAUDE.md keeps paying for in the other direction: a negative scan
// and a retraction comment naming the thing it retracts are on a COLLISION course by
// construction, because this repo writes down what it removed. #453's shared definition is
// what makes writing both safe — which is also why a private twelfth stripper here would be
// a defect and not a convenience.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathingPracticeIsInTheMainViewTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let guide  = "Sources/Echoelmusic/Studio/BreathGuideView.swift"
    private static let pacer  = "Sources/Echoelmusic/Bio/BreathPacer.swift"
    private static let app    = "Sources/Echoelmusic/EchoelmusicApp.swift"

    private static let stripAnchor = "struct BreathCoachStrip: View {"
    private static let panelAnchor = "private var bioPanel: some View {"

    // MARK: The mount

    /// RED on the pre-#486 tree at the `.contains` — `bioPanel` exists on the parent, so
    /// this is a mount finding and not an absence artefact.
    ///
    /// Stands against: quietly dropping the strip in a later `bioPanel` tidy-up. The panel
    /// would still show the numbers, so nothing else in the suite would notice that the
    /// active half of the loop went away again.
    func testTheStripIsMountedInTheBioPanel() throws {
        let panel = try block(startingAt: Self.panelAnchor, in: Self.studio)
        XCTAssertFalse(panel.isEmpty, """
        could not extract `bioPanel` from \(Self.studio) — the anchor \
        \(Self.panelAnchor) is gone, so every assertion below would pass on an empty \
        slice. Fix the anchor; do not delete the test (#367).
        """)
        XCTAssertTrue(panel.contains("BreathCoachStrip()"), """
        `bioPanel` no longer mounts `BreathCoachStrip()`. The breathing practice is the \
        ACTIVE half of the loop the panel measures, and it has no other door: \
        `BreathGuideView` and `MeditationView` are both doorless (#276), deliberately, \
        because of the founder ruling that there is no separate Meditation view. Removing \
        this mount makes the practice unreachable again — it does not move it.
        """)
    }

    /// RED (absence) on the pre-#486 tree.
    ///
    /// Stands against: the single most plausible next edit — "it is only a strip, inline it".
    /// See the header: `bioPanel` has no `panel(...)` wrapper, it is reached through
    /// `dropdownContent`, so an inlined 30 Hz read lands on the ROOT body — and "there is no
    /// Picker here" is a fact about today's tree, not a rule.
    func testTheThirtyHertzReadStaysInItsOwnLeafView() throws {
        let src = try code(of: Self.guide)
        XCTAssertTrue(src.contains(Self.stripAnchor), """
        `BreathCoachStrip` is no longer a `View` struct. `pacer.guidance` is rewritten \
        ~30×/s, and `bioPanel` is reached through `dropdownContent`, which is evaluated in \
        the ROOT body permanently — so an inlined read enrols `EchoelStudioView.body` as a \
        30 Hz observer and tears down every open `.menu` Picker of the instrument: the \
        10.76.41/50 freeze at three times the rate that caused it. A separate `View` struct \
        is the observation boundary; `AnyView` is not. Keep the struct.
        """)
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, """
        could not extract `BreathCoachStrip` from \(Self.guide) — fix the anchor rather \
        than the assertion (#367).
        """)
        XCTAssertTrue(strip.contains("pacer.guidance"), """
        `BreathCoachStrip` no longer reads `pacer.guidance`. If the paced amplitude moved \
        somewhere else, the 30 Hz read moved with it — re-point this assertion at its new \
        home in the SAME commit, so the leaf-view law keeps a witness.
        """)
    }

    // MARK: Safety — two halves, deliberately not one

    /// RED (absence) on the pre-#486 tree.
    ///
    /// Stands against: "the pacer already defaults to `.resonance`, this line is dead", and
    /// against the narrower version — "only force it when the pattern actually has holds".
    ///
    /// ⛔ The first draft asserted `hasHolds` AND the assignment, because the source was
    /// conditional. Both were corrected after review, and the reason is worth keeping: the
    /// conditional left `.coherent` untouched, so a re-doored guide could hand this strip a
    /// pattern its caption does not describe. It also justified itself with a sentence
    /// containing its own refutation — "the DOORLESS full-screen guide can LEAVE it on Box
    /// or 4-7-8". A doorless surface cannot leave anything: measured, the three writers of
    /// `pacer.pattern` are `BreathGuideView`'s picker (reachable only from `BioSourceView`,
    /// zero instantiations), `MeditationView` (reachable only via `showMeditation`, no
    /// setter at all), and this line. No reachable path can hand this strip a hold pattern
    /// TODAY. The forcing stays because it is what lets this surface honestly omit the
    /// hold-acknowledgement gate the day one of those is re-doored — not because of a
    /// hazard that exists now.
    func testTheStripCannotInheritAHoldPattern() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains("pacer.pattern = .resonance"), """
        `BreathCoachStrip` no longer forces `.resonance`. `BreathPacer` is SHARED, this \
        strip has no pattern picker, and it therefore cannot show the hold-acknowledgement \
        gate — `BreathPattern` states the law itself: the UI keeps resonance preselected and \
        never auto-selects a hold pattern. If this surface ever gains a picker, it gains the \
        gate in the SAME commit.
        """)
        XCTAssertFalse(strip.contains("if pacer.pattern.hasHolds"), """
        the forcing is conditional again. `hasHolds` is FALSE for `.coherent` (5 s/5 s), so \
        the conditional form lets a re-doored guide hand this strip a pattern the caption \
        does not describe. Both pace 6.0/min, so this is not a rate hazard — it is the \
        caption becoming false, and the unconditional form costs nothing because `reset()` \
        runs on the next line regardless.
        """)
    }

    /// RED (absence) on the pre-#486 tree.
    ///
    /// Stands against: "the strip is small, drop the four bullet lines" — and against the
    /// subtler version, pasting a shortened local copy of them. It anchors on the SHARED
    /// constant so a local re-wording fails even if it looks identical today.
    ///
    /// The SECOND half is the one review added, and it is about VISIBILITY rather than
    /// wording — the half a "renders the shared constant" scan cannot see. The first draft
    /// gated the bullets on `!pacer.isRunning`, citing the constant's own doc ("shown BEFORE
    /// a session"). Read the four lines instead of the doc: "breathe gently, never strain"
    /// and "stop if you feel dizzy or short of breath" are DURING-session instructions, the
    /// second being the only one that names an adverse event, and the fourth is the
    /// CLAUDE.md-mandated self-observation disclaimer. All four disappeared exactly while
    /// the session ran. That guarantee — "cannot drift from the guide" — covered wording and
    /// not visibility, and the divergence was in visibility.
    func testTheStripRendersTheSharedContraindications() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains("BreathPacer.contraindications"), """
        `BreathCoachStrip` no longer renders `BreathPacer.contraindications`. It must read \
        the SHARED constant, never a local copy: two copies of a safety notice are two \
        things that drift, and the doorless full-screen guide renders the same constant. \
        Shortening the list is a founder decision about safety copy, not a layout tidy-up.
        """)
        XCTAssertFalse(strip.contains("if !pacer.isRunning"), """
        the contraindications are gated on `!pacer.isRunning` again. Two of the four lines \
        are DURING-session instructions and one of those is the only line naming an adverse \
        event ("stop if you feel dizzy"); hiding them at the moment they apply inverts their \
        purpose, and it takes the mandated self-observation disclaimer with it. It also \
        inserts ~7 wrapped lines into the layout on every Start/Stop — the #382 shove, in \
        the panel #382 was written about. `BreathGuideView` renders its copy unconditionally.
        """)
    }

    /// RED (absence) on the pre-#486 tree.
    ///
    /// ⛔ This method exists because the FIRST draft re-committed the #485 defect one commit
    /// after #485 fixed it. The button was `minHeight: 34` with no `contentShape`, justified
    /// by "the neighbouring Open Routing button one row down still pins 34" — the same shape
    /// of wrong reference #485 had (`masterDoorButton`): the neighbour has the same omission
    /// and has simply never been audited. Under `.buttonStyle(.plain)` the hit test follows
    /// the LABEL'S GLYPH RUN (~15–17 pt, measured in #485), so a frame without a content
    /// shape grows the layout and not the target — under WCAG 2.5.8's 24 pt floor, never
    /// mind HIG's 44. `TapTargetFloorTests` is a pinned allowlist scoped to other files, so
    /// nothing would have gone red.
    ///
    /// Stands against: shrinking it back to match its unaudited neighbour.
    func testTheTransportIsAReachableTapTarget() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains(".frame(minHeight: 44)"), """
        the breathing guide's Start/Stop button is no longer at least 44 pt tall. This is \
        the ONLY transport for the practice — with the panel scrolled or the button missed, \
        there is no other way to stop the pacer. `minHeight` and not `height` (#262), so a \
        large Dynamic Type setting grows the label rather than clipping it.
        """)
        XCTAssertTrue(strip.contains(".contentShape(Rectangle())"), """
        the Start/Stop button lost `.contentShape(Rectangle())`. Under `.buttonStyle(.plain)` \
        the frame above then grows the LAYOUT without growing what is hit-tested — the \
        label's glyph run stays the target and the 44 becomes decoration. This is the exact \
        wording `TapTargetFloorTests` uses about the loudness Reset, and the exact defect \
        #485 fixed one commit before this file was written.
        """)
    }

    /// RED (absence) on the pre-#486 tree.
    ///
    /// This one pins a LIMIT rather than a feature, so that lifting it is a decision.
    /// Stands against: removing `onDisappear` to "let the guide keep running while you
    /// work" — which sounds like a feature and installs a pacer the user can neither see
    /// nor stop.
    func testTheGuideCannotRunInvisibly() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains(".onDisappear { pacer.stop() }"), """
        `BreathCoachStrip` no longer stops the pacer when the panel closes. Letting it run \
        on reads as a feature and is a state the user can neither see nor stop: the only \
        transport is inside this strip, so with the panel collapsed there is no Stop. If \
        background pacing is really wanted it needs a visible always-on indicator and its \
        own founder decision — not the removal of this line.
        """)
    }

    /// RED (absence) on the pre-#486 tree.
    ///
    /// The screen must stay awake while the guide paces. This repo had ALREADY made that
    /// decision — `updateKeepAwake()` lists `showMeditation` — but that flag has no setter,
    /// so the decision only ever applied to an unreachable surface. A training session with
    /// the transport STOPPED is exactly the case where every other term is false, so the
    /// screen dimmed and locked mid-session.
    ///
    /// Stands against: "one `.onChange` per flag is clearer" — which regrows the root body's
    /// modifier chain for no behaviour, and against dropping `showMeditation` from the OR
    /// because it is dead today, which silently un-wires it for the day it is re-doored.
    func testTheScreenStaysAwakeWhileThePracticeRuns() throws {
        let studio = try code(of: Self.studio)
        XCTAssertTrue(studio.contains("|| breathPacer.isRunning"), """
        `updateKeepAwake()` no longer counts a running breathing guide. With the transport \
        stopped — the normal state for a breathing session — every other term is false, so \
        iOS dims and locks the screen while the user is following the circle.
        """)
        // ⭐ #1044 WIDENED THIS LITERAL, and this is the §4 case in the flesh: the slice that
        // added the external-screen term had to move THIS needle in the SAME commit, or a
        // guard over correct code would have hit `XCTAssertTrue(false)` and stayed red while
        // three status deltas said nothing of mine is red (#655/#656, #960).
        //
        // The needle is deliberately still the WHOLE expression rather than a substring: what
        // it protects is that there is ONE modifier, and a substring check would stay green
        // after someone split it into three. The claim it makes is therefore now "all THREE
        // flags share one trigger", and a fourth flag moves this line again — on purpose.
        XCTAssertTrue(studio.contains(
            ".onChange(of: showMeditation || breathPacer.isRunning || isProjectingExternally)"), """
        the keep-awake trigger changed shape. It must stay ONE modifier covering ALL THREE \
        flags: splitting it up regrows the root body's modifier chain for no behaviour \
        (10.76.34); dropping `showMeditation` un-wires an unreachable surface silently \
        instead of leaving it ready for a re-door; and dropping `isProjectingExternally` \
        leaves #1044's term in `updateKeepAwake()` correct but never re-read, because this \
        expression is the only thing that observes the bridge.
        """)
    }

    // MARK: Premises — mostly green on both sides, and that is the point
    //
    // ⛔ This MARK said "green on both sides" and three method docs below repeated it. The
    // header already retracted that grading — the retraction was applied in ONE place of
    // four, which is the "look for the SECOND site" lesson CLAUDE.md logs, committed inside
    // a file whose header is about grading honestly. All three of these open by extracting
    // `BreathCoachStrip`, which does not exist on the parent, so their non-empty assertion
    // fires and they are red for the cheap reason. What each PINS is still a premise.

    /// Pins the wiring the whole slice rests on: the strip resolves
    /// `BreathPacer` from the environment, and the app injects exactly one.
    ///
    /// Stands against: someone giving `BreathCoachStrip` its own `@State private var pacer
    /// = BreathPacer()`. That compiles, renders, paces — and is a SECOND pacer, so the
    /// strip and the doorless guide would disagree about what the user is breathing.
    func testThereIsOnePacerAndItComesFromTheEnvironment() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains("@Environment(BreathPacer.self)"), """
        `BreathCoachStrip` no longer takes `BreathPacer` from the environment. Owning its \
        own instance would give the app two pacers with two different phases — the strip \
        and the doorless full-screen guide would disagree about what the user is breathing.
        """)
        let app = try code(of: Self.app)
        XCTAssertTrue(app.contains(".environment(breathPacer)"), """
        `EchoelmusicApp` no longer injects `breathPacer`. `BreathCoachStrip` is mounted in \
        `bioPanel` and resolves the pacer from the environment: without the injection the \
        strip traps at runtime the first time the Bio panel opens, and no compile gate sees \
        it (an `@Environment` miss is a runtime failure).
        """)
    }

    /// Pins the pacer's timer-free contract, which is why every host drives it from its own
    /// loop and why a second host was cheap to add at all.
    ///
    /// ⛔ THE FIRST DRAFT'S RATIONALE WAS THE INVERSE OF REALITY, and it concealed the one
    /// genuine multi-host hazard this design has. It said an internal `Timer` "would make
    /// two mounted hosts tick it twice per frame". Backwards: a timer belongs to the MODEL,
    /// so it advances the cycle once per fire no matter how many hosts are mounted. It is
    /// the CURRENT timer-free design that double-advances — `tick(dt)` does `cycleTime +=
    /// dt`, and each host runs its own 33 ms loop, so two mounted hosts pace ~12/min under a
    /// caption that says six. The DECISION is still right (pure, deterministic, testable, no
    /// clock running when nothing is on screen, and it is why a second host cost one loop);
    /// only the reason was wrong, and this repo's standard is that a wrong justification is
    /// worse than none because the next session cannot refute it.
    ///
    /// Stands against: "give `BreathPacer` its own `Timer` so hosts don't each need a loop."
    /// The real answer for two reachable hosts is a single owner or a monotonic `tick(at:)`.
    func testThePacerStaysTimerFreeAndIsDrivenByItsHost() throws {
        let src = try code(of: Self.pacer)
        XCTAssertFalse(src.contains("Timer.") || src.contains("Task.sleep"), """
        `BreathPacer` has grown its own clock. It is a PURE, timer-free model driven by \
        `tick(_:)` from whichever view is on screen — deterministic, testable, and with no \
        clock running when nothing is mounted, which is what let a second host \
        (`BreathCoachStrip`) exist for the cost of one loop. NOTE the cost of that choice, \
        which a timer would NOT cause: `tick(_:)` accumulates, so two mounted hosts double \
        the paced rate. Only one host is reachable today (`BreathGuideView` and \
        `MeditationView` are both doorless); the day a second is doored it needs a single \
        owner or a monotonic `tick(at:)`, not a `Timer`.
        """)
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, """
        could not extract `BreathCoachStrip` from \(Self.guide) — this was the one \
        strip-reading method missing the #367 bracket its siblings carry, so a broken anchor \
        used to report "no longer ticks the pacer" instead of "the anchor is gone".
        """)
        XCTAssertTrue(strip.contains("pacer.tick("), """
        `BreathCoachStrip` no longer ticks the pacer. `BreathPacer` has no clock of its \
        own, so a host that does not tick it renders a circle that never moves — a control \
        that lies by standing still.
        """)
    }

    /// Pins the reason this animation is allowed to exist at all.
    ///
    /// Stands against: "the breath circle would read better with a pulse/glow on each phase
    /// change." One breath cycle is ~10 s, so the circle moves at ~0.1 Hz — a **30×** margin
    /// under the 3 Hz WCAG ceiling (⛔ the first draft said "two orders", which is 100×; the
    /// source comment said "more than an order of magnitude", which is right. Two artifacts,
    /// one commit, two numbers). A per-phase flash is a DIFFERENT rate, and the Reduce
    /// Motion path is what carries pacing for anyone who cannot take motion at all.
    ///
    /// ⛔ The first draft anchored on the bare token `accessibilityReduceMotion`, which the
    /// `@Environment` DECLARATION alone satisfies: delete both uses and keep the property,
    /// and the test stays green while the circle animates under Reduce Motion. That is the
    /// #367 shape this file argues against seven times. It anchors on the `.animation` line
    /// now — the one that carries the behaviour.
    func testTheBreathCircleHonoursReduceMotion() throws {
        let strip = try block(startingAt: Self.stripAnchor, in: Self.guide)
        XCTAssertFalse(strip.isEmpty, "could not extract `BreathCoachStrip` from \(Self.guide)")
        XCTAssertTrue(strip.contains(".animation(reduceMotion ? nil :"), """
        the breath circle animates regardless of Reduce Motion. Reading \
        `accessibilityReduceMotion` is not enough — this is the line that acts on it. Under \
        Reduce Motion the circle must be static and `pacer.instruction` carries the pacing \
        instead, which is a COARSER grain (phase boundaries only, every 4 s / 6 s) and is \
        stated as a limit at the source rather than claimed as parity.
        """)
        XCTAssertTrue(strip.contains(".accessibilityHidden(true)"), """
        the breath circle is no longer hidden from VoiceOver. It is decoration that repeats \
        what `pacer.instruction` already says in words; announcing a shape-scale to a blind \
        reader adds noise, not information.
        """)
    }

    // MARK: Helpers

    /// The text of a declaration, from `anchor` to its matching close brace, with comments
    /// removed first. Brace-counted rather than line-counted so an inserted line cannot
    /// silently truncate the scan, and it returns "" when the anchor is missing so callers
    /// fail loudly instead of passing on an empty slice (#367).
    ///
    /// ⚠️ IT COUNTS BRACES IN STRING LITERALS TOO, and `SourceText.codeOnly` deliberately
    /// preserves literals. `bioPanel` contains `\u{201C}` / `\u{201D}` escapes — each
    /// contributing one `{` and one `}` — so today the extractor survives because those
    /// happen to BALANCE, not because it is robust. A single unbalanced brace inside a
    /// future literal in either scanned declaration would truncate the slice (loud, fine) or
    /// over-extend it (a false PASS, not fine). Named rather than fixed: a literal-aware
    /// scanner belongs in `SourceText` next to `codeOnly`, as one definition for the whole
    /// bundle (#453), not as a private twelfth copy here.
    private func block(startingAt anchor: String, in path: String) throws -> String {
        let src = try code(of: path)
        guard let start = src.range(of: anchor) else { return "" }
        var depth = 0
        var index = src.index(before: start.upperBound)   // the anchor's own `{`
        while index < src.endIndex {
            let ch = src[index]
            if ch == "{" { depth += 1 }
            if ch == "}" {
                depth -= 1
                if depth == 0 { return String(src[start.lowerBound...index]) }
            }
            index = src.index(after: index)
        }
        return ""
    }

    /// File contents with comments stripped by the ONE shared stripper (#453) — a single
    /// compiler-order pass, so a `//` inside a string literal is not treated as a comment.
    private func code(of path: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(path)
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    /// Gates on the DIRECTORY, not on each file: a `fileExists` bracket around every read
    /// turns the very catastrophe this bundle exists for into a green SKIP (#472).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
