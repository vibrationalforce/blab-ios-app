//
//  BreathGuideView.swift
//  Echoelmusic — Studio
//
//  The visible "active half" of the coherence loop: a breathing guide. An
//  expanding/contracting circle paces the chosen BreathPattern; live coherence from
//  the bus is shown beside it so the body closes the loop the app measures
//  (HRVCoherence). Resonance (~6/min, no holds) is the default and recommended
//  technique; opt-in hold patterns (Box, 4-7-8) require acknowledging their
//  contraindications first. Drives the pure BreathPacer from a UI-rate loop (no
//  audio-clock coupling). Flash-safe by construction: the only motion is the breath
//  circle at ≤0.2 Hz — far under the 3 Hz WCAG limit — and it is disabled entirely
//  under Reduce Motion (textual guidance instead).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BreathGuideView: View {

    @Environment(BreathPacer.self) private var pacer
    @Environment(EngineBus.self) private var bus
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Once the user acknowledges the hold-safety card, don't re-prompt this session.
    @State private var acknowledgedHolds = false
    @State private var showHoldWarning = false
    /// True biofeedback: drive the ball from the camera-measured breath, not the pace.
    @State private var followMyBreath = false

    var body: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                Spacer(minLength: 8)
                breathCircle
                Text(followingMeasured ? "Breathe naturally" : pacer.instruction)
                    .font(EchoelTheme.font(22, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .accessibilityLabel(followingMeasured ? "Breathe naturally" : pacer.instruction)
                coherenceReadout
                Spacer(minLength: 8)
                patternControl
                followControl
                startStop
                contraindications
            }
            .padding(20)
        }
        .task(id: pacer.isRunning) { await driveTicks() }
        .onDisappear { pacer.stop() }
        .sheet(isPresented: $showHoldWarning) { holdWarningSheet }
    }

    // MARK: Tick driver (UI-rate; not the audio/pattern clock)

    private func driveTicks() async {
        guard pacer.isRunning else { return }
        var last = Date()
        while !Task.isCancelled && pacer.isRunning {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            pacer.tick(now.timeIntervalSince(last))
            last = now
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Breathing Guide")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(EchoelTheme.text)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(EchoelTheme.dim)
            }
            .accessibilityLabel("Close breathing guide")
        }
    }

    // MARK: Breath circle

    private var breathCircle: some View {
        // 0.45…1.0 of the guide ring; fixed mid-size under Reduce Motion.
        let scale = reduceMotion ? 0.75 : (0.45 + 0.55 * ballAmplitude)
        return ZStack {
            Circle()
                .strokeBorder(EchoelTheme.border, lineWidth: 1)
                .frame(width: 240, height: 240)
            Circle()
                .fill(EchoelTheme.accent.opacity(0.18))
                .overlay(Circle().strokeBorder(EchoelTheme.accent, lineWidth: 2))
                .frame(width: 220, height: 220)
                .scaleEffect(scale)
            if reduceMotion {
                Text("\(Int((ballAmplitude * 100).rounded()))%")
                    .font(EchoelTheme.font(26, .bold))
                    .foregroundStyle(EchoelTheme.text)
            }
        }
        .frame(height: 250)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: ballAmplitude)
        .accessibilityHidden(true)
    }

    // MARK: Live coherence (the measured half of the loop)

    private var coherenceReadout: some View {
        let c = bus.freshBio()?.coherence ?? 0
        return VStack(spacing: 4) {
            Text(verbatim: c > 0
                 ? "Coherence " + EchoelDecimalText.string(c, decimals: 2)
                 : "Coherence —")
                .font(EchoelTheme.font(15, .semibold))
                .foregroundStyle(c > 0 ? EchoelTheme.accent : EchoelTheme.dim)
            Text("Breathe with the circle. With a chest strap, watch coherence rise.")
                .font(EchoelTheme.font(12))
                .foregroundStyle(EchoelTheme.dim)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Pattern picker (resonance default; holds opt-in)

    private var patternControl: some View {
        VStack(spacing: 8) {
            Picker("Breathing pattern", selection: patternSelection) {
                ForEach(BreathPattern.curated) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.segmented)
            .disabled(pacer.isRunning)   // change pattern only while stopped
            HStack(spacing: 6) {
                Text(pacer.pattern.evidence)
                if pacer.pattern.hasHolds {
                    Text("• includes holds")
                        .foregroundStyle(EchoelTheme.accent)
                }
            }
            .font(EchoelTheme.font(11))
            .foregroundStyle(EchoelTheme.dim)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            // The measured-breath toggle below can never light up for a pattern paced outside
            // `RespirationEstimator.reportableRange` — say so here rather than letting the user
            // read a dead readout as their own technique failing. Derived, so it cannot drift
            // from the arithmetic (#435).
            if let note = pacer.pattern.measurementNote {
                Text(note)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.accent)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var patternSelection: Binding<String> {
        Binding(
            get: { pacer.pattern.id },
            set: { newID in
                guard let p = BreathPattern.curated.first(where: { $0.id == newID }) else { return }
                pacer.pattern = p
            }
        )
    }

    // MARK: True biofeedback — drive the ball from the measured breath

    /// A fresh camera breath measurement, if the rPPG is running and its respiratory
    /// signal is clear. CameraRPPGBioPublisher only reports breathRate > 0 when the
    /// RSA-derived breath passes its confidence gate, so this doubles as "available".
    private var measuredBreath: BioSampleFrame? {
        guard let f = bus.freshBio(), f.source == .cameraPPG, f.breathRate > 0 else { return nil }
        return f
    }

    /// True when we are actually showing the user's measured breath (toggle on AND a
    /// clear signal present), as opposed to the paced guide.
    private var followingMeasured: Bool { followMyBreath && measuredBreath != nil }

    /// Ball amplitude [0,1]: the MEASURED breath when following, else the paced guide.
    private var ballAmplitude: Double {
        followingMeasured ? Double(measuredBreath?.breathPhase ?? 0.5) : pacer.guidance
    }

    private var followControl: some View {
        VStack(spacing: 4) {
            Toggle(isOn: $followMyBreath) {
                Text("Follow my breath (camera)")
                    .font(EchoelTheme.font(13))
                    .foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            if followMyBreath && measuredBreath == nil {
                // For a pattern paced below `RespirationEstimator.reportableRange` this branch
                // can be the PERMANENT state with the camera already running (4-7-8 never
                // publishes a rate, and this mode gates on `breathRate > 0`) — so the bare
                // "Start the camera" instruction would be a standing falsehood there. Both
                // clauses are true in both cases (#435).
                Text(pacer.pattern.pacedRateIsReportable
                     ? "Start the camera to measure your breath."
                     : "Start the camera — at this pace it may not find a breath rate.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .multilineTextAlignment(.center)
            } else if followingMeasured {
                Text("Following your breath — let it slow and even out.")
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.accent)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Start / Stop (holds gated behind acknowledgement)

    private var startStop: some View {
        Button {
            if pacer.isRunning {
                pacer.stop()
            } else if pacer.pattern.hasHolds && !acknowledgedHolds {
                showHoldWarning = true       // must acknowledge hold safety first
            } else {
                pacer.reset()
                pacer.start()
            }
        } label: {
            Text(pacer.isRunning ? "Stop" : "Start")
                .font(EchoelTheme.font(16, .semibold))
                .foregroundStyle(pacer.isRunning ? EchoelTheme.text : EchoelTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(pacer.isRunning ? EchoelTheme.fill : EchoelTheme.text))
        }
    }

    // MARK: Safety copy (hold patterns show the stricter card)

    private var contraindications: some View {
        let lines = pacer.pattern.hasHolds
            ? BreathPattern.holdContraindications
            : BreathPacer.contraindications
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                Text("• " + line)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hold-safety acknowledgement (required before a hold session)

    private var holdWarningSheet: some View {
        ZStack {
            EchoelTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Before breath-holds")
                    .font(EchoelTheme.font(18, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                ForEach(BreathPattern.holdContraindications, id: \.self) { line in
                    Text("• " + line)
                        .font(EchoelTheme.font(13))
                        .foregroundStyle(EchoelTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    acknowledgedHolds = true
                    showHoldWarning = false
                    pacer.reset()
                    pacer.start()
                } label: {
                    Text("I understand — start")
                        .font(EchoelTheme.font(16, .semibold))
                        .foregroundStyle(EchoelTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .fill(EchoelTheme.text))
                }
                Button { showHoldWarning = false } label: {
                    Text("Cancel")
                        .font(EchoelTheme.font(15))
                        .foregroundStyle(EchoelTheme.dim)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - The reachable half: a coach strip inside the bio panel
//
//  #486. Founder 2026-08-07 asked for "Training für kohärentes Atmen" alongside the
//  chanting/humming/toning/singing half that #485 put on the mix board. The training
//  apparatus was already built twice over — `BreathGuideView` above, and `MeditationView`
//  with duration, session recording and history — and BOTH are unreachable.
//
//  It does NOT get a door, and that is a decision rather than an omission. The founder's
//  verbatim ruling (decisions.csv 2026-07-12) is *"Meditation View nicht extra. Alles
//  findet in der Main View statt und ist Teil des Produktionsprozesses."* A door to a
//  separate breathing screen is the exact thing that was refused. So the practice comes
//  INTO the main view: `bioPanel` already shows what the body is doing (`BioStripView`),
//  and this is the active half sitting directly under it.
//
//  WHY A SEPARATE `View` STRUCT AND NOT INLINE CODE IN `bioPanel` — this is load-bearing,
//  not tidiness. `pacer.guidance` is rewritten ~30×/s by the tick loop. Read from inside
//  `EchoelStudioView.body` (which is what an inline `@ViewBuilder` fragment does) it would
//  register the whole root body as a 30 Hz observer and tear down every open `.menu`
//  Picker of the instrument — the 10.76.41/50 freeze, at three times the rate that caused
//  it. A `View` struct is a real observation boundary: only this leaf rebuilds.
//
//  DELIBERATELY NOT HERE, each for a reason:
//  · No coherence readout. `BioStripView` renders coherence a few points above in the SAME
//    panel; a second one would be two definitions of one number (#416) inside one panel.
//    The measured half is present — it is just not this view's job.
//  · No pattern picker and no hold-acknowledgement card. This strip paces resonance ONLY
//    (`BreathPacer`'s own safety law: "the UI must keep it preselected, never auto-select a
//    hold pattern"), so `start` forces `.resonance`. With no holds reachable from here, the
//    acknowledgement gate cannot be bypassed by this surface.
//    ⛔ THE FIRST DRAFT JUSTIFIED THAT FORCING WITH A SENTENCE CONTAINING ITS OWN
//    REFUTATION — "rather than trusting whatever the doorless full-screen guide may have
//    left in the shared pacer". A DOORLESS surface cannot leave anything. Measured: exactly
//    three writers of `pacer.pattern` exist in `Sources/` — `BreathGuideView`'s picker
//    (reachable only from `BioSourceView`, which has ZERO instantiations), `MeditationView`
//    (reachable only via `showMeditation`, which has no setter at all), and this line. No
//    reachable path today can hand this strip a hold pattern. The forcing is defence for the
//    day one of those is re-doored, and that is a good reason to keep it — it is what lets
//    this surface honestly omit the acknowledgement gate — but it is not the stated one.
//  · No copy of its own safety text. It renders `BreathPacer.contraindications`, the shared
//    constant, so the wording cannot drift from the guide above — and it renders them
//    UNCONDITIONALLY, matching `BreathGuideView`. The first draft hid them while running,
//    on the strength of the constant's own doc ("shown BEFORE a session"). Read the four
//    lines instead of the doc: "breathe gently, never strain" and "stop if you feel dizzy"
//    are DURING-session instructions, and the second is the only one naming an adverse
//    event. Hiding "stop if you feel dizzy" at the moment it applies inverts its purpose,
//    and it took the CLAUDE.md-mandated "self-observation, not medical diagnosis" line with
//    it. The secondary argument — "by then they have been read" — was an assumption about
//    the user, not a fact: nothing stops anyone pressing Start immediately.
//
//  HONEST LIMIT: the guide stops when the panel closes (`onDisappear`). You cannot breathe
//  along with the panel collapsed. That is the safe direction — a pacer running invisibly
//  is a state the user cannot see or stop — but it IS a limit, not an oversight.
//  ⚠️ AND `onDisappear` DOES NOT COVER EVERYTHING. It fires when the user switches chips
//  (`dropdownContent` is a `switch`, so the subtree is destroyed), but SwiftUI does NOT fire
//  it for a view behind a presented `.sheet`/`.fullScreenCover`, and `EchoelStudioView`
//  carries 14 of those. Opening one leaves the pacer ticking with its only Stop button
//  unreachable — a milder form of the very state the guard stands against. Self-resolving on
//  dismiss, so it is named here rather than fixed with scene-phase machinery.
//  ⚠️ REDUCE MOTION IS HONOURED AT A COARSER GRAIN THAN THE GUIDE ABOVE, and that is stated
//  rather than papered over: `BreathGuideView` keeps a live percentage inside its static
//  circle, so a Reduce Motion user still gets continuous pacing. Here only
//  `pacer.instruction` remains, and it changes at phase boundaries only (every 4 s / 6 s) —
//  you know WHETHER to breathe in, not WHERE you are in the breath. Not a safety defect; a
//  parity gap, and closing it is its own decision (a number changing ~30×/s inside a 56 pt
//  circle is not obviously the right accommodation for someone who asked for less motion).
@MainActor
struct BreathCoachStrip: View {

    @Environment(BreathPacer.self) private var pacer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                breathCircle
                VStack(alignment: .leading, spacing: 2) {
                    Text(pacer.isRunning ? pacer.instruction : "Coherent breathing")
                        .font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    // ⛔ BOTH CAPTIONS WERE REWRITTEN AFTER REVIEW, and the running one was the
                    // worse of the two. It said "The numbers above are your body answering" —
                    // an ASSERTION, ungated on any measurement existing. `start` paces; it does
                    // not start the camera, and `BioStripView` renders "—" for all four metrics
                    // with no source. The reachable sequence is: open Bio → Start → read "your
                    // body answering" over four em-dashes. That is precisely the state an App
                    // Store reviewer lands in (no strap, no HealthKit grant, rPPG acquisition
                    // fragile per #304/#410/#484), and it is the lying-control class #435/#480
                    // retracted. "Watch" invites; it cannot be false.
                    //
                    // The stopped one said "the pace the heart-rate numbers above respond to
                    // most", which this app's OWN cited copy contradicts (`BioScienceInfo`:
                    // "The exact best pace is individual — usually between 4.5 and 7 breaths per
                    // minute … Echoelmusic paces and measures it; it does not prescribe it").
                    // Three defects in one clause: it collapsed a population generalization onto
                    // THIS user, it named the one displayed metric that does NOT peak at 0.1 Hz
                    // (mean HR in bpm — what peaks is the AMPLITUDE of the oscillation, i.e.
                    // HRV and coherence), and it dropped the hedge the cited entry carries on
                    // purpose. It also named a second curated pattern: `.resonance` (4 s in /
                    // 6 s out) is not `.coherent` (5/5), so the title and the caption were
                    // saying two different names for one thing. The technique is described
                    // instead of named.
                    Text(pacer.isRunning
                         ? "Follow the circle. Watch HRV and coherence above as you settle."
                         : "Paces about 6 breaths a minute, with a longer exhale than inhale. Heart-rate swings usually grow largest near this pace — watch HRV and coherence above. Your own best pace is individual.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                startStop
            }
            // UNCONDITIONAL — see the header. Two of these four lines are DURING-session
            // instructions, one of them the only line naming an adverse event, and the fourth
            // is the CLAUDE.md-mandated self-observation disclaimer. Gating them on
            // `!pacer.isRunning` hid all four at the moment two of them apply, and inserted
            // ~7 wrapped lines into the layout on every Start/Stop — the #382 shove, in the
            // panel #382 was written about, landing on "Open Routing" and the Health opt-in
            // below. `BreathGuideView` renders its own copy unconditionally; this matches it.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(BreathPacer.contraindications, id: \.self) { line in
                    Text("• " + line)
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: pacer.isRunning) { await driveTicks() }
        .onDisappear { pacer.stop() }
    }

    // MARK: Transport

    private var startStop: some View {
        Button {
            if pacer.isRunning {
                pacer.stop()
            } else {
                // UNCONDITIONAL, not `if pacer.pattern.hasHolds` — see the header note.
                // The conditional form left `.coherent` (5 s/5 s) untouched, so a re-doored
                // guide could hand this strip a pattern the caption does not describe. Both
                // pace 6.0/min so there is no rate hazard; the caption is the thing that would
                // become false, and forcing costs nothing because `reset()` runs on the next
                // line anyway. `pattern`'s `didSet` resets the cycle, so this can never land
                // the user mid-breath.
                //
                // ⚠️ It silently discards a pattern chosen on another surface. Safe direction
                // (this surface may not pace holds), but it IS a cross-surface mutation, and
                // the day either full-screen guide is re-doored it needs a notice — together
                // with the other half this does not cover: if a re-doored host were ALREADY
                // running, mounting this strip gives `BreathPacer` two tickers, and it is
                // timer-free by design (`tick(dt)` accumulates), so the paced rate DOUBLES.
                // That needs a single owner or a monotonic `tick(at:)`, not a `Timer`.
                pacer.pattern = .resonance
                pacer.reset()
                pacer.start()
            }
        } label: {
            Text(pacer.isRunning ? "Stop" : "Start")
                .font(EchoelTheme.font(12, .semibold))
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12)
                // `minHeight`, not `height`, deliberately: #262 made chrome heights into
                // MINIMUMS so a large Dynamic Type setting can grow the label instead of
                // clipping it.
                //
                // ⛔ THE FIRST DRAFT PICKED 34 AND OMITTED `contentShape`, justifying the
                // number by "the neighbouring Open Routing button one row down still pins 34".
                // That is the #485 mistake one commit later, with the same shape of wrong
                // reference: the neighbour has the same missing `contentShape` and has simply
                // never been audited. Without it the `.plain` style hit-tests the LABEL'S
                // GLYPH RUN (~15–17 pt measured in #485), so the frame grows the layout and
                // not the target — under WCAG 2.5.8's 24 pt floor, never mind HIG's 44. The
                // right precedent for a panel button is #394's loudness Reset: 44 AND a
                // content shape. `TapTargetFloorTests` is a pinned list rather than a sweep,
                // so nothing would have gone red.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pacer.isRunning ? "Stop breathing guide" : "Start breathing guide")
        .accessibilityHint("Paces about six breaths a minute while this panel is open.")
    }

    /// UI-rate driver. Identical in shape to `BreathGuideView.driveTicks` on purpose: the
    /// pacer is pure and timer-free, so every host ticks it from its own loop.
    private func driveTicks() async {
        guard pacer.isRunning else { return }
        var last = Date()
        while !Task.isCancelled && pacer.isRunning {
            try? await Task.sleep(for: .milliseconds(33))
            let now = Date()
            pacer.tick(now.timeIntervalSince(last))
            last = now
        }
    }

    // MARK: Circle
    //
    // Flash-safe by construction: one breath cycle is ~10 s, so this moves at ~0.1 Hz —
    // more than an order of magnitude under the 3 Hz WCAG ceiling — and it does not move at
    // all under Reduce Motion, where the instruction text carries the pacing instead.

    private var breathCircle: some View {
        let amp = pacer.guidance
        let scale = reduceMotion ? 0.75 : (0.45 + 0.55 * amp)
        return ZStack {
            Circle()
                .strokeBorder(EchoelTheme.border, lineWidth: 1)
                .frame(width: 56, height: 56)
            Circle()
                .fill(EchoelTheme.accent.opacity(0.18))
                .overlay(Circle().strokeBorder(EchoelTheme.accent, lineWidth: 2))
                .frame(width: 50, height: 50)
                .scaleEffect(scale)
        }
        .frame(width: 56, height: 56)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: amp)
        .accessibilityHidden(true)
    }
}
#endif
