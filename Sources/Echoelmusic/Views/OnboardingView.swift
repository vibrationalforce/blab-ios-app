#if canImport(SwiftUI)
import SwiftUI

/// Minimal onboarding for v10 Beat-MVP: welcome → preview → tap to start.
///
/// HealthKit request removed — v10 Beat-MVP does not read biometrics on the
/// audio path. (Bio integration returns as an opt-in feature in v1.1+ when
/// the Record/Stream tabs ship.)
struct OnboardingView: View {

    @Binding var isComplete: Bool
    /// Retained for binding parity with EchoelmusicApp; unused in v10.
    @Binding var shouldAutoPlay: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    previewPage.tag(1)
                    readyPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("Echoelmusic")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)

            Text("Make Beats.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("A 16-step, 8-track sequencer in your pocket. Tap pads to play, toggle steps to build patterns.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            nextButton(label: "Continue")
        }
        .padding(.bottom, 60)
    }

    private var previewPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("Coming in v1.1")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                row(symbol: "mic.fill", text: "Record vocals over your beats")
                row(symbol: "video.fill", text: "Capture and trim video clips")
                row(symbol: "antenna.radiowaves.left.and.right", text: "Live stream to RTMP destinations")
            }
            .padding(.horizontal, 40)

            Text("This first release ships the beat maker. The rest is in active development.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            nextButton(label: "Got it")
        }
        .padding(.bottom, 60)
    }

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))

            Text("Ready")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Tap a pad to play. Toggle steps to build a pattern. Hit play.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                isComplete = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                    Text("Start")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 60)
    }

    // MARK: - Helpers

    private func row(symbol: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 20)
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
    }

    private func nextButton(label: String) -> some View {
        Button {
            withAnimation { currentPage += 1 }
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 40)
    }
}
#endif
