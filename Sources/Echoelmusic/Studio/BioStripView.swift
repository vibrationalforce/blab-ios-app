//
//  BioStripView.swift
//  Echoelmusic
//
//  Thin readout strip showing the latest BioSampleFrame published to
//  EngineBus — the body's live numbers (HR / HRV / breath / coherence) plus a
//  source tag. Deliberately minimal: legible numbers first, no extra controls
//  (transport, FX and panels live on the main screen, not here).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BioStripView: View {

    @Environment(EngineBus.self) private var bus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// #353c. Read HERE, in the leaf that lays the numbers out — never passed down from an
    /// ancestor. It is a settings-driven environment value, not a live signal, so unlike the bio
    /// publishers it costs no rebuilds; the placement rule is the same one either way.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Read the finger-on-lens flag HERE (this small leaf view), not in the parent
    /// `EchoelStudioView.body`. `fingerDetected` is rewritten ~10 Hz while reading; if the
    /// root body subscribed to it (the old `fingerOnLens:` argument), it re-evaluated 10×/s
    /// and tore down any open `.menu` Picker popover in the Composition panel — the "can't
    /// select the Tonart anymore" freeze. Confining the read to this Picker-free strip keeps
    /// the high-frequency invalidation off the selection menus.
    @Environment(CameraRPPGBioPublisher.self) private var cameraRPPG
    /// The shared transport, read HERE (a Picker-free leaf), never in `EchoelStudioView.body`
    /// (freeze rule). Only `isPlaying` is read — a low-frequency start/stop flag — to answer
    /// the survey-universal question "is my body driving the sound right now?" (the activity
    /// light below). `position` (16th-note, high-frequency) is never touched here.
    @Environment(Transport.self) private var transport

    /// True while a camera pulse-read is in progress but no real signal has locked
    /// yet — the strip shows live "reading…" feedback instead of a dead "No signal".
    var measuring: Bool = false
    /// One-tap entry from the otherwise-dead strip: bring the body's pulse in.
    ///
    /// ⚠️ No `= nil`, deliberately, after a round trip: it was written out on the theory that
    /// an implicit memberwise default is the kind of assumption that costs a CI round trip to
    /// disprove. The assumption was then DISPROVEN by evidence already in the repo — the
    /// pre-#234 call site omitted all eight of this view's other members, so the synthesized
    /// init demonstrably supplies defaults here. Explicit `= nil` is redundant, and SwiftLint's
    /// `redundant_optional_initialization` is on. Belt-and-braces is right while a fact is
    /// unknown and is just noise once it is known.
    ///
    /// ⛔ OPTIONAL SINCE #234, and `nil` is the case that matters. In `EchoelStudioView`'s
    /// Bio panel this handler was `startBiofeedback()` — i.e. a button labelled "Read pulse"
    /// that started the entire generative session. That is a lying control on its own, and
    /// after the founder's "3 Knöpfe zum Start → einer" it was also a hidden fourth Start,
    /// two taps from the header pill. The panel now passes nothing and the strip shows an
    /// honest "No signal" instead; the one Start is the front plate's own button, on the
    /// same screen. `BioSourceView` still passes a handler and is still right to: its
    /// `arm(true)` really does arm the sensor alone.
    var onStartPulse: (() -> Void)?

    /// Tapped metric → its plain-language explanation sheet ("app as a school").
    @State private var explain: BioMetric?
    /// The leading ⓘ → an overview that explains ALL the numbers at once (founder:
    /// "HRV etc. soll erklärt werden"). Makes the tap-to-learn discoverable.
    @State private var showGuide = false

    /// Brief "pulse locked — you can lift and play now" confirmation. Teaches the
    /// lock-THEN-play flow (device log 2026-07-07: the user played the touch instrument
    /// immediately, so the finger kept lifting and the read never locked). Shown for a few
    /// seconds when the pulse settles, then it gets out of the way. Low-frequency @State.
    @State private var lockedCueVisible = false
    /// Generation token so a later settle cancels an earlier auto-hide (no flicker).
    @State private var lockedCueToken = 0

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
            strip
        }
        // When the pulse settles, flash a brief "locked — you can lift & play" cue so the
        // user learns to LOCK first, THEN play (the take tempo is latched, so lifting the
        // finger to play no longer perturbs it). `isSettled` is low-frequency.
        //
        // ⛔ ONE BEHAVIOUR CHANGED WITH #382 AND IT IS NOT A SIDE EFFECT TO DISCOVER LATER:
        // the cue used to survive the camera being stopped mid-window, because its old branch
        // read `lockedCueVisible` alone. The slot is now gated on `isRunning`, so stopping the
        // measurement takes the cue with it. That is the right reading — "you can let go &
        // play" is a statement about a measurement that is happening.
        .onChange(of: cameraRPPG.isSettled) { _, settled in
            guard settled, cameraRPPG.isRunning else { return }
            lockedCueToken += 1
            let token = lockedCueToken
            withAnimation(.easeInOut(duration: 0.2)) { lockedCueVisible = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if token == lockedCueToken {
                    withAnimation(.easeInOut(duration: 0.2)) { lockedCueVisible = false }
                }
            }
        }
        // ⛔ AND THE COMMENT ABOVE ONCE ENDED "a restart re-arms it through the same token
        // path", WHICH WAS ONLY THE BENIGN HALF OF THE STORY. `stop()` sets `isSettled = false`,
        // which fires the handler above and is turned away by its own `guard` — so the token is
        // NOT bumped and `lockedCueVisible` stays `true` for the rest of the six seconds. Hiding
        // the slot made that invisible rather than harmless: restart the camera inside that
        // window and the branch renders again with the flag still true, so "Pulse detected — you
        // can let go & play" appears IMMEDIATELY, in a take where nothing has been detected, and
        // `accessibilityHidden(!lockedCueVisible)` is `false`, so VoiceOver says it out loud.
        // That is the same false sentence the slot's own rationale argues against, reached by a
        // different door. Stopping is the honest place to disarm: bump the token so the pending
        // auto-hide cannot fire late, and clear the flag now.
        .onChange(of: cameraRPPG.isRunning) { _, running in
            guard !running, lockedCueVisible || lockedCueToken > 0 else { return }
            lockedCueToken += 1
            lockedCueVisible = false
        }
    }

    /// The one status line above the strip. Recovery/cooling (urgent) wins; otherwise the
    /// brief "pulse locked" confirmation. Both read low-frequency state in THIS leaf, so
    /// they never churn the parent body (freeze rule).
    ///
    /// ⭐ THE THIRD BRANCH RESERVES ITS SLOT INSTEAD OF APPEARING IN IT (#382), and the reason
    /// is that this view is the FIRST child of `EchoelStudioView.bioPanel`'s `VStack`. Below it
    /// sit the explanatory sentence, the "Open Routing" button and `HealthWriteOptInRow()`. As
    /// an ordinary `else if lockedCueVisible`, the six-second cue INSERTED itself and then
    /// REMOVED itself — two layout changes, six seconds apart, shoving two live controls at a
    /// moment when the user is plausibly reaching for one of them. The behaviour is old; #353d
    /// made it big, because the banner now scales and wraps, so at AX3+ the shove is on the
    /// order of 80–110 pt rather than the 26 pt it used to be.
    ///
    /// The slot holds the REAL cue view, hidden with `.opacity` — not a fixed `minHeight`.
    /// That distinction is the whole point: a constant can only be right at one Dynamic Type
    /// size, whereas the actual view reserves exactly what it will need at whatever size the
    /// reader has chosen, and keeps doing so if the sentence is ever reworded.
    ///
    /// ⛔ WHAT THIS DOES **NOT** BUY, because the first version of this block implied it did
    /// and both mandatory reviewers caught the same over-claim. The panel does not "hold
    /// still" full stop; it holds still against the CUE'S OWN TIMER. Two height changes remain,
    /// and they are worth knowing about rather than rediscovering on a device:
    ///   1. The slot is inserted when the camera STARTS and removed when it STOPS. That is
    ///      still two shoves of the full banner height — the trade is that both are now
    ///      user-initiated, instead of arriving unannounced six seconds apart while the user
    ///      reaches for "Open Routing". Better, not free.
    ///   2. Branch 1 wins over branch 3 whenever `recoveryState.userHint != nil`, and the two
    ///      branches render DIFFERENT strings through the same wrapping `banner` — so a stall,
    ///      a thermal `.cooling` or an iOS `.interrupted` resizes the slot mid-measurement, by
    ///      a wrapped line or two at AX3+. Those transitions are low-frequency and genuinely
    ///      informative, so they are left alone; but they are not nothing, and a device pass
    ///      that only watches the six-second window will not see them.
    ///
    /// ⚠️ AND THE SAME "TAX" ARGUMENT THAT REJECTS AN UNCONDITIONAL `else` APPLIES, HONESTLY,
    /// TO WHAT SHIPPED. Reserving blank height for someone who never starts the camera would
    /// be a tax on everyone; what ships charges it to every MEASURING user for the whole
    /// measurement — a blank banner row above the strip whenever nothing needs saying. That is
    /// the deliberate trade (a stable panel while the body is being read), not an oversight,
    /// and it is written down here so the next reader weighs the same two costs I did rather
    /// than only the one that favoured the answer. `menuPanelHost` scrolls, so the reserved
    /// height cannot push the persisted Health opt-in out of reach even at AX5.
    ///
    /// ⚠️ `.accessibilityHidden(!lockedCueVisible)` IS NOT OPTIONAL POLISH, and it travels as
    /// part of a THREE-modifier house pattern (`WorkspaceView`: *"Hidden means INERT, not
    /// merely transparent"* — `.opacity` + `.allowsHitTesting` + `.accessibilityHidden`).
    /// `.opacity(0)` removes a view from neither the accessibility tree nor the hit-test
    /// region. `banner` ends in `.accessibilityLabel(text)`, which propagates that sentence
    /// onto the subtree's elements — so without the hide a VoiceOver user would find "Pulse
    /// detected — you can let go & play" sitting there for the entire measurement, including
    /// long before any pulse has been detected. The layout bug was an annoyance for sighted
    /// users; that would be a false statement made only to the reader who cannot check it.
    /// (⛔ The first version called `.accessibilityLabel` the thing that "makes it an element"
    /// and called the modifiers "a pair". Neither is right: elements come from
    /// `.accessibilityElement(children:)`, which this banner does not use, and the house
    /// pattern is three. `allowsHitTesting` costs nothing today — the banner holds only an
    /// `Image`, a `Text` and a `Spacer` — but the omission would become a live bug the moment
    /// anyone puts a control in it, and the wording is what a future author copies.)
    ///
    /// ⚠️ AND THE GATE STAYS `cameraRPPG.isRunning`, deliberately, rather than becoming an
    /// unconditional `else`. `LockCueDoesNotShoveTheControlsTests` pins both halves.
    @ViewBuilder private var statusBanner: some View {
        if cameraRPPG.isRunning, let hint = cameraRPPG.recoveryState.userHint {
            banner(hint, color: EchoelTheme.warning, systemImage: "camera.metering.center.weighted")
        } else if cameraRPPG.permissionDenied, bus.freshBio() == nil {
            // UX-1: denied camera access was a SILENT dead end — the strip kept
            // coaching "Cover camera" which can never work. Name the real fix.
            // Gate on RAW fresh frames (not hasLiveSignal, which excludes the
            // .fallback demo): a user who deliberately picked Simulation must not
            // be nagged about the camera — matches the header pill's suppression.
            banner(PulseCue.cameraDenied.fullHint,
                   color: EchoelTheme.warning, systemImage: "video.slash")
        } else if cameraRPPG.isRunning {
            banner("Pulse detected — you can let go & play",
                   color: EchoelTheme.success, systemImage: "checkmark.circle.fill")
                .opacity(lockedCueVisible ? 1 : 0)
                .allowsHitTesting(lockedCueVisible)
                .accessibilityHidden(!lockedCueVisible)
        }
    }

    /// ⭐ THIS LINE IS THE ONLY PLACE THE STRIP GIVES AN INSTRUCTION, and until #353d it was
    /// the one piece of text in the strip that Dynamic Type could not touch at all. It said
    /// `.system(size: 11, weight: .medium)`, an ABSOLUTE size: a user at AX5 read it at 11 pt,
    /// the same 11 pt everyone else gets. Not "grows less than asked" — does not grow.
    ///
    /// There are exactly THREE things this helper ever renders, and they are worth naming
    /// because the list is what tells a reader how much text has to fit:
    ///   · `recoveryState.userHint` — "Camera recovering…", "Device cooling down — pulse holds
    ///     for a moment", "Camera paused by iOS — waiting to resume";
    ///   · `PulseCue.cameraDenied.fullHint` — "Camera access is off — enable it in Settings to
    ///     read your pulse";
    ///   · the lock cue — "Pulse detected — you can let go & play".
    ///
    /// ⛔ THE FIRST VERSION OF THIS PARAGRAPH LISTED A STRING THIS BANNER NEVER SHOWS, and one
    /// that does not exist in `Sources/` at all: it claimed the AX5 user read *"Cover the
    /// camera and flash"* here. The real wording is `PulseCue.coverLens.fullHint` = "Cover the
    /// rear camera + flash", and its only consumer is `HeaderMonitors` via `acquisitionCue` —
    /// a different surface entirely. "Enable camera access" was a paraphrase of the line above.
    /// The wrong list mattered because it is a claim about how LONG the longest sentence is,
    /// which is exactly what a reader checks before deciding whether wrapping is safe. Verified
    /// by grep: `banner(` has three call sites in this file and no fourth.
    ///
    /// ⛔ It also said "`.system(size:)` without `relativeTo:`", which sends a reader hunting
    /// for an argument that does not exist — `Font.system(size:weight:design:)` has none.
    /// `relativeTo:` lives only on `Font.custom(_:size:relativeTo:)`; the fix is a change of
    /// FAMILY, not an added argument.
    ///
    /// ⚠️ THE DISTINCTION THAT MAKES THIS WORTH FIXING AHEAD OF ITS NEIGHBOUR. The strip below
    /// carries `.minimumScaleFactor(0.6)`, which reads like the same defect and is NOT: a scale
    /// factor is a fraction of the CURRENT size, so at AX3 those numbers still land larger than
    /// the default-size ones — the increase is capped, not cancelled. Worth revisiting (#353c)
    /// and a genuinely harder call, because the alternative on a 375 pt phone is the "…"
    /// truncation the founder complained about twice. This banner had no such trade: it can be
    /// MADE to wrap — it sits in a `VStack` with no fixed height, nothing downstream measures
    /// it, and the strip's `.lineLimit(1)` belongs to `strip`, not here. It could always have
    /// scaled.
    ///
    /// ⛔ "IT WRAPS FREELY" IS WHAT THIS SENTENCE SAID FOR ONE COMMIT, and the Nachlese
    /// thirty-odd lines below already calls that derivation weaker than it sounds — absence of
    /// a `lineLimit` is not presence of a wrap. Corrected HERE too rather than left to be
    /// contradicted from further down, because this is the paragraph a session reads when
    /// deciding whether the neighbouring `.minimumScaleFactor(0.6)` (#353c) can get the same
    /// treatment. It cannot, on this reasoning alone: that row is width-bound in a way this
    /// one is not.
    ///
    /// ⚠️ THE WEIGHT IS DELIBERATELY DROPPED — and this IS a visible de-emphasis, not the
    /// render-neutral cleanup the first version of this comment claimed.
    ///
    /// ⛔ THAT FIRST VERSION CITED #361 AND THE REFUTATION WAS THREE LINES ABOVE THE HELPER IT
    /// CITED. `EchoelTheme.font`'s own doc says, in bold: "`.font(.system(size:weight: .medium))`
    /// IS NOT THIS BUG and must not be 'cleaned up' with it: SF ships a real medium and renders
    /// it … do not conflate the two." The OLD spelling here was `.system(size: 11, weight:
    /// .medium)` — SF Medium, which reached the screen. So this is SF-Medium-11 → Atkinson-
    /// Regular-11: real strokes lost, not an imaginary weight tidied away. Writing it up as
    /// "resolves to Regular anyway" was a checkable-but-false premise of exactly the kind this
    /// file keeps paying for, drawing the one analogy the theme file forbids by name.
    ///
    /// The decision stands on its own terms: the brand family has no Medium, so the honest
    /// choices are Regular or `.semibold` (the Bold face). Regular is chosen because the
    /// emphasis this line needs is already carried twice over — by the semantic colour (warning
    /// amber at ≈7.9:1, success green at ≈9.6:1 over their own tinted fills) and by the icon
    /// beside it — and because the line now GROWS with the reader's setting, which buys back far
    /// more legibility than a weight step. If a device look says otherwise, `.semibold` is the
    /// one real alternative; `.medium` is not on the menu here whatever it looked like before.
    ///
    /// The icon moves with it for the same reason: an SF Symbol pinned at 10 pt beside text that
    /// now reaches AX5 would read as a speck. A custom `Font` sizes a symbol just as it sizes a
    /// glyph — `EchoelNumberPad` and `EchoelStudioView` already do this — so it scales in step.
    private func banner(_ text: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(EchoelTheme.font(10))
            Text(text)
                .font(EchoelTheme.font(11))
                // ⛔ #353d-NACHLESE: WITHOUT THIS THE SCALING FIX ABOVE COULD SILENTLY BECOME A
                // TRUNCATION BUG, and the guard as first written could not have told anyone.
                // A wrapping `Text` beside a `Spacer` in an `HStack` is exactly the shape where
                // SwiftUI can settle on one truncated line instead of wrapping, which is why
                // every other multi-line banner in this design system pins it — see
                // `nonStandardTuningBanner`, same icon + text + `Spacer` build, same modifier.
                // `BioStripView` had ZERO occurrences of it. The original rationale asserted
                // "it wraps freely" from the ABSENCE of a `lineLimit`, which is a different
                // and weaker claim.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .accessibilityLabel(text)
    }

    /// ⭐ #353c — THE SOURCE TAG STEPS ASIDE AT ACCESSIBILITY SIZES, and this is the one
    /// number-bearing row in the app where that matters most.
    ///
    /// THE MEASUREMENT, not a hunch: on a 375 pt phone this row carries the ⓘ, the driving dot,
    /// four dividers, FOUR metric cells and an 88 pt tag slot inside 375 − 24 pt of padding. The
    /// four cells share roughly 50 pt each. Every one of them holds a label, a value and a unit,
    /// and the whole row is `lineLimit(1)` with `minimumScaleFactor(0.6)` — so as Dynamic Type
    /// grows, the numbers do not grow with it. They shrink, down to 60 % of a 12 pt face, which
    /// is ~7 pt. The user who RAISED the text size is the one who ends up with the smallest
    /// numbers in the app. That is the defect, and it is invisible at the default size.
    ///
    /// The fix is the cheapest one that actually returns width: at an accessibility size the tag
    /// leaves the row and takes its fixed 88 pt slot with it, which is about 22 pt back per cell
    /// — a ~40 % wider cell, not a rounding difference. Nothing else changes.
    ///
    /// ⚠️ AT EVERY NON-ACCESSIBILITY SIZE THE LAYOUT IS BYTE-FOR-BYTE THE OLD ONE. That is the
    /// safety property this slice is built around: there is no simulator here, so the branch that
    /// every user sees today is the branch that is not touched. `dynamicTypeSize` is read in THIS
    /// leaf — never in an ancestor (the 10.76.50 freeze law); it is an environment value that
    /// changes when the user changes a setting, not a live signal, so it costs nothing.
    ///
    /// ⛔ WHY NOT `ViewThatFits`, which is the obvious tool: it picks the first candidate that
    /// fits, and `minimumScaleFactor` makes the one-row candidate ALWAYS report a fit — it
    /// shrinks instead of overflowing. The second candidate would never be chosen, and the guard
    /// would still be green. An explicit size threshold is checkable; a measurement that cannot
    /// fail is not.
    private var strip: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    metricsRow
                    // Trailing, so the tag stays where the eye already looks for it — same
                    // corner as before, one line down. No fixed width here: this row has the
                    // whole strip to itself, and pinning it would re-create the squeeze that
                    // moving it was meant to end.
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        sourceControl
                    }
                }
            } else {
                HStack(spacing: 6) {
                    metricsRow
                    sourceControl
                        .frame(width: 88, alignment: .trailing)
                }
            }
        }
        // lineLimit/scale/font BEFORE the sheets: these are ENVIRONMENT values, and sheet
        // content inherits the environment at the .sheet attachment point — with the old
        // order (sheets first, lineLimit after) every Text INSIDE the info sheets rendered
        // one line, shrunk to 60 %, truncated to "…" (founder, twice: "die Infos über HRV
        // kann man immer noch nicht lesen. Wegen den …"). The width fix in the sheet could
        // never cure that. Strip-only modifiers must sit INSIDE the sheet attachments.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        // ⛔ WAS `.system(size: 12, weight: .medium, design: .monospaced)` — SF Mono, the one
        // place in the app that showed a bio number in a face other than Atkinson (#363).
        // The SAME heart rate appears in `HeaderMonitors` and `BodyTempoField` as
        // `EchoelTheme.font(...).monospacedDigit()`, so a performer glancing between the
        // header and this strip read one value in two typefaces. Atkinson Hyperlegible is
        // bundled precisely because it is the accessibility-first face; opting the densest
        // numeric readout in the app OUT of it was backwards.
        //
        // The per-value `.monospacedDigit()` in `metric(label:value:unit:)` is what actually
        // stops the digits dancing — a tabular-figures request, which is the house idiom
        // (`HeaderMonitors` does exactly this). A monospaced DESIGN was never needed for
        // that; it also monospaced the labels and units, which nothing asked for.
        //
        // ⚠️ DEVICE-VISIBLE, and honestly so: Atkinson's advances are wider than SF Mono's at
        // the same size, so this strip gets tighter. `.minimumScaleFactor(0.6)` already
        // absorbs that, but "already absorbs it" is a claim about a layout engine, not a
        // sighting — check the strip on a 375 pt phone with the four metrics filled.
        .font(EchoelTheme.font(12))
        .sheet(item: $explain) { BioMetricInfoView(metric: $0) }
        .sheet(isPresented: $showGuide) { BioMetricsGuideView() }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // ⛔ WAS an inline `Color(red: 0.07, green: 0.07, blue: 0.09)` — the app's SECOND
        // panel grey, one step lighter than `EchoelTheme.surface` (0.055/0.055/0.070) and
        // nowhere justified (#363). Two greys for "a panel's fill" is the kind of drift that
        // reads as sloppiness without anyone being able to name what is wrong: the strip sat
        // a shade proud of every panel it neighbours.
        .background(EchoelTheme.surface)
        .foregroundStyle(EchoelTheme.text)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EchoelTheme.text.opacity(0.08))
                .frame(height: 1)
        }
    }

    /// The metrics themselves — equal-width cells that always fit the offered width, so a value
    /// changing digit-count (or the source tag toggling width) cannot reflow its neighbours or
    /// overflow the edge (the old "wobble"). Extracted from `strip` by #353c so both layouts
    /// share ONE definition: two copies of this row is how the compact and the accessibility
    /// version would silently drift apart, and only one of them is ever screenshotted.
    private var metricsRow: some View {
        HStack(spacing: 6) {
            infoButton
            drivingIndicator
            divider
            metricButton(label: "HR",  value: hrString,        unit: "bpm",   metric: .heartRate)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "HRV", value: hrvString,       unit: hrvUnit, metric: .hrv)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Br",  value: breathString,    unit: "/min",  metric: .breath)
                .frame(maxWidth: .infinity)
            divider
            metricButton(label: "Coh", value: coherenceString, unit: nil,     metric: .coherence)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Info affordance

    /// Makes the tap-to-learn discoverable: a muted ⓘ at the strip's leading edge that opens
    /// the overview of ALL bio numbers. (Each metric cell is also individually tappable for a
    /// deep-dive — the guide's subtitle says so.) Founder 2026-07-03: "HRV etc. soll erklärt
    /// werden" — the explanations existed but were invisible.
    private var infoButton: some View {
        Button { showGuide = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(EchoelTheme.dim)
                // The advertised tap-to-learn affordance was a bare 12 pt glyph —
                // nearly impossible to hit (AX audit 2026-07-09). Target ≥ the
                // strip's height; glyph unchanged.
                .frame(width: 32, height: 32)
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What these bio numbers mean")
        .accessibilityHint("Opens a plain-language guide to heart rate, HRV, coherence and breathing")
    }

    // MARK: - Activity light ("is my body driving this?")

    /// The one thing the strip answers FIRST (UI survey 2026-07-11 — all five target
    /// groups asked for it): is the body shaping the live sound right now? Honest, not
    /// decorative — GREEN only when a take is PLAYING *and* a fresh, real bio frame exists
    /// (so the body genuinely drives the running generative composition). A dim hollow ring
    /// = a real signal is present but nothing is playing (live, not driving). A faint ring =
    /// no live body. No animation (A11y / ≤3 Hz — the survey's Lena explicitly rejected a
    /// decorative pulse); colour alone carries the state. Accent green stays reserved for the
    /// live/playing bio state, which is exactly what this is.
    private var driving: Bool { transport.isPlaying && hasLiveSignal }

    private var drivingIndicator: some View {
        // Tap opens the same plain-language guide as the ⓘ (survey law #1: the light shows
        // ONE thing at a glance; the meaning is one tap away, not always on screen).
        Button { showGuide = true } label: {
            Group {
                if driving {
                    Circle().fill(EchoelTheme.success)
                } else if hasLiveSignal {
                    Circle().strokeBorder(EchoelTheme.dim, lineWidth: 1)
                } else {
                    Circle().strokeBorder(EchoelTheme.dim.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(width: 7, height: 7)
            .frame(width: 20, height: 20)      // 20 pt touch/hit slack; glyph stays 7 pt
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(driving
            ? "Your body is driving the sound"
            : (hasLiveSignal ? "Body signal live, not driving yet" : "No live body signal"))
        .accessibilityHint("Double tap to learn how your body shapes the sound")
    }

    // MARK: - Metric cells

    /// A metric cell you can tap to learn what it means. Plain button style keeps
    /// the compact strip look; carries an explicit VoiceOver label + hint.
    private func metricButton(label: String, value: String, unit: String?, metric m: BioMetric) -> some View {
        Button { explain = m } label: {
            metric(label: label, value: value, unit: unit)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(m.title), \(value)\(unit.map { " " + $0 } ?? "")")
        .accessibilityHint("Double tap to learn what this means")
    }

    private func metric(label: String, value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(EchoelTheme.dim)
            Text(value)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .foregroundStyle(EchoelTheme.dim)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(EchoelTheme.text.opacity(0.1))
            .frame(width: 1, height: 10)
    }

    // MARK: - Source control (live tag · measuring · one-tap pulse entry)

    /// The right end of the strip. FOUR honest states, no synthetic data ever:
    /// • a real signal is live → green source tag (HR / PPG / BLE…). Only a real,
    ///   fresh signal turns it green;
    /// • camera access denied → the one real door, the system Settings;
    /// • a read is in progress → live "Reading… / Connecting…" feedback;
    /// • nothing yet → EITHER a one-tap button that brings the body in, when the
    ///   host passed `onStartPulse` (only `BioSourceView` does, and its handler arms
    ///   the sensor alone), OR a static "No signal" tag when it did not.
    ///
    /// ⛔ THE THIRD BULLET USED TO SAY the no-signal state was "a one-tap button …
    /// so the most bio-looking element is the gateway to the instrument, not a dead
    /// end", full stop. That stopped being true for the app's only reachable mount
    /// with #234: in `EchoelStudioView`'s Bio panel the button was a "Read pulse"
    /// label that started the entire generative session, and it is gone. Corrected
    /// here rather than contradicted from the branch below — a comment that a newer
    /// comment has to argue against is the drift this file keeps paying for.
    @ViewBuilder private var sourceControl: some View {
        if hasLiveSignal {
            liveTag
        } else if cameraRPPG.permissionDenied, bus.freshBio() == nil {
            // UX-1: with access denied the camera can never start, so neither
            // "Reading…" nor "Read pulse" is honest — offer the one real door.
            // Raw fresh-frame gate (not hasLiveSignal): the .fallback demo is a
            // deliberate source choice, don't override it with a camera nag.
            openSettingsButton
        } else if measuring {
            measuringTag
        } else if onStartPulse != nil {
            startPulseButton
        } else {
            noSignalTag
        }
    }

    /// The fourth state, added with #234: no signal, and this strip is NOT the place to
    /// start one. It is not the "dead end" the doc above warns about — the Bio panel that
    /// mounts it sits on the front plate, with the labelled Start button in the same view.
    /// Naming that button here is what keeps it a signpost rather than a dead end.
    private var noSignalTag: some View {
        Text("No signal")
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
            .foregroundStyle(EchoelTheme.dim)
            .accessibilityLabel(Text("No body signal yet"))
            // #307: named "Create from Within" until the founder replaced that button with an
            // Ableton-style play triangle. A VoiceOver hint that names a control which is no
            // longer on screen is worse than no hint — it sends someone hunting.
            .accessibilityHint(Text("Press Play to start; your body then drives the sound."))
    }

    /// The honest replacement for the dead end: camera access is off, and the
    /// only fix lives in the system Settings — one tap takes the user there.
    private var openSettingsButton: some View {
        Button { openAppSettings() } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.slash").font(.system(size: 9))
                Text("Enable camera")
            }
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(EchoelTheme.warning.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
            .foregroundStyle(EchoelTheme.warning)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Camera access is off")
        .accessibilityHint("Opens Settings so you can allow camera access and read your pulse")
    }

    private var liveTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
            Text(sourceText)
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(EchoelTheme.success.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
        .foregroundStyle(EchoelTheme.success)
        .accessibilityLabel("Bio source: \(sourceText)")
    }

    private var measuringTag: some View {
        let amber = EchoelTheme.warning
        // ⛔ "Cover camera" IS ONLY TRUE FOR THE CAMERA. This tag shows whenever a session
        // runs without a live signal, and the host passes `measuring: running` — so with a
        // BLE strap or the Simulation selected it used to instruct the user to cover a lens
        // that has nothing to do with the reading. Pre-existing, but #234 made it the only
        // non-live state the Bio panel can show, so the wrong instruction became the whole
        // message. `cameraRPPG.isRunning` is the low-frequency "camera is the live source"
        // flag; `fingerDetected` is the 10 Hz one this leaf already reads, so no new churn
        // and no new observer (freeze rule).
        let camera = cameraRPPG.isRunning
        let finger = cameraRPPG.fingerDetected
        let caption: LocalizedStringKey = camera
            ? (finger ? "Reading…" : "Cover camera")
            : "Connecting…"
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 9))
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text(caption)
        }
        .lineLimit(1)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(amber.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall))
        .foregroundStyle(amber)
        // Same three-way split as the visible caption — a VoiceOver user must not be told to
        // cover a lens that is not the source either.
        .accessibilityLabel(camera
                            ? (finger ? Text("Reading your pulse")
                                      : Text("Cover the rear camera and flash to read your pulse"))
                            : Text("Waiting for your bio source to deliver a signal"))
    }

    /// The one-tap gateway to the live body, for a host that passes `onStartPulse`.
    /// (`EchoelStudioView`'s Bio panel no longer does — see the property's own note.)
    private var startPulseButton: some View {
        Button { onStartPulse?() } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill").font(.system(size: 9))
                Text("Read pulse")
            }
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(EchoelTheme.text.opacity(0.25), lineWidth: 1))
            .foregroundStyle(EchoelTheme.dim)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Read your pulse")
        .accessibilityHint("Starts the camera to read your heartbeat so your body drives the sound")
    }

    /// A real sensor (camera PPG / HealthKit / BLE / Watch / Oura) is publishing
    /// FRESH frames. A frozen reading (dropped strap, lifted finger, stalled Watch)
    /// expires after the freshness window, so the strip stops claiming a live body.
    private var hasLiveSignal: Bool {
        // Gate on `usableBio()` — the SAME per-source window the sound engine uses
        // (ModulationEngine.tick). The fixed-5 s `freshBio()` here made the strip
        // flicker to "No signal" for a Watch/HealthKit source that publishes only
        // every few minutes (its reading stays usable for 90 s and keeps driving
        // the music), so the live indicator now matches whether the body is
        // actually shaping the sound. A truly frozen source still expires.
        if let bio = bus.usableBio(), bio.source != .fallback { return true }
        return false
    }

    private var sourceText: String {
        if let bio = bus.usableBio(), bio.source != .fallback {
            return sourceLabel(bio.source)
        }
        return "No signal"
    }

    // MARK: - Formatting

    private var hrString: String {
        // While the camera is the live source, show the CALM display value (holds the last
        // confident reading through noisy patches) so this number matches the header monitor
        // and doesn't bounce. Music still uses the honest bus HR internally; other sources
        // (BLE/HealthKit) and the pre-lock phase fall back to the bus value.
        if cameraRPPG.isRunning, cameraRPPG.displayBPM > 0 {
            return EchoelDecimalText.string(cameraRPPG.displayBPM, decimals: 0)
        }
        guard let v = bus.latestBio?.heartRateBPM else { return "—" }
        return EchoelDecimalText.string(v, decimals: 1)
    }

    /// Physiologically plausible RMSSD window (ms). Camera rPPG's beat-to-beat
    /// timing is noisy and can inflate RMSSD to impossible values (e.g. 500+ ms,
    /// above the mean RR interval) — science-first, we show a real number only
    /// inside this window and "—" otherwise, rather than print a wrong figure.
    private static let plausibleHRVms: ClosedRange<Float> = 3...300

    /// True RMSSD in ms when the source provides a plausible reading; the
    /// normalized [0..1] value for sources that only publish that (HealthKit);
    /// "—" when the ms reading is physiologically impossible (noisy rPPG).
    private var hrvString: String {
        guard let bio = bus.latestBio else { return "—" }
        if Self.plausibleHRVms.contains(bio.hrvRMSSDms) {
            // Whole ms from 10 up ("HRV 15 ms", not "15.2"): the strip cell is the
            // narrowest surface in the app and the decimal was what pushed it into
            // "HRV 15.." truncation on small phones (founder video v173). Sub-10
            // readings keep one decimal — there the digit carries real information.
            // The FORMAT is a ternary, not a literal — which is exactly why the #267 sweep
            // missed this line while converting the one below it. A grep for
            // `String(format: "%` structurally cannot see it, so the strip would have shown
            // "HRV 8.4 ms" beside "coh 0,72". Use the same helper, choose the precision first.
            return EchoelDecimalText.string(bio.hrvRMSSDms,
                                            decimals: bio.hrvRMSSDms < 10 ? 1 : 0)
        }
        if bio.hrvRMSSDms == 0 && bio.hrvNormalized > 0 { return EchoelDecimalText.string(bio.hrvNormalized, decimals: 3) }
        return "—"
    }

    private var hrvUnit: String? {
        guard let bio = bus.latestBio, Self.plausibleHRVms.contains(bio.hrvRMSSDms) else { return nil }
        return "ms"
    }

    /// Physiologically plausible breathing-rate window (breaths/min). A camera pulse read
    /// does not derive respiration, so it publishes 0 — and "0.0 /min" is impossible (you
    /// can't breathe zero times a minute). Show a real number only inside the plausible
    /// window, otherwise "—" (honest: not measured), matching how coherence/HRV behave.
    /// The window itself now lives on `BioSampleFrame`, so this view, the modulation
    /// readout and the EchoelAI narration share one answer to "is there a breath
    /// reading" — they had started to drift apart. `BreathGuideView` still owns a
    /// FOURTH, narrower test (`source == .cameraPPG && breathRate > 0`); it agrees today
    /// only because `RespirationEstimator` clamps to 4…30, which sits inside this window.
    private var breathString: String {
        guard let bio = bus.latestBio, bio.hasMeasuredBreath else { return "—" }
        return EchoelDecimalText.string(bio.breathRate, decimals: 1)
    }

    /// Coherence is real only on sources with beat-to-beat RR (BLE / camera);
    /// HealthKit publishes 0 ("not available"). Show a measured value only for a
    /// FRESH frame whose coherence is > 0 — otherwise "—" (never "0.000", which
    /// would read as "incoherent" rather than "not yet / not available").
    private var coherenceString: String {
        guard let bio = bus.freshBio(), bio.coherence > 0 else { return "—" }
        return EchoelDecimalText.string(bio.coherence, decimals: 2)
    }

    private func sourceLabel(_ source: BioSource) -> String {
        switch source {
        case .oura:       return "Oura"
        case .healthKit:  return "Health"
        case .ble:        return "BLE"
        case .watch:      return "Watch"
        case .cameraPPG:  return "PPG"
        case .faceCam:    return "Face"
        case .fallback:   return "—"
        }
    }
}
#endif
