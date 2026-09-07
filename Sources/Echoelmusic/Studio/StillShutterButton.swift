// The guard MIRRORS `VisualRecorder`'s own (`canImport(AVFoundation) && canImport(Metal)`) plus
// SwiftUI. A narrower one would reference a type that does not exist on a platform without those
// two frameworks — the compile error would land here, far from its cause.
#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Metal)
import SwiftUI

/// #986 — the shutter for the visual still, WITH its answer.
///
/// WHY THIS IS ITS OWN LEAF AND NOT THREE LINES IN `EchoelStudioView`:
/// the outcome has to be READ to be shown, and every read registers its reader as an observer of
/// `VisualRecorder`. The fullscreen control row lives inside `EchoelStudioView`'s body, which is
/// the host of the genre/key `.menu` Pickers — the 10.76.41/50 law. `stillOutcomeToken` is COLD
/// (it moves once per tap, not ten times a second), so this is not today's freeze; the point is
/// that the read is one edit away from a hot neighbour and the leaf costs nothing. The record
/// button beside it reads `isRecording` inline for the same cold reason — that is history, not a
/// licence, and it is not touched here (one slice, one change).
///
/// It also keeps the still's TWO halves — the tap and what became of it — in one place, so a later
/// change cannot move one without seeing the other.
struct StillShutterButton: View {

    /// WHERE THE ANSWER GOES. #1063 measured why this had to become a choice rather than stay
    /// one layout: `FloatingVisualLayout.chromeFit` reports **0 pt of slack** in the fullscreen
    /// bar on a 375 pt phone with nothing recording, and 18 pt on a 393 pt one. A sentence
    /// placed IN that row would be compressed to nothing — SwiftUI shrinks a `Text` before it
    /// shrinks the rigid icon frames beside it — so the button would be back to the silence
    /// #986 exists to remove, in the surface D1 is merging everything into.
    ///
    /// The tap and its answer still live in ONE view, which is the #986 law. Only the
    /// GEOMETRY differs.
    enum AnswerPlacement {
        /// Beside the button, in the same row. For a row with no width budget.
        // ⚠️ NO CALLER SINCE #1069. Its one call site was the fullscreen cover's top row, which
        // S3c deleted; the surviving mount is `FloatingVisualWindow` with `.below`. Kept, and the
        // reason is specific: the two placements are what let ONE leaf serve a row with width to
        // spare AND a bar with none. S4 (wrap the fullscreen bar instead of shedding it) is the
        // likely producer. Named here rather than left silent — a case with no producer is a
        // finding in this repo even when keeping it is right.
        case beside
        /// Hanging below the button as an OVERLAY — it contributes no layout width, so a
        /// width-budgeted bar is unaffected whether the sentence is up or not.
        case below
    }

    let recorder: VisualRecorder

    /// No default, on purpose (#431): a defaulted argument that no call site writes never
    /// appears in a diff, so the choice would be invisible exactly where it matters.
    let answer: AnswerPlacement

    /// The sentence currently on screen, or nil. LOCAL on purpose: the recorder owns the FACT
    /// (which outcome), this view owns the PRESENTATION (how long it stays). A timestamp on the
    /// model would need a timer to expire and would make every observer re-render for a value
    /// nobody else reads.
    @State private var shown: VisualRecorder.StillOutcome?

    /// How long the answer stays up. Long enough to read one short sentence, short enough that it
    /// is gone before the next considered tap.
    private static let dwell: Duration = .seconds(2.2)

    /// How far below the button the overlay answer hangs. The chrome bar is 44 pt tall and the
    /// camera glyph is centred in it, so ~30 pt clears the bar's lower edge and puts the sentence
    /// over the picture — where the eye already is after a considered tap.
    private static let answerDrop: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            Button { recorder.requestStill() } label: {
                Image(systemName: "camera.circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("Save this frame as a picture")

            if answer == .beside, let outcome = shown {
                answerText(outcome)
            }
        }
        // TRAILING, so a long sentence ("Photos access is off — allow it in Settings") grows
        // LEFT into the picture instead of off the right edge — the shutter sits near the end of
        // the bar. `fixedSize` keeps it one unwrapped line; the overlay itself claims no layout
        // width, which is the whole reason this placement exists.
        .overlay(alignment: .bottomTrailing) {
            if answer == .below, let outcome = shown {
                answerText(outcome)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(EchoelTheme.bg.opacity(0.92)))
                    .offset(y: Self.answerDrop)
                    // Display only: a tap here belongs to the play surface underneath, and the
                    // sentence clears itself after `dwell`.
                    .allowsHitTesting(false)
            }
        }
        // The TOKEN is watched, never the outcome value: two denials in a row are two events and
        // must both be shown, and a plain `onChange` on the enum would see no change for the
        // second one.
        .onChange(of: recorder.stillOutcomeToken) { _, _ in
            guard let outcome = recorder.lastStillOutcome else { return }
            withAnimation(.easeOut(duration: 0.15)) { shown = outcome }
        }
        // Re-armed by the token: a second still while the first sentence is still up restarts the
        // dwell instead of letting the old timer clear the new answer early.
        .task(id: recorder.stillOutcomeToken) {
            guard shown != nil else { return }
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { shown = nil }
        }
    }

    /// The sentence itself — ONE definition for both placements, so the two can differ in
    /// geometry and never in words or colour.
    private func answerText(_ outcome: VisualRecorder.StillOutcome) -> some View {
        Text(StillFeedback.sentence(for: outcome))
            .font(EchoelTheme.font(12))
            .foregroundStyle(outcome == .saved ? EchoelTheme.text : EchoelTheme.recording)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The words. Pure and separate so the guard can drive them without a view.
///
/// Every sentence says what HAPPENED and, where the user can act, what to do — a denial that only
/// says "failed" sends someone back to tap the same dead button.
enum StillFeedback {
    static func sentence(for outcome: VisualRecorder.StillOutcome) -> String {
        switch outcome {
        case .saved:  return "Saved to Photos"
        case .denied: return "Photos access is off — allow it in Settings"
        case .failed: return "Could not save this frame"
        }
    }
}
#endif
