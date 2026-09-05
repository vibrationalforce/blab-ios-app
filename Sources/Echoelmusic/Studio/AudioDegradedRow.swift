//
//  AudioDegradedRow.swift
//  Echoelmusic — Studio
//
//  #585 — the reader `AudioEngine.degraded` never had.
//
//  ⛔ THE DEFECT. `AudioEngine` self-heals a stopped engine up to `maxRecoveryAttempts` times and
//  then gives up, setting `degraded = true` and `lastAudioError`. Its own declaration says why:
//  *"so the UI can offer a 'tap to retry' affordance instead of silently showing 'stopped'"*.
//  There was no such affordance, and no reader at all — `git grep -n "degraded\|lastAudioError"`
//  over `Sources/` and `Tests/` returned only `AudioEngine.swift` itself. The promise in that
//  comment had never been kept.
//
//  What that costs is not subtle. The trigger is cheap — a wobbling headphone plug produces
//  `.oldDeviceUnavailable`, three failed recoveries, done. Everything else keeps running: the
//  transport plays, the visual moves, the pulse reads, the meters tick. There is simply no sound,
//  and no control anywhere says so or offers a way back. The user's only working move is to
//  relaunch the app — the experience this whole self-healing layer was built to remove.
//
//  ⭐ WHY A ROW AND NOT AN ALERT. `EchoelStudioView`'s body carries 14 presentation modifiers and
//  a 15th is the metadata-decoder SIGSEGV — the black screen of 10.76.34. A banner inside an
//  existing `VStack` line adds no modifier at all. It is also the better answer on its own terms:
//  an alert steals focus from a performance for a condition that may resolve when the plug is
//  reseated, and it cannot stay visible while the user goes looking for the cause.
//
//  ⭐ WHY ITS OWN FILE AND ITS OWN `View`. The freeze law: any body that reads a high-frequency
//  `@Observable` registers as an observer at that rate, and `AudioEngine` publishes `masterLevel`
//  from the meter poll. Reading `degraded` from `EchoelStudioView.body` would be safe TODAY —
//  SwiftUI tracks the properties actually accessed — but it puts a live audio object one careless
//  edit away from the root body, and this repo has paid for that four times (10.76.41/43/47/48/50).
//  A leaf that touches exactly two fields and nothing else cannot become that.
//
//  ⚠️ HONEST LIMIT: this row is compile-verified only. Whether it is legible, correctly placed and
//  reassuring rather than alarming at the moment audio dies is a DEVICE probe, and the state is
//  awkward to reach on purpose (unplug a headset mid-take, repeatedly, until recovery gives up).
//

#if canImport(SwiftUI)
import SwiftUI

/// The one visible consequence of `AudioEngine.degraded`: says what happened, offers the retry.
///
/// Renders NOTHING while audio is healthy, so it costs no height in the normal case — the row it
/// mounts into keeps its exact layout until the moment there is something to say.
@MainActor
struct AudioDegradedRow: View {

    /// ⚠️ READ EXACTLY TWO PROPERTIES IN THIS BODY — `degraded` and `lastAudioError` — and never
    /// `masterLevel`, `masterLevelR`, `isRunning` or anything the meter poll writes. Both of these
    /// change at most a handful of times per session; a meter value changes ~15×/s and would make
    /// this view, and any menu presented above it, rebuild at that rate.
    @Environment(AudioEngine.self) private var audioEngine

    var body: some View {
        if audioEngine.degraded {
            HStack(spacing: 8) {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.warning)
                    .accessibilityHidden(true)
                // The engine's own sentence, not a rewritten one. It names the CAUSE
                // ("Audio stopped (route change) and auto-recovery gave up."), which is what
                // makes the difference between a user who reseats a plug and one who reinstalls.
                Text(audioEngine.lastAudioError ?? "Audio stopped and could not restart.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    // `start()` IS the retry: it clears `degraded`, `lastAudioError`,
                    // `wasInterrupted` and `recoveryAttempts`, and re-arms self-healing after an
                    // intentional stop. Calling it is idempotent on a running engine.
                    audioEngine.start()
                } label: {
                    Text("Retry")
                        .font(EchoelTheme.font(11, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .background(
                            RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                                .stroke(EchoelTheme.borderStrong, lineWidth: 1))
                        // The 28 pt box is the visual size; the tap target is the full 44.
                        .contentShape(Rectangle().inset(by: -8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry starting audio")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(EchoelTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .stroke(EchoelTheme.borderStrong, lineWidth: 1)))
            // One announcement when it appears, rather than a live region that would re-speak
            // itself on every unrelated redraw.
            .accessibilityElement(children: .contain)
        }
    }
}
#endif
