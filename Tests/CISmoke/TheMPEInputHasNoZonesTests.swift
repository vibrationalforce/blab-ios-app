// TheMPEInputHasNoZonesTests.swift
//
// ⛔ RENAMED BY #942, FROM `TheMPEDimensionsReachNoVoiceTests`, BECAUSE THE OLD NAME BECAME
// FALSE. A file name is a claim, and it is the first claim a session reads. #939 gave Press a
// path and #942 gave Slide one; together with pitch bend, ALL THREE of MPE's continuous
// dimensions now reach the built-in voice, so "the MPE dimensions reach no voice" is simply
// wrong. What the file has really guarded from the start — and what no roadmap item threatens
// — is the ZONE half: no RPN 6,6 zone is announced to us, no member channel is told apart
// (`event.channel` is read nowhere), and it is ONE monophonic voice. That is the durable
// claim, so that is the name.
//
// ⚠️ THE HISTORICAL RECORDS KEEP THE OLD NAME ON PURPOSE. `scratchpads/SESSION_LOG.md`,
// `decisions.csv` and `memory/LEDGER_COUNTS.md` describe what happened on a given day and are
// not rewritten (#456 moves LIVE prose, not the log of the past). Live pointers — the four
// `Sources/` headers, `CLAUDE.md`, `ContentPipeline/CLAIMS.md`, `scripts/dead-needles.py`,
// `PLAN_MPE_IN_2026-08-31.md` and `TheComposerWritesPerNoteVelocityTests` — moved in this
// same commit.
//
// Echoel — #548. `CLAUDE.md` line 39 promised per-note expression to a voice that discards it.
//
// WHAT THIS GUARDS. The always-loaded file's pipeline line read
// "CoreMIDI MPE → controllerEvents → synth notes (performer priority)". Measured, that arrow
// carries three claims and keeps one:
//   · MPE — `MIDIBusPublisher` parses MPE traffic but does NOT disambiguate zones; its own
//     header names "MPE master vs. member channel disambiguation, RPN 6,6 zone detection, and
//     channelPressure" as absent. (⛔ That header used to end the sentence with "intentionally
//     NOT wired in this first cycle" and #770 struck those words — see claim 6. The quotation
//     is trimmed to the half that still exists verbatim; a citation of a live file that no
//     longer contains the quoted words is the stale-witness defect, #472.)
//   · → synth — the consumer `BioReactiveSynthVoice.apply(controller:)` handled `.noteOn`,
//     `.noteOff` and `.pitchBend` and `break`d on everything else, never reading
//     `event.channel`, which is where a member channel would arrive.
//     ⭐ #939 AND #942 MOVED TWO DIMENSIONS OUT OF THAT `break`. Channel Pressure is parsed
//     (`MIDIEventParse`), carried (`MIDIInput.onChannelPressure`), published
//     (`MIDIBusPublisher`) and CONSUMED (→ `EchoelDDSP.expressionGain`, a master-gain
//     multiply in the render block); CC 74 Slide is consumed the same way
//     (→ `EchoelDDSP.renderCutoffScale`, a per-sample multiply on the filter cutoff).
//     ⛔ AND THE SENTENCE THIS REPLACES MISCOUNTED IN BOTH DIRECTIONS. It called slide,
//     air-CC and pressure "exactly the three dimensions that MAKE it MPE" — but MPE's three
//     continuous dimensions are pitch bend (X), CC 74 slide (Y) and channel pressure (Z).
//     PITCH BEND was left out although this voice has always handled it, and `.airCC`
//     (CC 21–31, `EngineBus`: "air dimensions") was counted in although no MPE document
//     defines it. That off-by-one is why "one of three" and "two of three" appeared in this
//     file's history as if a third dimension were still owed. Today ALL THREE reach the
//     voice, and the arrow's MPE claim is STILL false, for the reason that never depended on
//     the count: no zone is announced to us (RPN 6,6), no member channel is told apart, and
//     the voice is monophonic. **Dimensions without zones is expressive MIDI, not MPE.**
//   · notes, plural — `apply(controller:)` calls `playNote(` exactly once and `releaseNote()`
//     exactly once, onto ONE `synth`. It is ONE monophonic voice, so per-note anything is
//     unreachable by construction, not merely unwired. (⛔ #943b: this read "`heldByController`
//     is a single `Bool`". #943 turned that into a computed `Bool` over a held-key STACK, so
//     the sentence read as if the stack were the polyphony it denies. The monophony was never
//     in the latch — it is in the single `synth` and the single `playNote` call.)
// What survives, and the corrected line keeps it: notes, pitch bend and performer priority
// over the breath envelope really do reach the voice.
//
// ⭐ WHY THE GUARD IS ON THE CONSUMER AND NOT ON THE PROSE. The obvious shape — scan
// `CLAUDE.md` for "MPE" — is the #486/#491 collision this repo has already paid for twice:
// that file deliberately quotes retracted claims inside ⛔ blocks, so a negative prose scan
// necessarily meets its own retraction and goes red on the very commit that fixes the text.
// Pinning the CONSUMER instead means the guard reds on the day someone builds a real MPE
// receiver — which is precisely the day the always-loaded line must change back. It fires on
// the right event rather than forbidding correct work (#364).
//
// ⚠️ THE LIMIT. SOURCE-TEXT SCAN. `apply(controller:)` is `private`; the file exposes
// `applyControllerForTests` under `#if DEBUG`, so a behavioural version of claim 1 is
// possible in principle — but it would prove "an air-CC event changes no audible parameter",
// and this bundle cannot hear. What the text can carry is which cases WRITE which parameter,
// which case still falls into a bare `break`, and that no member channel is read; that is the
// claim, stated as such.
// (⛔ This sentence said "the three cases" and #939 made it two, #942 one — the number was
// baked into prose that later slices were always going to move. It is now written without a
// count at all: the claim is about WHICH cases the voice discards, never how many.)
//
// ⚠️ THE OTHER PROSE SURFACES ARE ALREADY HONEST — `docs/faq.html` ("Full MPE zone handling
// (per-note channels, pressure) … on the roadmap, not in the app today"),
// `docs/architecture.html`, the App Store description and `ContentPipeline/CLAIMS.md`. That is
// why the correction borrows the FAQ's already-vetted wording instead of inventing a fifth
// spelling (#416).
//
// ⛔ AND THIS PARAGRAPH SAID "`CLAUDE.md` WAS THE LONE OUTLIER". IT WAS NOT (#766). Every one
// of the five surfaces #548 enumerated is PROSE. `SignalRouter`'s SOURCE port was still named
// "MIDI / MPE In", rendered by `PatchbayView` behind the reachable `showRouting` sheet — the
// only surface a player reads WHILE PATCHING, and it carried the claim for two months after
// the prose was corrected. `testTheRoutingScreenOffersNoMPEInput` is the sixth. **A capability
// claim has as many surfaces as somebody enumerates**; "all of them checked" only ever means
// "all the ones I thought of".
//
// ⛔ AND THE SIXTH WAS NOT THE LAST EITHER (#770) — the SEVENTH is a GATTUNG this file had
// not looked at once. Surfaces one to five were prose a founder reads; six was a label a player
// reads; seven is what a DEVELOPER reads: `MIDIInput`'s own class doc ("Minimal CoreMIDI input
// receiver for MIDI 2.0, MPE, and standard MIDI") and the `os_log` line at the end of its
// `setupMIDI()` ("MIDI: Input ready (MIDI 2.0 + MPE + network)"). The detection sign worked
// exactly as written down after #768: when every checked surface shares one GATTUNG, the
// ENUMERATION is what was incomplete, not the care taken over each item.
//
// ⭐ AND MEASURING IT MADE THE FINDING SHARPER THAN THE COPY FIX. `MIDIBusPublisher`'s header
// called channel pressure "intentionally NOT wired in this first cycle" — a WIRING gap, which
// sends a session to that class to attach a callback. There is no callback:
// `MIDIEventParse.event(word0:word1:)` has no case for Channel Pressure (0xD0 in the MIDI 1.0
// branch, 0xD in the MIDI 2.0 branch) in EITHER switch, and `MIDIInEvent` has no case to carry
// one. The byte is dropped by `default: return nil` one layer below any wiring. Claim 6 pins
// that, so the note can never drift back to naming the wrong file.
//
// ⛔ THE EIGHTH SURFACE (#774) IS THE FILE WHOSE ONLY JOB IS TO PREVENT THIS. Claim 3 below
// has pinned "one monophonic voice" in the CODE since #548 — and `ContentPipeline/CLAIMS.md`,
// the register a video script is required to read before writing a caption, still listed
// "**MIDI-Eingang**: externer Controller spielt die Stimmen". Plural. The very word #548 struck
// from `CLAUDE.md` for being unreachable by construction, sitting for months in the one file
// that exists to keep captions honest. Measured again for #774, comment-stripped: outside
// `EngineBus` there is exactly ONE consumer of `controllerEvents`. `PolySynthVoice` does call
// `start(subscribing:)` but never reads that topic, and `LaneVoiceRack`'s bio voice says in its
// own comment that it is "NEVER subscribed to the bus".
//
// ⭐ AND THE ROW DIRECTLY BELOW IT WAS SCRUPULOUS THE WHOLE TIME — "gespielte NOTEN an dein Rig
// (MIDI 1.0)", switch and default named. **Writing one line honestly does not harden the line
// next to it.** That is the sharpest form of the enumeration lesson so far: the two rows are
// adjacent, one author, one table, and only one of them was checked.
//
// ⚠️ AND THE OBVIOUS OVER-CORRECTION WAS CHECKED AND REJECTED: the MIDI input is NOT hidden
// behind the "Body voice" arm switch. `apply(controller:)` is deliberately not `isArmed`-gated
// ("the performer always leads", `BioReactiveSynthVoice.swift:285`) — only the BREATH path is.
// A controller sounds immediately; it is merely monophonic. Claim 8 asserts the copy, and
// claim 4 already pins the arm-independence premise it rests on.
//
// ⚠️ HONEST GRADING FOR #766 (parent `c1d285b`), TRANSCRIBED in Python against both trees:
// **claim 5 is a REGRESSION** — the `id: "midi.in"` line reads `name: "MIDI / MPE In"` on the
// parent and `name: "MIDI In"` here. Claims 1-4 stay COUNTERWEIGHTS, green on both; they are
// the premises that make claim 5 true rather than a style preference.
//
// ⭐ EARLIER GRADING FOR #548 (the commit that created this file): **ZERO REGRESSIONS, and that
// was the correct result, not a gap.** That slice changed PROSE in `CLAUDE.md`; every assertion
// described code neither tree touched, so all four were green on both by construction. Booking
// them as caught regressions would have been the flattering-direction defect (#433). What the
// file bought was the FUTURE red — and #766 is the first instalment of exactly that.
//
// ⛔ THE NINTH SURFACE (#775) IS THE FIRST THAT UNDER-CLAIMED. Eight surfaces promised MPE the
// app does not have; `docs/architecture.html` did the opposite — it listed "MPE out" among the
// ROADMAP items, twice, while `CLAUDE.md` had said since #713 that MPE OUT is real and
// switchable. **A truth sweep that only looks for over-claims finds half the defects**, and
// every needle set in this repo's claim guards is a list of things-not-to-promise. The under-
// claim costs differently but it does cost: it is the page a rig owner reads before deciding
// whether Echoel can drive their MPE synth, and it told them no.
//
// ⛔ AND #775's OWN SWEEP WALKED PAST THREE FALSE SENTENCES (#778). It read every sentence on
// every page — the sentence-level pass was the whole point of that cycle — and it asked each
// one only about the token "MPE". `docs/tools.html` and `docs/faq.html` (twice) said in plain
// words that "CC 74 slide plays/reaches the built-in voices", without ever using that token.
// **The lesson is one turn past #766: an enumeration is incomplete when it enumerates SURFACES
// but not the WORDINGS a claim can take.** #766 said a capability claim has as many surfaces as
// someone lists; #778 says it has as many phrasings as someone lists, and a needle built from
// the word the last defect happened to use is a needle for the last defect. Claim 10's needle
// is therefore built from the CAPABILITY (a per-note dimension + "plays/reaches a voice"),
// which no rewording of "MPE" can slip past.
//
// ⚠️ HONEST GRADING FOR #775 (parent `d7c1083`), TRANSCRIBED in Python against both trees:
// **claim 9's page sweep is a REGRESSION CATCH** — twelve sentences across five pages call MPE
// output roadmap on the parent, none here. Its code half (three dimensions plus the zone
// announcer) is a COUNTERWEIGHT, green on both, and is the DURABLE one: it reds the day MPE
// output is removed and names the prose to move back. #367 driven: making any one page lump it
// again reds the sweep; deleting the Press send or renaming `sendMPEConfiguration` reds the code
// half; and a CONTROL that rewords an honest sentence stays GREEN — the #364 property, checked
// rather than asserted.
//
// ⛔ AND #775 SHIPPED RED (#776). Removing `private static let architecture` — correct, the
// sweep no longer names one page — left ONE reference alive inside a failure message's string
// INTERPOLATION, `\(Self.architecture)`, and the gate answered with `TEST BUILD FAILED`. Two
// diagnostics, ONE root cause (#689: count causes, not lines). The check that would have caught
// it is one line and is now reflexive after deleting a member:
//     git grep -n "Self\.<name>" -- Tests/CISmoke Sources
// ⚠️ And a naive version of that audit over the whole bundle reports TWENTY files, all false:
// `Self.x` also occurs inside NEEDLE STRINGS, which are prose to the compiler. The shape that
// is genuinely code inside a literal is the INTERPOLATION `\(Self.x)` — which is exactly what
// broke here, and what a string-blanking pass would have missed. Re-audited on that shape:
// this file was the only real one.
//
// ⛔ AND THE SWEEP CRIED WOLF ONCE ON A CORRECT TREE BEFORE IT SHIPPED, which is recorded rather
// than quietly fixed. `components(separatedBy: ". ")` does not split `".)"`, so `faq.html`'s
// honest MPE sentence was glued to the next one — "VST3 and CLAP are not planned." — and
// inherited the word "planned". The driver caught it; the boundary now skips a run of closing
// marks after the terminator. A checker with false alarms is a checker nobody reads (#665), and
// this one would have started its life with one.
//
// ⚠️ HONEST GRADING FOR #774 (parent `534a9f3`), TRANSCRIBED in Python against both trees:
// **claim 8 is a REGRESSION CATCH** — the `**MIDI-Eingang**` row reads "spielt die Stimmen" on
// the parent and names one monophonic voice here. #367 driven: restoring the plural into the
// row turns it red; relabelling the row makes the ANCHOR fail rather than pass silently (#454);
// and a CONTROL confirms the new §6b, which QUOTES the struck wording, leaves it green — the
// #491 trap the row anchor exists to avoid. Claims 1-7 are unchanged COUNTERWEIGHTS here.
//
// ⚠️ HONEST GRADING FOR #770 (parent `4267cb5`), TRANSCRIBED in Python against both trees:
// **`testTheInputLogLineDoesNotAnnounceMPE` is a REGRESSION CATCH** — the log literal reads
// "(MIDI 2.0 + MPE + network)" on the parent and "(MIDI 1.0 + 2.0 notes/CC/bend + network)"
// here. **`testTheInputPathParsesNoChannelPressure` is a COUNTERWEIGHT, green on both** (#343):
// it pins the premise that makes the retraction more than a wording preference, and it is the
// assertion that goes red the day the follow-up is really built. Both were driven against
// deliberately mutated trees (#367) — adding `case channelPressure` to `MIDIInEvent`, adding
// `case 0xD0:` to the MIDI 1.0 switch, and adding `case 0xD:` to the MIDI 2.0 switch each turn
// the intended assertion red, and a CONTROL that only writes "0xD0" into a COMMENT leaves it
// green (the #762 comment-as-code trap, checked rather than assumed).
//
// ⚠️ THE #770 GRADING ABOVE IS HISTORY: #939 BUILT THE FOLLOW-UP THE COUNTERWEIGHT WAS
// WAITING FOR, so `testTheInputPathParsesNoChannelPressure` is gone and
// `testTheInputPathParsesPressureAndStillNoZones` stands in its place. Nothing was softened —
// the three positive needles are the same three tokens the old CONTROL mutation used, asserted
// in the other direction, and the zone counterweight is new.
//
// ⚠️ HONEST GRADING FOR #939 (parent `8bb8ae6`), TRANSCRIBED in Python against both trees,
// ALL EIGHT assertions of claims 1, 1b, 2 and 6 driven — not only the changed ones (§3's
// delta-blindness rule):
// **ZERO REGRESSIONS.** SIX are FORWARD guards — they name symbols this same commit creates
// (`case channelPressure`, `Float(data1) / 127.0`, `case 0xD:`, `case .slide, .airCC:` without
// press, `synth.expressionGain =`, `amplitude * patchOutputLevel * expressionGain`) and could
// never have been red on the parent for their named reason. TWO are COUNTERWEIGHTS, green on
// both trees (no `event.channel` read; no RPN/zone token in the parser). Booking the six as
// regressions would be the flattering-direction defect #433 names.
//
// ⚠️ HONEST GRADING FOR #942 (parent `6cdc529`), TRANSCRIBED in Python against both trees,
// ALL 43 assertions driven — not only the changed ones (§3's delta-blindness rule, which has
// now paid for itself three times in this file):
// **ZERO REGRESSIONS.** FIVE are FORWARD guards — they name symbols this same commit creates
// (`case .airCC:` standing alone, `synth.renderCutoffScale =`, its clear in `panic()`, its
// clear in `reset()`, and the mono writer going through `clampExpressionScale`) and could
// never have been red on the parent for their named reason. The remaining 37 are
// COUNTERWEIGHTS, green on both. Claim 1's "the first statement is `break`" could not RUN on
// the parent at all, because `case .airCC:` does not exist there as its own case — an ANCHOR
// failure, which is the #454 shape and is deliberately NOT booked as a catch (#433).
//
// ⭐ CLAIM 10c NEEDED A THIRD TREE TO GRADE, and that is the point of its shape. It is green
// on the parent — correctly, because it is CONDITIONAL on the consumer, and the parent's
// consumer did not sound slide, so the parent's prose was honest. What it buys was measured
// by running the WORKTREE's two source files against the PARENT's prose: 43 checks, ONE fail,
// naming all three pages that had to be edited by hand this slice (`faq.html`, `tools.html`,
// `architecture.html`). A guard whose truth depends on the code it guards cannot be graded by
// two trees alone.
//
// ⭐ #367 DRIVEN, ELEVEN MUTATIONS, each moving exactly ONE assertion and no other:
// giving `.airCC` a statement reds claim 1's `break` check · renaming the case reds its
// existence check · removing the render multiply, the `panic()` line, the `reset()` line and
// the writer's clamp each red their own claim · declaring a second `clampExpressionScale`
// overload reds the one-definition check · dropping the POLY writer's clamp reds the other
// half of 1d · pluralising a site sentence reds 10a · saying air-CC reaches a voice reds 10b.
// TWO CONTROLS confirm the #364 property rather than assuming it: moving the slide write into
// a COMMENT still reds (the #762 comment-as-code trap, checked), and REWORDING an honest
// sentence ("the one voice" → "the single built-in performer voice") stays GREEN.
//
// ⛔ AND TWO OF THE FIRST ELEVEN MUTATIONS DID NOT LAND, which is recorded because a mutation
// that changes nothing reads exactly like a guard that does not fire (#776). One renamed
// `case .slide:` while leaving `case .airCC:` intact — it tested nothing. The other added a
// `clampExpressionScale2`, which the needle `func clampExpressionScale(` correctly does not
// match. Both were re-done to land before their result was believed.
//
// ⚠️ AND THE NEIGHBOURING PAGE GUARDS WERE MEASURED, NOT ASSUMED (#942). Seven other CISmoke
// files read `docs/*.html`. Every string literal in them (comments stripped) was tested
// against the ADDED and REMOVED text of the three pages this slice reworded: **0 literals
// newly present** (which could trip a ban) and **0 literals lost** (which could break a
// positive needle). The review that found this slice's compile error explicitly left this
// unmeasured; "low risk" and "measured" are different words (§2).
//
// ⛔ AND DRIVING **EVERY** ASSERTION IN THE FILE — not the changed ones — FOUND **THREE LIVE
// REDS ON A CORRECT TREE**, none of them caused by this slice. That is §3's delta-blindness
// rule paying for itself a second time (#937 was the first), and it is the reason the sweep was
// done at all: #939 had to touch this file anyway, so the whole file was transcribed.
//   1. **claim 7's `"timbre"` needle** matched `architecture.html`'s *Voice timbre* row — the
//      vocal-analysis feature — because `claimsItPlaysAVoice` finds "play" inside "**play**er".
//      The needle bought nothing ("slide"/"cc 74" already catch every genuine MPE use) and cried
//      wolf four ways. Removed; see the ⛔ at the helper.
//   2. **claim 10 was genuinely red on the PROSE**: `faq.html` put "bidirectional OSC is on the
//      roadmap" and "MPE output" in ONE sentence, so a shipped capability read as roadmap. The
//      guard's own failure message says what to do — name them separately — and that is the fix.
//      This one is a REGRESSION CATCH: the guard was right and the page was wrong.
//   3. **claim 12's citation rule was per-LINE** and `APP_STORE_LISTING_v1.md` wraps its
//      blockquote between "MPE **in** stays" and "unclaimable (#548/#770)." — one honest
//      sentence, split by a reflow. Window widened to ±1 line.
// Two needle defects, one real prose defect. #396 is why none surfaced: a genuinely red guard
// is indistinguishable from the host dying on every push.
//
// ⭐ `SourceText.codeOnly` is now TRAGEND for claim 6, MEASURED over {4 assertions × 2 trees}:
// **1 of 8** verdicts flips. On the WORKTREE the zone counterweight is green stripped and RED
// raw, because `MIDIEventParse`'s own retraction comment says "Zone detection (RPN 6,6)" —
// the honest sentence that explains why this is not MPE would have reddened the guard that
// pins it. Exactly the #762 comment-as-code trap, this time caught by measuring instead of
// asserting. (It was PROPHYLACTIC — 0 of 6 — for the pre-#939 shape of this claim.)
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC for claims 1-4 too, MEASURED (#453) over
// {4 claims × 2 trees}:
// **0 of 8** verdicts flip. The scanned members carry comments that mention `.slide` and
// `channel`, but every assertion is scoped to a brace-matched body and asks about tokens that
// the comments happen not to spell in a way that would flip a verdict. Said plainly rather
// than claimed load-bearing — three slices in this repo asserted that without measuring and
// had to retract.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMPEInputHasNoZonesTests: XCTestCase {

    private static let voice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let router = "Sources/Echoelmusic/Core/SignalRouter.swift"
    private static let dsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"
    private static let parse = "Sources/Echoelmusic/Audio/MIDIEventParse.swift"
    private static let input = "Sources/Echoelmusic/Audio/MIDIInput.swift"
    private static let claims = "ContentPipeline/CLAIMS.md"
    private static let out = "Sources/Echoelmusic/Audio/MIDIOutput.swift"
    private static let readme = "README.md"

    /// The correction this guard protects, quoted so a failure can point at it precisely.
    ///
    /// ⛔ #942 REWROTE THE QUOTED HALF, and the reason is worth keeping: this string named the
    /// FAQ's wording "notes, pitch bend and CC 74 slide are PARSED" as the already-vetted
    /// phrasing to copy. #939 and #942 sounded pressure and slide, so the sentence a failure
    /// message told the next session to copy had become the false one — a guard handing out
    /// stale copy is worse than a guard saying nothing, because it is prescriptive. What
    /// survives untouched is the DURABLE half: no zones, no member channels, one voice.
    private static let prose = """
        CLAUDE.md's pipeline line (search for `controllerEvents → `). It must not promise MPE, \
        per-note expression or polyphony from this path. Three continuous dimensions do reach \
        the built-in voice — pitch bend, press (#939) and slide (#942) — but no MPE zone is \
        announced to us (RPN 6,6), no member channel is told apart, and it is ONE monophonic \
        voice. Dimensions without zones is expressive MIDI, not MPE input.
        """

    // MARK: - claim 1 — the one dimension that is NOT MPE is the one still discarded

    /// ⭐ #939 TOOK THIS CLAIM FROM THREE TO TWO AND #942 TOOK IT TO ONE, and each step is
    /// #364 in action: a guard must not forbid correct work. Channel pressure reaches the
    /// voice since #939 (`expressionGain`, claim 1b); CC 74 slide reaches it since #942
    /// (`renderCutoffScale`, claim 1c). Pinning "the expression dimensions are discarded"
    /// would have reddened this file on each tree that did the work.
    ///
    /// ⚠️ AND WHAT IS LEFT IS NOT AN MPE DIMENSION AT ALL, which is the honest thing to say
    /// rather than dressing the remainder up as a surviving gap. MPE's three continuous
    /// dimensions are pitch bend (X), CC 74 slide (Y) and channel pressure (Z) — all three now
    /// reach this voice. `.airCC` is CC 21–31 (`EngineBus`: "air dimensions"), a breath /
    /// wind-controller convention that no MPE document defines. Its `break` therefore says
    /// nothing about MPE either way; it is kept because a page claiming air-CC sounds a voice
    /// would still be false (claim 10b).
    ///
    /// ⛔ THE FILE'S OWN HEADER USED TO CALL SLIDE, AIR-CC AND PRESSURE "exactly the three
    /// dimensions that MAKE it MPE" — off by one in both directions. It counted `.airCC` in
    /// and left PITCH BEND out, and pitch bend is the dimension this voice has always handled.
    /// Corrected in the header for #942; recorded here because the miscount is what made
    /// "one of three", "two of three" and this claim's own name read as bookkeeping.
    ///
    /// ⚠️ WHAT DID **NOT** CHANGE, which is why this file survives rather than being deleted,
    /// and what its NAME now says: `event.channel` is read nowhere (claim 2), the performer
    /// path is still monophonic (claim 3), no RPN 6,6 zone is detected (claim 6), and the
    /// routing screen still offers no MPE input (claim 5). Three dimensions without zones and
    /// without member channels is expressive MIDI, not MPE input.
    func testTheAirDimensionIsStillDiscarded() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertTrue(body.contains("case .airCC:"), """
            `BioReactiveSynthVoice.apply(controller:)` no longer discards air-CC in a case of \
            its own. If you gave it an effect, say so on the pages claim 10 guards — but note \
            that air-CC is NOT an MPE dimension, so it changes nothing about \(Self.prose)
            """)
        // The `break` must be the WHOLE handling. A body that grew statements under that case
        // would keep the needle above green while the behaviour changed — the "green for a
        // reason that no longer exists" failure this bundle exists to prevent (#456).
        guard let caseRange = body.range(of: "case .airCC:") else {
            return   // already failed above with a message that says what to do
        }
        let rest = body[caseRange.upperBound...]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        XCTAssertEqual(rest.first, "break", """
            The air-CC case is no longer a bare `break` — its first statement is \
            "\(rest.first ?? "")". Something now happens for those events, so the pages that \
            say nothing consumes air-CC need the same edit (claim 10b), and \(Self.prose)
            """)
    }

    // MARK: - claim 1b — and PRESS really does reach the sound, not just a property

    /// ⭐ #939, and it is the COUNTERWEIGHT to claim 1 (#343). Claim 1 alone is satisfied by
    /// deleting `.channelPressure` from the switch entirely, which would take the dimension
    /// back out while reading greener than before. This claim is the other half: press must
    /// write `expressionGain`, and `expressionGain` must reach the master-gain target — a
    /// property nobody multiplies is the "wired, doorless, ineffective" category this repo
    /// carries at six other places.
    ///
    /// ⚠️ IT PINS THE PATH, NOT THE DEPTH. `pressDepth` is a founder-ear number
    /// (NEEDS-FOUNDER-VERIFY); asserting its value would redden the day the founder asks for a
    /// different swell, which is exactly the change this guard should welcome.
    func testPressReachesTheMasterGain() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertTrue(body.contains("synth.expressionGain ="), """
            Channel pressure no longer writes `synth.expressionGain`. Either the dimension was \
            taken back out — then claim 1 above must go back to naming three, and the prose in \
            `CLAUDE.md`, `MIDIInput.swift` and `SignalRouter.swift` with it (#456) — or it \
            found another route, in which case re-anchor here on that route.
            """)
        let dsp = try source(Self.dsp)
        XCTAssertTrue(SourceText.codeOnly(dsp)
            .contains("amplitude * patchOutputLevel * expressionGain"), """
            `expressionGain` no longer multiplies the master-gain target in `EchoelDDSP`'s \
            render block. The property would still exist and the switch would still write it, \
            so every other claim here stays green while PRESS becomes inaudible — a control \
            that moves a number nobody reads.
            """)

        // THE THIRD HALF, from the mandatory audio-thread review of #939: a gain that can be
        // RAISED and never LOWERED is a stuck fader nobody can clear. Both latches that already
        // exist for the note must cover the press — `panic()` (controller unplugged mid-note, or
        // the event dropped under SPSC flood) and `EchoelDDSP.reset()` (a reset voice must not
        // carry a stale gain into whatever plays next, the #174 argument one line above it).
        // Without these the BREATH voice inherits +3.5 dB for the rest of the session.
        let panicBody = try memberBody("public func panic()", in: Self.voice)
        XCTAssertTrue(panicBody.contains("synth.expressionGain = 1"), """
            `panic()` no longer clears the press gain. A press that never got its release \
            leaves this voice above nominal with no control able to restore it — the exact \
            shape `panic()` exists to break for the note latch beside it.
            """)
        // ⛔ #408 — THIS DID NOT ANCHOR ON `public func reset()`, AND THE FIRST DRAFT DID.
        // That signature occurs TWICE in `EchoelDDSP.swift` (mono and `EchoelPolyDDSP`), so
        // `memberBody` refused it — caught by transcribing before pushing, not by CI. The
        // unique token is the neighbouring `velocityGain = 1` (exactly one occurrence in the
        // comment-stripped file); the scan then asks only the statements up to that block's
        // close. Scoping is not decoration here: the bare needle `expressionGain = 1` occurs
        // TWICE, because the property's own `didSet` default is `expressionGain = 1.0`.
        // (`dsp` is the comment-stripped text bound above — one read, two questions.)
        let resetTail = try XCTUnwrap(dsp.range(of: "velocityGain = 1")).upperBound
        let block = dsp[resetTail...]
        let close = block.range(of: "}")?.lowerBound ?? block.endIndex
        XCTAssertTrue(block[..<close].contains("expressionGain = 1"), """
            `EchoelDDSP.reset()` no longer clears the press gain beside `velocityGain`. It \
            clears `velocityGain` for the reason its own comment gives; the press factor \
            multiplies the same target and needs the same line.
            """)
    }

    // MARK: - claim 1c — and SLIDE really does reach the sound, on a per-SAMPLE parameter

    /// ⭐ #942, the same shape as claim 1b one step down (#343). Claim 1 is satisfied by
    /// deleting `.slide` from the switch, which would take the dimension back out while
    /// reading greener than before. This claim is the other half, and it pins the DESTINATION
    /// as well as the write, because the destination is the whole design decision:
    ///
    /// · the switch must write `synth.renderCutoffScale`. The obvious alternative,
    ///   `brightness`, is wrong twice — `applyBioReactive` rewrites it from the bio frame
    ///   (~1 Hz, so a slide is erased within a second) and its `didSet` recomputes the whole
    ///   spectral envelope, which a CC 74 stream would trigger hundreds of times a second;
    /// · `renderCutoffScale` must still MULTIPLY the cutoff in the render. A property nobody
    ///   multiplies is the "wired, doorless, ineffective" category this repo carries at six
    ///   other places, and every other claim here would stay green while slide went silent;
    /// · both latches must clear it, for the #939 reviewer's reason: a slide that never got
    ///   its release — controller unplugged mid-note, or the event dropped under SPSC flood —
    ///   would otherwise hold the filter open for the rest of the session, and the BREATH
    ///   voice would inherit it with no control able to restore it.
    ///
    /// ⚠️ IT PINS THE PATH, NOT THE DEPTH. `slideDepth` is a founder-ear number
    /// (NEEDS-FOUNDER-VERIFY); asserting its value would redden the day the founder asks for a
    /// narrower or wider sweep, which is exactly the change this guard should welcome.
    func testSlideReachesTheFilterCutoff() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertTrue(body.contains("synth.renderCutoffScale ="), """
            CC 74 slide no longer writes `synth.renderCutoffScale`. Either the dimension was \
            taken back out — then claim 1 above must go back to naming it, and the prose in \
            `CLAUDE.md`, `MIDIInput.swift`, `SignalRouter.swift`, `ContentPipeline/CLAIMS.md` \
            and `docs/{faq,tools,architecture}.html` with it (#456) — or it found another \
            route, in which case re-anchor here on that route.
            """)
        let dsp = try source(Self.dsp)
        XCTAssertTrue(SourceText.codeOnly(dsp)
            .contains("filterCutoff * renderCutoffScale"), """
            `renderCutoffScale` no longer multiplies the cutoff in `EchoelDDSP`'s render block. \
            The property would still exist and the switch would still write it, so every other \
            claim here stays green while SLIDE becomes inaudible — a control that moves a \
            number nobody reads.
            """)

        let panicBody = try memberBody("public func panic()", in: Self.voice)
        XCTAssertTrue(panicBody.contains("synth.renderCutoffScale = 1"), """
            `panic()` no longer clears the slide scale. A slide that never got its release \
            leaves this voice with the filter held open and no control able to restore it — \
            the exact shape `panic()` exists to break for the note and press latches beside it.
            """)
        // Same anchoring as claim 1b, and for the same #408 reason: `public func reset()`
        // occurs TWICE in `EchoelDDSP.swift` (mono and `EchoelPolyDDSP`), so the unique token
        // is the neighbouring `velocityGain = 1` and the scan asks only that block. Scoping is
        // load-bearing here too: the bare needle `renderCutoffScale = 1` also appears as the
        // property's own default declaration.
        let resetTail = try XCTUnwrap(dsp.range(of: "velocityGain = 1")).upperBound
        let block = dsp[resetTail...]
        let close = block.range(of: "}")?.lowerBound ?? block.endIndex
        XCTAssertTrue(block[..<close].contains("renderCutoffScale = 1"), """
            `EchoelDDSP.reset()` no longer clears the slide scale beside `velocityGain`. It \
            clears `velocityGain` for the reason its own comment gives; the slide factor \
            multiplies the same filter and needs the same line.
            """)
    }

    // MARK: - claim 1d — ONE clamp guards the scale, and both writers go through it

    /// ⭐ #942. `renderCutoffScale` had two writers as of this slice and only one of them was
    /// sanitised: `EchoelPolyDDSP` clamped through `clampExpressionScale`, the mono performer
    /// voice had no door at all. The failure that opens is QUIET rather than loud — the render
    /// clamps the product with the NaN-safe `clamped(to: Self.cutoffRange)`, which maps a
    /// non-finite value to the LOWER bound, i.e. a 20 Hz filter that sounds silent while every
    /// control still reads healthy (the #29/#92 permanent-silence class).
    ///
    /// ⚠️ THE FIX WAS A MOVE, NOT A SECOND CLAMP, and that is what this claim pins. The helper
    /// was `private` to `EchoelPolyDDSP` while its own first sentence called itself "One clamp
    /// for every writer of a per-note expression scale"; #942 moved it onto `EchoelDDSP` — the
    /// type that owns the property — so there stays exactly ONE definition (#416). A second,
    /// differently-bounded clamp (the first draft used 0.05…8 against the helper's 0.1…8) is
    /// precisely what this asserts against.
    ///
    /// ⚠️ IT DOES NOT ASSERT THE BOUNDS. Those are a DSP judgement the founder's ear may move;
    /// what must not drift is that there is one helper and that every writer calls it.
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS CLAIM COULD NOT SEE THE COPY THAT ALREADY EXISTED —
    /// found by #942's mandatory audio-thread review, not by the guard. It counted
    /// occurrences of `func clampExpressionScale(` and asserted ONE, so a HAND-INLINED copy
    /// was invisible to it by construction. `EchoelPolyDDSP.setCutoffScale` carried
    /// `min(max(scale.isFinite ? scale : 1, 0.1), 8)` — the helper's body character for
    /// character — while the helper's own doc pointed at it ("Bounds match `setCutoffScale`").
    /// The two govern ONE product: `cutoffScale` and the per-note scale are multiplied at the
    /// fan-out and re-clamped through the helper. #942 routed the setter through the helper
    /// AND added the body scan below.
    /// **The law: a "one definition" claim needs a needle on the BODY, because an inlined copy
    /// has no name to count.** A guard that can only see declarations checks the vocabulary,
    /// not the decision.
    func testOneClampGuardsTheExpressionScale() throws {
        let dsp = SourceText.codeOnly(try source(Self.dsp))
        let declarations = dsp.components(separatedBy: "func clampExpressionScale(").count - 1
        XCTAssertEqual(declarations, 1, """
            `clampExpressionScale` is declared \(declarations) times in \(Self.dsp), not once. \
            Two clamps for one property is how the mono and poly writers drift apart: the \
            render's own NaN handling maps a bad value to a 20 Hz filter, which sounds like \
            silence while every control reads healthy. Keep ONE definition (#416).
            """)
        let voiceBody = try memberBody("private func apply(controller event: ControllerEvent)",
                                       in: Self.voice)
        XCTAssertTrue(voiceBody.contains("clampExpressionScale("), """
            The mono performer voice writes `renderCutoffScale` without going through \
            `clampExpressionScale`. The poly writer has clamped since it was written; this one \
            takes its value straight off the MIDI wire.
            """)
        XCTAssertTrue(dsp.contains("clampExpressionScale(cutoffScale * voiceCutoffScale["), """
            The poly writer no longer clamps its per-voice cutoff scale. Both writers of \
            `renderCutoffScale` must pass through the one helper — if the poly path moved to \
            another shape, re-anchor here on it rather than dropping the claim.
            """)
        // The half the declaration count cannot see: an INLINED copy of the helper's body.
        // The needle is the tail of that body, which is specific enough that nothing else in
        // this file spells it and short enough to survive a reformat of the head.
        let inlined = dsp.components(separatedBy: "0.1), 8)").count - 1
        XCTAssertEqual(inlined, 1, """
            The expression-scale clamp's body appears \(inlined) times in \(Self.dsp), not once. \
            A hand-inlined copy is exactly what the declaration count above cannot see, and it \
            is how `setCutoffScale` carried a second copy of this law for months while the \
            helper's doc pointed at it. Route the new writer through `clampExpressionScale`; \
            if the BOUNDS themselves changed, change them in the helper and this needle with \
            them, in the same commit.
            """)
    }

    // MARK: - claim 2 — no member channel is read, so no zone can exist

    func testTheVoiceReadsNoMemberChannel() throws {
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertFalse(body.contains("event.channel"), """
            `apply(controller:)` now reads `event.channel`. That is where an MPE member \
            channel arrives, so this voice may have started distinguishing per-note zones — \
            the capability `CLAUDE.md` used to claim. Good news, and it means \(Self.prose)
            """)
    }

    // MARK: - claim 3 — one voice, so "notes" plural was never reachable here

    /// ⛔ #943b — THIS CLAIM WENT RED ON A CORRECT TREE AND THE COMMIT SHIPPED ANYWAY. Its
    /// needle was the LITERAL `private var heldByController = false`, and #943 replaced that
    /// stored `Bool` with a bounded held-note stack plus a derived flag. The monophony it pins
    /// never stopped being true; the WITNESS was deleted under it.
    ///
    /// ⭐ THE LESSON IS THE ONE `Tests/CISmoke/CLAUDE.md` §4 ALREADY WRITES DOWN, unlearned:
    /// **when you delete or rename a declaration, grep the BLOCKING BUNDLE for it, not only
    /// `Sources/`.** #776 made that reflex for `Self.<name>` after deleting a member; this is
    /// the same reflex for a source-text needle, and #942b had just paid for the sibling
    /// version (an argument label). Neither `Xcode Compile Check` nor `dead-needles.py` could
    /// see it AT THE TIME: the first builds `Sources/` alone, and the second only recognised a
    /// receiver bound as `Self.source(…)` — while this file binds `try source(Self.voice)`,
    /// plain — and skipped the whole file anyway, because it reads `docs/*.html` for claim 10
    /// and the tool's file-level path proxy refused any guard naming a non-`Sources/` path.
    ///
    /// ⭐ #944 CLOSED BOTH, USING THIS EXACT DEFECT AS ITS KNOWN POSITIVE. Run over `25d34dc`
    /// the tool now reports one finding, at this file, on the line the reviewer named. The
    /// sentence above is kept in the past tense rather than deleted: it is the reason the
    /// widening #941 had measured and declined became worth shipping (`Tests/CISmoke/CLAUDE.md`
    /// §4). Do not read it as a standing property of the tool.
    ///
    /// ⚠️ MEASURED, not inferred — `grep -c "private var heldByController = false"` on
    /// `BioReactiveSynthVoice.swift`: **1** at `febecdb`, **0** at `25d34dc` (the tree #943
    /// actually shipped), **0** here. So the guard really was red on a correct tree for one
    /// commit, and the re-anchored form below is green on all three trees that HAVE the
    /// declaration. Recorded because "it would have gone red" is a guess and this is not.
    ///
    /// ⚠️ RE-ANCHORED ON WHAT #943 LEAVES INVARIANT, not on a spelling. Monophony is now two
    /// facts that no note-priority rewrite can quietly take away: the flag is Bool-valued and
    /// DERIVED from the stack (a derived flag cannot disagree with the keys — that was the
    /// point of #943), and the switch still starts exactly ONE note and releases exactly ONE.
    /// A second `playNote(` in that member is what polyphony would actually look like here.
    func testThePerformerPathIsMonophonic() throws {
        let code = try source(Self.voice)
        XCTAssertTrue(code.contains("private var heldByController: Bool"), """
            `heldByController` is no longer a Bool-valued single flag on this voice. If the \
            performer path became polyphonic, "synth notes" is finally true of it and \
            \(Self.prose)
            """)
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        XCTAssertEqual(body.components(separatedBy: "playNote(").count - 1, 1, """
            `apply(controller:)` starts more than one note. ONE monophonic voice is the whole \
            claim — a second `playNote(` in this member is what polyphony would look like, and \
            \(Self.prose)
            """)
        XCTAssertEqual(body.components(separatedBy: "releaseNote()").count - 1, 1, """
            `apply(controller:)` releases more than one note. Same claim from the other side: \
            one voice has exactly one release.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the true half is still true

    /// #343. A file that only asserts "MPE does not arrive" stays green on a tree that deleted
    /// external MIDI input altogether, leaving a corrected sentence that is now wrong the other
    /// way. So pin what the corrected line still promises: the dimensions exist on the event
    /// type, and notes and bend still reach the voice.
    ///
    /// ⛔ THIS DOC SAID THE DIMENSIONS ARE "IGNORED, not absent" — true when #343 wrote it,
    /// false since #942. Press (#939) and Slide (#942) are consumed; only `.airCC` is ignored.
    /// The ASSERTION never depended on that word — it asks whether the cases exist on
    /// `ControllerEvent.Kind` — which is why it stayed green and silently stale.
    func testNotesAndBendStillReachTheVoice() throws {
        let busCode = try source(Self.bus)
        for dimension in ["case channelPressure", "case slide", "case airCC"] {
            XCTAssertTrue(busCode.contains(dimension), """
                `ControllerEvent.Kind` no longer carries `\(dimension)`. The point of the \
                corrected prose is that the wire carries these dimensions at all — two of them \
                now sound (press #939, slide #942) and air-CC is carried and ignored. If the \
                event type stopped carrying one, the honest sentence changes again — \
                \(Self.prose)
                """)
        }
        XCTAssertTrue(busCode.contains("public let channel: UInt8"), """
            `ControllerEvent.channel` is gone. Claim 2 asserts the voice does not READ it, \
            which only means something while the field exists to be read.
            """)
        let body = try memberBody("private func apply(controller event: ControllerEvent)",
                                  in: Self.voice)
        for handled in ["case .noteOn:", "case .noteOff:", "case .pitchBend:"] {
            XCTAssertTrue(body.contains(handled), """
                `apply(controller:)` no longer handles `\(handled)`. External MIDI notes and \
                bend are the half of the pipeline line that IS true; if they stopped arriving, \
                the corrected sentence overstates in the other direction — \(Self.prose)
                """)
        }
    }

    /// The routing screen must not offer an MPE INPUT the app cannot receive.
    ///
    /// ⛔ #766 — THE SIXTH SURFACE, AND #548 CHECKED FIVE. That slice corrected CLAUDE.md's
    /// pipeline line, the FAQ, `architecture.html`, the App Store text and
    /// `ContentPipeline/CLAIMS.md`. Every one of them is PROSE. `SignalRouter`'s source port
    /// was named "MIDI / MPE In" and is rendered by `PatchbayView`, which is reachable through
    /// the `showRouting` sheet — so the only surface a player reads WHILE PATCHING kept the
    /// claim for two months after the prose was fixed. A capability claim's surfaces are only
    /// as many as somebody enumerates.
    ///
    /// ⚠️ THE SINK KEEPS ITS NAME ON PURPOSE (#364). "MIDI / MPE Out" is TRUE: MPE out is real
    /// and switchable since #713, with two persisted toggles in this same routing surface. The
    /// asymmetry is the finding; a guard that banned "MPE" from the file would forbid the
    /// honest half and be deleted along with the law.
    ///
    /// ⚠️ IT ANCHORS ON THE SOURCE LINE, NOT ON A FILE-WIDE COUNT. `id: "midi.in"` occurs once
    /// and is the identity a rename cannot silently take with it; the display name travels
    /// beside it. A file-wide "MPE In" ban would also match the retraction comment above the
    /// line, which QUOTES the struck name — the #491 shape, red on the commit that fixes it.
    func testTheRoutingScreenOffersNoMPEInput() throws {
        let router = try source(Self.router)
        guard let line = SourceText.codeOnly(router)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("id: \"midi.in\"") })
        else {
            throw MPEAnchorMissing(reason: """
                No port declares `id: "midi.in"` in \(Self.router) — this scan found nothing \
                rather than nothing wrong (#454). If the port moved, re-anchor it here in the \
                same commit.
                """)
        }
        XCTAssertFalse(String(line).contains("MPE"), """
            The MIDI INPUT port is called "\(line.trimmingCharacters(in: .whitespaces))" again.

            The app cannot receive MPE: `MIDIBusPublisher` disambiguates no zones and \
            `apply(controller:)` never reads `event.channel`, so no member channel exists to \
            tell apart — the claims the tests above pin. The three continuous dimensions DO \
            reach the voice (bend, press #939, slide #942); dimensions without zones is \
            expressive MIDI, not MPE input. MPE **out** \
            is real, so the sink port keeps its name; only the SOURCE must not promise it. \
            If a real MPE receiver is built, this whole file goes red together and the \
            corrected prose goes back — \(Self.prose)
            """)
    }

    // MARK: - claim 9 — the website sold the working half as roadmap

    /// #775. Every surface before this one over-claimed; this is the FIRST that UNDER-claimed,
    /// and it is worth naming as a distinct failure. `docs/architecture.html` listed "MPE out"
    /// twice among things that are ROADMAP, while `CLAUDE.md` had said since #713 that MPE OUT
    /// is real and switchable. One of the two was wrong for months and the code says which.
    ///
    /// Measured: `MIDIOutput` announces the zone from three sites, allocates member channels
    /// 2–16, and `sendExpression` emits all three per-note dimensions on every note-on while
    /// the two shipped switches are on — Glide (0xE0), Slide (CC 74) and Press (0xD0). The
    /// producer is `PianoRollModel`'s tick handler, which runs from app start.
    ///
    /// ⚠️ MIDI 2.0 OUT REALLY IS ROADMAP AND WAS LEFT ALONE. `MPEExpression.midi2NoteOnMessages`
    /// has zero callers — declaration only. The page was right about that half, and correcting
    /// a sentence is not a licence to correct the clause next to it (#774's lesson, applied in
    /// the other direction).
    ///
    /// ⛔ AND THE FIRST VERSION OF THIS TEST PINNED ONE PAGE, which is the exact defect the
    /// header above spends four paragraphs on. `docs/architecture.html` carried two of the
    /// occurrences; a line-based grep then found seven more across `faq`, `overview`, `index`
    /// and `tools`, and a SENTENCE-level pass found a tenth in `press.html` that the
    /// line-based one could not see. **Ten passages edited across six files** — and the finished
    /// guard, transcribed against the parent, flags **twelve sentences** there, because a page's
    /// JSON-LD block repeats the claim in prose the editor never sees. Two numbers, two
    /// operations, both correct: passages I rewrote vs. sentences the scan rejects. A guard
    /// pinned to the page I happened to open would have gone green with eleven alive. It sweeps
    /// `docs/` from the directory now (#769), sentence by sentence (#775's own near-miss).
    ///
    /// ⚠️ ONE ACCEPTED COST, STATED (#364): a genuinely correct future sentence — "MPE out over
    /// MIDI 2.0 is on the roadmap" — would red here. The failure message asks for the transport
    /// in its own sentence instead, which is the wording this cycle had to write nine times
    /// anyway. A guard that cannot be tripped by a careless sentence cannot catch this defect.
    ///
    /// The second half is the DURABLE one: it pins the code premise, so removing MPE out reds
    /// here and the message names the prose to move back.
    func testTheSiteDoesNotSellShippedMPEOutputAsRoadmap() throws {
        for (name, html) in try websitePages() {
            for sentence in sentences(in: html) where mentionsMPEOutput(sentence) {
                let lower = sentence.lowercased()
                XCTAssertFalse(lower.contains("roadmap") || lower.contains("planned"), """
                    `docs/\(name)` calls MPE output roadmap: "\(sentence)"

                    MPE OUT SHIPS. `MIDIOutput` announces the zone, allocates member channels \
                    2–16 and sends Glide (0xE0), Slide (CC 74) and Press (0xD0) on every \
                    note-on while the two routing switches are on. What IS roadmap is MPE on \
                    the way IN, and native MIDI 2.0 out — name those separately, in their own \
                    sentence, rather than in one clause with the half that works.

                    If MPE output was actually REMOVED, the second half of this test is red \
                    too and this sentence is correct again — read that failure first.
                    """)
            }
        }

        // COUNTERWEIGHT (#343): the premise that makes "LIVE" true on the page. Without this,
        // a tree that deleted MPE output would keep this file green while the site promised it.
        let code = try source(Self.out)
        for (needle, dimension) in [("0xE0 | UInt8(ch)", "Glide (14-bit pitch bend)"),
                                    ("MPEExpression.slideCCIndex", "Slide (CC 74)"),
                                    ("0xD0 | UInt8(ch)", "Press (channel pressure)")] {
            XCTAssertTrue(code.contains(needle), """
                `MIDIOutput` no longer sends \(dimension) on the MPE output path. The page now \
                says MPE out is LIVE with all three dimensions — if the path lost one, that \
                sentences under `docs/` must move in the same commit (#456), and so \
                must `CLAUDE.md`'s "MPE OUT ist real und schaltbar".
                """)
        }
        XCTAssertTrue(code.contains("private func sendMPEConfiguration()"), """
            `MIDIOutput` no longer announces the MPE zone. Zone announcement is what makes the \
            output MPE rather than plain multi-channel MIDI; the site's "the zone is announced" \
            sentence must move with it.
            """)
    }

    // MARK: - claim 11 — the caption register may say the half that ships

    /// #780. THE PARAGRAPH WAS CORRECTED AND THE RULE LINE WAS NOT, AND THE RULE LINE IS THE
    /// ONE A SCRIPT AUTHOR COPIES. `ContentPipeline/CLAIMS.md` §6 has said since #548 that
    /// "MPE OUT ist real und schaltbar, MPE IN nicht" — and the Erlaubt/Nicht-erlaubt line
    /// underneath still banned the bare tokens "MPE" and "per-note expression" outright.
    ///
    /// Two concrete costs, which is why this is a defect and not editorial taste:
    ///   · "per-note expression" is the literal on-screen label of a shipped switch
    ///     (`PatchbayView`), so a caption could not name a control the user can see.
    ///   · A rig owner read "no" where the app says yes — the same under-claim #775 removed
    ///     from the website, left standing one cycle longer in the file whose entire purpose
    ///     is stopping false captions (#456: every home in the same commit).
    ///
    /// ⚠️ THE BAN'S REASON SURVIVES AND SHAPES THE REPAIR. A DIRECTIONLESS "MPE" really does
    /// promise the missing half, so the direction word is mandatory, not decoration: "MPE"
    /// alone stays forbidden, "MPE-Ausgang" / "MPE out" is allowed. This claim asserts that the
    /// ALLOWANCE exists; it never asserts the ban is gone.
    ///
    /// ⚠️ AND THE HEADING ANCHOR IS LENIENT BY CONSTRUCTION, measured while driving this:
    /// `range(of: "### 6. MPE")` matches a PREFIX, so renaming the section to "### 6. MPE-Zeug"
    /// keeps it green. That is acceptable (it is still the MPE section) but it must be said,
    /// because a driven mutation that only renames the suffix proves nothing — the mutation
    /// that actually tests the anchor removes the token.
    ///
    /// The code premise is not restated here (#416): claim 9 already pins the zone announcer
    /// and all three send paths, so removing MPE output reds there first.
    func testTheCaptionRegisterMaySayMPEOutput() throws {
        let text = try rawFile(Self.claims)
        XCTAssertTrue(text.contains("| **MPE-AUSGANG an Dein Rig**"), """
            `ContentPipeline/CLAIMS.md` has no allowed row for MPE OUTPUT.
            It ships: the zone is announced, notes are spread over member channels 2–16, and
            each carries Glide, Slide and Press, behind two switches in the reachable routing
            surface. A caption writer reads the ✅ table to learn what may be said; with no row
            there, the shipped half is invisible to them.
            If MPE output was genuinely removed, claim 9's code half is red too — read that
            failure first, then this row, `docs/`, `README.md` and `CLAUDE.md` all move in the
            same commit (#456).
            """)
        guard let start = text.range(of: "### 6. MPE") else {
            throw MPEAnchorMissing(reason: """
                `CLAIMS.md` no longer has a "### 6. MPE" section. This guard cannot look, which
                is not the same as finding nothing wrong (#454) — re-anchor it in the same
                commit as the rename.
                """)
        }
        let rest = text[start.upperBound...]
        let section = String(rest[..<(rest.range(of: "\n### ")?.lowerBound ?? rest.endIndex)])
        XCTAssertTrue(section.contains("MPE-AUSGANG") || section.contains("MPE out"), """
            `CLAIMS.md` §6 no longer allows the DIRECTED output wording. Its own paragraph says
            MPE out is real and switchable; a rule line that forbids every form of the word
            contradicts the reasoning printed directly above it.
            The repair is not to drop the ban — a directionless "MPE" still promises the input
            half, which runs into a `break` (claim 1). It is to require the direction word.
            """)

        // THE SECOND PROSE HOME, and the one that denies the capability with a CODE premise
        // rather than a caption rule. `README.md` said the two output flags had no writer in
        // `Sources/` — false since #713. One decision, two homes, one claim (#416); the
        // enumeration of homes is the whole lesson of #766/#778.
        let readme = try rawFile(Self.readme)
        XCTAssertFalse(readme.contains("neither flag has a writer"), """
            `README.md` still says the MPE output flags have no writer.
            They do: `MIDIOutput.applyOutputPreferences()` reads `StudioDefaultKeys.midiOutMPE`
            and `.midiOutExpression`, and `PatchbayView`'s two toggles drive them through
            `.onChange`. Both default OFF, which is the honest caveat — "off by default" is not
            the same sentence as "impossible".
            """)
        let code = try source(Self.out)
        XCTAssertTrue(code.contains("public func applyOutputPreferences()"), """
            `MIDIOutput.applyOutputPreferences()` is gone — the writer that makes both prose
            repairs above true. If the switches were genuinely unwired again, `README.md` and
            `CLAIMS.md` §6 move back in the same commit (#456).
            """)
    }

    // MARK: - claim 10 — the site does not pluralise what a dimension reaches

    /// #778. THE NEEDLE WAS THE WORD "MPE", AND THE CLAIM WAS MADE WITHOUT IT. Claim 9 swept
    /// every `docs/*.html` sentence one cycle earlier and passed over three sentences that
    /// said, in plain words, that CC 74 slide *plays* / *reaches* "the built-in voices":
    /// `tools.html`, and twice in `faq.html`. They never used the token the sweep looked for.
    ///
    /// ⛔ #942 TURNED THE FIRST HALF OF THAT DEFECT TRUE, AND THE GUARD HAD TO FOLLOW (#364).
    /// Those sentences were false in two independent ways, and only one of them has expired:
    ///   · "slide plays a voice" — FALSE when #778 wrote it (`.slide` hit `break`), TRUE since
    ///     #942 gave it `renderCutoffScale`. A needle that still banned it would redden this
    ///     file on the sentence that finally tells the truth. The dimension half of the needle
    ///     is therefore GONE for slide and press;
    ///   · "voices", PLURAL — false then and false now, and nothing on the roadmap changes it.
    ///     `git grep -c ControllerEvent` over `PolySynthVoice.swift` and `SubBassVoice.swift`
    ///     is 0/0; `apply(controller:)` holds exactly one `playNote(` onto one `synth`
    ///     (claim 3). ONE monophonic voice consumes the bus. That is the same plural `CLAUDE.md` retracted about its own line
    ///     at #770 and `CLAIMS.md` at #774.
    /// **The durable claim was always the plural, not the dimension.** #939 had already split
    /// the pressure case out on exactly this reasoning; #942 finishes the split by making the
    /// plural law the ONE rule for every dimension, instead of a general ban plus a pressure
    /// exception that would need a slide exception next.
    ///
    /// ⚠️ THE NEEDLE STAYS TWO-PART, because MPE **out** legitimately sends all three
    /// dimensions and must stay sayable. A dimension word alone is fine ("Slide (CC 74) and
    /// Press" on the output path); a sounding verb alone is fine ("notes and pitch bend play
    /// the built-in performer voice"). Only a dimension word in a sentence that claims it
    /// plays or reaches a VOICE is asked the plural question — sending to an external rig does
    /// not involve one of our voices.
    func testTheSiteDoesNotPluraliseWhatADimensionReaches() throws {
        for (name, html) in try websitePages() {
            for sentence in sentences(in: html) where namesAPerNoteInputDimension(sentence) {
                guard claimsItPlaysAVoice(sentence) else { continue }
                let lower = sentence.lowercased()

                // 10a — the durable law. Three continuous dimensions reach the built-in voice
                // (bend, press #939, slide #942), but it is ONE monophonic voice, and press and
                // bend are CHANNEL-wide messages, never per-note.
                XCTAssertFalse(lower.contains("voices") || lower.contains("per-note"), """
                    `docs/\(name)` pluralises what a per-note expression dimension reaches, or \
                    calls a channel-wide message per-note: "\(sentence)"

                    Pitch bend, press (#939) and slide (#942) DO reach the built-in performer \
                    voice — singular. `apply(controller:)` calls `playNote(` exactly once, \
                    onto one `synth`; claim 3 pins that. Channel pressure and channel \
                    pitch bend are channel-wide by definition. Say "the built-in performer \
                    voice", and do not call a channel message per-note.

                    Zones (RPN 6,6) and member channels are still absent (claims 2 and 6), \
                    which is why this is still not MPE input — dimensions without zones is \
                    expressive MIDI.
                    """)

                // 10b — the ONE dimension that still reaches nothing. Not an MPE dimension
                // (CC 21–31), so this is not an MPE claim; it is simply false.
                XCTAssertFalse(namesAirCC(sentence), """
                    `docs/\(name)` says air-CC plays or reaches a voice: "\(sentence)"

                    IT DOES NOT. `BioReactiveSynthVoice.apply(controller:)` — the only \
                    `ControllerEvent` consumer in `Sources/` — runs `.airCC` into a bare \
                    `break`; claim 1 pins exactly that, so this claim does not restate the code \
                    premise (#416). Air-CC is parsed and carried on the bus; nothing sounds it.

                    If a voice now really consumes it, claim 1 \
                    (`testTheAirDimensionIsStillDiscarded`) is red too — read that failure \
                    first, then this sentence is correct again and this guard, `CLAIMS.md` \
                    §6b, `README.md` and `CLAUDE.md`'s MPE paragraph all move in the same \
                    commit (#456).
                    """)
            }
        }
    }

    // MARK: - claim 10c — and the site does not DENY a dimension that really sounds

    /// ⭐ #942, and it is the #775 lesson turned into a check instead of a habit. Every needle
    /// in this file until now looked for an OVER-claim; #775 found that `architecture.html`
    /// had done the opposite with MPE **out** and cost a rig owner the truth for two months.
    /// #942 found the same shape FIVE more times, all by hand, none by a guard. This claim
    /// covers THREE of the five, MEASURED by running the worktree's code against the parent's
    /// prose (43 checks, this one the single FAIL, naming all three):
    ///   · `faq.html` and `tools.html` — "CC 74 slide and air-CC are parsed and carried on the
    ///     control bus, but no voice consumes them yet";
    ///   · `architecture.html`'s Next row — "Slide and air-CC are parsed and carried on the
    ///     bus; nothing sounds them yet".
    /// All three were true when written and false the moment slide got `renderCutoffScale`.
    ///
    /// ⚠️ AND IT WOULD **NOT** HAVE CAUGHT THE OTHER TWO — said plainly rather than left for
    /// the next session to discover, because both had already survived a whole slice unnoticed
    /// (they are stale since **#939**, not #942). `README.md` listed "channel pressure" among
    /// what is *not* wired, and README is not in this claim's corpus — it reads `docs/*.html`.
    /// `architecture.html`'s stack row said "MPE zone/**pressure** handling ROADMAP", and
    /// "roadmap" is deliberately NOT a denial phrase here: it is the honest word for the zone
    /// half on the very same pages, so banning it beside a dimension name would forbid correct
    /// sentences. Widening either half is a later slice with its own measurement, not a
    /// one-line addition to the needle list.
    ///
    /// ⭐ THE SHAPE THAT MAKES IT #364-SAFE: the claim is CONDITIONAL ON THE CODE, not on a
    /// date. It reads `apply(controller:)` first; a page may only be forbidden from denying
    /// what the consumer is measured to do in the SAME run. Take slide's write back out and
    /// this claim stops applying by itself, so restoring the honest "no voice consumes it"
    /// sentence is never red — the failure mode that would have made a fixed-date version of
    /// this guard forbid correct work.
    ///
    /// ⚠️ AIR-CC IS DELIBERATELY OUT OF SCOPE and must stay sayable: nothing consumes it
    /// (claim 1), so "no voice consumes it" is the TRUE sentence about it. A sentence that
    /// names only air-CC is never asked.
    func testTheSiteDoesNotDenyADimensionThatSounds() throws {
        let consumer = try memberBody("private func apply(controller event: ControllerEvent)",
                                      in: Self.voice)
        // (label, the words a page uses for it, the property the consumer writes)
        var sounding: [(String, [String], String)] = []
        if consumer.contains("synth.renderCutoffScale =") {
            sounding.append(("CC 74 slide", ["slide", "cc 74", "cc74"], "renderCutoffScale"))
        }
        if consumer.contains("synth.expressionGain =") {
            sounding.append(("channel pressure", ["channel pressure"], "expressionGain"))
        }
        guard !sounding.isEmpty else {
            // Both dimensions were taken back out. Claim 1b/1c already say so loudly; this
            // claim simply has nothing to assert, and saying so beats a silent green.
            return
        }
        let denials = ["no voice consumes", "nothing sounds", "reaches no voice",
                       "not wired", "no voice reads", "consumed by no voice"]
        for (name, html) in try websitePages() {
            for sentence in sentences(in: html) {
                let lower = sentence.lowercased().replacingOccurrences(of: "\u{00A0}", with: " ")
                guard denials.contains(where: { lower.contains($0) }) else { continue }
                for (label, needles, property) in sounding
                where needles.contains(where: { lower.contains($0) }) {
                    XCTFail("""
                        `docs/\(name)` says \(label) does not reach a voice, and the consumer \
                        measured in this same run says it does: "\(sentence)"

                        `BioReactiveSynthVoice.apply(controller:)` writes `synth.\(property)` \
                        for it (claims 1b/1c pin the whole path through to the render block and \
                        both latches). An UNDER-claim costs differently from an over-claim but \
                        it does cost: this is the page a controller owner reads before deciding \
                        whether Echoel can use their keyboard, and it tells them no.

                        Air-CC is a different case and stays sayable — nothing consumes it. If \
                        you really removed the dimension's path, claim 1c is red too and this \
                        claim switches itself off; read that failure first.
                        """)
                }
            }
        }
    }

    // MARK: - claim 8 — the caption register does not promise voices, plural

    /// #774. `ContentPipeline/CLAIMS.md` is the list a short-form script must read before
    /// writing a caption; a wrong row there becomes a public promise. Its MIDI-INPUT row said
    /// the controller plays "die Stimmen".
    ///
    /// ⚠️ IT ANCHORS ON THE ROW, NOT ON THE FILE. The corrected row and the new §6b both QUOTE
    /// the struck wording — a file-wide ban would go red on the very commit that repairs it,
    /// the #491 shape this bundle has paid for. The row is found by its own label, which occurs
    /// once, and only that line is asked the question.
    func testTheClaimsRegisterDoesNotPromisePolyphonicMIDIInput() throws {
        let text = try rawFile(Self.claims)
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("**MIDI-Eingang**") }
        guard rows.count == 1, let row = rows.first else {
            throw MPEAnchorMissing(reason: """
                Expected exactly one row labelled `**MIDI-Eingang**` in \(Self.claims); found \
                \(rows.count). This scan found nothing rather than nothing wrong (#454) — if \
                the register was restructured, re-anchor it here in the same commit.
                """)
        }
        XCTAssertFalse(String(row).contains("die Stimmen"), """
            The caption register promises "die Stimmen" (plural) for MIDI input again: \
            "\(row.trimmingCharacters(in: .whitespaces))".

            Measured, and claim 3 above pins it: `BioReactiveSynthVoice` is the only consumer \
            of `controllerEvents`, and `apply(controller:)` calls `playNote(` exactly once, \
            onto one `synth`. If the performer path really became polyphonic, this whole \
            file goes red together and \(Self.prose)
            """)
    }

    // MARK: - claim 6 — PRESS is parsed ONCE, correctly, and nothing zone-shaped came with it

    /// ⭐ #770 WROTE THIS CLAIM AS AN ABSENCE AND #939 IS THE DAY IT PREDICTED. It used to
    /// assert that `MIDIInEvent` had no pressure case and that both protocol branches fell to
    /// `default: return nil`; its own failure message said "every claim in this file is due for
    /// review together" if that ever changed. It is therefore REWRITTEN, not deleted (#364) —
    /// a guard that reds on the correct tree gets removed, and the law goes with it.
    ///
    /// What is worth pinning is no longer the absence but the SHAPE of the parse:
    /// · the case EXISTS, so claim 1b's consumer has something to consume;
    /// · MIDI 1.0 reads **`data1`**, not `data2`. Channel Pressure is a TWO-byte message —
    ///   status plus ONE data byte — while every neighbouring case in that switch reads the
    ///   SECOND byte. Copying the neighbours' shape compiles, always reports 0, and is
    ///   indistinguishable from a player who is not pressing. Nothing else in this repo can
    ///   catch that: it is a silent-wrong-value bug, not a compile error;
    /// · nothing ZONE-shaped appeared alongside it. RPN 6,6 zone detection and
    ///   master-vs-member disambiguation are what would turn this into MPE INPUT, and their
    ///   absence is what keeps the corrected prose honest.
    ///
    /// ⚠️ It does NOT assert that pressure reaches audio — that is claim 1b, on the consumer.
    /// This one is the producer half, exactly as #770 scoped it.
    func testTheInputPathParsesPressureAndStillNoZones() throws {
        let event = try memberBody("public enum MIDIInEvent", in: Self.parse)
        XCTAssertTrue(event.contains("case channelPressure("), """
            `MIDIInEvent` no longer carries a pressure case. If the dimension was taken back out, claim 1 \
            must go back to naming three and the prose in `CLAUDE.md`, `MIDIInput.swift`, \
            `MIDIBusPublisher.swift` and `SignalRouter.swift` moves with it (#456). If it was renamed, \
            re-anchor here. Either way \(Self.prose)
            """)

        let decode = try memberBody("public static func event(word0: UInt32, word1: UInt32?)",
                                    in: Self.parse)
        XCTAssertTrue(decode.contains("Float(data1) / 127.0"), """
            The MIDI 1.0 Channel Pressure case no longer reads the FIRST data byte. Channel Pressure \
            carries status + ONE data byte, so a `data2` read returns whatever follows in the word — in \
            practice a constant 0, which looks exactly like a player who is not pressing. This assertion \
            exists because that bug is silent.
            """)
        XCTAssertTrue(decode.contains("case 0xD:"), """
            The MIDI 2.0 branch no longer decodes Channel Pressure (status nibble 0xD). A MIDI 2.0 \
            controller would then send Press that this receiver drops, while the MIDI 1.0 path still \
            delivers it — one dimension that works on half the protocols.
            """)

        // COUNTERWEIGHT (#343): parsing one dimension is not MPE. The moment zones appear,
        // every "no MPE input" sentence this file protects has to be re-read.
        let parseCode = try source(Self.parse).lowercased()
        XCTAssertFalse(parseCode.contains("rpn") || parseCode.contains("zone"), """
            `MIDIEventParse` now mentions RPN or zones in CODE. Zone detection (RPN 6,6) and \
            master-vs-member channel disambiguation are what make an input path MPE, so if they landed, \
            this whole file is due for review together and \(Self.prose)
            """)
    }

    /// The `os_log` line the seventh surface was found in. Anchored on the message prefix rather
    /// than on the whole literal, because the surrounding text is exactly what a future cycle may
    /// legitimately reword (#655: a guard pinned to a full literal went red for five commits when
    /// a helper took ownership of the prefix).
    func testTheInputLogLineDoesNotAnnounceMPE() throws {
        let code = try source(Self.input)
        guard let line = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("\"MIDI: Input ready") })
        else {
            throw MPEAnchorMissing(reason: """
                No "MIDI: Input ready" log line in \(Self.input) — this scan found nothing \
                rather than nothing wrong (#454). If the line moved or was renamed, re-anchor \
                it here in the same commit.
                """)
        }
        XCTAssertFalse(String(line).contains("MPE"), """
            The MIDI input readiness log announces MPE again: \
            "\(line.trimmingCharacters(in: .whitespaces))".

            A developer reading Console during device triage is a surface like any other, and \
            this was the seventh one for this single claim. If a real MPE receiver was built, \
            the line is finally true — and then \(Self.prose)
            """)
    }

    // MARK: - source access

    private struct MPEAnchorMissing: Error { let reason: String }

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

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454: a skip passes CI).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw MPEAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// 12 — REGRESSION. `docs/dev/*.md` claimed MPE **input** in five files, and NOTHING here
    /// swept them (#787). Claim 10 reads `docs/*.html`; claims 1–9 and 11 name individual files.
    /// Markdown one directory down fell in the gap between the two, which is why a plain
    /// "MIDI 2.0/MPE in" survived in `FEATURE_MATRIX.md` and a ✅ next to "MIDI/MPE **IN**"
    /// survived in `VISION_REALITY_2026-07.md` — the two files a session reads to learn what
    /// ships.
    ///
    /// ⭐ THE LESSON IS #766's, WITH A NEW MECHANISM, and it is why this claim is
    /// DIRECTORY-DRIVEN rather than a list. #766 said a capability claim has as many SURFACES as
    /// somebody enumerated; #778 said as many WORDINGS. This one had neither problem — it had an
    /// unenumerated FILE TYPE. The sweep covered `.html` under `docs/` and named `.md` files one
    /// by one, so `docs/dev/*.md` was invisible to both halves. A guard that names its inputs
    /// can only ever be as complete as the last person's memory.
    ///
    /// THE RULE, and it is deliberately weaker than "never write MPE": **a line that claims MPE
    /// INPUT must cite its own retraction (#548 or #770) on the same line.** That keeps every
    /// honest mention legal — including the ⛔ blocks this repo writes on purpose, which quote
    /// the retracted claim verbatim and would trip any naive negative scan (#491) — while a
    /// fresh, uncited "MPE in" is red.
    ///
    /// ⚠️ OUT OF SCOPE ON PURPOSE: a DIRECTIONLESS "MPE" (e.g. "CoreMIDI (MIDI 2.0/MPE)"). Three
    /// such lines were corrected by hand in #787, but forbidding the bare word here would
    /// duplicate `ContentPipeline/CLAIMS.md` §6, which already owns that rule (#416). This claim
    /// owns exactly one thing: the INPUT direction being asserted without its retraction.
    ///
    /// ⚠️ #364: building real MPE input is legitimate and turns this red. That red is the
    /// signal, not the verdict — the message names what must move with it.
    func testTheDevDocsDoNotClaimMPEInput() throws {
        let dir = try repoRoot().appendingPathComponent("docs/dev")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".md") }.sorted()
        guard !names.isEmpty else {
            throw MPEAnchorMissing(reason: """
                No `.md` under `docs/dev`. Found nothing rather than nothing wrong (#454) — \
                if those docs moved, re-anchor this claim in the same commit.
                """)
        }
        var offenders: [String] = []
        var sawAnyMention = false
        for name in names {
            let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let raw = text.components(separatedBy: .newlines)
            let flat = raw.map {
                $0.replacingOccurrences(of: "*", with: "")
                    .replacingOccurrences(of: "_", with: " ").lowercased()
            }
            for (n, line) in flat.enumerated() {
                guard line.contains("mpe") else { continue }
                sawAnyMention = true
                let claimsInput = line.contains("mpe in") || line.contains("mpe input")
                    || line.contains("mpe-in") || line.contains("mpe eingang")
                guard claimsInput else { continue }
                // ⛔ #939 — THE CITATION WINDOW IS ±1 LINE, AND IT USED TO BE THE LINE ITSELF.
                // Driven over the whole corpus, the old form was RED on a correct tree:
                // `APP_STORE_LISTING_v1.md` wraps its blockquote as "MPE **in** stays" /
                // "unclaimable (#548/#770)." — one honest sentence, split by the wrap, and the
                // guard read only the first half. Markdown reflows; a rule that a prose file
                // must not wrap between a claim and its citation is unenforceable and would
                // have been re-broken by the next editor. One line either side is still tight
                // (it cannot reach a neighbouring paragraph's citation without an intervening
                // MPE-input claim of its own) and it survives a rewrap. Same discovery route as
                // the two other live reds this slice found here: transcribe the WHOLE file.
                let window = flat[max(0, n - 1)...min(flat.count - 1, n + 1)]
                let cited = window.contains { $0.contains("#548") || $0.contains("#770") }
                if !cited {
                    offenders.append("docs/dev/\(name):\(n + 1) — "
                        + raw[n].trimmingCharacters(in: .whitespaces))
                }
            }
        }
        XCTAssertTrue(sawAnyMention, """
            No line under docs/dev mentions MPE at all. That is not a pass — the needle can no \
            longer match the corpus it points at (#454/#779). Re-anchor before trusting a green.
            """)
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) line(s) under docs/dev claim MPE INPUT without citing the \
            retraction that governs it:
            \(offenders.joined(separator: "\n"))
            Measured: `MIDIBusPublisher` tells no MPE zones apart and no member channel is \
            distinguished. All three continuous dimensions now sound — pitch bend, press \
            (#939) and slide (#942) — and that is still not MPE INPUT: a zone is what MPE \
            adds, and RPN 6,6 has no producer here. MPE **out** is real \
            and switchable (#713); the direction word is the whole claim. If real MPE input was \
            just built, this red is correct and the prose in CLAUDE.md, README.md and \
            ContentPipeline/CLAIMS.md §6 moves in the SAME commit (#456).
            """)
    }

    /// Every shipped page under `docs/`, read from the directory (#769: a hand-typed page list
    /// is the trap this repo has closed twice). Non-recursive on purpose — the six files one
    /// level down are three redirect stubs and three screenshot mockups, measured in #772 to
    /// carry no capability claim.
    private func websitePages() throws -> [(String, String)] {
        let docs = try repoRoot().appendingPathComponent("docs")
        let names = try FileManager.default.contentsOfDirectory(atPath: docs.path)
            .filter { $0.hasSuffix(".html") }.sorted()
        guard !names.isEmpty else {
            throw MPEAnchorMissing(reason: """
                No `.html` under `docs/`. This scan found nothing rather than nothing wrong \
                (#454) — if the site moved, re-anchor it here in the same commit.
                """)
        }
        return try names.map {
            ($0, try String(contentsOf: docs.appendingPathComponent($0), encoding: .utf8))
        }
    }

    /// Tag-stripped sentences. ⛔ THE FIRST VERSION OF #775 SCANNED LINES AND FOUND NINE OF THE
    /// TEN OCCURRENCES — `docs/press.html` split its claim across a line the needle could not
    /// see, and only a sentence-level pass found it. A claim does not respect line boundaries.
    private func sentences(in html: String) -> [String] {
        var text = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; text.append(" "); continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { text.append(ch) }
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "—")
        // ⛔ AND `components(separatedBy: ". ")` WAS NOT ENOUGH, caught by the driver on a
        // CORRECT tree before this shipped: `faq.html` ends a sentence with ".)" and the next
        // one is "VST3 and CLAP are not planned." — glued together, the honest MPE sentence
        // inherited the word "planned" and the guard cried wolf. A checker with false alarms is
        // a checker nobody reads (#665), so the boundary skips a run of closing marks after the
        // period rather than demanding the period sit directly against a space.
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            i += 1
            guard ch == "." || ch == "!" || ch == "?" else { continue }
            var j = i
            while j < chars.count, ")\"']»".contains(chars[j]) { j += 1 }
            guard j < chars.count, chars[j].isWhitespace else { continue }
            out.append(current)
            current = ""
            i = j
        }
        out.append(current)
        return out
            .map { $0.split(separator: " ").joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// #778. The per-note expression dimensions a page can name. It is HALF a needle: the
    /// sentence is only asked the plural question once `claimsItPlaysAVoice` also holds.
    ///
    /// ⛔ #939 REMOVED `"channel pressure"` FROM THIS LIST AND #942 PUT IT BACK — read the two
    /// together, because the second move is not a reversal of the first. #939 removed it
    /// because the list was then a BAN LIST ("this dimension may not be said to play a voice"),
    /// and press had just started doing exactly that, so keeping it would have reddened the
    /// guard on the truthful sentence (#364). #942 rebuilt the claim around the PLURAL instead
    /// — the half that is false for every dimension, now and after zones ship — so the list is
    /// no longer a ban list but a SELECTOR, and pressure belongs in a selector.
    ///
    /// ⛔ AND `"timbre"` CAME OUT IN THE #939 SWEEP, BECAUSE IT WAS RED ON A CORRECT TREE —
    /// the needle-collision law, and the second live instance found by driving the guard
    /// rather than reading it. `docs/architecture.html`'s **Voice timbre** row (the
    /// vocal-analysis feature, nothing to do with MIDI) reads "A player holds a tone … Voice
    /// timbre row": `claimsItPlaysAVoice` finds "play" inside "**play**er" and then "voice"
    /// after it, so the pair matched a sentence about a completely different subsystem. The
    /// word also appears in "timbre transfer", "DDSP timbre presets" and "HRV opens or closes
    /// the timbre". It never bought anything either: every genuine MPE use on the site is
    /// "Slide / timbre (CC 74)" or "slide/timbre CC74", which `"slide"` and `"cc 74"` already
    /// catch. An over-broad needle that catches nothing new and cries wolf four ways is the
    /// #665 shape — a checker with false alarms is a checker nobody reads. It stays out.
    ///
    /// ⚠️ `"press"` IS DELIBERATELY NOT A NEEDLE, only `"channel pressure"`. It is a substring
    /// of "expression", "impression" and "pressure" itself — the same collision class as
    /// "timbre" above, and the site says "Press (channel pressure)" everywhere it means the
    /// dimension, so the longer form loses nothing.
    ///
    /// ⚠️ HOW LONG THE `"timbre"` NEEDLE WAS RED IS NOT MEASURED, and #396 is why nobody saw
    /// it: the pipeline reports `failure` on every push, so a genuinely red guard looks exactly
    /// like the host dying. Same discovery route as #937 — transcribe the WHOLE file, not the
    /// diff.
    private func namesAPerNoteInputDimension(_ sentence: String) -> Bool {
        let lower = sentence.lowercased().replacingOccurrences(of: "\u{00A0}", with: " ")
        return lower.contains("slide")
            || lower.contains("cc 74") || lower.contains("cc74")
            || lower.contains("channel pressure")
            || namesAirCC(sentence)
    }

    /// CC 21–31. NOT an MPE dimension — `EngineBus` calls them "air dimensions" and no MPE
    /// document defines them — and the only one of the four that still reaches no voice.
    private func namesAirCC(_ sentence: String) -> Bool {
        let lower = sentence.lowercased().replacingOccurrences(of: "\u{00A0}", with: " ")
        return lower.contains("air-cc") || lower.contains("air cc")
    }

    /// The second half of the two-part needle: does the sentence claim it PLAYS or REACHES one
    /// of our voices? "consumes"/"carried"/"parsed" are deliberately NOT verbs here — the
    /// repaired pages use them to say the opposite, and a guard that reddens on its own repair
    /// is the #491 shape this bundle has already paid for.
    private func claimsItPlaysAVoice(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        for verb in ["play", "plays", "played", "reach", "reaches"] {
            guard let r = lower.range(of: verb) else { continue }
            if String(lower[r.upperBound...]).contains("voice") { return true }
        }
        return false
    }

    private func mentionsMPEOutput(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        return lower.contains("mpe out") || lower.contains("mpe output")
    }

    /// A file read WITHOUT the Swift comment stripper. `CLAIMS.md` is Markdown: `codeOnly`
    /// would treat a `//` inside a URL as a line comment and a `/*` in prose as a block, which
    /// is the shape `SourceText`'s own header warns about. A SKIP without a checkout, a FAILURE
    /// when a named file moved (#454).
    private func rawFile(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw MPEAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// The brace-matched body of `signature`. Brace-matched rather than a line window because
    /// this repo writes 30-line comment blocks between statements and `codeOnly` preserves line
    /// count, so any fixed window is unsound by construction (#408/#489). The signature is
    /// asserted UNIQUE first: an anchor that occurs twice can silently read the wrong member.
    private func memberBody(_ signature: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        let hits = text.components(separatedBy: signature).count - 1
        guard hits == 1 else {
            throw MPEAnchorMissing(reason: """
                `\(signature)` occurs \(hits)× in \(relativePath); this scan needs exactly one \
                so it cannot read a different member. Re-anchor it.
                """)
        }
        guard let start = text.range(of: signature),
              let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw MPEAnchorMissing(reason: "no body after `\(signature)` in \(relativePath)")
        }
        var depth = 0
        var out = ""
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw MPEAnchorMissing(reason: "unbalanced braces after `\(signature)`")
    }
}
