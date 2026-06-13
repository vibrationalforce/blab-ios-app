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
    /// Gates the Start button — the user must acknowledge the safety notice.
    @State private var acknowledgedSafety = false

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

            Text("Your heartbeat makes music.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("Bio-reactive, drum-free generative loops in any key and BPM — composed by your heart and breath, exported to your DAW.")
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

            Text("The wider vision")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
                row(symbol: "sparkles", text: "Living visuals that move with your body")
                row(symbol: "lightbulb.fill", text: "Light & stage — DMX / Art-Net")
                row(symbol: "antenna.radiowaves.left.and.right", text: "Capture, edit & live broadcast")
            }
            .padding(.horizontal, 40)

            Text("This release is the bio-reactive instrument. Visuals, light, video and broadcast are in active development.")
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

            Text("Breathe, lock a key and BPM, and let your body compose. Export to your DAW.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Required safety & privacy notice.
            VStack(alignment: .leading, spacing: 8) {
                safetyRow("heart.text.square", "For self-observation, not medical diagnosis.")
                safetyRow("car", "Not while driving or operating machinery.")
                safetyRow("exclamationmark.triangle", "Not under the influence of alcohol or drugs.")
                safetyRow("cross.case", "Coordinate any therapeutic use with your provider.")
                safetyRow("eye", "Visuals are capped at a safe 3 Hz flash rate.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 32)

            Toggle(isOn: $acknowledgedSafety) {
                Text("I understand")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .tint(.white)
            .padding(.horizontal, 32)

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
            .disabled(!acknowledgedSafety)
            .opacity(acknowledgedSafety ? 1 : 0.4)
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 40)
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

    private func safetyRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(.white.opacity(0.45))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
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
