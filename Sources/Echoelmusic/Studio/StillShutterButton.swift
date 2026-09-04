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

    let recorder: VisualRecorder

    /// The sentence currently on screen, or nil. LOCAL on purpose: the recorder owns the FACT
    /// (which outcome), this view owns the PRESENTATION (how long it stays). A timestamp on the
    /// model would need a timer to expire and would make every observer re-render for a value
    /// nobody else reads.
    @State private var shown: VisualRecorder.StillOutcome?

    /// How long the answer stays up. Long enough to read one short sentence, short enough that it
    /// is gone before the next considered tap.
    private static let dwell: Duration = .seconds(2.2)

    var body: some View {
        HStack(spacing: 8) {
            Button { recorder.requestStill() } label: {
                Image(systemName: "camera.circle")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .accessibilityLabel("Save this frame as a picture")

            if let outcome = shown {
                Text(StillFeedback.sentence(for: outcome))
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(outcome == .saved ? EchoelTheme.text : EchoelTheme.recording)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
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
