#if canImport(SwiftUI)
import SwiftUI

/// First-run onboarding: welcome → wider-vision → ready + mandatory safety gate,
/// then Start drops into the instrument home.
///
/// NOTE (corrected 2026-07-22): the old comment here claimed "does not read
/// biometrics on the audio path" — that is FALSE and long-stale. Reading the body
/// (camera rPPG / HealthKit → the bio-generative voice) IS the core feature, as
/// the on-screen copy itself says ("Your heartbeat makes music"). The HealthKit
/// permission is asked at a real bio-use moment (studio `startBioSource`, UX-3),
/// not here. Cold-start choreography (auto-arm after the Start gesture, wonder-first
/// copy) is planned in `scratchpads/PLAN_COLD_START_CHOREOGRAPHY_2026-07-22.md`.
struct OnboardingView: View {

    @Binding var isComplete: Bool
    /// Retained for binding parity with EchoelmusicApp; unused in v10.
    @Binding var shouldAutoPlay: Bool
    @State private var currentPage = 0
    /// Gates the Start button — the user must acknowledge the safety notice.
    @State private var acknowledgedSafety = false

    var body: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()

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

            // ⛔ DECORATIVE. Without this VoiceOver announces "square grid four by three
            // fill" — an SF Symbol's API name, read aloud, as the FIRST thing a blind user
            // hears from Echoel. All three page glyphs carry no information the headline
            // below them does not already carry.
            Image(systemName: "square.grid.4x3.fill")
                .font(EchoelTheme.font(48))
                .foregroundStyle(EchoelTheme.text.opacity(0.3))
                .accessibilityHidden(true)

            Text("Echoelmusic")
                .font(EchoelTheme.font(32, .bold))
                .foregroundStyle(EchoelTheme.text)

            Text("Your heartbeat makes music.")
                .font(EchoelTheme.font(17))
                .foregroundStyle(EchoelTheme.text.opacity(0.6))
                .multilineTextAlignment(.center)

            Text("Bio-reactive generative loops in any key and BPM — composed by your heart and breath, exported to your DAW.")
                .font(EchoelTheme.font(15))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))   // WCAG AA on black (was 0.35)
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
                .font(EchoelTheme.font(48))
                .foregroundStyle(EchoelTheme.text.opacity(0.3))
                .accessibilityHidden(true)

            Text("The wider vision")
                .font(EchoelTheme.font(24, .bold))
                .foregroundStyle(EchoelTheme.text)

            VStack(alignment: .leading, spacing: 12) {
                row(symbol: "sparkles", text: "Living visuals that move with your body")
                row(symbol: "lightbulb.fill", text: "Light & stage — DMX / Art-Net")
                row(symbol: "waveform.circle", text: "Immersive spatial objects — ADM-OSC")
            }
            .padding(.horizontal, 40)

            Text("This release is the bio-reactive instrument — with living visuals, stage light and immersive output built in.")
                .font(EchoelTheme.font(13))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))   // WCAG AA on black (was 0.25 — near-invisible)
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
                .font(EchoelTheme.font(48))
                .foregroundStyle(EchoelTheme.text.opacity(0.3))
                .accessibilityHidden(true)

            Text("Ready")
                .font(EchoelTheme.font(24, .bold))
                .foregroundStyle(EchoelTheme.text)

            Text("Breathe, lock a key and BPM, and let your body compose. Export to your DAW.")
                .font(EchoelTheme.font(15))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))   // WCAG AA on black (was 0.4)
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
            .background(EchoelTheme.fill, in: RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge))
            .padding(.horizontal, 32)
            // Named as a container so a VoiceOver user knows what the five rows below the
            // heading ARE before reading them, and so the toggle's hint can refer to it.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Safety and privacy notice")

            Toggle(isOn: $acknowledgedSafety) {
                Text("I understand")
                    .font(EchoelTheme.font(14))
                    .foregroundStyle(EchoelTheme.text.opacity(0.7))
            }
            .tint(EchoelTheme.text)
            .padding(.horizontal, 32)
            // ⚠️ THIS TOGGLE IS A CONSENT, not a preference — the Start button below stays
            // disabled until it is on. Sighted users read the five warnings sitting directly
            // above it; a VoiceOver user arriving at the control heard only "I understand,
            // switch, off", with no statement of WHAT is understood. That is the one place in
            // onboarding where a missing hint is a substantive problem rather than a rough
            // edge, so it names the notice explicitly.
            .accessibilityHint("Confirms you have read the safety and privacy notice above: "
                               + "for self-observation, not medical diagnosis; not while "
                               + "driving or under the influence; visuals capped at 3 hertz.")

            Spacer()

            Button {
                isComplete = true
            } label: {
                HStack(spacing: 8) {
                    // Inside a Button label SwiftUI combines children, so without this the
                    // button announces "play fill, Start" — the glyph name read as part of
                    // the action.
                    Image(systemName: "play.fill")
                        .font(EchoelTheme.font(13))
                        .accessibilityHidden(true)
                    Text("Start")
                }
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(EchoelTheme.text, in: RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge))
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
                .font(EchoelTheme.font(14))
                .frame(width: 20)
                .foregroundStyle(EchoelTheme.text.opacity(0.5))
                .accessibilityHidden(true)
            Text(text)
                .font(EchoelTheme.font(14))
                .foregroundStyle(EchoelTheme.text.opacity(0.6))
            Spacer()
        }
    }

    private func safetyRow(_ symbol: String, _ text: String) -> some View {
        // 0.7 opacity like the page's body copy — at 0.5 the MANDATED safety
        // warnings were the least legible text in onboarding (~4.3:1, below the
        // WCAG AA 4.5:1 small-text minimum; AX audit 2026-07-09).
        HStack(alignment: .top, spacing: 8) {
            // The glyph restates the sentence; announcing "cross case" before "Coordinate any
            // therapeutic use with your provider" adds noise to a MANDATED warning.
            Image(systemName: symbol)
                .font(EchoelTheme.font(11))
                .frame(width: 16)
                .foregroundStyle(EchoelTheme.text.opacity(0.6))
                .accessibilityHidden(true)
            Text(text)
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))
            Spacer(minLength: 0)
        }
    }

    private func nextButton(label: String) -> some View {
        Button {
            withAnimation { currentPage += 1 }
        } label: {
            Text(label)
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(EchoelTheme.text, in: RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge))
        }
        .padding(.horizontal, 40)
    }
}
#endif
