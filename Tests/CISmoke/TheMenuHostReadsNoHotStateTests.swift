// TheMenuHostReadsNoHotStateTests.swift
// Echoel — #918 (bio producer) · #919 (meter + automation producer).
// The freeze that cost five device builds, and the SECOND producer that can cause it.
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
// ⛔ THIS GUARD HAS BEEN WRONG TWELVE TIMES. Defects 1–8 were found by DRIVING it as a
// mutation — never by reading it — and the eighth (#919) is the first that was RED on a correct
// tree and SHIPPED that way, invisible behind two known blind spots at once.
//
// ⭐ DEFECTS 9–12 CAME FROM A SECOND READER, NOT FROM MORE DRIVING, and that is the finding of
// #919b. I drove nine mutants, transcribed all 29 assertions, and swept the whole repo — and
// still missed a false green, a missing floor, a #364 false red, and a whole needle. Driving
// answers "does my model of the guard behave?"; it cannot ask "is my model of the guard the
// right one?". Both were needed, and the reviewer independently reproduced defect 8 from its
// own transcription, which is the only reason I trust either of us on it:
//     9.  FALSE GREEN — `environmentReceiver` searched the WHOLE FILE.
//         `EchoelStudioView.swift` declares that binding twice; delete the HOST's and the leaf's
//         is returned, the unwrap succeeds, and the "still used in this file" check passes too.
//         The scan then ran with a receiver the scanned type no longer had. Now type-scoped.
//     10. FALSELY GREEN — the meter derivation had NO floor while the bio half had one. Move
//         those declarations elsewhere and the set silently collapses to one name, with both
//         engine scans green over a needle set that looks for almost nothing.
//     11. RED ON CORRECT WORK (#364) — every anchor asserted a MAGNITUDE (`> 20`, `> 0`).
//         Extracting reads into their own leaf structs — the repair THIS FILE TEACHES — removes
//         members from the scanned type. `EchoelmusicApp` had exactly one, so inlining it went
//         red. The anchor is now "the scan still found `body`".
//     12. COVERAGE GAP — `: some Scene {` was not a needle, so `EchoelmusicApp.body`, the
//         OUTERMOST body in the app, was skipped while its child `mainContent` was scanned. The
//         file whose thesis is "the read was one level up" was missing the top level.
//
// Recorded in full because the pattern is the finding:
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
//     4. `-> some View` FUNCTIONS were not scanned at all. A mutant put a hot read in
//        `menuChip` and the guard stayed green. ⛔ The counts that stood here ("19 in
//        `EchoelStudioView`, 1 in `WorkspaceView`") were FILE-wide under a TYPE-scoped scan —
//        inside the scanned spans it is 18 and 0, and `WorkspaceView`'s single one belongs to
//        another struct the scan never enters. A retraction that motivates a needle with a
//        number the needle cannot reach.
//     5. A ONE-LINE computed property in the PUBLISHER was not treated as computed, so
//        `rrWindowMs` and `coachingHint` never entered the derivation.
//     6. The computed pass was ONE HOP through PUBLIC members only. `acquisitionCue` reaches
//        its hot inputs through a private `placementCue`; `coachingHint` needs three hops.
//     7. `SurfaceHost` — a third ancestor between the root and the Picker host — was not
//        scanned at all.
//     ⛔ #919 FOUND THAT THIS REPAIR WAS INCOMPLETE AND SHIPPED RED — see `mentions`. Treating
//        the one-liner as computed was necessary and not sufficient: its body was then tested
//        with a needle that could not match, so `rrWindowMs` still never entered the set.
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
//   · It scans view-BUILDING members (`: some View {`, `-> some View {`) of the named ancestor
//     types, in their `struct` and in any `extension`. A read inside a plain helper called
//     FROM a body is still a real defect and is not seen. ⛔ THIS SAID "the two that exist
//     today … which is CHECKED, not assumed" and both halves were wrong. It is THREE
//     (`snapToLockWhenReady`, `startBioSource`, `bodyTempoTrustworthy`) — and the `why:` message
//     of the host scan said three in the same file, 200-odd lines away, so one fact carried two
//     numbers. And nothing checks it: `git grep bodyTempoTrustworthy -- Tests/CISmoke` finds
//     nothing, and no assertion here touches a call site. The CONCLUSION survives a hand read —
//     all three are reached from action paths — but "checked" was the claim, and it was assumed.
//   · An ACTION closure written inside such a member (`Button { … }`, `.onAppear { … }`,
//     `.task { … }`) is not body evaluation, and a hot read there would be reported although
//     it is safe. None exists today. Note the neighbouring case is the OPPOSITE: the value
//     argument of `.onChange(of:)` IS evaluated during body, so flagging that is correct.
//   · It anchors on a RECEIVER SPELLING. An alias (`let cam = cameraRPPG`), a hot value passed
//     down as a function argument, or a renamed binding is invisible to it. The `AudioEngine`
//     half derives its spelling from the file's own `@Environment` binding, so a rename moves
//     the guard with it; the bio half still has the name written down and a counterweight
//     proving it still matches.
//
// ⭐ #919/#928 — THERE ARE THREE PRODUCERS, and the second is SIX TIMES HOTTER. (#919 found
// two and this line said "TWO" for three weeks; #928 found the third, `metronome.bpm`, at
// the bottom of section 6. A count of producers is an ENUMERATION of what someone thought
// of, never a measured set — the same law the MPE surfaces taught.) `AudioEngine` runs a
// 60 Hz meter poll timer over a set of `@Observable` readouts, and `AutomationPlayer.applyStep`
// rewrites `masterVolume` on every transport step. Same defect class, same repair, no guard
// until now — and the automation half is not hypothetical: `MasterVolumeField` exists as its
// own struct BECAUSE that read once sat inline in `masterPanel` and tore down the Tonart/Genre
// Picker. The scan is shared rather than copied into a sibling file: it has been wrong seven
// times, and a copy would inherit all seven.
//
// ⚠️ THE THREE SCANS COVER DIFFERENT NUMBERS OF ANCESTORS — say it exactly. The chain is
// `EchoelmusicApp` → `WorkspaceView` → `SurfaceHost` → `EchoelStudioView`. The BIO scan runs on
// all four. The ENGINE scan runs on two: `EchoelStudioView`, which declares an
// `@Environment(AudioEngine.self)` binding, and `EchoelmusicApp`, which owns the engine as
// `@State`. `WorkspaceView` and `SurfaceHost` hold no engine reference at all, so pointing the
// engine scan at them would be a claim that cannot fail (#367). Nine files under `Sources/`
// declare an `@Environment(AudioEngine.self)` binding, so "only `EchoelStudioView` has one"
// would be false — that was the over-broad first draft of this very line. The day one of the
// other two gains a reference, point the same call at it; nothing else has to change.
// The METRONOME scan (#928) covers the same two, for the same reason and with one addition:
// `testTheTwoMiddleAncestorsHoldNeitherNarrowProducer` asserts that PREMISE — that neither
// middle ancestor references the type at all — so the day one of them gains the binding the
// guard goes red and NAMES the scan that has to be extended, instead of the gap sitting there
// silently. ⚠️ So "the day one gains a reference, point the call at it" is no longer a hope
// you have to remember: it is a failing test that tells you.
// ⭐ #929 GENERALISED IT: the same claim now covers `AudioEngine`, because measured, the engine
// scan had the identical hole and had had it longer. `CameraRPPGBioPublisher` is deliberately
// absent from that table — `WorkspaceView` must hold it (`isRunning`), and listing it would
// forbid required work (#364). The bio scan needs no premise: it already covers all four.
//
// ⛔ AND THE FOURTH ANCESTOR WAS FOUND THE SAME WAY THE THIRD WAS — by asking whether the LIST
// was complete rather than whether each entry was right. `EchoelmusicApp` sits above
// `WorkspaceView`, owns BOTH publishers, and builds `mainContent`; #918 enumerated the
// surfaces a session thinks about and stopped one short, exactly as its own defect 7 did with
// `SurfaceHost`. Twice now. The rule to carry forward: when every checked item is the same
// KIND, suspect the enumeration, not the entries.
//
// ⭐ MEASURED BEFORE THE CLAIM WAS WRITTEN, over the whole repo and not just the ancestors:
// exactly four `View` structs read a hot engine readout today — `ScopePeakLabel`,
// `MasterVolumeField`, `MasterLoudnessGrid`, `SpectralDonutView` — every one a small dedicated
// leaf, and NONE of them hosts a `Picker`. `AudioInputPickerView` and `FloatingVisualWindow`
// hold the binding and read nothing hot. So the tree is clean by construction as well as by
// this scan, which is what makes this a recurrence guard rather than a bug report.
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
// ⚠️ HONEST GRADING (#433/#464) — the parent is `99b0829`, measured against it by DRIVING every
// assertion, not from memory.
//
// **1 REGRESSION, and it was already shipped RED.** On the parent,
// `testTheHotSetIsDerivedAndSelectsTheOneThatCausedTheFreeze` FAILS its `rrWindowMs` claim: the
// `mentions` boundary bug below made the `analyzer.` seed branch dead, so the hot set was 13
// where it should be 14. Red on the parent for exactly the reason its name gives, green here.
// Calling this slice "0 regressions, pure prevention" would have been the flattering-direction
// error §3 warns about — and I nearly did, because the SOURCE tree is clean for both producers
// and that is what I checked first. The tree being clean and the GUARD being green are two
// different questions.
//
// **#928 ADDED FIVE FORWARD GUARDS (section 6) — PROPHYLAKTISCH (0 of 5).** All five are green
// on their parent `d540d08` and green here: a forward guard, not a regression found. Driven,
// not read: four mutants (a `.bpm` read in the host → claim 3 red with the line; the relay
// renamed → claim 1 red plus the `found` assertion; a second relay writing `beatsPerBar` →
// claims 2 AND 3 red; `bpm` marked `@ObservationIgnored` → claim 1 red).
// ⛔ AND #928's OWN FIRST DRAFT SHIPPED TWO DEFECTS A REVIEWER FOUND BY READING, WHICH IS WHY
// "I drove four mutants" is not the same sentence as "this is sound": claim 3's anchor
// `contains("var metronome")` also matched `private var metronomeRow` one file-section away —
// a FOURTH needle collision after #921b/#924/#926, and the first not caught by driving — and
// claim 4 is green only because the relay writes `metronome?.bpm` with a `?`. Both are
// repaired in #928b and both are written down at the claims themselves.
//
// The three older sections: 0 FORWARD guards. 0 red by ANCHOR ABSENCE. Everything else is a
// COUNTERWEIGHT, and per §343 that is the content. The counterweights exist so no negative
// claim can pass by finding nothing (#367): each derivation must SELECT a named property
// (`waveform`, `rrWindowMs`, `coachingHint`, `masterLevel`, `masterVolume`) and must EXCLUDE
// one (`isRunning`, `monitorPollTick`); the leaves must still read what the scans look for;
// each scan asserts it found view-building members; and every receiver spelling is proved real
// before it is used — unwrapped where it is derived, and asserted against its DECLARATION where
// it is written down.
//
// ⚠️ ONE CLAIM CARRIES A NEEDLE THAT IS MEASURED UNMATCHABLE, and "every anchor is asserted"
// must not paper over it: `testTheAppLevelAncestorBuildsNoViewFromHotBio` scans a file where
// `cameraRPPG.` occurs ZERO times — the app only INJECTS the object. Its DECLARATION anchor
// proves the object exists and the spelling is real; it does NOT prove the needle could ever
// match. Kept anyway, because the point of that scan is the day someone adds the first such
// read to the topmost body — but it is the one negative claim here without a matching
// counterweight, and it is named rather than counted as covered.
// ⚠️ #928 MADE IT THREE, and the file's rule is that they be NAMED, not counted as covered.
// After `SourceText.codeOnly`, `metronome.bpm` occurs ZERO times in BOTH `EchoelStudioView`
// and `EchoelmusicApp` — its only two occurrences in the latter are comments, and the relay's
// own write carries a `?`. So both metronome scans are forward guards over a needle that
// cannot match today, exactly like the bio app-level one. There is also no reachability
// counterweight for the metronome half (no `…StillReadsTheClicksTempo` leaf test), because
// there is no leaf reading it — the day one is written, that test is the counterweight to add.
//
// ANCHOR ABSENCE: 0 — every anchor is asserted, including the 60 Hz
// interval literal, which XCTFails by name rather than returning an empty set.
//
// ⚠️ THAT SENTENCE IS TRUE OF THE START ANCHOR ONLY, and the first draft let it stand for both
// ends. `span` falls back to `lines.endIndex` when it finds no closing brace at the opener's
// indentation — SILENTLY. A reformatted closer therefore over-collects rather than failing, and
// the floor on the derived set is what catches the consequence. Do not read "every anchor
// XCTFails" as covering the closing brace; it does not.
//
// ⛔ ONE OF THOSE ANCHORS WAS NEARLY A CLAIM THAT COULD NEVER HOLD. The app-level counterweight
// was going to be "the app still reads `cameraRPPG.`" — by symmetry with the leaf claims. It
// occurs ZERO times there: the app only INJECTS the object. Measuring the anchor before
// writing it is what turned it into a DECLARATION check; by symmetry alone it would have been
// a red guard on a correct tree, in the same file that already carries two of those (#367).
//
// ⛔ THE FOUR #919b REPAIRS WERE DRIVEN TOO, not just reasoned: removing the HOST's own
// `@Environment` binding must now yield nil (it does — the old file-wide lookup returned the
// leaf's name, the exact false green); a hot read placed in `EchoelmusicApp.body` must go RED
// (it does — it was invisible before); and renaming or extracting a member must leave the
// anchor GREEN (it does — that is the whole point of dropping the magnitude).
//
// ⛔ AND THE BOUNDARY REPAIR WAS DRIVEN IN BOTH DIRECTIONS, because a looser needle is how a
// guard starts matching things it should not: an identifier needle must still refuse
// `isLockedExtra` and `wasIsLocked` (it does), a receiver needle must still refuse
// `myanalyzer.foo` (it does), and it must match `analyzer.rawIntervalsMs` and a trailing
// `analyzer.` (it does). Only the RIGHT boundary was relaxed, and only for a needle that ends
// in a non-word character.
//
// ⛔ THE #919 LOGIC WAS DRIVEN AS NINE MUTATIONS BEFORE IT WAS BELIEVED, because #918
// proved that reading a guard finds nothing (four of its seven defects were FALSELY GREEN and
// invisible to any run on correct code). Driven, with the result each had to give: a plain `=`
// on the `@ObservationIgnored` counter must stay EXCLUDED (it does — the filter reads the
// attribute, not the `&+=` spelling); a new observable readout added to the closure must be
// PICKED UP (it is); removing the interval literal must FAIL LOUDLY (it does); a 60 Hz read in
// a multi-line-signature `-> some View` func must go RED (it does); `masterVolume` in a
// one-line computed var must go RED (it does); a leaf `View` struct declared in the same file
// — the DOCUMENTED repair — must stay GREEN (it does, #364); a 60 Hz read and a ~10 Hz read
// placed in `EchoelmusicApp.mainContent` must both go RED (they do); and injecting the
// publisher object with `.environment(cameraRPPG)` — the CORRECT pattern, one line away from
// the mutation — must stay GREEN (it does).
//
// ⚠️ NOT COMPILE-VERIFIED by the cheap gate: `Xcode Compile Check` builds `Sources/` alone.
// This file builds only in the CI/CD `Build for Testing` step.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMenuHostReadsNoHotStateTests: XCTestCase {

    private static let publisher = "Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift"
    private static let root = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let host = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    /// ⛔ THE THIRD ANCESTOR, missed by the first version. The chain is
    /// `EchoelmusicApp.mainContent` → `WorkspaceView` → `SurfaceHost` → `EchoelStudioView`,
    /// and `SurfaceHost` wraps the Picker host DIRECTLY. It is clean today, so leaving it out
    /// made the guard green partly by luck — and "a hot read one level above the level the
    /// last fix reached" is the 10.76.50 finding word for word.
    private static let wrapper = "Sources/Echoelmusic/Studio/SurfaceSwitcher.swift"
    /// The spelling the bio scan anchors on. It is a NEEDLE, not a fact about the code: an
    /// alias or a renamed binding makes it miss, which is why
    /// `testTheRootStillReadsTheStartStopFlag` exists to prove it still matches something.
    private static let bioReceiver = "cameraRPPG"

    // ⭐ #919 — THE SECOND PRODUCER, and it is SIX TIMES HOTTER than the first.
    // ⛔ AND THE COUNT IS DELIBERATELY NOT WRITTEN HERE OR IN THE HEADER. `meterProperties`
    // retracts it in its own doc — "it is not a fact to keep here" (#818) — and the first draft
    // of #919 then wrote "nine" twice more, in this block and in the header, i.e. argued the
    // count is a date and kept it anyway. The number is printed by
    // `testTheMeterHotSetIsDerivedFromTheSixtyHertzTimer`'s failure message.
    // `AudioEngine` runs a 60 Hz meter poll timer that rewrites `@Observable` readouts on
    // every tick, and `AutomationPlayer.applyStep` rewrites `masterVolume` on every transport
    // step. Both are the same defect class as the ~10 Hz camera, and neither had a guard.
    // This is NOT a hypothetical: `MasterVolumeField` exists as its OWN struct precisely
    // because `masterVolume` was once read inline in `masterPanel` and tore down the
    // Tonart/Genre Picker — the founder's "menus freeze while playing". The repair shipped;
    // nothing stopped it coming back.
    private static let audioEngine = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let automation = "Sources/Echoelmusic/Core/AutomationPlayer.swift"
    /// The leaf where these reads BELONG — the needle-reachability fixture for the meter half.
    private static let loudnessLeaf = "Sources/Echoelmusic/Studio/MasterLoudnessGrid.swift"

    // ⛔ THE FOURTH ANCESTOR, and it was missed for the SAME reason `SurfaceHost` was (#918
    // defect 7): the chain was enumerated from the surfaces a session thinks about, and the one
    // ABOVE all of them holds BOTH producers. `EchoelmusicApp` stores `cameraRPPG` and
    // `audioEngine` as `@State` and builds `mainContent`. It is clean today — it INJECTS the
    // objects (`.environment(cameraRPPG)`) and reads no property off them, which is exactly
    // right and must stay green. But a single `Text("\(audioEngine.masterLevel)")` there would
    // churn every surface in the app, and nothing was watching the topmost one.
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    /// The engine spelling, hard-written for the same reason `bioReceiver` is: `EchoelmusicApp`
    /// holds it as `@State`, not `@Environment`, so the `@Environment`-shaped derivation used
    /// for `EchoelStudioView` does not apply. Each scan below asserts the DECLARATION first, so
    /// a rename fails loudly here instead of quietly emptying the needle.
    private static let engineReceiver = "audioEngine"
    // ⭐ #928 — THE THIRD PRODUCER, and it was invisible to both derivations above because it
    // is neither the camera nor the engine: it is a THIRD object. `Transport.onTempoChange`
    // pushes `metronome?.bpm` on every tempo change, and during a glide that is up to ~20 Hz.
    // `EchoelmusicApp` says so at the registration site in its own words. Nothing scanned it.
    // ⚠️ WHY THIS ONE IS EASY TO WALK INTO, unlike the two above: `EchoelStudioView.body`
    // ALREADY reads four `metronome.` properties (the Tempo panel's rows) and they are all
    // legitimately COLD — user-set, human rate. So the receiver is in habitual use inside the
    // very body that must not read the hot one, and the two spellings differ by one word.
    private static let metronomeVoice = "Sources/Echoelmusic/Audio/MetronomeVoice.swift"
    private static let metronomeReceiver = "metronome"
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

    // MARK: - 2. The three ancestors
    // ⛔ THIS HEADING SAID "the two ancestors" until #919, with three tests under it. It was
    // left over from before `SurfaceHost` was added — the #918 review found the missing
    // ancestor and nobody moved the label with it. A heading that miscounts what follows is
    // small, but it is the same defect as a name describing a procedure the code stopped
    // taking (#374): a reader trusts it instead of counting.

    func testTheWrapperBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.wrapper, of: "SurfaceHost",
                                          receiver: Self.bioReceiver, hot: try hotProperties(), why: """
            `SurfaceHost` sits BETWEEN the root and the Picker host. It is clean today; the \
            claim exists because the defect's whole history is that each fix reached one level \
            and the next read appeared one level above it.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") }, """
            ANCHOR ASSERTION: `SurfaceHost.body` must still be among the members the scan
            walked. Scanned: \(members).
            """)
    }

    func testTheRootBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.root, of: "WorkspaceView",
                                          receiver: Self.bioReceiver, hot: try hotProperties(), why: """
            `WorkspaceView` is the ROOT. A ~10 Hz read in any of its view-building members \
            rebuilds every surface below it ten times a second and tears down whatever Picker \
            popover the player has open — the founder's "kann ich nicht mehr auswählen", \
            reported five times. The repair is never to throttle: confine the read to its own \
            small leaf `View` struct (`PulseMonitorMiniLive` is the worked example) so only that \
            leaf churns.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") }, """
            ANCHOR ASSERTION, and #919b made it a NAME rather than a MAGNITUDE. The member \
            needles (`: some View {`, `-> some View {`, `: some Scene {`) are what the negative \
            claim iterates over; if they stop matching, the loop runs zero times and the claim \
            passes by finding nothing (#367). But a COUNT floor is red on the documented repair \
            — extracting reads into their own leaf structs removes members from this type — so \
            the guard would have punished the fix it teaches (#364). `body` survives both.
            """)
    }

    func testTheMenuHostBuildsNoViewFromAHotReadout() throws {
        let members = try assertNoHotRead(in: Self.host, of: "EchoelStudioView",
                                          receiver: Self.bioReceiver, hot: try hotProperties(), why: """
            `EchoelStudioView` hosts the Picker menus themselves. `AnyView(...)` is NOT an \
            observation boundary, so a read in ANY member this body evaluates — including a \
            dropdown panel — registers the whole body as a 10 Hz observer. ⛔ THIS MESSAGE USED \
            TO END WITH THE LAW THE HEADER RETRACTS — "reads inside `private func` bodies and \
            `.task {}` closures are not body evaluation" — word for word, in the text a session \
            reads WHEN THE GUARD FIRES. The truth: only members that do not BUILD A VIEW are out \
            of scope, and a `private func … -> some View` is body evaluation like any other. \
            Three plain helpers do read hot state here; they are reached from ACTION paths, and \
            that is ASSUMED from a hand read of their call sites, not asserted by anything in \
            this file.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") }, """
            ANCHOR ASSERTION: `EchoelStudioView.body` must still be among the members the
            scan walked. A count floor stood here and was red on the documented repair
            (extracting reads into leaf structs removes members) — #364 in the guard that
            teaches it. Scanned \(members.count) members.
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

    // MARK: - 4. The second producer (#919) — meter poll + automation lane

    func testTheMeterHotSetIsDerivedFromTheSixtyHertzTimer() throws {
        let meter = try meterProperties()
        XCTAssertTrue(meter.contains("masterLevel"), """
            DERIVATION CLAIM. `masterLevel` is the stereo mix level the 60 Hz poll timer \
            rewrites; if the derivation cannot find it, every negative claim below is green \
            for having an empty needle set (#367). Selected: \(meter.sorted()).
            """)
        XCTAssertFalse(meter.contains("monitorPollTick"), """
            EXCLUSION CLAIM, and it must hold for the RIGHT reason. `monitorPollTick` is \
            written inside the very same closure but is `@ObservationIgnored`, so it cannot \
            invalidate any body. The derivation filters on that attribute — NOT on the `&+=` \
            spelling that happens to keep it out of the assignment regex today. A future \
            `self.monitorPollTick = 0` in that closure must stay excluded.
            """)
        XCTAssertGreaterThanOrEqual(meter.count, 5, """
            FLOOR, and the bio half had one while this half did not. `isObservationTracked` \
            returns false for any name whose DECLARATION it cannot resolve, and it resolves only \
            by scanning `AudioEngine.swift` for `var <name>`. Move those declarations into an \
            extension in another file and the set silently collapses to one, while both engine \
            scans stay green over a one-element needle set — a scan that looks for almost \
            nothing. Selected \(meter.count): \(meter.sorted()).
            """)
    }

    func testTheAutomationRewriteIsTreatedAsHot() throws {
        let hot = try audioEngineHotProperties()
        XCTAssertTrue(hot.contains("masterVolume"), """
            THE DOCUMENTED HISTORICAL BUG, in guard form. `AutomationPlayer.applyStep` writes \
            `audioEngine.masterVolume` on EVERY transport step. Read inline in `masterPanel` it \
            invalidated the whole studio body and tore down the open Tonart/Genre Picker — the \
            "menus freeze while playing" report. The repair was `MasterVolumeField`, a struct \
            whose only job is to hold that one read. This claim is what keeps the repair from \
            being tidied away. Selected: \(hot.sorted()).
            """)
    }

    func testTheMenuHostBuildsNoViewFromAHotEngineReadout() throws {
        let receiver = try XCTUnwrap(environmentReceiver(for: "AudioEngine", of: "EchoelStudioView", in: Self.host), """
            `EchoelStudioView` no longer declares `@Environment(AudioEngine.self)`. The scan \
            below anchors on that binding's NAME, so without it the claim would pass by having \
            nothing to look for. Either the binding moved and this guard follows it, or the \
            host genuinely stopped holding the engine — say which in the commit.
            """)
        // ⛔ THE UNWRAP ALONE IS NOT ENOUGH. `environmentReceiver` takes the first `var ` after
        // the `@Environment(...)` marker; a layout it does not expect would hand back a name
        // that appears nowhere, and the scan below would then look for a spelling that cannot
        // match — green while proving nothing (#367). This asserts the derived name is a name
        // the file actually USES, which is the cheap half of the same question.
        XCTAssertTrue(SourceText.codeOnly(try read(Self.host)).contains("\(receiver)."), """
            `environmentReceiver` derived "\(receiver)" from \(Self.host), and that spelling \
            occurs nowhere in the file. The derivation read the wrong `var`. The scan below \
            anchors on it, so it would pass by looking for something that does not exist.
            """)
        let members = try assertNoHotRead(in: Self.host, of: "EchoelStudioView",
                                          receiver: receiver,
                                          hot: try audioEngineHotProperties(), why: """
            `EchoelStudioView` hosts the Picker menus. A 60 Hz meter read in any member this \
            body evaluates rebuilds the whole subtree sixty times a second — six times worse \
            than the biofeedback freeze, and it happens whenever audio is RUNNING rather than \
            only when the camera is on. The repair is the same and is already written down \
            twice in `MasterLoudnessGrid.swift`: give the read its own small leaf `View`.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") }, """
            ANCHOR ASSERTION: `EchoelStudioView.body` must still be among the members the
            scan walked. A count floor stood here and was red on the documented repair
            (extracting reads into leaf structs removes members) — #364 in the guard that
            teaches it. Scanned \(members.count) members.
            """)
    }

    func testTheLoudnessLeafStillReadsTheMeter() throws {
        let receiver = try XCTUnwrap(environmentReceiver(for: "AudioEngine", of: "MasterLoudnessGrid", in: Self.loudnessLeaf))
        let hot = try audioEngineHotProperties()
        let text = SourceText.codeOnly(try read(Self.loudnessLeaf))
        let found = hot.sorted().filter { text.contains("\(receiver).\($0)") }
        XCTAssertFalse(found.isEmpty, """
            COUNTERWEIGHT AND SELF-TEST. `testTheMenuHostBuildsNoViewFromAHotEngineReadout` is \
            a NEGATIVE claim, and a negative claim whose needle cannot match is green forever \
            (#367). `MasterLoudnessGrid` is where these reads BELONG — the law is "in a leaf", \
            not "nowhere" — so it must still contain at least one, spelled exactly the way the \
            scan looks for it. Empty here means the scan above proves nothing.
            """)
    }

    // MARK: - 5. The topmost ancestor (#919)

    func testTheAppLevelAncestorBuildsNoViewFromHotBio() throws {
        let app = SourceText.codeOnly(try read(Self.app))
        XCTAssertTrue(app.contains("var \(Self.bioReceiver) = CameraRPPGBioPublisher()"), """
            ANCHOR FIRST, and it is NOT the one you would reach for: `\(Self.bioReceiver).` \
            occurs ZERO times in \(Self.app) — the app only INJECTS the object — so a \
            "still reads it" counterweight would be a claim that can never hold (#367). The \
            DECLARATION is the thing that proves the spelling is real, and it is what a rename \
            has to carry with it.
            """)
        let members = try assertNoHotRead(in: Self.app, of: "EchoelmusicApp",
                                          receiver: Self.bioReceiver, hot: try hotProperties(), why: """
            `EchoelmusicApp` is ABOVE `WorkspaceView`, which was itself the surprise of 10.76.50 \
            ("the read was one level up"). It owns the publisher. A ~10 Hz read in `mainContent` \
            would rebuild literally every surface. Passing the object on with `.environment(...)` \
            is NOT such a read and stays green — that is the correct pattern, not a violation.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") }, """
            ANCHOR ASSERTION: `EchoelmusicApp.body` (a `some Scene`) must still be among
            the scanned members. It is the OUTERMOST body in the app. Scanned: \(members).
            """)
    }

    func testTheAppLevelAncestorBuildsNoViewFromHotEngineState() throws {
        let app = SourceText.codeOnly(try read(Self.app))
        XCTAssertTrue(app.contains("var \(Self.engineReceiver): AudioEngine"), """
            ANCHOR FIRST: the `@State` declaration is what makes "\(Self.engineReceiver)" the \
            right spelling to scan for. If it is renamed or the app stops owning the engine, \
            this fails by name rather than the scan below going quietly green.
            """)
        let members = try assertNoHotRead(in: Self.app, of: "EchoelmusicApp",
                                          receiver: Self.engineReceiver,
                                          hot: try audioEngineHotProperties(), why: """
            Same ancestor, the 60 Hz producer. `EchoelmusicApp` calls `\(Self.engineReceiver).` \
            a dozen times — all of it lifecycle and action code, none of it body evaluation, \
            which is why this is a real risk rather than a theoretical one: the name is already \
            in scope and in habitual use one line away from a view builder.
            """)
        XCTAssertTrue(members.contains { $0.contains("var body") },
                      "EchoelmusicApp.body is no longer among the scanned members: \(members)")
    }

    // MARK: - 6. The third producer (#928) — the click's tempo relay

    func testTheClickHotSetIsDerivedFromTheTempoRelay() throws {
        let hot = try metronomeHotProperties()
        XCTAssertTrue(hot.contains("bpm"), """
            DERIVATION CLAIM, and every negative claim below is worthless without it (#367). \
            `bpm` is the one `MetronomeVoice` property the transport relay writes; if the \
            derivation cannot find it the scans go green over an EMPTY needle set, which looks \
            identical to a clean tree. Selected: \(hot.sorted()).
            If the relay legitimately moved, move the anchor — do not hard-code a list.
            """)
        XCTAssertGreaterThanOrEqual(hot.count, 1, """
            FLOOR. The derivation collapsed to nothing: either the `onTempoChange(id: \
            "\(Self.metronomeReceiver)")` registration is gone from \(Self.app), or \
            `isObservationTracked` can no longer resolve declarations in \
            \(Self.metronomeVoice) — moving them into an extension in another file does \
            exactly that, silently.
            """)
    }

    func testTheClicksUserSetRowsAreNotTreatedAsHot() throws {
        let hot = try metronomeHotProperties()
        // ⛔ THIS IS THE #364 HALF, and it is the reason the claim exists at all. These four
        // ARE read in `EchoelStudioView.body` today (the Tempo panel's rows and the mix
        // board's Click strip) and that is CORRECT: a human turns them, at human rate. If one
        // of them ever lands in the hot set, the red below is not "revert the row" — it is
        // "a machine now writes this, so its read must move into its own leaf `View`".
        for cold in ["enabled", "beatsPerBar", "level", "accentDownbeat"] {
            XCTAssertFalse(hot.contains(cold), """
                `\(cold)` entered the hot set: something other than the user now writes it at \
                machine rate. The four `metronome.` reads in `EchoelStudioView.body` become a \
                Picker-tearing churn the moment that is true. Move EVERY read of it into a \
                leaf struct (the `MasterVolumeField` shape) — measured, three of these four are \
                read in TWO different members, so moving one row leaves this red — then delete \
                `\(cold)` from this list in the same commit. Hot set: \(hot.sorted()).
                """)
        }
    }

    func testTheMenuHostBuildsNoViewFromTheClicksTempo() throws {
        // ⛔ THE FIRST DRAFT ANCHORED ON `contains("var metronome")` AND THAT ANCHOR COULD NOT
        // FAIL FOR ITS OWN STATED REASON (#408, caught by review). The needle it protects is
        // the `@Environment` binding at one line — but the same substring also matches
        // `private var metronomeRow: some View {` and `@Bindable var metronome = metronome`
        // further down the SAME file. Rename the binding to `click` and `metronomeRow`
        // survives untouched: the anchor stays green while the needle is dead, which is the
        // exact #921b/#924/#926 failure its own message claimed to prevent — a FOURTH
        // instance, and the first one found by reading rather than by driving.
        // The repair is not a longer string: it is to DERIVE the name, so a rename MOVES the
        // guard instead of blinding it. `environmentReceiver` was written for this and the
        // engine half already calls it.
        let receiver = try XCTUnwrap(
            environmentReceiver(for: "MetronomeVoice", of: "EchoelStudioView", in: Self.host), """
            `EchoelStudioView` no longer declares `@Environment(MetronomeVoice.self)`. The scan \
            below anchors on that binding's NAME, so without it the claim would pass by having \
            nothing to look for. Either the binding moved and this guard follows it, or the \
            host genuinely stopped holding the click — say which in the commit.
            """)
        let members = try assertNoHotRead(in: Self.host, of: "EchoelStudioView",
                                          receiver: receiver,
                                          hot: try metronomeHotProperties(), why: """
            The menu host already reads FOUR `\(receiver).` properties across TWO members \
            `body` evaluates — `mixerPanel`'s Click strip and `metronomeRow` — and every one \
            of them is legitimately cold. A fifth read spelled `.bpm` churns the whole studio \
            body at up to ~20 Hz during a tempo glide and tears down any open Tonart/Genre \
            Picker: the founder's "menus freeze while playing", from a third producer.
            ⚠️ THE OBVIOUS NEXT EDIT HAS A SPELLING THIS SCAN CANNOT SEE. A "current tempo" \
            caption written as `private var tempoCaption: String { "\\(metronome.bpm)" }` and \
            read from a body is invisible here — the scan only enters `some View`/`some Scene` \
            members (the general limit is stated in this file's header). It churns just the \
            same. Put the read in a leaf `View`, never in a `String` helper a body calls.
            """)
        XCTAssertFalse(members.isEmpty, """
            THE NEEDLE MUST BE ABLE TO MATCH. No `some View` member was scanned in \
            `EchoelStudioView`, so the negative claim above proved nothing.
            """)
    }

    func testTheTopmostAncestorBuildsNoViewFromTheClicksTempo() throws {
        let app = SourceText.codeOnly(try read(Self.app))
        // The parens were in the first draft and pinned the initializer's ARITY: `= .init()`,
        // an added `MetronomeVoice(sampleRate:)` argument or an explicit type annotation would
        // all turn this red on correct work (#364). The sibling engine anchor uses the
        // annotation form for the same reason.
        XCTAssertTrue(app.contains("var \(Self.metronomeReceiver) = MetronomeVoice"), """
            ANCHOR FIRST: `EchoelmusicApp` OWNS the click as `@State`, which is why it is also \
            the file the relay is registered in. If it stops owning it, this fails by name.
            """)
        _ = try assertNoHotRead(in: Self.app, of: "EchoelmusicApp",
                                receiver: Self.metronomeReceiver,
                                hot: try metronomeHotProperties(), why: """
            The topmost ancestor, same law as the engine half: a read here churns EVERY \
            surface in the app.
            ⚠️ AND THIS SCAN IS GREEN BY ONE CHARACTER — say it rather than discover it. The \
            relay itself lives INSIDE `mainContent`, a member this scan enters, and writes \
            `\(Self.metronomeReceiver)?.bpm`. The needle has no `?`, so it misses. Change the \
            capture to a strong `[\(Self.metronomeReceiver)]` or add a `guard let` and this \
            claim goes RED ON ENTIRELY CORRECT CODE — a write inside `.task {}` is not body \
            evaluation. If that happens the repair is to exclude the relay's own span here, \
            NOT to undo the capture change (#364). This retires the header's "None exists \
            today" line about action-closure occurrences: one now exists, one character away.
            """)
    }

    func testTheTwoMiddleAncestorsHoldNeitherNarrowProducer() throws {
        // ⛔ THE COVERAGE GAP THIS CLOSES, and it took a reviewer to see it for the click:
        // the BIO scan runs on all FOUR ancestors, the ENGINE and METRONOME scans on TWO.
        // Two lines in `WorkspaceView` — an `@Environment` binding plus a readout in `topBar`
        // — leave every claim above GREEN while reproducing the 10.76.50 shipped bug in the
        // exact member that caused it. `EchoelmusicApp` injects both objects with
        // `.environment(…)`, so every descendant can bind one: it really is one line away.
        //
        // ⭐ THE ENGINE HALF WAS THE SAME GAP AND HAD STOOD LONGER (#929). #928's reviewer
        // wrote "the engine half has no such claim and could take one" as an aside; measured,
        // it is the identical hole in an older scan. Generalising the ONE claim beats adding a
        // near-copy beside it (#416) — a second almost-identical test is where two truths
        // start to drift.
        //
        // Pointing the scans at those files today would be a claim that cannot fail (#367);
        // this asserts their PREMISE instead, so the day it stops holding, the guard names the
        // scan that has to be extended rather than going quietly green over an absent needle.
        //
        // ⚠️ `CameraRPPGBioPublisher` IS DELIBERATELY NOT IN THIS TABLE, and leaving it out is
        // the load-bearing part: `WorkspaceView` legitimately holds the publisher — it reads
        // `isRunning` for start/stop, which `testTheRootStillReadsTheStartStopFlag` requires.
        // Listing it here would forbid correct, REQUIRED work (#364) and contradict a claim
        // twenty lines up. The bio scan needs no premise because it already covers all four.
        let narrowlyScanned = [
            ("MetronomeVoice", "the ~20 Hz `bpm` write", "TheClicksTempo"),
            ("AudioEngine", "the 60 Hz meter poll and the per-step `masterVolume` write",
             "AHotEngineReadout"),
        ]
        for path in [Self.root, Self.wrapper] {
            let text = SourceText.codeOnly(try read(path))
            for (type, producer, scanSuffix) in narrowlyScanned {
                XCTAssertFalse(text.contains(type), """
                    \(path) now references `\(type)`. That is NOT forbidden and this is not a \
                    request to undo it — but the `\(type)` scan runs only on \
                    `EchoelStudioView` and `EchoelmusicApp`, so this ancestor is now UNGUARDED \
                    for \(producer), and a read here churns every surface below it.
                    In the SAME commit: add a `testTheMiddleAncestorBuildsNoViewFrom\
                    \(scanSuffix)` pointing `assertNoHotRead` at this file, and take this \
                    entry out of the table.
                    """)
            }
        }
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
    /// Whole-word containment — with the RIGHT boundary applied only when the needle ends in a
    /// word character.
    ///
    /// ⛔ THIS WAS BROKEN IN `380fcdc` AND NOTHING SAW IT — the eighth defect of this guard, and
    /// the first one that was RED rather than merely wrong. The right-hand boundary was
    /// unconditional, so the seed needle `analyzer.` could match only where a dot is followed by
    /// a NON-word character. In a property access it never is. The entire "computed getter reads
    /// the 15 fps analyzer" branch was therefore DEAD, and `rrWindowMs` — the property whose own
    /// doc comment in the publisher states this very freeze law — silently left the hot set.
    /// `testTheHotSetIsDerivedAndSelectsTheOneThatCausedTheFreeze` was red on the parent tree,
    /// exactly as its name promises (#367 held; the derivation was what lied).
    ///
    /// ⭐ IT SURVIVED A SHIP BECAUSE OF TWO BLIND SPOTS AT ONCE, and both are written down
    /// elsewhere in this repo: the CI job log carries only `tail -200 test.log`, so a failure
    /// earlier in the run leaves no trace (#807/#445), and delta grading compares parent with
    /// worktree, so an assertion red on BOTH produces no delta and is reported by nothing. The
    /// only thing that finds it is `Tests/CISmoke/CLAUDE.md` §3's rule — when a slice rewrites a
    /// guard substantially, DRIVE EVERY ASSERTION IN IT, not only the ones it changed. #919 did
    /// that and this is what it caught.
    private func mentions(_ name: String, in body: String) -> Bool {
        // A needle ending in `.` is a RECEIVER prefix, not an identifier: `analyzer.` is meant
        // to match `analyzer.rawIntervalsMs`. Demanding a boundary after the dot asks for the
        // one thing a property access can never provide.
        let needsRightBoundary = name.last.map(isWordChar) ?? false
        var searchFrom = body.startIndex
        while let r = body.range(of: name, range: searchFrom..<body.endIndex) {
            let beforeOK = r.lowerBound == body.startIndex
                || !isWordChar(body[body.index(before: r.lowerBound)])
            let afterOK = !needsRightBoundary
                || r.upperBound == body.endIndex || !isWordChar(body[r.upperBound])
            if beforeOK && afterOK { return true }
            searchFrom = r.upperBound
        }
        return false
    }

    private func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    // MARK: - Derivation, second producer (#919)

    /// The readouts the 60 Hz meter poll timer rewrites, DERIVED from the timer closure rather
    /// than listed — a list names today's set and misses tomorrow's addition in silence (#818).
    /// ⛔ THE FIRST DRAFT OF THIS LINE WROTE THE COUNT ("the nine readouts"), in the doc of the
    /// function whose entire purpose is not to have a list. The count is printed by
    /// `testTheMeterHotSetIsDerivedFromTheSixtyHertzTimer`'s failure message; it is not a fact
    /// to keep here.
    ///
    /// The closure is located by its interval literal and extracted by BRACE MATCHING, never by
    /// a fixed line window: this repo writes 30-line comment blocks inside closures, so any
    /// window is unsound by construction (#408).
    ///
    /// ⭐ THE `@ObservationIgnored` FILTER IS NOT COSMETIC. `monitorPollTick` is written in this
    /// closure and is observation-ignored, so a body reading it does NOT churn. Filtering on the
    /// ATTRIBUTE and not on the `&+=` spelling is the difference between an exclusion that holds
    /// and one that holds by accident until someone writes `= 0`.
    private func meterProperties() throws -> Set<String> {
        let lines = SourceText.codeOnly(try read(Self.audioEngine))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let anchor = "Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0"
        guard let start = lines.firstIndex(where: { $0.contains(anchor) }),
              let (lo, hi) = span(of: lines[start], in: lines, from: start) else {
            XCTFail("""
                the 60 Hz meter poll timer is gone from \(Self.audioEngine), or its interval is \
                no longer spelled `1.0 / 60.0`. This derivation anchors on that literal. Do not \
                replace it with a hard-coded property list — move the anchor.
                """)
            return []
        }
        var names: Set<String> = []
        for line in lines[lo..<hi] {
            // ⚠️ LIMIT: the FIRST `self.` on the line only. `if self.x { self.hot = v }`, or
            // two assignments separated by `;`, drops a producer silently. No such line
            // exists in this closure today; stated because the failure direction is a
            // quiet omission from the hot set, not a loud one.
            guard let range = line.range(of: "self.") else { continue }
            let rest = line[range.upperBound...]
            let name = String(rest.prefix { isWordChar($0) })
            guard !name.isEmpty else { continue }
            // Only an ASSIGNMENT makes the property a producer; a read inside the closure does
            // not. `&+=`, `+=` and `==` are deliberately not assignments for this purpose.
            let after = rest.dropFirst(name.count).drop { $0 == " " }
            guard after.first == "=", after.dropFirst().first != "=" else { continue }
            guard isObservationTracked(name, in: lines) else { continue }
            names.insert(name)
        }
        return names
    }

    /// Whether a stored property of the scanned type can invalidate a body that reads it.
    /// `@ObservationIgnored` — on the declaration line or the line above it — means it cannot.
    ///
    /// ⚠️ LIMIT, stated rather than engineered around: it takes the FIRST `var <name>` in the
    /// file that looks like a declaration. A local variable of the same name declared earlier
    /// would be read instead. It cannot happen for a name the closure assigns through `self.`
    /// unless someone shadows a master readout inside a function above line 68 — and the
    /// failure direction is EXCLUSION, so that one property would quietly leave the hot set
    /// while the others still guard. Do not "fix" it with an indentation rule: a property that
    /// moves into a nested type would then be dropped for the same reason, silently.
    private func isObservationTracked(_ name: String, in lines: [String]) -> Bool {
        for (index, line) in lines.enumerated() where line.contains("var \(name)") {
            let declared = line.contains("var \(name):") || line.contains("var \(name) =")
            guard declared else { continue }
            if line.contains("@ObservationIgnored") { return false }
            if index > 0, lines[index - 1].contains("@ObservationIgnored") { return false }
            return true
        }
        return false
    }

    /// `AudioEngine` properties an automation lane rewrites on every transport step.
    /// Derived from the write sites, so a second automatable engine parameter joins the hot set
    /// the day it is wired — which is exactly when a session is most likely to read it inline.
    private func automationRewrittenProperties() throws -> Set<String> {
        let text = SourceText.codeOnly(try read(Self.automation))
        var names: Set<String> = []
        var rest = text[...]
        let needle = "audioEngine?."
        while let range = rest.range(of: needle) {
            let tail = rest[range.upperBound...]
            let name = String(tail.prefix { isWordChar($0) })
            let after = tail.dropFirst(name.count).drop { $0 == " " }
            if !name.isEmpty, after.first == "=", after.dropFirst().first != "=" {
                names.insert(name)
            }
            rest = tail
        }
        return names
    }

    /// Both `AudioEngine` producers as one set. They are unioned rather than checked
    /// separately because a body does not care WHICH tick invalidated it — one hot read is one
    /// freeze. The two derivations stay apart so a failure message names the real source.
    private func audioEngineHotProperties() throws -> Set<String> {
        let meter = try meterProperties()
        let automated = try automationRewrittenProperties()
        return meter.union(automated)
    }

    /// The local name a view gives an `@Environment(<Type>.self)` binding — the spelling the
    /// scan anchors on. Derived from the source, so a rename moves the guard with it instead of
    /// silently emptying its needle.
    ///
    /// ⛔ SCOPED TO `owner`'s SPAN, AND THE FIRST VERSION WAS NOT — a review drove the hole.
    /// `EchoelStudioView.swift` declares this binding TWICE: once in the host at line 71 and
    /// once in a small leaf lower down. A file-wide search meant that deleting the HOST's
    /// binding still returned "audioEngine", from the leaf — the unwrap succeeded, the
    /// "still used in this file" check succeeded too (the name is used elsewhere in the file),
    /// and the scan then ran with a receiver the scanned type no longer has. Green for a
    /// reason other than the one its message states: #367 in its named form.
    private func environmentReceiver(for type: String, of owner: String,
                                     in path: String) throws -> String? {
        let lines = SourceText.codeOnly(try read(path))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let (lo, hi) = span(of: "struct \(owner):", in: lines) else { return nil }
        let text = lines[lo..<hi].joined(separator: "\n")
        guard let range = text.range(of: "@Environment(\(type).self)") else { return nil }
        var rest = text[range.upperBound...]
        guard let varRange = rest.range(of: "var ") else { return nil }
        rest = rest[varRange.upperBound...]
        let name = String(rest.prefix { isWordChar($0) })
        return name.isEmpty ? nil : name
    }

    // MARK: - Derivation, third producer (#928)

    /// `MetronomeVoice` properties the TRANSPORT writes — i.e. the ones a body evaluating them
    /// registers on at machine rate rather than at the rate a finger turns a row.
    ///
    /// Anchored on the relay's own registration, not on a property list: the whole point is
    /// that a future second relay (a step subscriber writing `beatsPerBar`, say) must ENTER
    /// this set by itself and turn `testTheClicksUserSetRowsAreNotTreatedAsHot` red, instead
    /// of a hand-written list going stale in the direction that looks clean.
    ///
    /// ⚠️ STATE THE LIMIT BEFORE THE CLAIM (§1), because "must enter by itself" is only true
    /// under THREE conditions, and a writer that breaks any one of them is invisible while
    /// this set still looks complete:
    ///   1. it is registered in `EchoelmusicApp.swift` — the file this scans;
    ///   2. under the id literal `"metronome"` (or an `addStepSubscriber` of that name);
    ///   3. writing through a receiver spelled `metronome` / `metronome?`.
    /// A machine writer elsewhere, under another id, or through another binding name would
    /// leave `level` cold in this set while `metronome.level` is read in two host members —
    /// claims 2 and 3 both green over a real churn. Measured today: the only writers of the
    /// five tracked properties are this relay and four user `Binding` setters in the host,
    /// and `MetronomeVoice` itself has no internal writer (its five audio mirrors are all
    /// `@ObservationIgnored`, so the `didSet` chain and the render closure cannot invalidate
    /// a body).
    ///
    /// ⚠️ TWO MORE LIMITS, both in the safe direction. (a) ONE write per line: the loop
    /// `break`s after the first matching prefix, so `metronome?.bpm = b; metronome?.level = c`
    /// drops the second — `meterProperties()` carries the same limit for the same reason.
    /// (b) RATE IS NOT CHECKED: any assignment inside a machine-rate relay is ASSUMED
    /// machine-rate, so a one-shot write added there would over-collect. That fails toward a
    /// false red, not a false green.
    private func metronomeHotProperties() throws -> Set<String> {
        let lines = SourceText.codeOnly(try read(Self.app))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let declarations = SourceText.codeOnly(try read(Self.metronomeVoice))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var names: Set<String> = []
        var found = false
        // EVERY registration, not the first: a second relay is exactly the change this claim
        // has to notice, and `firstIndex` would read one closure and call the set complete.
        for (index, line) in lines.enumerated()
        where line.contains("onTempoChange(id: \"\(Self.metronomeReceiver)\")")
              || line.contains("addStepSubscriber(\"\(Self.metronomeReceiver)\"") {
            // ⚠️ A ONE-LINE relay (`{ [weak metronome] bpm in metronome?.bpm = bpm }`) has no
            // closing `}` at the opener's indent, so `span` falls back to `endIndex` and this
            // reads the rest of the file for `metronome.X =`. Harmless today — there is no
            // later write site in that file — and it over-collects rather than under-collects,
            // i.e. it fails toward a false red.
            guard let (lo, hi) = span(of: line, in: lines, from: index) else { continue }
            found = true
            for body in lines[lo..<hi] {
                // Both spellings: the relay captures `[weak metronome]`, so it writes
                // `metronome?.bpm`; a non-optional caller elsewhere writes `metronome.bpm`.
                for prefix in ["\(Self.metronomeReceiver)?.", "\(Self.metronomeReceiver)."] {
                    guard let range = body.range(of: prefix) else { continue }
                    let rest = body[range.upperBound...]
                    let name = String(rest.prefix { isWordChar($0) })
                    guard !name.isEmpty else { continue }
                    // An assignment makes it a producer; a read inside the closure does not.
                    let after = rest.dropFirst(name.count).drop { $0 == " " }
                    guard after.first == "=", after.dropFirst().first != "=" else { continue }
                    // `@ObservationIgnored` mirrors (`audioSamplesPerBeat` and friends) cannot
                    // invalidate a body, so writing one is not a churn risk. Filtered on the
                    // ATTRIBUTE, never on a naming convention.
                    guard isObservationTracked(name, in: declarations) else { continue }
                    names.insert(name)
                    break
                }
            }
        }
        XCTAssertTrue(found, """
            no transport relay onto `\(Self.metronomeReceiver)` was found in \(Self.app). \
            Either it is gone — then delete this whole section, the click no longer has a \
            machine writer — or it was re-spelled and this anchor has to move. Do NOT leave it: \
            an anchor that matches nothing makes three negative claims green for free.
            """)
        return names
    }

    // MARK: - The scan

    /// Every member of `type` that BUILDS A VIEW, in its `struct` and in any `extension`.
    ///
    /// ⛔ TWO NEEDLES, NOT ONE. The first version matched only `: some View {`, so all 19
    /// `-> some View` FUNCTIONS in `EchoelStudioView` and the 1 in `WorkspaceView` were
    /// invisible — and a driven mutant put a hot read in `menuChip` and stayed green. A
    /// `@ViewBuilder private func` is body evaluation just as much as a computed `var`.
    ///
    /// ⭐ #919 MADE THE RECEIVER AND THE HOT SET PARAMETERS. They were baked in as
    /// `cameraRPPG` + `hotProperties()`, which read as "this is the freeze producer" when it is
    /// only the FIRST one found. A second producer exists and is six times hotter; see
    /// `audioEngineHotProperties()`. The algorithm is deliberately NOT duplicated into a
    /// sibling file — it has been wrong seven times, and a copy would inherit every one.
    ///
    /// ⛔ #919b MADE IT RETURN THE MEMBER DECLARATIONS, NOT A COUNT. Every caller then asserted a
    /// MAGNITUDE (`> 20`, `> 0`), and a magnitude is red on the DOCUMENTED REPAIR: extracting
    /// reads into their own small leaf `View` structs — the very fix this file teaches — removes
    /// members from the scanned type. `EchoelmusicApp` was worse: one member, so `> 0` reddened
    /// if `mainContent` were inlined. #364 in the guard that teaches the repair. The anchor is
    /// now "the scan still found `body`", which survives both refactors and still fails loudly
    /// if the needles stop matching.
    ///
    /// ⛔ AND `: some Scene {` WAS NOT A NEEDLE. `EchoelmusicApp.body` is a Scene, and it is the
    /// OUTERMOST body in the app — the file whose whole thesis is "the read was one level up"
    /// scanned the child and skipped the parent that wraps it. Measured clean today; it was a
    /// gap, not a defect, and it is one needle.
    private func assertNoHotRead(in path: String, of type: String,
                                 receiver: String, hot: Set<String>,
                                 why: String) throws -> [String] {
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
            return []
        }

        var offences: [String] = []
        var members: [String] = []
        for (lo, hi) in spans {
            for index in lo..<hi where lines[index].contains(": some View {")
                                       || lines[index].contains("-> some View {")
                                       || lines[index].contains(": some Scene {") {
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
                members.append(lines[start].trimmingCharacters(in: .whitespaces))
                let member = lines[start] + "\n" + memberBody(in: lines, from: start)
                for name in hot.sorted() where member.contains("\(receiver).\(name)") {
                    offences.append("line \(index + 1): \(lines[index].trimmingCharacters(in: .whitespaces)) reads \(receiver).\(name)")
                }
            }
        }
        XCTAssertTrue(offences.isEmpty, """
            \(path) builds a view from a hot `\(receiver)` readout:
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
