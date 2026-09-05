// BodyTempoField.swift
// Echoel — THE tempo control (founder 2026-07-04: "Das mit den zwei Anzeigen irritiert
// immernoch … Beim BPM-Lock, wo auch der Kammerton eingestellt werden kann, geht einfach
// eine Anzeige mit, die gesynct ist mit der Biofeedback-BPM-Rate. Vier Stellen nach dem
// Komma und lockbar.")
//
// PRECISION FOLLOWS MEANING (#368, founder 2026-08-01 — he circled `71,0000` in three
// separate device screenshots): the LOCKED field keeps the four decimals he asked for above,
// because there the number is a value he sets and edits. UNLOCKED it shows ONE, because
// there it is a camera measurement and the other three digits were never information. The
// full reasoning, including why this is not the format-divergence the ⛔ below forbids, sits
// on `followingText`.
//
//   • UNLOCKED — the number is THE CLOCK (`transport.tempo`), which the body drives
//     through the generative mapping. It tints accent while a live pulse is driving it.
//   • Tap the lock — the number FREEZES where the clock already is, and is then editable
//     to 0.0001 BPM via the Echoel number pad. Unlock → the body drives it again.
//
// ⛔ UNLOCKED USED TO SHOW `cameraRPPG.displayBPM` — THE RAW PULSE — IN A BOX LABELLED
// "Tempo", and #491 (founder 2026-08-07, screenshot of v10.79.374 (2491): *"Transport,
// bpm, Schloss und Biofeedback bar zu einer schöneren Ebene ohne doppelt bpm zusammen
// fassen"*) is what finally made that visible. Two things were wrong with it, and the
// founder saw the SECOND one:
//   1. IT WAS NOT THE TEMPO. `EchoelStudioView`'s unlocked branch resolves the take's
//      tempo as `StudioCalculator.tilted(genreTempo(suggestedTempo, into: style.tempoRange),
//      …).rounded()` — octave-folded into the genre's window, tilted by the performer
//      signature, then converged in capped steps. On a genre whose window does not contain
//      the pulse that is a DIFFERENT NUMBER, and the field claimed it was the tempo.
//   2. IT WAS THE PULSE MONITOR'S NUMBER. `PulseMonitorMiniLive` sits in the same row
//      since #289 and shows `cameraRPPG.displayBPM` too — and `displayBPM` and `isLocked`
//      are byte-wise the same fact (both are `pulseTrustworthy`, #484), so whenever the
//      pill showed a number this box showed the SAME one, one decimal apart. That is the
//      "doppelt bpm".
// The founder's own 2026-07-04 line quoted at the top says *"beide behalten"* — keep BOTH
// controls. So the fix is not to delete one of them: it is to make them show the two
// DIFFERENT facts they are named for. The pill is the heart rate. This is the clock.
//
// ⛔ AND LOCKING JUMPED THE CLOCK. `toggleLock` adopted the SHOWN value, i.e. the pulse —
// so locking at a moment when the genre had folded 72 bpm up to 144 pulled the beat down
// to 72 in one gesture. It now freezes the clock WHERE IT IS, which is what a lock means
// and is continuous by construction. The "lock captures the number you see" invariant is
// unchanged — it got STRONGER, because the number you see is now the one the clock runs at.
// HOME (founder 2026-07-15 "Das soll da oben hin"): the `compact` variant lives in the
// instrument's transport row next to Play (word labels dropped to fit). This is THE one
// musical-tempo control — the pulse monitor (live rate) stays separately in the brand
// header ("beide behalten").
//
// ⛔ THIS SENTENCE ENDED "the full variant is available for panels", and no panel has ever
// built one: the repo has exactly ONE construction site and it passes `compact: true`.
// "Available" was true of the TYPE and false of the APP, which is the reading that matters
// to a session deciding whether the wide arm is load-bearing. Since #504 neither parameter
// carries a default, so the next call site has to say which variant it wants out loud.
//
// RENDER SAFETY (freeze rule): this view observes THREE sources, not one. (⛔ "TWO" stood
// here until #647 added `bus.usableBio()` for the spoken label; a count in this paragraph is
// the number a session checks before folding the row somewhere, so it moves with the code.)
// `cameraRPPG.displayBPM` updates ~10 Hz (the accent-tint flag), and since #491
// `transport.tempo` is read UNCONDITIONALLY — 8 Hz at 120 BPM, up to ~20 Hz during a
// glide. The third, added by #647, is the SLOWEST: `latestBio` is REASSIGNED at ~1 Hz. (That
// is the PUBLISH rate, not the consumers' dedup rate — #459: a rate belongs to exactly one
// operation, and quoting a neighbour's number takes its OPERATION with it.)
// ⛔ This paragraph named only the camera until #491, and it was written when the
// tempo read sat behind a `?:` that a live pulse short-circuited away; the second source
// is not new here, it just became unavoidable. This is a LEAF `View` struct — ALL THREE
// reads live HERE, so only this row rebuilds and the Picker-hosting Composition panel / root
// body never subscribe. Folding this row inline into `startControlRow` would be the
// 10.76.41/50 freeze, and it would now be THREE churn sources instead of one.
// ⛔ THOSE TWO WORDS SAID "both" AND "TWO" FOR ONE REVIEW PASS — in the same paragraph whose
// #647 edit had just declared "a count in this paragraph is the number a session checks before
// folding the row somewhere, so it moves with the code". Updating the headline number and
// leaving the two restatements below it is #425 in miniature: a claim and its own refutation,
// 10 lines apart, with the WRONG one in the sentence a session reads last before deciding.

// ⚠️ `import Foundation` is conventional here, NOT load-bearing: `TempoFollowLabel` uses only
// `String` and same-module `Core/` types. What lets it sit above the guard is that
// `BioSampleFrame`/`BioSource` are declared outside `Core/EngineBus.swift`'s
// `#if canImport(Observation)` block — do not infer that removing the import would break it, or
// that adding one elsewhere is what makes a type platform-free.
import Foundation

/// What VoiceOver is told is driving the UNLOCKED tempo readout (#647).
///
/// ⛔ THE SPOKEN LABEL WAS AN UNCONDITIONAL CAUSAL CLAIM. `"Tempo, driven by your body"` was
/// read out whenever the field was unlocked, and the clock it describes is driven through
/// `BioComposer.tempo(for:)` from the composer input — i.e. from `bus.usableBio()`, which under
/// the Simulation source is the demo generator's fabricated frame and with no usable frame at
/// all is whatever the clock was last set to. A sighted player already gets a discriminator
/// (the readout tints accent while a pulse is driving it); a VoiceOver player got the same
/// sentence in every state. That is the #632/#627b pattern exactly — the visible half marked,
/// the spoken half not — and it is the last registered entry of that pattern in this family.
///
/// ⭐ `.body` KEEPS ITS WORDS. The claim is TRUE when a real body is driving the clock, and the
/// phrase is the founder's. Only the other two states get their own sentence.
///
/// ⚠️ KEYED ON THE FRAME SOURCE, NOT ON THE FIELD'S OWN `liveBodyBPM`, and that choice is the
/// whole slice. `liveBodyBPM` is camera-only (`cameraRPPG.isRunning && displayBPM > 0`), so
/// keying the sentence on it would announce "not your body" while a BLE strap or Apple Watch
/// drives the clock — an over-correction, which is this family's remaining risk and what it has
/// already had to retract twice. `usableBio()` is the same gate the composer itself asks.
///
/// ⛔ THE VERB WAS "driven by" FOR ONE COMMIT AND THAT WAS AN OVER-CLAIM (#647 review). This
/// function knows ONE thing: whether a usable reading is arriving and whose it is. It does NOT
/// know whether the clock is following that reading, and there are FOUR other writers plus three
/// gates between the two:
///   · `bodyTempoTrustworthy(frame)` — for the camera this is `isSettled`, so through the ~13 s
///     warm-up (and every re-lock) `usableBio()` returns a real frame while the composer
///     DELIBERATELY holds the previous tempo. "driven by your body" was flatly false there.
///   · `generate()` is the only `.flowServo` writer. Open the app, start the pulse, never press
///     Start: the clock sits at the transport default and nothing has read a body at all. That
///     is the ORDINARY first-run state, not an edge case.
///   · opening a project restores a tempo from a file with the lock off.
///   · `.automation` and `.modulationRoute` both write the clock; dormant today (#541/#473), but
///     a persisted document reaches them.
/// "following" is this file's OWN name for the unlocked state (`followingValue`, `followingText`,
/// `followingSpoken`, "the FOLLOWING readout"), and it describes what is measured — a reading is
/// arriving and this is whose it is — instead of asserting a causal chain this type cannot see.
///
/// ⭐ THE EXACT ROUTE EXISTS AND IS DELIBERATELY NOT TAKEN YET. `PatternEngine.lastTempoSource`
/// already carries `user · flowServo · automation · modulationRoute · unspecified`, and this view
/// already holds `@Environment(BeatPlayer.self)`. Two things make it its own slice rather than a
/// one-line swap: it is documented "diagnostic only — nothing branches on it", so branching
/// changes its contract; and the compose path stamps `.flowServo` even on the HOLD branch, so it
/// still needs the trustworthy gate to exclude the warm-up. Registered, not guessed at.
///
/// ⚠️ AND ONE STALENESS THIS CANNOT SEE. `usableBio()` reads the observable `latestBio` AND the
/// wall clock; observation registers on `latestBio` only. Unlocked, camera off (strap or Watch),
/// transport stopped, nothing else in this body churns — so when the strap drops, `latestBio`
/// stops changing, this view stops re-rendering, and the label keeps naming a body indefinitely.
/// ⛔ The first version of this block called that "the same handling as `AlwaysOnBioRow`'s
/// bounded lag" and that was FALSE IN THE LOAD-BEARING HALF: that row wraps its content in
/// `TimelineView(.periodic(from: .now, by: 1))` precisely BECAUSE the wall-clock half needs its
/// own tick, and its header calls that "load-bearing, not decoration". There is no such tick
/// here, so the lag is UNBOUNDED, not bounded. The mechanism is named so the fix is a lookup and
/// not a rediscovery; it is not taken in this pass because adding a 1 Hz tick to the transport
/// row is a render-structure change with no local compiler and no device to check it against.
public enum TempoFollowLabel {

    /// The VoiceOver label for the unlocked readout, given the frame currently driving the clock.
    public static func spoken(for frame: BioSampleFrame?) -> String {
        guard let frame else { return "Tempo, following — no reading is arriving" }
        // The second of exactly TWO sites whose real-body branch is the bare subject, so the
        // shared half is written once (the other is `breathVoiceHint`). Of the ten sites, one
        // IS the definition and seven cannot do this — their body branch says "your pulse",
        // "four body channels", "your measured body state"; see `BioProvenanceCopy`.
        // ⛔ This read "Nine of the eleven other sites", which implies thirteen. The census is
        // ten: 2 substitutable + 1 definition + 7 not. Written from the feel of the list.
        return "Tempo, following " + BioPanelRowCopy.subject(synthetic: frame.source.isSynthetic)
    }

    /// What tapping the lock OPEN hands the clock back to (#647 review).
    ///
    /// ⚠️ A SEPARATE SENTENCE, NOT A REUSE OF `spoken(for:)`. This one is about what a TAP will
    /// do, so it is future-tense and names an actor; that one is about what is arriving now. One
    /// string for both would read wrong in one of the two places, which is the collapse #634b
    /// had to retract. Same three states, same source of truth.
    public static func unlockHint(for frame: BioSampleFrame?) -> String {
        guard let frame else { return "Tempo locked — tap to let it follow again" }
        return frame.source.isSynthetic
            ? "Tempo locked — tap to let the simulated demo source drive it again"
            : "Tempo locked — tap to let your body drive it again"
    }
}

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BodyTempoField: View {

    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @Environment(Transport.self) private var transport
    /// The frame currently driving the clock — the SAME gate `BioComposer` asks (#647).
    ///
    /// ⚠️ A THIRD OBSERVED SOURCE IN THIS LEAF, and the render-safety paragraph at the top of
    /// the file is the reason that is legal rather than an oversight: this is a leaf `View`
    /// struct, so the read lives HERE and no Picker-hosting ancestor subscribes. It is also the
    /// SLOWEST of the three — `latestBio` is REASSIGNED at ~1 Hz (the PUBLISH rate; #459 — a
    /// rate belongs to exactly one operation, not the consumers' dedup rate), against
    /// `transport.tempo` at up to ~20 Hz
    /// during a glide. Folding this row inline would still be the 10.76.41/50 freeze, now with
    /// three churn sources instead of two.
    @Environment(EngineBus.self) private var bus
    @Environment(BeatPlayer.self) private var player

    // Shared with the transport-bar lock button + tap tempo (same keys + defaults).
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    /// Parent hook (recompose after a lock change) — called on lock/unlock/edit.
    ///
    /// ⛔ NO DEFAULT, DELIBERATELY (#440/#443). This read `= {}`, and
    /// `TempoLockAlwaysAsksForARecomposeTests` already wrote the hole down as one a text scan
    /// cannot close: "a second `BodyTempoField(compact:)` built without the argument would
    /// pass this guard and post nothing — the same defect, one level of indirection out."
    /// A no-op default cannot be caught by a scan because it appears in no diff; a REQUIRED
    /// argument is caught by the compiler at the call site that forgets it. The one call site
    /// already passes it, so removing the default changes nothing that ships.
    var onLockChanged: () -> Void

    /// COMPACT mode for the top chrome (founder 2026-07-15 "Das soll da oben hin",
    /// beide behalten): drops the "Tempo"/"BPM" word labels so the field fits the
    /// transport bar next to Play. Same 4-decimal value + lock, just narrower —
    /// still the one musical-tempo control (no second widget).
    ///
    /// ⛔ NO DEFAULT EITHER, AND HERE IT HID SOMETHING BIGGER. This read `var compact: Bool =
    /// false`, and the ONE construction site in the whole repo passes `compact: true`
    /// (`EchoelStudioView.startControlRow`, since #411). So `false` had no writer — and every
    /// non-compact arm of the three ternaries below (`spacing: compact ? 6 : 10`, the "Tempo"
    /// word label, `width: compact ? 30 : 34`) is unreachable while looking alive. Measured,
    /// not assumed: `git grep -n "BodyTempoField(" -- .` finds exactly one construction, no
    /// preview, no test constructs it.
    ///
    /// ⚠️ THE WIDE ARM IS NOT DELETED, AND THAT IS A DECISION. Three guards in the blocking
    /// bundle needle those ternaries verbatim (`OneChromeControlHeightTests`,
    /// `TapTargetFloorTests`, `TheTempoBoxShowsTheClockTests` — the last expects TWO
    /// accent-tint reads, one per arm). Removing the arm is a multi-file change to a control
    /// the founder marked twice in one week (#455, #491), not a cleanup. What this line does
    /// is smaller and sound: it stops the dead arm from being reachable-looking BY DEFAULT.
    /// The header prose above once said the full variant "is available for panels" — no panel
    /// uses it, and that sentence is corrected there.
    var compact: Bool

    /// Is a trustworthy pulse currently driving the clock?
    ///
    /// ⚠️ SINCE #491 THIS IS NOT A VALUE, IT IS A FLAG — it has exactly ONE consumer, the
    /// accent tint on the unlocked readout ("the body is driving this number"). It must not
    /// become a displayed number again: that is what made this box duplicate the pulse pill
    /// beside it (see the ⛔ block at the top of the file). Kept as a `Double` rather than a
    /// `Bool` only because the `> 0` test is the same trust gate `PulseMonitorMiniLive` uses,
    /// and reading it the same way is what keeps the two in step.
    ///
    /// ⚠️ REGISTERED, NOT FIXED (#647): the sentence above — "a trustworthy pulse is driving the
    /// clock" — is CAMERA-ONLY, so the accent tint stays plain while a BLE strap or Apple Watch
    /// drives the clock just as truly. That is an UNDER-marking, and it is why #647 keyed the
    /// spoken label on `bus.usableBio()` instead of on this flag: keying speech on a camera test
    /// would have announced "not your body" to a strap user. The two halves therefore answer
    /// slightly different questions on purpose — the tint means "the camera is locked on", the
    /// label means "whose reading drives the clock". Making the tint ask the wider question is a
    /// separate, visual slice; it must NOT be done by pointing this flag at a different
    /// predicate, because its whole reason for existing is to stay byte-wise in step with
    /// `PulseMonitorMiniLive` (#484).
    private var liveBodyBPM: Double {
        #if canImport(AVFoundation)
        if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 { return cameraRPPG.displayBPM }
        #endif
        return 0
    }

    /// What the unlocked display shows: THE CLOCK.
    ///
    /// ⚠️ This read is unconditional since #491 (it used to sit behind a `?:` that
    /// short-circuited it away whenever a pulse was live), so this view now observes
    /// `transport.tempo` on every take. `Transport.setTempo` assigns unconditionally and
    /// `PatternEngine.advance()` relays it once per tick — 8 Hz at 120 BPM, up to ~20 Hz
    /// during a glide. That is legal ONLY because this is a leaf `View` struct: the read
    /// lives here, so the Picker-hosting bodies above never subscribe (10.76.41/50). Folding
    /// this row inline into `startControlRow` would be the freeze.
    private var followingValue: Double { transport.tempo }

    /// The FOLLOWING readout, formatted exactly the way the LOCKED one is.
    ///
    /// ⛔ These two states diverged for one commit and it was the worst artefact #232 G
    /// produced. The locked state is an `EchoelValueField`, which #232 G localized; the
    /// following state is a plain `Text(String(format: "%.4f"))`, which it did not. So a
    /// German player tapping the lock watched the SAME number in the SAME 76 pt box change
    /// its decimal separator — strictly worse than before the slice, where both read
    /// "70.0000". The release note called the residual risk "a value field next to a
    /// monitor"; this was not a neighbour, it was one tap apart inside one control.
    ///
    /// ⭐ ONE DECIMAL, NOT FOUR (#368) — and the divergence from the LOCKED state that this
    /// creates is deliberate, so read the paragraph above before "fixing" it back.
    ///
    /// The founder circled `71,0000` in the transport bar three times across three device
    /// screenshots. The four decimals here were his own 2026-07-04 ask, quoted at the top of
    /// this file — but they were asked for the LOCKABLE field, and this state is not that.
    /// Unlocked, the number is a READING and not a setting. Nothing that produces it resolves
    /// to 0.0001 BPM: the take's tempo is `…genreTempo(…).rounded()`, i.e. a whole BPM, and
    /// `glideTempo` eases between two whole BPMs. Three of the four decimals were never
    /// information, and in the shipped build they read `,0000` because the value arrives
    /// already rounded — a precision claim the number cannot fill, in the narrowest row the
    /// app has.
    ///
    /// ⛔ THE PARAGRAPH ABOVE USED TO SAY "the number is a MEASUREMENT: `cameraRPPG.displayBPM`,
    /// derived from an autocorrelation over a ~10 s window of camera frames". #491 made that
    /// premise false — this state shows the clock now, not the pulse. The CONCLUSION (one
    /// decimal) survives untouched and is if anything better founded: the old premise had a
    /// 10 s autocorrelation behind it, the new one has an integer. Corrected rather than
    /// deleted, because a stale premise under a live conclusion is exactly what invites the
    /// next session to "restore" four decimals here.
    ///
    /// ⛔ THE APP ALREADY CONTRADICTED ITSELF ABOUT THIS NUMBER, which is what settles it:
    /// `followingSpoken` right below has ALWAYS used one decimal. So a sighted user read
    /// "71,0000" while VoiceOver said "71,0 beats per minute" — the same value, the same
    /// instant, two precisions. The ⛔ above forbids the locked/following pair diverging in
    /// FORMAT for no reason; it cannot also require the seen and spoken forms to diverge.
    /// One decimal is the reading both now share.
    ///
    /// WHY THE LOCKED STATE KEEPS FOUR. Locking is the moment the number stops being a
    /// reading and becomes a SETTING — `toggleLock` rounds to 1e-4 and persists it, and the
    /// number pad edits it to that resolution. A format change there marks a change of
    /// meaning, which is the opposite of the separator defect the ⛔ describes: that one
    /// changed appearance while the meaning stayed identical.
    private var followingText: String {
        EchoelDecimalText.string(followingValue, decimals: 1)
    }

    /// The spoken form of the same number. Kept beside `followingText` so the two cannot
    /// drift: `EchoelValueField.accessibleValue` already speaks the seen string, and the
    /// following state has to match that or VoiceOver flips format on the same lock tap.
    private var followingSpoken: String {
        "\(EchoelDecimalText.string(followingValue, decimals: 1)) beats per minute"
    }

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            if lockBPM {
                // Locked: exact, editable to 0.0001 BPM (Echoel number pad).
                //
                // ⛔ THIS LINE SAID "like Kammerton" UNTIL #440, and that comparison is now
                // false: the concert-pitch row runs on `decimals: 2`. It was never a good
                // anchor either — A4's own comment always promised "exact to 0.01 Hz", so the
                // two rows agreed only by accident, because BOTH were silently inheriting
                // `EchoelValueField`'s default of 4. Once one of them was made to match its
                // own promise, the comparison broke. Anchor an intent to its OWN reason, not
                // to a neighbour that might be wrong for a different one.
                //
                // WHY FOUR SURVIVES HERE, stated so a "consistency" sweep has to argue with
                // it: locking is the moment this number stops being a reading and becomes a
                // SETTING (`toggleLock` rounds to 1e-4 and persists it), and a performer
                // matching an external clock needs that resolution. This is now the ONLY
                // reachable row in the app on the default grid, and
                // `Tests/CISmoke/EveryReachableRowStatesItsGridTests.swift` pins the sentence
                // above so the intent cannot be lost first and swept away second.
                //
                // Compact chrome: empty label (box-only) so it fits next to Play.
                EchoelValueField(label: compact ? "" : "Tempo", value: lockedBinding,
                                 range: Transport.minTempo...Transport.maxTempo, unit: "BPM",
                                 onCommit: onLockChanged,
                                 boxWidth: compact ? 76 : nil)
                    .accessibilityLabel("Tempo, locked")
            } else if compact {
                // Following, compact: just the running number (no word labels) — a tap
                // opens nothing (it follows the body); the lock beside it freezes it.
                Text(followingText)
                    .font(EchoelTheme.font(14, .semibold).monospacedDigit())
                    .foregroundStyle(liveBodyBPM > 0 ? EchoelTheme.accent : EchoelTheme.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minWidth: 76, height: EchoelTheme.controlHeight)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(TempoFollowLabel.spoken(for: bus.usableBio()))
                    .accessibilityValue(followingSpoken)
            } else {
                // Following: the number runs along with the live biofeedback rate.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Tempo")
                        .font(EchoelTheme.font(13))
                        .foregroundStyle(EchoelTheme.text)
                    Spacer(minLength: 8)
                    Text(followingText)
                        .font(EchoelTheme.font(15, .semibold).monospacedDigit())
                        .foregroundStyle(liveBodyBPM > 0 ? EchoelTheme.accent : EchoelTheme.text)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    Text("BPM")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(TempoFollowLabel.spoken(for: bus.usableBio()))
                .accessibilityValue(followingSpoken)
            }

            Button { toggleLock() } label: {
                Image(systemName: lockBPM ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lockBPM ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: compact ? 30 : 34, height: EchoelTheme.controlHeight)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        // #367: same correction as the transport button. Note what is NOT
                        // changed: the two `border` strokes in the FOLLOWING tempo READOUT — its
                        // compact and its wide branch — stay decorative, and the comment there
                        // says why: "a tap opens nothing (it follows the body)". A reading is
                        // ornament; this lock is a control. That is the boundary, not "every
                        // stroke in the file".
                        //
                        // (Those two were cited by LINE NUMBER here until the #367 Nachlese.
                        // `HeaderMonitors`, edited in the SAME commit, says "no line numbers here
                        // on purpose: this edit moves them" — and CLAUDE.md strikes the pattern
                        // twice. Naming the branches costs nothing and survives an insertion.)
                        .strokeBorder(lockBPM ? EchoelTheme.accent : EchoelTheme.borderStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // 44 pt HIG tap target — the SAME idiom as this control's immediate neighbour in
            // the transport bar, the "•••" overflow (`WorkspaceView`, #113): the visible chip
            // stays 30×32 and only the hit area grows, −6 → 42×44. Both numbers are honest:
            // 42 is under the 44 pt floor in WIDTH, and that is the neighbour's compromise
            // too, taken here for the same reason — the alternative is widening the visible
            // chip, which unbalances a row whose whole point is that it reads as one block.
            //
            // ⛔ WHY THIS WAS MISSING AND WHY IT MATTERS THAT IT WAS. Its two neighbours were
            // BOTH fixed for exactly this — the "•••" by #113, the playback ▶/⏸ by #307's
            // Nachlese (grown to a real 44×48) — and this one sat between them untouched, so
            // the row already contained the precedent, the rationale and a worked example.
            // That is what makes it a founder-visible defect rather than a nitpick: it is the
            // control that decides whether the tempo follows the body at all, and it had the
            // smallest hit area of the three.
            //
            // THE OUTSET FITS WITHOUT OVERLAPPING, and the margins are tight enough to state
            // rather than assume. LEFT: 6 pt to the value box (this view's own `HStack`
            // spacing in compact mode), so the outset reaches exactly its edge — 0 pt into a
            // control that is hit-testable only in the locked state. RIGHT: 12 pt to the
            // "•••", which outsets 6 pt back, so the two meet at the midpoint. Neither
            // overlaps. Shrinking either gap, or raising this inset past 6, breaks that.
            .contentShape(Rectangle().inset(by: -6))
            // ⛔ THE UNLOCKED LABEL USED TO SAY "tap to follow your pulse again" (#491,
            // founder 2026-08-07 "ohne doppelt bpm"). Unlocking does NOT return the box to
            // your pulse — it returns it to the CLOCK, which the body drives through the
            // generative mapping. Saying "your pulse" named the pulse pill's number, i.e.
            // exactly the duplication this slice removed, and it said it in the layer that
            // no screenshot can show (#480: an accessibility string is invisible while
            // VoiceOver is off, which is how the wrong word survives).
            // #647 review: this button spoke the SAME unconditional body claim 268 lines below
            // the readout that was just fixed, and a VoiceOver player reaches it on the next
            // swipe. Under Simulation, unlocking hands the clock back to the demo generator —
            // so "let your body drive it again" named the wrong actor in exactly the state the
            // slice above exists to mark. It asks the same one definition.
            .accessibilityLabel(lockBPM ? TempoFollowLabel.unlockHint(for: bus.usableBio())
                                        : "Lock tempo at this value")
        }
        // ⛔ THIS CONTROL CARRIES ITS OWN NON-GREEDINESS NOW, and #455 is why (founder
        // 2026-08-07, v10.79.371 screenshot with the tempo box scribbled out): in LOOP mode
        // the box stood roughly a third of the screen tall, with the lock and the pulse pill
        // beside it at their normal 32 pt.
        //
        // THE MECHANISM WAS ALREADY WRITTEN DOWN, in two places, before it happened.
        // `EchoelValueField`'s scrub layer is a bare `Rectangle()`, which accepts ANY proposed
        // height — its own comment says so and ends with "Do not remove that without removing
        // this greediness at the source". `WorkspaceView`'s transport bar says the same from
        // the other side: a VStack ranks children by flexibility, so a row hosting this field
        // reports ∞ and starts SPLITTING free space with the instrument below it.
        //
        // ⭐ WHAT ACTUALLY WENT WRONG IS NOT THAT SOMEONE IGNORED THOSE COMMENTS. The
        // protection was a property of the BAR (`.fixedSize` + `.frame(minHeight: 44)` on
        // `WorkspaceView.transportBar`), not of the CONTROL. #411 moved this field OUT of that
        // bar and into `EchoelStudioView.startControlRow` on a founder ask — a move whose whole
        // point was that the control is mountable anywhere, and every word of its
        // freeze-safety argument was correct. The layout half simply did not travel with it,
        // because nothing said it had to. That is the #416 shape: one decision, two owners, and
        // no way to notice when they come apart.
        //
        // So the fix is placed HERE and not on the new row: whichever bar this lands in next
        // inherits it. `startControlRow` is deliberately left untouched, so this file is the
        // single answer to "why does the tempo field not stretch".
        //
        // ⚠️ ONLY THE LOCKED BRANCH WAS EVER GREEDY. The following branches pin their own
        // frames (compact: `76×32`; wide: padded Texts). So this was a LOOP-mode-only defect,
        // and a Flow-mode screenshot would have shown nothing — worth knowing before reading a
        // report that says "the tempo field looks fine here".
        //
        // ⚠️ NO `minHeight` TWIN HERE, unlike the three chrome bars. Theirs floors the whole
        // BAR at the 44 pt HIG tap target; this view is a control inside a row whose height is
        // already pinned by its siblings (the ▶ button's `FloatingVisualLayout.startButtonHeight`,
        // the lock's own 32). Adding a floor here would be a second opinion about a height this
        // view does not own.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Locking adopts the SHOWN value as the musical tempo — the clock GLIDES to it
    /// (never jumps; the glide engine eases stopped or playing). Unlocking lets the clock
    /// resume its gentle body-follow.
    ///
    /// ⛔ "THE SHOWN VALUE" USED TO MEAN THE BODY RATE, and that made this a jump dressed
    /// as a lock (#491): the box showed `cameraRPPG.displayBPM` while the clock ran at the
    /// genre-tilted mapping of it, so locking a 144 bpm pulse over a 72 bpm clock moved the
    /// music by an octave of tempo in one tap. The line below is unchanged — it still reads
    /// `followingValue` — and it became correct because `followingValue` is now the clock.
    /// That is the whole shape of this slice: the invariant "lock captures the number you
    /// see" was never broken, the NUMBER was wrong.
    private func toggleLock() {
        if lockBPM {
            lockBPM = false
        } else {
            // NaN-safe: `min(max(v, lo), hi)` would pass NaN through both clamps, and
            // `lockedBPM` is PERSISTED — a NaN written here survives the next launch and
            // is the one live path that can hand a NaN to the sequencer's tempo.
            let v = followingValue.clamped(to: Transport.minTempo...Transport.maxTempo)
            lockedBPM = (v * 10_000).rounded() / 10_000
            // No click push here. While PLAYING, `glideTempo` eases over ~2 s, so setting
            // the click to the target would run it ahead of the sequencer until the next
            // relay yanked it back — an audible blip on every lock. While STOPPED the glide
            // eases too (deliberately — the founder asked that the number never jump), so
            // the click now slides to the locked tempo over ~2.5 s instead of snapping to
            // it. That is the coherent behaviour (click and displayed tempo finally agree
            // throughout the ease) but it IS a change to what the stopped click does, and
            // the stopped click is the only thing audible on that path.
            // NEEDS-FOUNDER-VERIFY on device: lock while stopped, listen to the ease.
            player.pattern.glideTempo(to: lockedBPM, source: .user)
            lockBPM = true
        }
        onLockChanged()
    }

    /// Locked edits are precise + instant (setTempo cancels any in-flight glide).
    private var lockedBinding: Binding<Double> {
        Binding(get: { lockedBPM },
                set: { v in
                    lockedBPM = v.clamped(to: Transport.minTempo...Transport.maxTempo)
                    player.pattern.setTempo(lockedBPM, source: .user)
                })
    }
}
#endif
