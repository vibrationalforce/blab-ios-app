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

    /// The consent toggle's VoiceOver hint, hoisted out of the modifier deliberately.
    /// `accessibilityHint` has three overloads (`LocalizedStringKey`, `StringProtocol`, `Text`)
    /// and a multi-part `+` chain passed straight in is the only such inference site anywhere
    /// in `Sources/` — no precedent that it resolves the way I expect, and CI is the only
    /// compiler here. Binding it to a property pins the type to `String` before the modifier
    /// ever sees it. Cheap insurance against a red gate for zero behavioural difference.
    ///
    /// ⚠️ KNOWN AND DELIBERATE: this string is NOT localised. (An earlier version of this note
    /// said it was "the only string on this screen that isn't" — wrong by two: `"Echoelmusic"`
    /// and `"Start"` are also absent from the catalog, both legitimately, being identical in
    /// German. Corrected because a confidently-stale claim in a comment is this repo's most
    /// expensive recurring defect.) Being a `String` (built by `+`) it hits `accessibilityHint`'s
    /// `StringProtocol` overload, which does not look anything up; and it cannot become a
    /// `LocalizedStringKey` without collapsing to one ~200-character source line. Acceptable
    /// precisely because of the rule two properties below: the CONSENT lives in the LABEL,
    /// which IS localised. This hint only enumerates what the label already commits to, for
    /// users who have hints switched on. Fixing it properly means giving it a short symbolic
    /// key — a different key style from the rest of the catalog, so it waits for the slice
    /// that decides that question for the whole app rather than being smuggled in here.
    private static let consentHint =
        "Confirms you have read the safety and privacy notice above: for self-observation, "
        + "not medical diagnosis; not while driving or under the influence; visuals capped "
        + "at 3 hertz."

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
                // Rotor heading navigation is how a VoiceOver user skims a screen. Without
                // the trait these three page titles are headings by font weight only, so the
                // rotor finds nothing at all on the first screen of the app.
                .accessibilityAddTraits(.isHeader)

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
                .accessibilityAddTraits(.isHeader)

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
                .accessibilityAddTraits(.isHeader)

            Text("Breathe, lock a key and BPM, and let your body compose. Export to your DAW.")
                .font(EchoelTheme.font(15))
                .foregroundStyle(EchoelTheme.text.opacity(0.7))   // WCAG AA on black (was 0.4)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Required safety & privacy notice.
            VStack(alignment: .leading, spacing: 8) {
                // The box had NO visible title — five bare sentences in a grey rectangle, and
                // the only thing naming them was a code comment. Sighted users were in the
                // same position as VoiceOver users. A real heading fixes both at once, and is
                // what the container label below should be belt-and-braces for rather than
                // the sole channel.
                Text("Safety & privacy")
                    .font(EchoelTheme.font(11, .bold))
                    .foregroundStyle(EchoelTheme.dim)
                    .accessibilityAddTraits(.isHeader)
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
            // Named as a container so the rows are grouped rather than loose. ⚠️ A `.contain`
            // container label is ADVISORY — iOS announces it on entering the group, and not
            // reliably across versions or navigation modes. That is exactly why the visible
            // heading above exists: this line must not be the only thing naming the notice.
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
            // disabled until it is on. Sighted users read the warnings sitting directly above
            // it; a VoiceOver user arriving at the control heard only "I understand, switch,
            // off", with no statement of WHAT is understood.
            //
            // ⛔ THE SUBSTANCE IS IN THE LABEL, NOT THE HINT, and the first version got this
            // wrong. `Speak Hints` is user-disableable (and off in some configurations), hints
            // are spoken only after a delay and are interruptible, and Voice Control users
            // never receive them at all. A consent whose meaning lives only in a hint is a
            // consent a real user can legitimately never hear while still being able to flip
            // the switch and unblock Start. The label is unconditional; the hint carries the
            // enumeration for those who have hints on.
            .accessibilityLabel("I understand the safety and privacy notice above")
            .accessibilityHint(Self.consentHint)

            Spacer()

            Button {
                isComplete = true
            } label: {
                HStack(spacing: 8) {
                    // Inside a Button label SwiftUI MERGES the children into one announcement,
                    // so an unhidden SF Symbol gets its glyph description read out ahead of
                    // "Start". (The earlier version of this comment quoted the exact string
                    // VoiceOver would say. That was a guess dressed as a fact — the symbol
                    // description varies by symbol and OS version, and I have no device to
                    // check it on. The label above pins the announcement regardless.)
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
            // Disabled state was communicated by OPACITY alone — VoiceOver said "Start,
            // dimmed, button" and named no way out. Same defect class as the Patchbay dot:
            // one channel, and some users cannot receive it.
            // ⚠️ `Text(...)` on BOTH branches, not bare literals. A ternary is a weaker
            // inference site than a direct argument: with two string literals the solver can
            // legitimately default them to `String` and pick the generic `StringProtocol`
            // overload, which does NOT look anything up — so the one label that explains why
            // Start is disabled would stay English in every language, with no diagnostic
            // anywhere. `Text(literal)` is unambiguously the `LocalizedStringKey` initialiser
            // and `accessibilityLabel(_: Text)` is a concrete overload, so the question does
            // not arise. ("Start" needs no catalog entry — it is the same word in German and
            // falls back to its own key.)
            .accessibilityLabel(acknowledgedSafety
                                ? Text("Start")
                                : Text("Start — confirm the safety notice above first"))
            .disabled(!acknowledgedSafety)
            .opacity(acknowledgedSafety ? 1 : 0.4)
            .padding(.horizontal, 40)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Helpers

    // ⛔ `text` IS `LocalizedStringKey`, NOT `String`, AND THAT IS THE WHOLE POINT.
    // `Text("literal")` resolves to the `LocalizedStringKey` initialiser and looks the
    // literal up in the String Catalog for free. `Text(someString)` resolves to the
    // `StringProtocol` initialiser, which NEVER localises — even when the value came from a
    // literal one line away at the call site. So a helper typed `String` silently turns
    // every caller's literal into permanently-English text while looking identical in the
    // diff. This is the single trap that decides whether the catalog does anything at all;
    // `symbol` stays `String` because an SF Symbol name must never be translated.
    private func row(symbol: String, text: LocalizedStringKey) -> some View {
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

    private func safetyRow(_ symbol: String, _ text: LocalizedStringKey) -> some View {
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

    private func nextButton(label: LocalizedStringKey) -> some View {
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
