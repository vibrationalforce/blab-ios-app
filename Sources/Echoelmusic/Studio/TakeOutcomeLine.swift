// The guard MIRRORS `VisualRecorder`'s own (`canImport(AVFoundation) && canImport(Metal)`) plus
// SwiftUI — the same reasoning as `StillShutterButton`: a narrower one would reference a type that
// does not exist on a platform without those frameworks.
#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Metal)
import SwiftUI

/// #990 — what became of the VIDEO take, said on screen.
///
/// WHY A LEAF AND NOT A LINE IN THE HOST: the outcome has to be READ to be shown, and every read
/// registers its reader as an observer of `VisualRecorder`. The fullscreen control row lives in
/// `EchoelStudioView`'s body, which hosts the genre/key `.menu` Pickers (10.76.41/50). Same shape
/// as `StillShutterButton`, and for the same reason.
///
/// WHY IT IS SEPARATE FROM THE STILL'S ANSWER: a still and a take can finish moments apart, and
/// one sentence cannot say two things. Two leaves, two tokens, two dwell timers.
struct TakeOutcomeLine: View {

    let recorder: VisualRecorder

    @State private var shown: VisualRecorder.TakeOutcome?

    /// Longer than the still's 2.2 s. A lost TAKE is unrepeatable — a performance happened and did
    /// not get written — so its sentence is worth reading twice, and unlike the still there is no
    /// second artefact to check afterwards.
    private static let dwell: Duration = .seconds(4)

    var body: some View {
        Group {
            if let outcome = shown {
                Text(TakeFeedback.sentence(for: outcome))
                    .font(EchoelTheme.font(12))
                    .foregroundStyle(outcome == .saved ? EchoelTheme.text : EchoelTheme.recording)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onChange(of: recorder.takeOutcomeToken) { _, _ in
            guard let outcome = recorder.lastTakeOutcome else { return }
            withAnimation(.easeOut(duration: 0.15)) { shown = outcome }
        }
        .task(id: recorder.takeOutcomeToken) {
            guard shown != nil else { return }
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { shown = nil }
        }
    }
}

/// The words. Pure and separate so a guard can drive them without a view.
///
/// `.empty` and `.failed` say different things because the user can act differently: an empty take
/// is worth retrying, a writer error usually is not. "Nothing was recorded" also answers the
/// question the REC badge raised by counting seconds the whole time.
enum TakeFeedback {
    static func sentence(for outcome: VisualRecorder.TakeOutcome) -> String {
        switch outcome {
        case .saved:  return "Take saved to Photos"
        case .empty:  return "Nothing was recorded — the visual sent no frames"
        case .failed: return "The recording could not be written"
        }
    }
}
#endif
