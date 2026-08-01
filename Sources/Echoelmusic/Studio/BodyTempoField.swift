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
//   • UNLOCKED — the number RUNS ALONG with the live biofeedback BPM (trust-gated calm
//     display value; falls back to the clock tempo when no pulse is live).
//   • Tap the lock — the number FREEZES: the shown body value becomes the musical tempo
//     (the clock GLIDES to it, never jumps) and is then editable to 0.0001 BPM via the
//     Echoel number pad. Unlock → it follows the body again.
// HOME (founder 2026-07-15 "Das soll da oben hin"): the `compact` variant lives in the
// transport bar next to Play (word labels dropped to fit); the full variant is available
// for panels. This is THE one musical-tempo control — the pulse monitor (live rate) stays
// separately in the brand header ("beide behalten").
//
// RENDER SAFETY (freeze rule): `cameraRPPG.displayBPM` updates ~10 Hz. This is a LEAF
// view — the read lives HERE, so only this row rebuilds; the Picker-hosting Composition
// panel / root body never subscribe to the 10 Hz churn.

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BodyTempoField: View {

    #if canImport(AVFoundation)
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    #endif
    @Environment(Transport.self) private var transport
    @Environment(BeatPlayer.self) private var player

    // Shared with the transport-bar lock button + tap tempo (same keys + defaults).
    @AppStorage("studio.lockBPM") private var lockBPM = false
    @AppStorage("studio.lockedBPM") private var lockedBPM: Double = 70

    /// Parent hook (recompose after a lock change) — called on lock/unlock/edit.
    var onLockChanged: () -> Void = {}

    /// COMPACT mode for the top chrome (founder 2026-07-15 "Das soll da oben hin",
    /// beide behalten): drops the "Tempo"/"BPM" word labels so the field fits the
    /// transport bar next to Play. Same 4-decimal value + lock, just narrower —
    /// still the one musical-tempo control (no second widget).
    var compact: Bool = false

    /// The live body rate when a trustworthy pulse is on screen, else 0.
    private var liveBodyBPM: Double {
        #if canImport(AVFoundation)
        if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 { return cameraRPPG.displayBPM }
        #endif
        return 0
    }

    /// What the unlocked display shows: the body rate, or the clock as honest fallback.
    private var followingValue: Double { liveBodyBPM > 0 ? liveBodyBPM : transport.tempo }

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
    /// Unlocked, the number is a MEASUREMENT: `cameraRPPG.displayBPM`, derived from an
    /// autocorrelation over a ~10 s window of camera frames. Nothing in that chain resolves
    /// to 0.0001 BPM. Three of the four decimals were never information, and in the shipped
    /// build they read `,0000` because the value arrives already rounded — a precision claim
    /// the number cannot fill, in the narrowest row the app has.
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
                // Locked: exact, editable to 0.0001 BPM (Echoel number pad), like Kammerton.
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
                    .frame(width: 76, height: 32)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tempo, following your pulse")
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
                .accessibilityLabel("Tempo, following your pulse")
                .accessibilityValue(followingSpoken)
            }

            Button { toggleLock() } label: {
                Image(systemName: lockBPM ? "lock.fill" : "lock.open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lockBPM ? EchoelTheme.accent : EchoelTheme.dim)
                    .frame(width: compact ? 30 : 34, height: 32)
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
            .accessibilityLabel(lockBPM ? "Tempo locked — tap to follow your pulse again"
                                        : "Lock tempo at this value")
        }
    }

    /// Locking adopts the SHOWN value (the body rate, 4-decimal exact) as the musical
    /// tempo — the clock GLIDES to it (never jumps; the glide engine eases stopped or
    /// playing). Unlocking lets the clock resume its gentle body-follow.
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
            player.pattern.glideTempo(to: lockedBPM)
            lockBPM = true
        }
        onLockChanged()
    }

    /// Locked edits are precise + instant (setTempo cancels any in-flight glide).
    private var lockedBinding: Binding<Double> {
        Binding(get: { lockedBPM },
                set: { v in
                    lockedBPM = v.clamped(to: Transport.minTempo...Transport.maxTempo)
                    player.pattern.setTempo(lockedBPM)
                })
    }
}
#endif
