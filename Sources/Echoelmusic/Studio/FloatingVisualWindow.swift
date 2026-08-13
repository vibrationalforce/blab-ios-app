#if canImport(SwiftUI) && canImport(MetalKit) && canImport(UIKit)
import SwiftUI

// FloatingVisualWindow.swift
// Echoel — the immersive visual as a FLOATING, resizable, show/hide window (founder
// 2026-07-02: "als kleines Fenster flexibel groß ein- und ausblendbar machen …
// interessanter aber weniger komplex von den Einstellungen"). The core product is the
// bio-reactive MUSIC; the visual rides along as a calm picture-in-picture you can move,
// grow (S/M/L) and dismiss — no VJ sliders here (the deep controls stay in Studio).
//
// Render safety: this is a LEAF overlay. Its body reads only LOW-frequency @State
// (size, drag position) — never a ~10 Hz bio value — so it can float over any surface
// without rebuilding the surface tree / freezing an open menu (freeze rule). The real
// `MetalBioView` pulls the live bio itself inside its `draw(in:)` loop (off the SwiftUI
// graph). Only ONE `MetalBioView` renders app-wide at a time (GPU rule): this window is
// the single Metal path at the WorkspaceView root.

/// A finished MP4 clip to share (Identifiable so `.sheet(item:)` can present it).
private struct RecordedClip: Identifiable {
    let id = UUID()
    let url: URL
}

/// On-screen recording feedback: a red dot + "REC m:ss" elapsed, ticking once a second.
/// Small rounded chip (not a pill) per Uncodixfy; drawn over the visual while recording.
private struct RecordingBadge: View {
    let start: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, start.map { context.date.timeIntervalSince($0) } ?? 0)
            HStack(spacing: 5) {
                Circle().fill(EchoelTheme.recording).frame(width: 7, height: 7)
                Text("REC \(timeString(elapsed))")
                    .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
            .padding(8)
        }
        .accessibilityLabel("Recording")
    }

    private func timeString(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

/// A COMPACT position/loop readout for the Visual Instrument's TOP BAR (founder 2026-07-07:
/// "sowas in klein" + "Das muss mit nach oben in die Leiste"). Mirrors `TransportPositionView`
/// (bar.beat.step + a slim loop-progress capsule) at a smaller size. Its OWN leaf so the ~10 Hz
/// `transport.position` read stays confined here and never rebuilds the floating window (freeze
/// rule); reads only low-frequency `loopBars` besides.
@MainActor
private struct MiniTransportView: View {
    @Environment(Transport.self) private var transport
    // Default MUST match the semantic owner EchoelStudioView.loopBars (= .eight,
    // founder: 8-bar produce-able phrase) — @AppStorage defaults are per-declaration,
    // so a diverging copy lies on fresh installs until the key is first written
    // (H15-LOOPBARS).
    @AppStorage(StudioDefaultKeys.loopBars.key) private var loopBars: LoopBarLength = StudioDefaultKeys.loopBars.value

    var body: some View {
        let pos = transport.position
        let bars = max(1, loopBars.rawValue)
        let barInLoop = pos.bar % bars
        let sixteenth = pos.step % Transport.stepsPerBeat
        let loopFraction = Double(barInLoop * Transport.stepsPerBar + pos.step)
            / Double(bars * Transport.stepsPerBar)
        return HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 34, height: 3)
                Capsule().fill(transport.isPlaying ? EchoelTheme.accent : Color.white.opacity(0.5))
                    .frame(width: 34 * max(0.02, loopFraction), height: 3)
            }
            Text(String(format: "%d.%d.%d", barInLoop + 1, pos.beat + 1, sixteenth + 1))
                .font(EchoelTheme.font(10).monospacedDigit())
                .foregroundStyle(.white)
            Text("\(barInLoop + 1)/\(bars)")
                .font(EchoelTheme.font(9).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loop position")
    }
}

@MainActor
struct FloatingVisualWindow: View {

    /// Show/hide — owned by WorkspaceView (persisted there), toggled from the header.
    @Binding var isPresented: Bool

    /// Honour the system Reduce Motion setting here too (the fullscreen path already did) —
    /// otherwise the floating visual keeps animating for a user who asked motion to stop.
    /// Accessibility + consistency parity fix (visuals audit 2026-07-03).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MP4 capture (founder 2026-07-02: "WAV und MP4 sind die Formate der Wahl"). The
    // window's MetalBioView is the single Metal path, so it is the one capture instance;
    // tapping record writes the bio-reactive visual (+ the live audio) to an .mp4 to share.
    #if canImport(AVFoundation)
    @Environment(VisualRecorder.self) private var recorder
    @Environment(AudioEngine.self) private var audioEngine
    /// For idle-tone colour + entrainment pulse parity with the fullscreen visual (audit #5:
    /// the floating window fell back to C4 and ignored an ARMED entrainment). Both reads are
    /// LOW-frequency (user-set toggles/keys) — safe in this leaf body per the freeze rule.
    @Environment(PolySynthVoice.self) private var synth
    /// The play surface's DEDICATED voice (own patch + position morph; never steals
    /// from the generative bed). Falls back to the shared voice if absent.
    @Environment(\.touchSynth) private var touchSynth
    /// Position-morph amount for the play surface (shared key with the Studio panel).
    @AppStorage(StudioDefaultKeys.touchMorphDepth.key) private var touchMorphDepth = StudioDefaultKeys.touchMorphDepth.value
    /// Note-name spelling for the Field's cell labels (#232 E). A user setting, so a
    /// low-frequency read — but it is read HERE and passed down rather than read inside the
    /// UIKit surface, because a draw-time `UserDefaults` read would not know when to redraw.
    @AppStorage(StudioDefaultKeys.noteNaming.key) private var noteNamingRaw = StudioDefaultKeys.noteNaming.value
    // For a fitting MP4 name (founder: "Session Recording für video und auch passender
    // Name") — same convention as the WAV: Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4.
    @Environment(SessionContext.self) private var session
    @Environment(Transport.self) private var transport
    @AppStorage(StudioDefaultKeys.genre.key) private var genre: MusicStyle = StudioDefaultKeys.genre.value
    /// Delivery loudness target, shared with the Master panel — read here so this
    /// window's WAV export obeys the same setting as the Studio export buttons.
    @AppStorage(StudioDefaultKeys.loudnessTarget.key)
    private var loudnessTargetRaw = StudioDefaultKeys.loudnessTarget.value
    @State private var recordedClip: RecordedClip?
    /// When recording started — drives the on-screen REC elapsed time.
    @State private var recordStart: Date?

    // WAV audio capture (founder 2026-07-07: "ein wav Aufnahme Knopf wäre auch im Visual
    // Instrument gut" + "Video und wav Aufnahme muss Natürlichkeit erkennbar sein"). The MP4
    // above muxes lossy AAC audio; this writes a LOSSLESS WAV of the same performance so the
    // organic, natural character of the bio-generative take survives (WAV = PCM; only a LUFS
    // gain is applied, never a lossy codec). Independent of the MP4 path — the MP4 grabs the
    // ring at stop, this uses RetroCapture's live-file write — so you can arm BOTH for one take.
    @State private var wavRecording = false
    @State private var wavRecordStart: Date?
    @State private var wavClip: RecordedClip?
    @State private var wavExporting = false
    #endif

    // Visual DESIGN (founder: "Visual Design muss möglich sein" + "Feinschliff, alles
    // User-optimiert"). EVERY design control the Visual panel exposes is now SHARED
    // (@AppStorage), so each live tweak shows in this window immediately — Look/blend and
    // the six energy/palette params. Single source of truth; no drift between panel + window.
    // Defaults: a rich look (Aurora, index 5) out of the box — "interessanter" than flat
    // Rings. ⛔ This line also RESTATED "saturation 0.82 (professional, not neon)" and #578
    // retracted both halves at the declaration (founder: "Bunter"). Restating a shared
    // default's VALUE in prose is #416 — it was the fifth spelling of this one number, and
    // the paragraph's own next sentence explains why that is self-defeating: the whole point
    // of binding `StudioDefaultKeys` is that there is nothing left to keep in sync by hand.
    // Kept IDENTICAL to EchoelStudioView's declarations so an absent key resolves to the
    // same value in both views (no drift before the user touches a control).
    @AppStorage(StudioDefaultKeys.visualStyle.key) private var visualStyle = StudioDefaultKeys.visualStyle.value
    @AppStorage(StudioDefaultKeys.visualStyleB.key) private var visualStyleB = StudioDefaultKeys.visualStyleB.value
    @AppStorage(StudioDefaultKeys.visualBlend.key) private var visualBlend = StudioDefaultKeys.visualBlend.value
    @AppStorage(StudioDefaultKeys.visualIntensity.key) private var visualIntensity = StudioDefaultKeys.visualIntensity.value
    @AppStorage(StudioDefaultKeys.visualDetail.key) private var visualDetail = StudioDefaultKeys.visualDetail.value
    @AppStorage(StudioDefaultKeys.visualMotion.key) private var visualMotion = StudioDefaultKeys.visualMotion.value
    @AppStorage(StudioDefaultKeys.visualSpread.key) private var visualSpread = StudioDefaultKeys.visualSpread.value
    @AppStorage(StudioDefaultKeys.visualHue.key) private var visualHue = StudioDefaultKeys.visualHue.value
    @AppStorage(StudioDefaultKeys.visualSaturation.key) private var visualSaturation = StudioDefaultKeys.visualSaturation.value

    // P5: the sky mixed into the IMAGE, per parameter (founder: "Klang und Bild
    // aber getrennte und mehrere Parameter"). Each visual influence crossfades the
    // user's base toward the weather target by its own intensity mixer — 0 = the
    // user's value unchanged (bit-identical when weather is off or a mixer is 0).
    // `current` changes only on the once-per-session fetch → render-safe.
    #if canImport(WeatherKit) && canImport(CoreLocation)
    @Environment(WeatherProvider.self) private var weatherProvider
    @AppStorage(StudioDefaultKeys.weatherEnabled.key) private var weatherEnabled = StudioDefaultKeys.weatherEnabled.value
    // Observe the IMAGE mixers so dragging one in the panel updates this visual
    // LIVE (they change only on a user drag → render-safe). Keys + defaults match
    // WeatherMood.Param, so the wiring and these reads agree on "unset = default".
    @AppStorage(WeatherMood.Param.hue.mixKey)        private var wxMixHue = WeatherMood.Param.hue.defaultIntensity
    @AppStorage(WeatherMood.Param.saturation.mixKey) private var wxMixSat = WeatherMood.Param.saturation.defaultIntensity
    @AppStorage(WeatherMood.Param.glow.mixKey)       private var wxMixGlow = WeatherMood.Param.glow.defaultIntensity
    @AppStorage(WeatherMood.Param.movement.mixKey)   private var wxMixMove = WeatherMood.Param.movement.defaultIntensity
    #endif

    /// The user-customizable SEQUENCE the look slider fades through (founder 2026-07-08:
    /// "man soll das was im slider passiert selbst customizen … mehr Optionen"). Persisted
    /// as a compact "3,5,7" string, SHARED with the main-menu customizer, parsed by
    /// LookBlendMap. Same key + default in both views so an absent key resolves identically —
    /// and since #227 that identity is DERIVED from `LookBlendMap.defaultSequence` rather than
    /// re-typed as `"3,5,7"` here and in `EchoelStudioView`. Two hand-written copies of one
    /// default is the bug `StudioDefaultKeys` exists to prevent.
    @AppStorage(LookBlendMap.storageKey)
    private var sliderLooksRaw = LookBlendMap.string(from: LookBlendMap.defaultSequence)
    private var sliderLooks: [Int] { LookBlendMap.sequence(from: sliderLooksRaw) }

    /// The Studio's key root — same key + default as EchoelStudioView, so the IDLE tint of
    /// this window matches the fullscreen visual's tonic instead of a hardcoded C4.
    @AppStorage(StudioDefaultKeys.rootIndex.key) private var rootIndex = StudioDefaultKeys.rootIndex.value
    /// The Studio's scale — the fullscreen play surface quantizes touches into
    /// this key (same key + default as EchoelStudioView). Low-frequency reads.
    @AppStorage(StudioDefaultKeys.scale.key) private var touchScale: Scale = StudioDefaultKeys.scale.value
    /// Fretboard grid over the play surface (founder 2026-07-08: "eine Art
    /// Griffbrett einblenden … Gitter mit Feldern in den passenden Farben").
    @AppStorage(StudioDefaultKeys.touchShowGrid.key)
    private var touchShowGrid = StudioDefaultKeys.touchShowGrid.value
    /// Slide-expression depths + glide for the play surface (founder 2026-07-08:
    /// "hin und her sliden verändert den Sound … Glide bzw. Portamento kann man
    /// auch einstellen"). Same keys + defaults as EchoelStudioView's menu.
    @AppStorage(StudioDefaultKeys.touchSlideVibrato.key) private var touchSlideVibrato = StudioDefaultKeys.touchSlideVibrato.value
    @AppStorage(StudioDefaultKeys.touchSlideChorus.key) private var touchSlideChorus = StudioDefaultKeys.touchSlideChorus.value
    @AppStorage(StudioDefaultKeys.touchGlide.key) private var touchGlide = StudioDefaultKeys.touchGlide.value
    @AppStorage(StudioDefaultKeys.touchLife.key) private var touchLife = StudioDefaultKeys.touchLife.value
    @AppStorage(StudioDefaultKeys.touchSyncStrength.key)
    private var touchSyncStrength = StudioDefaultKeys.touchSyncStrength.value
    @AppStorage(StudioDefaultKeys.touchSyncGrid.key)
    private var touchSyncGrid: TouchQuantizer.Grid = StudioDefaultKeys.touchSyncGrid.value

    /// ULTRASYNC as configured right now. The microtiming rides the EXISTING "Life"
    /// control rather than adding a third knob: Life already means "two identical taps
    /// never produce two identical notes", and the founder's ask was explicitly "auch
    /// microtime" — so extending that same word to WHEN a note falls is what it already
    /// promised. It only bites while Sync > 0, so Life alone behaves exactly as before.
    /// 8 ticks ≈ 8 ms at 120 BPM: a breath, not a stumble.
    private var touchQuantizer: TouchQuantizer {
        TouchQuantizer(grid: touchSyncGrid,
                       strength: Float(touchSyncStrength),
                       microtiming: Humanizer(timingTicks: Int((touchLife * 8).rounded()),
                                              velocityJitter: 0))
    }

    // SELF-PLAY (#224). Same keys the Field panel writes — this window is where the surface
    // actually lives, so it is where the dials become a `Params`.
    @AppStorage(StudioDefaultKeys.fieldAutoPlayMotion.key)
    private var fieldMotionRaw = StudioDefaultKeys.fieldAutoPlayMotion.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayDensity.key)
    private var fieldDensity = StudioDefaultKeys.fieldAutoPlayDensity.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlaySpan.key)
    private var fieldSpan = StudioDefaultKeys.fieldAutoPlaySpan.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayCentre.key)
    private var fieldCentre = StudioDefaultKeys.fieldAutoPlayCentre.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayBand.key)
    private var fieldBand = StudioDefaultKeys.fieldAutoPlayBand.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayBandDrift.key)
    private var fieldBandDrift = StudioDefaultKeys.fieldAutoPlayBandDrift.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayVoices.key)
    private var fieldVoices = StudioDefaultKeys.fieldAutoPlayVoices.value
    @AppStorage(StudioDefaultKeys.fieldAutoPlayPeriod.key)
    private var fieldPeriod = StudioDefaultKeys.fieldAutoPlayPeriod.value
    // The arp's rhythm (#253 A7, + `push` with #258/A2c). FIVE keys, not six: `density` stays the
    // Field's own row, because `FieldAutoPlay.arpTouches` overwrites the stored copy with it — a
    // second key for that one dimension would be two controls for one musical quantity.
    @AppStorage(StudioDefaultKeys.fieldArpRhythmCharacter.key)
    private var fieldArpCharacter: RoleRhythm.Character = StudioDefaultKeys.fieldArpRhythmCharacter.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmGate.key)
    private var fieldArpGate = StudioDefaultKeys.fieldArpRhythmGate.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmAccent.key)
    private var fieldArpAccent = StudioDefaultKeys.fieldArpRhythmAccent.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmEvolve.key)
    private var fieldArpEvolve = StudioDefaultKeys.fieldArpRhythmEvolve.value
    @AppStorage(StudioDefaultKeys.fieldArpRhythmPush.key)
    private var fieldArpPush = StudioDefaultKeys.fieldArpRhythmPush.value

    /// Self-play as configured right now, or `nil` when it is off.
    ///
    /// `nil` rather than a zero-density `Params` is deliberate: `nil` stops the clock, while
    /// a silent `Params` would leave a display link running to decide, sixty times a second,
    /// to do nothing. Off must cost nothing.
    ///
    /// An unrecognised stored motion also reads as OFF — the same direction as the rest of
    /// this app's lossy decoding, and the safe one for a generator: a build that renamed a
    /// case must not leave a user's field playing something they did not choose.
    private var fieldAutoPlay: FieldAutoPlay.Params? {
        guard let motion = FieldAutoPlay.Motion(rawValue: fieldMotionRaw) else { return nil }
        return FieldAutoPlay.Params(
            motion: motion,
            density: Float(fieldDensity),
            span: Float(fieldSpan),
            centre: Float(fieldCentre),
            band: Float(fieldBand),
            bandDrift: Float(fieldBandDrift),
            // Both clamped HERE as well as inside the generator: these come off disk as
            // Doubles a user or a corrupt payload can set to anything, and `Int(...)` of a
            // huge or non-finite Double TRAPS in Swift before any generator sees it.
            voices: Int(fieldVoices.clamped(to: 1...Double(FieldAutoPlay.maxVoices))),
            periodSteps: Int(fieldPeriod.clamped(to: 1...Double(FieldAutoPlay.maxPeriodSteps))),
            // `density` is NOT passed: `FieldAutoPlay.arpTouches` overwrites it with the Field's own
            // Density above, so a value here could only ever be a second, contradicting rate dial.
            // Clamped on the way in for the reason `RoleRhythm.Params.init(from:)` gives — the
            // memberwise init deliberately does not clamp, `hit(...)` clamps at use, and these three
            // arrive as Doubles off disk that a corrupt payload can set to anything.
            // Gate clamps to `minGate` and not 0, so this bound matches the range the panel's Note
            // length row offers. Both ends are already enforced inside `hit(...)`; having the two
            // sites state DIFFERENT floors (0.05 in the view, 0 here) was the shape that invites a
            // later reader to "fix" whichever one they find first.
            // `push` is clamped to 0…maxPush and NOT to the model's bipolar −maxPush…maxPush:
            // the row only offers the late half (see `StudioDefaultKeys.fieldArpRhythmPush` for
            // why), so a negative value here could only come from a hand-edited or corrupt
            // payload — and folding it to 0 matches exactly what `pushDelaySeconds` would do
            // with it anyway. Same both-ends-enforced-twice pattern as gate/accent/evolve above.
            arpRhythm: RoleRhythm.Params(character: fieldArpCharacter,
                                         gate: Float(fieldArpGate.clamped(
                                             to: Double(RoleRhythm.minGate)...1)),
                                         accent: Float(fieldArpAccent.clamped(to: 0...1)),
                                         push: Float(fieldArpPush.clamped(
                                             to: 0...Double(RoleRhythm.maxPush))),
                                         evolve: Float(fieldArpEvolve.clamped(to: 0...1))))
    }

    /// Snap size, persisted so the window reopens the size you left it.
    @AppStorage("visual.floating.size") private var sizeRaw = WindowSize.small.rawValue
    private var windowSize: WindowSize { WindowSize(rawValue: sizeRaw) ?? .medium }

    /// Card CENTRE in the parent's coordinate space. `nil` until first layout → defaults
    /// to the bottom-trailing dock (above the transport / bottom bar). Kept in @State
    /// (per-launch) — a low-frequency value, safe to read in this leaf's body.
    @State private var center: CGPoint?
    /// Drag anchor so a move continues from where the card currently sits.
    @State private var dragAnchor: CGPoint?
    /// Stable-resize dip (see `cycleSize`): true for the instant of the one-step
    /// size snap, easing back to full brightness right after.
    @State private var resizeDip = false

    enum WindowSize: Int, CaseIterable {
        case small, medium, large, fullscreen
        var next: WindowSize { WindowSize(rawValue: (rawValue + 1) % WindowSize.allCases.count) ?? .small }
        /// How much of the available box the PICTURE may claim along whichever edge binds.
        /// ONE number, not a width/height pair: the pair was two independent fractions
        /// (small used to be 0.38 × width by 0.30 × height), which made the card's shape a
        /// by-product of the container's shape — a landscape phone turned "small" into a
        /// ≈ 324 × 76 pt letterbox strip. The shape now comes from
        /// `FloatingVisualLayout.pictureAspect`; this only scales it. Fullscreen fills
        /// everything (short-circuited in `size(in:)`), so its value is unused.
        var fraction: CGFloat {
            switch self {
            case .small:      return FloatingVisualLayout.smallStep
            case .medium:     return FloatingVisualLayout.mediumStep
            case .large:      return FloatingVisualLayout.largeStep
            case .fullscreen: return 1.0
            }
        }
        var label: String {
            switch self {
            case .small:      return "Small"
            case .medium:     return "Medium"
            case .large:      return "Large"
            case .fullscreen: return "Fullscreen"
            }
        }
        var isFullscreen: Bool { self == .fullscreen }
    }

    private let margin: CGFloat = 12
    /// 44 pt — the HIG/WCAG minimum touch-target height (AX audit 2026-07-09: the
    /// bar's 28×22 pt buttons sat millimetres apart next to a drag handle; users
    /// hit record instead of resize). The glyphs stay small; the TARGETS are tall.
    private let handleHeight: CGFloat = 44

    /// Slider position ⇄ current look, STUFENLOS (founder 2026-07-07: "langem slider,
    /// der durch alle Modi stufenlos überblendet"). A continuous position crossfades
    /// between neighbouring looks via the renderer's style/styleB/blend (already eased
    /// in the shader path, so scrubbing MORPHS live). Mapping lives in LookBlendMap
    /// (pure, unit-tested, single source of the look order); writes the SHARED design
    /// keys so the main menu stays in sync.
    private var lookScrub: Binding<Double> {
        Binding(
            get: { LookBlendMap.position(a: visualStyle, b: visualStyleB, frac: Float(visualBlend), sequence: sliderLooks) },
            set: { v in
                let m = LookBlendMap.blend(at: v, sequence: sliderLooks)
                if visualStyle != m.a { visualStyle = m.a }
                if visualStyleB != m.b { visualStyleB = m.b }
                visualBlend = Double(m.frac)
            }
        )
    }

    /// Tonic frequency for the IDLE tint (when nothing sounds the renderer falls back to this;
    /// while music plays it pulls the live tone itself from the bus). Mirrors the fullscreen
    /// visual's mapping minus the per-take transpose (a @State there, irrelevant while idle).
    private var idleToneHz: Double {
        #if canImport(AVFoundation)
        return session.a4Hz * pow(2.0, (Double(60 + rootIndex) - 69.0) / 12.0)
        #else
        return 261.63
        #endif
    }

    /// Armed brainwave-entrainment visual pulse — same LOW-frequency guard as the fullscreen
    /// path (never the 10 Hz auto target), so the floating picture breathes with an armed
    /// entrainment exactly like the fullscreen one. 0 = none.
    private var entrainmentPulse: Double {
        #if canImport(AVFoundation)
        guard synth.entrainmentEnabled, let band = synth.entrainmentManualBand else { return 0 }
        return BioEntrainmentDirector.visualHz(for: band)
        #else
        return 0
        #endif
    }


    #if canImport(AVFoundation)
    /// ⭐ #311 NACHLESE — THE ONE HAZARD THE FIRST VERSION OF THAT SLICE CREATED, and the reason
    /// this wrapper exists rather than a plain `$binding`.
    ///
    /// `.opacity(0)` and `.allowsHitTesting(false)` do NOT suppress sheet presentation: a sheet
    /// presents in its own UIKit context and does not care that its host is invisible. Before
    /// #311, hiding the visual UNMOUNTED this window and took both share-sheet slots with it.
    /// Now they are permanently armed — and both are driven by ASYNC completions that outlive the
    /// hide (`recorder.stop()`, and the WAV export's `AVAssetExportSession`, seconds long).
    ///
    /// So this sequence became reachable, and was structurally impossible the day before: stop a
    /// take → hide the visual → open any panel/modal on the instrument → the export finishes → an
    /// INVISIBLE window presents a share sheet on top of it. That is the documented
    /// "two modals true at once → invisible tap-blocking layer" hang, arrived at without the user
    /// doing anything unusual. (`EchoelStudioView` also lowers this window's flag itself when it
    /// raises a fullscreen cover, so a share sheet over a cover was reachable too.)
    ///
    /// HELD, NOT DROPPED — and that distinction is the whole design. Gating the sheet on
    /// `isPresented` alone would silently swallow a finished export; returning `nil` for the ITEM
    /// while leaving the `@State` intact means the share simply waits and presents when the
    /// picture comes back. That is strictly better than the pre-#311 behaviour, where hiding
    /// destroyed the `@State` and the export was lost with no way to reach the file.
    private func heldWhileHidden(_ clip: Binding<RecordedClip?>) -> Binding<RecordedClip?> {
        Binding(get: { isPresented ? clip.wrappedValue : nil },
                set: { clip.wrappedValue = $0 })
    }
    #endif

    var body: some View {
        GeometryReader { geo in
            let full = windowSize.isFullscreen
            let sz = size(in: geo.size)
            // Fullscreen: pin to the exact centre (no drag/clamp). Else: the dragged/docked spot.
            let c = full
                ? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                : clamp(center ?? defaultCenter(in: geo.size, card: sz), in: geo.size, card: sz)
            card(size: sz, in: geo.size)
                .frame(width: sz.width, height: sz.height)
                .position(c)
                // Stable-resize dip: the picture eases back in AFTER the one-step
                // size snap (see cycleSize) — the single drawable reconfiguration
                // happens while dimmed, so no raw glitch frame is ever visible.
                .opacity(resizeDip ? 0.2 : 1)
        }
        // Fullscreen bleeds to the sides + under the home indicator, but KEEPS the top safe
        // area so the toolbar (change-look / record / exit) never hides under the notch —
        // you must still be able to manipulate the visual (founder). Floating sizes: no bleed.
        .ignoresSafeArea(edges: windowSize.isFullscreen ? [.bottom, .horizontal] : [])
        // ⚠️ NO LONGER THE THING THAT FADES, and left in place deliberately rather than
        // deleted. Since #311 this window is never inserted or removed — `WorkspaceView`
        // mounts it unconditionally and animates its `.opacity(...)` instead — so a
        // transition, which only runs on insertion/removal, has nothing to run on. The
        // show/hide fade the player sees comes from the two `withAnimation` blocks that
        // toggle the visibility flag (the header monitor button and this window's own close
        // button). Kept because it is the correct modifier the day anything conditionally
        // mounts this window again, and because deleting it would read as "the fade was
        // removed" when the fade is exactly where it was.
        .transition(.opacity)
        #if canImport(AVFoundation)
        .sheet(item: heldWhileHidden($recordedClip)) { clip in ShareSheet(url: clip.url) }
        .sheet(item: heldWhileHidden($wavClip)) { clip in ShareSheet(url: clip.url) }
        #endif
    }

    // MARK: - Toolbar controls (position readout + WAV record)

    #if canImport(AVFoundation)
    /// Lossless-WAV record button + live elapsed time, sized to sit in the top bar next to the
    /// video button. Distinct waveform glyph so it reads as AUDIO vs. the video glyph (founder:
    /// both recorders must be recognizable).
    @ViewBuilder private var wavRecordControl: some View {
        HStack(spacing: 5) {
            if wavRecording && audioEngine.retroCapture.writeFailed {
                // The take stopped reaching disk (a full volume, a revoked container).
                // Showing the running clock here would be the lying-control class: the
                // number would keep climbing while nothing more is being written. Say it
                // instead, in the one place the performer is already looking.
                Text("WAV FAILED")
                    .font(EchoelTheme.font(10, .semibold))
                    // `danger`, NOT `recording`: this is the one red in the bar that means
                    // "something went wrong", and it sits two lines from the red that means
                    // "a take is running". Same colour today, opposite messages — the token
                    // names are what keep them separable if either is ever retuned.
                    .foregroundStyle(EchoelTheme.danger)
            } else if wavRecording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, wavRecordStart.map { context.date.timeIntervalSince($0) } ?? 0)
                    Text("WAV \(recTimeString(elapsed))")
                        .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            } else if wavExporting {
                Text("WAV …")
                    .font(EchoelTheme.font(10, .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Button { toggleWavRecording() } label: {
                Image(systemName: wavRecording ? "stop.circle.fill" : "waveform.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(wavRecording ? EchoelTheme.recording : (wavExporting ? EchoelTheme.dim : EchoelTheme.text))
                    .frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .disabled(wavExporting)
            .accessibilityLabel(wavRecording ? "Stop WAV audio recording" : "Record lossless WAV audio")
            .accessibilityValue(wavRecording && audioEngine.retroCapture.writeFailed
                                ? "Writing to disk failed" : "")
        }
    }

    private func recTimeString(_ s: TimeInterval) -> String {
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
    #endif

    // MARK: - Card

    /// The visual base with the sky mixed in per parameter (P5). Weather off, no
    /// snapshot yet, or every mixer at 0 → returns the user's values untouched.
    private func weatheredVisuals()
        -> (hue: Double, saturation: Double, intensity: Double, motion: Double) {
        #if canImport(WeatherKit) && canImport(CoreLocation)
        guard weatherEnabled, let snap = weatherProvider.current else {
            return (visualHue, visualSaturation, visualIntensity, visualMotion)
        }
        let wx = WeatherMood.contribution(for: snap)
        func mix(_ base: Double, _ target: Float, _ intensity: Double) -> Double {
            Double(WeatherMood.blend(base: Float(base), target: target, intensity: Float(intensity)))
        }
        return (mix(visualHue, wx.hue, wxMixHue),
                mix(visualSaturation, wx.saturation, wxMixSat),
                mix(visualIntensity, wx.glowTarget, wxMixGlow),
                mix(visualMotion, wx.motionTarget, wxMixMove))
        #else
        return (visualHue, visualSaturation, visualIntensity, visualMotion)
        #endif
    }

    /// The picture layer of the window — the live renderer, OR a quiet stand-in while an
    /// external screen has the picture (#206).
    ///
    /// WHY A SWAP AND NOT AN `if` AROUND THE WHOLE WINDOW. The obvious move — hide
    /// `FloatingVisualWindow` while a beamer is connected — is WRONG here, and it took
    /// reading `card(...)` to see why: `TouchInstrumentView` is an OVERLAY on this layer,
    /// so hiding the window takes the phone's PLAY SURFACE with it. That is the precise
    /// opposite of the founder's ask ("es soll trotzdem vom iPhone aus spielbar sein").
    /// Swapping only the Metal layer honours BOTH halves: the beamer takes the image, the
    /// phone keeps the instrument. Every overlay (touch, REC badge, hint) is attached
    /// AFTER this call and is therefore untouched by the swap.
    ///
    /// GPU LAW (decisions.csv 2026-07-03): ONE `MetalBioView` app-wide — two live
    /// renderers starve the GPU and produced the documented black immersive.
    ///
    /// ⚠️ KNOWN GAP — and it is GUARDED, not merely documented. The capturing instance is
    /// THIS one (`capturesVideo: true`), so while the beamer has the picture, video
    /// capture has no source. A comment alone would have left a red REC pill counting up
    /// over a file whose writer session never started — a lost take, mid-show, from a
    /// control that claimed to be recording (the lying-control class, #164). The video
    /// button is therefore DISABLED while yielded (`videoCaptureYielded`). WAV audio
    /// capture is unaffected — it comes off the audio engine, not off this layer.
    /// Handing capture to the external instance is NOT a one-line change —
    /// `AVAssetWriter` is configured from the first frame's size, and plugging a projector
    /// in mid-recording would switch portrait phone frames to landscape beamer frames
    /// inside one file. That is its own slice.
    ///
    /// HONEST LIMIT: the hand-over is not instantaneous. `isConnected` flips before the
    /// external window is built and after it is torn down, so the ordering can only ever
    /// leave a GAP (a black beamer or a dark card for one layout pass), never a sustained
    /// overlap. A single frame of overlap during the SwiftUI update that reacts to the
    /// flag is possible and is not what the GPU law is about.
    #if canImport(AVFoundation)
    /// True when the phone has handed its renderer to an external screen and NO capture is
    /// already in flight — i.e. when starting a video recording would silently produce an
    /// empty file. Blocks the START only; a recording already running when the cable goes
    /// in stays stoppable. All reads are event-rate (a cable connect, a hide, a record tap), so
    /// this is not a freeze-law read.
    ///
    /// ⭐ `|| !isPresented` ADDED IN THE #311 NACHLESE, and the reason is that #311 created a
    /// SECOND — and far more common — way for `visualLayer` to drop the capturing renderer: the
    /// hidden branch. The rule this property encodes ("no renderer ⇒ no start, or you get a red
    /// REC pill counting up over a writer session that never began", the lying-control class
    /// #164) applied to that branch from the moment it existed, and the slice that added it did
    /// not extend the guard. It was blocked in practice only BY ACCIDENT — `allowsHitTesting`
    /// makes the button untappable while hidden — and a guard that holds by accident is exactly
    /// the kind this repo has had to re-learn.
    ///
    /// ⛔ WHAT THIS DID NOT COVER — HALF CLOSED BY #319, and the half that remains is named
    /// precisely because the first version of this note treated both as one problem. It said:
    /// "start a video recording, THEN hide the picture … the renderer is gone. Filed as its own
    /// slice; it needs a stop-or-pause decision, not another boolean here."
    ///  · The HIDE route is fixed, and it needed neither a stop nor a pause: the picture simply
    ///    keeps rendering while a take runs (`mustKeepRenderingForRecording`). Ending a capture
    ///    because a window was hidden would have been the wrong answer to a real defect.
    ///  · The EXTERNAL-SCREEN route is still open, and it is genuinely the harder one: the
    ///    phone yields its renderer because the external stage has one, so recording through it
    ///    means deciding which renderer feeds the writer — not adding a condition.
    private var videoCaptureYielded: Bool {
        (ExternalStageBridge.shared.isConnected || !isPresented) && !recorder.isRecording
    }
    #endif

    /// ⭐ #319 — THE ONE STATE IN WHICH HIDING THE PICTURE MAY NOT DROP THE RENDERER.
    ///
    /// `VisualRecorder` has exactly one frame source: `MetalBioView`'s draw loop calling
    /// `capture(from:in:device:)`. No renderer ⇒ no frames ⇒ the writer is never even built.
    /// Start a video take and then tap the header's monitor button and, before this property
    /// existed, the take silently became nothing: `recorder.isRecording` stayed true, the REC
    /// badge kept counting wall-clock seconds (it counts from a `Date`, not from what was
    /// written), the window went to `opacity(0)`, and `stop()` returned `nil` — a recording
    /// that recorded nothing, reported by no control anywhere, because the badge is invisible
    /// in that state too. `videoCaptureYielded` already forbids STARTING a take while the
    /// picture is yielded; it had no counterpart for yielding while one runs, and the
    /// `!isPresented` block below said so out loud without closing it.
    ///
    /// The fix is to keep rendering, not to stop or pause the take: the user asked to record
    /// the picture, so the GPU cost of rendering it is the cost they asked for, and hiding a
    /// window is far too casual a gesture to end a performance capture.
    ///
    /// ⛔ IT IS DELIBERATELY NOT `recorderIsRecording` ALONE. The external-stage branch below
    /// yields the phone's renderer BECAUSE the external screen has one — the "ONE MetalBioView
    /// app-wide" law. Forcing the local renderer back while an external stage is connected
    /// would run two, which is a worse defect than the one being fixed. So an externally-held
    /// picture still wins, and recording into it stays the open half of #319: it needs a
    /// decision about WHICH renderer feeds the writer, not another condition here.
    private var mustKeepRenderingForRecording: Bool {
        recorderIsRecording && !ExternalStageBridge.shared.isConnected
    }

    /// (No `#if canImport(UIKit)` inside: the WHOLE file is already gated on
    /// `canImport(UIKit)` at line 1, so an inner guard would imply a portability story
    /// this file does not have.)
    @ViewBuilder
    private func visualLayer(_ wv: (hue: Double, saturation: Double, intensity: Double, motion: Double)) -> some View {
        if !isPresented && !mustKeepRenderingForRecording {
            // ⭐ #311 — THE PICTURE IS OFF, THE WINDOW IS NOT. Since the founder's
            // *"die arps soll immer hörbar sein und nicht nur, wenn das Visual Fenster auf
            // ist"*, `WorkspaceView` no longer unmounts this window when the monitor button
            // hides it — it only makes it transparent and inert — because unmounting took the
            // `TouchInstrumentView` overlay (and with it the Field's self-play display link)
            // down as well. See the ⭐ #311 block at that mount site for the full chain.
            //
            // A permanently mounted window has to PAY for the work it used to avoid by simply
            // not existing, and this branch is the largest of those payments: a `MetalBioView`
            // behind an `.opacity(0)` would keep rendering at 60 fps for a picture nobody can
            // see. So the hidden state renders NOTHING — not the stand-in below, which exists
            // to explain where the picture WENT, and a hidden window has not sent its picture
            // anywhere. `Color.clear` keeps the card's geometry (and therefore the play
            // surface's normalized coordinates) exactly as they are when visible, so toggling
            // the picture cannot move a generated note. It is `Color.clear` and not
            // `EmptyView()` on purpose: only a shape accepts the `maxWidth/maxHeight: .infinity`
            // frame that the overlay measures itself against.
            //
            // ⛔ THE FIRST VERSION OF THIS BLOCK CALLED ITSELF "the ONE cost", AND THAT WAS
            // WRONG THE DAY IT WAS WRITTEN. Two more sat one branch away and were found by the
            // review, not by me: `MiniTransportView` kept rebuilding at the ~8 Hz step rate for
            // an invisible readout (now `&& isPresented`), and the two share `.sheet(item:)`
            // slots could present FROM a hidden window (now `heldWhileHidden`). Counting the
            // costs of a lifetime change is the work; asserting there is only one is how the
            // second and third stay invisible.
            //
            // The GPU law (ONE `MetalBioView` app-wide) is upheld more strictly than before,
            // not less: hidden now costs zero renderers where it used to cost zero by
            // teardown. (Since #319 there is ONE exception, and it is still one renderer:
            // a running video take keeps this branch out — see `mustKeepRenderingForRecording`.)
            Color.clear
        } else if ExternalStageBridge.shared.isConnected {
            // Not a placeholder for a missing feature — a deliberate statement of where
            // the picture went, so a performer who looks down does not think the visual
            // died. Solid fill, no animation: nothing here may flash (WCAG) and nothing
            // here may cost the GPU, which is the entire point of yielding.
            ZStack {
                Color.black
                VStack(spacing: 6) {
                    Image(systemName: "tv")
                        .font(.system(size: 22, weight: .regular))
                    Text("On external screen")
                        .font(EchoelTheme.font(12))
                }
                .foregroundStyle(EchoelTheme.dim)
            }
            .allowsHitTesting(false)   // the play surface above must get every touch
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Visual is showing on the external screen")
        } else {
            liveVisual(wv)
        }
    }

    /// The real renderer. `capturesVideo: true` → this instance feeds the shared
    /// VisualRecorder when recording (on the phone it is the only Metal path, so no
    /// double-capture). The look params are the SHARED design keys (style/blend + the six
    /// energy/palette params), so every tweak in the Visual panel shows here live.
    private func liveVisual(_ wv: (hue: Double, saturation: Double, intensity: Double, motion: Double)) -> some View {
        MetalBioView(capturesVideo: true, reduceMotion: reduceMotion, toneHz: idleToneHz,
                     intensity: Float(wv.intensity), ringDensity: Float(visualDetail),
                     motion: Float(wv.motion), spread: Float(visualSpread),
                     hueShift: Float(wv.hue), saturation: Float(wv.saturation),
                     style: visualStyle, styleB: visualStyleB, blend: Float(visualBlend),
                     entrainmentPulseHz: entrainmentPulse)
    }

    @ViewBuilder
    private func card(size: CGSize, in bounds: CGSize) -> some View {
        let wv = weatheredVisuals()
        VStack(spacing: 0) {
            handleBar(in: bounds, card: size)
            visualLayer(wv)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                #if canImport(UIKit) && canImport(AVFoundation)
                // PLAY SURFACE at EVERY size (founder 2026-07-07: "das Visual in ein
                // Multi-Touch Instrument umwandeln … wie mit den Fingern durchs Wasser" +
                // "in den anderen kleinen Ansichten auch spielbar"). Touches become
                // scale-quantized notes on the take's own synth patch (coherent by
                // construction) + water rings under the fingers — no dead-touch state to
                // explain, so no "only in fullscreen" hint is needed. Was fullscreen-only,
                // but the window is moved by the LOGO handle (not the visual body), so the
                // play layer never competes with drag/resize. UIKit-gated: the multi-touch
                // layer is a UIView (macOS CI has none).
                .overlay {
                    TouchInstrumentView(key: MusicalKey(root: rootIndex, scale: touchScale),
                                        synth: touchSynth ?? synth,
                                        quantizer: touchQuantizer,
                                        // Reads `position`/`tempo` — but INSIDE the
                                        // closure, i.e. at touch time, not while this
                                        // body evaluates. Capturing the reference is not
                                        // a property access, so this window does not
                                        // become an ~8 Hz observer (freeze law).
                                        musicalNow: { [transport] in
                                            guard let tick = transport.currentTick() else { return nil }
                                            let bpm = transport.tempo
                                            guard bpm > 0 else { return nil }
                                            return TouchMusicalTime(
                                                tick: tick,
                                                secondsPerTick: 60.0 / (bpm * Double(TimelineTime.ticksPerQuarter)))
                                        },
                                        reduceMotion: reduceMotion,
                                        morphDepth: touchMorphDepth,
                                        lifeDepth: touchLife,
                                        showGrid: touchShowGrid,
                                        slideVibrato: touchSlideVibrato,
                                        slideChorus: touchSlideChorus,
                                        glide: touchGlide,
                                        // Seed left at 0 deliberately: `.drift` is meant to
                                        // be an irregular FIGURE that returns, not noise
                                        // (see `FieldAutoPlay.Motion.drift`). A per-session
                                        // random seed would make the same settings sound
                                        // different every launch, which is the opposite of
                                        // what a saved setting means.
                                        autoPlay: fieldAutoPlay,
                                        autoPlaySeed: 0,
                                        noteNaming: NoteNaming(stored: noteNamingRaw))
                }
                #endif
                #if canImport(AVFoundation)
                // Recording feedback — a red REC pill with elapsed time, top-leading over
                // the visual so it's clear a clip is being captured.
                .overlay(alignment: .topLeading) {
                    if recorder.isRecording { RecordingBadge(start: recordStart) }
                }
                #endif
                // FIRST-RUN INVITATION (vision Step 2b, founder law #1: "app open, finger
                // on camera, in 3 seconds it lives"). The one gesture a new user can't
                // discover by feel — the camera is on the BACK, nothing on screen implies
                // it. A single, once-ever, self-fading whisper on the HOME (fullscreen) that
                // teaches the two core gestures, then never returns. Non-blocking
                // (allowsHitTesting false — never steals the first play-touch), flash-safe
                // (one opacity ramp, far under 3 Hz), reduce-motion aware. Own leaf → reads
                // only @AppStorage (freeze rule), no bio; no sheet added.
                .overlay(alignment: .bottom) {
                    if windowSize.isFullscreen {
                        InstrumentHintOverlay(reduceMotion: reduceMotion)
                            .padding(.bottom, 44)
                    }
                }
        }
        .background(Color.black)
        // No rounded corners / border in fullscreen — a true edge-to-edge picture.
        // ⛔ #483: the `12` here was a LITERAL until 2026-08-07 while the border two lines below
        // already read `EchoelTheme.radiusLarge`. The first draft of #483 folded the border and
        // left THIS one, because the guard's parser only sees a literal immediately after
        // `cornerRadius:` and a ternary hides it — i.e. the fold INTRODUCED the very split it
        // removes elsewhere: move the token to 14 and the stroke follows while the clip stays 12,
        // a visible hairline mismatch on the floating card. Found by the #483 reviewer.
        // The lesson is the parser's, not this line's: a value-based scan is only as wide as its
        // syntax, so the blind spots are named in `RadiusHasOneSpellingTests`' header instead of
        // being quietly relied on.
        .clipShape(RoundedRectangle(cornerRadius: windowSize.isFullscreen ? 0 : EchoelTheme.radiusLarge))
        .overlay {
            if !windowSize.isFullscreen {
                RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge).strokeBorder(EchoelTheme.border, lineWidth: 1)
            }
        }
        // Shadow is for the FLOATING card only. In fullscreen a blurred shadow forces an
        // OFFSCREEN render pass of the whole edge-to-edge Metal layer every frame, and that
        // extra compositing pass beats against the MTKView's synchronized present → the
        // fullscreen EchoelSynth "glitch" (founder 2026-07-09). Radius 0 + clear removes the
        // offscreen pass entirely; the modifier stays in the chain (params only) so toggling
        // fullscreen never changes view identity (no MTKView teardown / flash on toggle).
        .shadow(color: .black.opacity(windowSize.isFullscreen ? 0 : 0.35),
                radius: windowSize.isFullscreen ? 0 : 8,
                y: windowSize.isFullscreen ? 0 : 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating visual")
    }

    /// The only chrome: a drag handle + a size cycle + a close button. Deliberately no
    /// sliders (founder: fewer settings).
    private func handleBar(in bounds: CGSize, card: CGSize) -> some View {
        // #365: what actually FITS on this card, not what the size step would like to show.
        // `card` was already a parameter here — it was only ever read as a drag fallback,
        // so the bar has always known its own budget and never spent it.
        let fit = FloatingVisualLayout.chromeFit(
            cardWidth: card.width,
            isFullscreen: windowSize.isFullscreen,
            showsTransport: windowSize != .small && isPresented,
            wavBusy: wavRecording || wavExporting,
            videoBusy: recorderIsRecording)
        return HStack(spacing: 8) {
            // Drag ONLY by this handle — NOT the whole bar. A DragGesture spanning the whole
            // bar competed with the buttons: a tap with the slightest finger move started a
            // drag and cancelled the button tap, so "die Farbpalette ist nicht anklickbar"
            // (founder). Confining the drag here frees every toolbar button to receive taps.
            // The Echoel LOGO is the drag handle now (founder 2026-07-07: "im Visual
            // Fenster soll man das Logo sehen, oben links — anstatt das Burgermenü,
            // das keinen Nutzen hat"). Same 40-wide hit target + drag gesture as the
            // old ≡, so move-by-handle still works; the window is just branded now.
            EchoelLogoMark()
                .frame(width: 20, height: 20)
                .frame(width: 40, height: handleHeight)
                .contentShape(Rectangle())
                .gesture(
                    // MUST be `.global`: the default `.local` space measures the drag inside
                    // the handle's OWN frame, which MOVES as the window follows the drag — so
                    // the reported translation feeds back on itself and the window trembles
                    // while you move it (founder: "zittert, wenn man es verschiebt"). A fixed
                    // (screen) space gives a stable translation → smooth drag.
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            let base = dragAnchor ?? (center ?? defaultCenter(in: bounds, card: card))
                            if dragAnchor == nil { dragAnchor = base }
                            center = CGPoint(x: base.x + value.translation.width,
                                             y: base.y + value.translation.height)
                        }
                        .onEnded { _ in dragAnchor = nil }
                )
                .accessibilityLabel("Echoelmusic — drag to move the visual")
            Spacer(minLength: 0)
            // PRODUCER DOOR (founder 2026-07-22: "die Ebene der tighten Loops — Video
            // und wav — muss für mich als Produzent noch mit reindürfen"). In fullscreen
            // the studio chrome is hidden BENEATH this visual; this labeled "Studio" chip
            // drops out of fullscreen to the docked PiP size, revealing the instrument
            // controls with the visual kept as a small floating picture. (This comment used
            // to promise "timeline · clips · per-track instruments · video lanes · WAV
            // export"; the first four were deleted by #121 Slice 4 and #167, and the same
            // stale list had leaked into the button's VoiceOver hint below — where a user
            // could not see it was untrue.) The running session survives
            // (the chrome stayed MOUNTED, no teardown). A FIRST-CLASS door, not the tiny
            // resize glyph. Shown only in fullscreen; in the floating sizes the DAW is
            // already on screen. Neutral tokens (accent green stays reserved for live bio).
            if windowSize.isFullscreen, fit.studioChip {
                Button { exitToStudio() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Studio")
                            .font(EchoelTheme.font(12, .semibold))
                    }
                    .foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // WAS GERMAN, AND WAS LYING. It read "Studio — die Produzenten-Ebene öffnen"
                // / "Verlässt das Vollbild und zeigt Timeline, Clips und Spuren" — two
                // defects in two lines. German, in an app that ships in English and has no
                // localisation at all (zero `.strings` files), so a VoiceOver user hears one
                // sentence in another language. And it promised a timeline, clips and tracks:
                // all three were deleted (#121 Slice 4, #167). A hint that describes a screen
                // which no longer exists is worse than none — a blind user is told to expect
                // something that cannot appear, with nothing on screen to correct them.
                .accessibilityLabel("Studio")
                // ⚠️ "small" WAS REMOVED FROM THIS SENTENCE ON PURPOSE (#366). The docked size
                // is `.small` normally and `.large` while a take is recording, because the
                // small card cannot hold the running recorder's stop button. A hint that
                // names one of two outcomes is a hint that is wrong half the time, and the
                // half it is wrong in is the one where the user is mid-performance.
                .accessibilityHint("Leaves fullscreen and shows the instrument controls, with the field kept as a floating picture")
            }
            // Live LOOK slider, STUFENLOS (founder 2026-07-07: "langem slider, der durch
            // alle Modi stufenlos überblendet … während des Spielens"). Dragging morphs
            // continuously between the looks (crossfade in the renderer), no steps. The
            // founder's explicit "slider" ask overrides the EchoelValueField default:
            // this is a live VJ control over the visual, not a Studio parameter row.
            // Fullscreen only — that's where the bar has the width for a LONG slider.
            // A single-look sequence has no range to fade — guard against a degenerate
            // 0...0 Slider (founder's customizer can trim the sequence down to one look).
            if windowSize.isFullscreen, fit.lookSlider, LookBlendMap.maxPosition(for: sliderLooks) > 0 {
                Slider(value: lookScrub, in: 0...LookBlendMap.maxPosition(for: sliderLooks))
                    .tint(EchoelTheme.accent)
                    .frame(minWidth: 90, maxWidth: 170)
                    .accessibilityLabel("Visual look")
                    .accessibilityValue(LookBlendMap.nearestName(at: lookScrub.wrappedValue, sequence: sliderLooks))
            }
            // The transport-position readout + WAV control live UP HERE in the bar now
            // (founder 2026-07-07: "Das muss mit nach oben in die Leiste") — not floating over
            // the picture. Position is its own leaf (`MiniTransportView` reads Transport itself)
            // so its ~10 Hz updates never rebuild this window (freeze rule); display-only, so it
            // never steals a touch from the play surface.
            // The position readout needs a little width to stay legible — show it from Medium
            // up (and fullscreen). On the Small window it would crowd the record/resize buttons.
            // ⚠️ `&& isPresented` IS NOT REDUNDANT WITH THE `.opacity(0)` ABOVE THIS WINDOW, and
            // leaving it out made the #311 commit's own justification false. `MiniTransportView`
            // reads `transport.position`, which moves at the STEP rate (~8 Hz at 120 BPM). Since
            // the window is mounted permanently, an ungated instance keeps rebuilding ~8×/s while
            // playing, forever, to draw a capsule and two labels nobody can see — and because the
            // instrument-home seed opens at `.fullscreen`, `windowSize != .small` is the DEFAULT
            // state, so that was the common case and not an edge one. #311 argued "hidden costs no
            // renderer" while shipping exactly that cost one branch away. Not a freeze (this
            // window is a SIBLING of the instrument, not an ancestor — it cannot tear down a
            // Picker below), but wasted work that is invisible in every test and screenshot.
            if fit.miniTransport {
                MiniTransportView()
                    .allowsHitTesting(false)
            }
            // Fretboard grid toggle — shows which note lives where on the play
            // surface (fields in each note's physical colour). Display-only aid.
            if fit.gridToggle {
                Button { touchShowGrid.toggle() } label: {
                    Image(systemName: touchShowGrid ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(touchShowGrid ? EchoelTheme.accent : EchoelTheme.text)
                        .frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(touchShowGrid ? "Hide note grid" : "Show note grid")
            }
            #if canImport(AVFoundation)
            if fit.wavRecord { wavRecordControl }
            // MP4 VIDEO capture. Distinct "video" glyph (vs. the WAV button's waveform)
            // so the two recorders are recognizable at a glance (founder: "Video
            // und wav Aufnahme muss … erkennbar sein").
            //
            // ⚠️ DISABLED WHILE THE BEAMER HAS THE PICTURE (#206). The capturing renderer
            // is THIS window's `MetalBioView`, and `visualLayer` unmounts it while an
            // external screen is connected — so a "recording" started now would show a
            // red pill counting up and produce a file whose writer session never started.
            // A control that says it is recording while nothing is captured is the
            // lying-control class (#164), and losing a take mid-show is the worst place
            // to meet it. Blocking the START is one line; handing capture over to the
            // external instance is its own slice (`AVAssetWriter` fixes its dimensions on
            // the first frame). The guard deliberately does NOT block a STOP: a recording
            // already running when the cable goes in must stay stoppable.
            if fit.videoRecord {
                Button { toggleRecording() } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "video.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(recorder.isRecording
                                         ? EchoelTheme.recording
                                         : (videoCaptureYielded ? EchoelTheme.dim : EchoelTheme.text))
                        .frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -5))
                }
                .buttonStyle(.plain)
                .disabled(videoCaptureYielded)
                .accessibilityLabel(recorder.isRecording
                                    ? "Stop video recording"
                                    : (videoCaptureYielded
                                       ? "Video recording unavailable while the visual is on the external screen"
                                       : "Record MP4 video"))
            }
            #endif
            Button { cycleSize() } label: {
                // Cycles Small → Medium → Large → Fullscreen → Small. Shows a "contract"
                // glyph in fullscreen so it's obvious the next tap leaves fullscreen.
                Image(systemName: windowSize.isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(windowSize.isFullscreen ? "Exit fullscreen" : "Resize visual")
            .accessibilityValue(windowSize.label)
            Button { withAnimation(.easeInOut(duration: 0.15)) { isPresented = false } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(width: 28, height: 44).contentShape(Rectangle().inset(by: -5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide visual")
        }
        .padding(.horizontal, 10)
        .frame(height: handleHeight)
        // ⛔ WAS `.frame(maxWidth: .infinity)`, AND THAT IS THE STRUCTURAL HALF OF #365.
        // `maxWidth: .infinity` clamps a view UP to the proposal and never DOWN past its
        // own children — so an `HStack` of rigid items reports its oversize width, the
        // enclosing `VStack` adopts it, and the background, the border and the
        // `.clipShape` are all drawn at THAT width, outside the card and off the screen.
        // Capping at the card makes the bar structurally incapable of reporting wider
        // than the thing it sits in, whatever anyone adds to the row later. The budget
        // above is what keeps the items INSIDE that cap; this line is the backstop for
        // the day someone adds a control and forgets the budget.
        .frame(maxWidth: card.width)
        .background(EchoelTheme.bg.opacity(0.92))
        // NOTE: the move-drag lives on the ≡ handle only (see above), NOT the whole bar, so it
        // can never swallow a toolbar-button tap.
    }

    /// STABLE resize (founder 2026-07-08: "die Funktion zum Vergrößern des Fensters
    /// ist schuld an den Glitches im Bild — erneuere diese Funktion mit einer
    /// stabileren Variante"): the size SNAPS in one step instead of animating.
    /// Animating the frame re-allocated the MTKView's Metal drawable on EVERY
    /// animation frame (~11× in 0.18 s) while the shader rendered with a
    /// per-frame-changing aspect — the resize glitches. One snap = ONE drawable
    /// re-allocation; a brief content dip (see `resizeDip`) covers that single
    /// reconfiguration frame so the change reads soft, not raw.
    /// Sizes too narrow to hold a RUNNING recorder's stop button, widened to the first one
    /// that fits. ONE owner for the #365 geometry rule, because it has two doors (#366).
    ///
    /// ⛔ IT HAD ONE OWNER AND TWO DOORS, WHICH IS THE SAME AS HAVING NONE. #365 taught
    /// `cycleSize` to skip `.small` and `.medium` while a take runs — a running recorder
    /// PINS its own stop button, so the floor is ≈252 pt with nothing optional left to shed,
    /// against a ≈147–175 pt small card and a ≈232–275 pt medium one. `exitToStudio` sets a
    /// size too, and it was left setting `.small` unconditionally. So the Studio chip walked
    /// straight into the exact state the resize button refuses to enter: mid-take, the
    /// toolbar overflows the card again and the logo goes first — the founder's original
    /// "geht über den Rand hinaus", through the other door.
    ///
    /// ⚠️ AND IT MADE A SHIPPED TEST'S REASONING FALSE. `ChromeBudgetFitsTests` skips the
    /// busy small/medium combinations on the stated ground that they are "unreachable rather
    /// than broken". That was true of `cycleSize` and never true of this function. A guard
    /// that documents WHY it does not test something has to be re-read whenever a second
    /// writer appears — the assertions were still right, the sentence justifying their
    /// absence was not.
    private func sizeWideEnoughForARunningTake(_ size: WindowSize) -> WindowSize {
        let busy = wavRecording || wavExporting || recorderIsRecording
        guard busy, size == .small || size == .medium else { return size }
        return .large
    }

    /// PRODUCER DOOR action: leave fullscreen for the docked PiP so the instrument controls
    /// are revealed, the visual kept as a floating picture. Uses the SAME stable dip as
    /// `cycleSize` (one drawable re-allocation hidden behind a brief content dip, never the
    /// animated multi-frame resize that glitched). The chrome stayed mounted beneath, so the
    /// running session (bio + transport) is uninterrupted by the drop.
    ///
    /// ⛔ THE OLD DOC PROMISED A SCREEN THAT NO LONGER EXISTS: "the full DAW chrome — tight
    /// loops, video, WAV — is revealed". The DAW surfaces went with #121 Slice 4 and #167.
    /// The same sentence, in user-facing form, was already corrected in this button's
    /// `accessibilityHint` once (it used to name timeline, clips and tracks, in German) —
    /// the comment version survived that pass because only the string was searched.
    private func exitToStudio() {
        resizeDip = true
        DispatchQueue.main.async {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { sizeRaw = sizeWideEnoughForARunningTake(.small).rawValue }
            withAnimation(.easeOut(duration: 0.22)) { resizeDip = false }
        }
    }

    private func cycleSize() {
        resizeDip = true
        // ⛔ THE TWO SMALL STEPS ARE SKIPPED WHILE A RECORDER RUNS, and that is a geometry
        // consequence rather than a preference (#365). A running recorder PINS its own
        // stop button (see `FloatingVisualLayout.chromeFit`), so the floor is logo 40 +
        // the busy WAV control 104 + resize 28 + close 28, plus four gaps and the
        // padding: ≈252 pt with nothing optional left to shed. The small card is
        // ≈147–175 pt and the medium ≈232–275 pt, so BOTH are provably too narrow on a
        // 375 and a 393 pt phone. Cycling therefore runs large ↔ fullscreen until the
        // take ends, and every step is reachable again the moment it does.
        //
        // ⚠️ I NEARLY SHIPPED THIS SKIPPING ONLY `.small`. The medium case came out of
        // simulating the budget across three device widths × four busy states, not out of
        // reading the code — 252 vs 244 pt is an eight-point overflow that no amount of
        // staring at the source reveals. Any change to the costs above must re-run that
        // simulation; `ChromeBudgetFitsTests` is where it now lives.
        //
        // ⛔ THE BUSY TEST USED TO BE INLINE HERE, and that is exactly how `exitToStudio`
        // got to set `.small` mid-take (#366). The rule now lives in
        // `sizeWideEnoughForARunningTake`, which BOTH size-setting paths call — a geometry
        // law with two writers needs one owner, same reasoning as the single lifecycle owner
        // per sensor.
        //
        // Two frames later: apply the snap while the content is dimmed, then ease
        // the picture back in. No frame animation ever touches the Metal view.
        DispatchQueue.main.async {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                sizeRaw = sizeWideEnoughForARunningTake(windowSize.next).rawValue
            }
            withAnimation(.easeOut(duration: 0.22)) { resizeDip = false }
        }
    }

    /// `recorder` only exists behind `canImport(AVFoundation)`; reading it through this
    /// one accessor keeps `cycleSize` free of a second `#if` in the middle of a
    /// transaction, where a mismatched branch is easy to introduce and hard to see.
    private var recorderIsRecording: Bool {
        #if canImport(AVFoundation)
        return recorder.isRecording
        #else
        return false
        #endif
    }

    #if canImport(AVFoundation)
    /// Start/stop MP4 capture of the visual (with live audio). On stop, present the share
    /// sheet. Tip: size the window up (L) before recording for a higher-resolution clip —
    /// the video is rendered at the window's on-screen size.
    private func toggleRecording() {
        if recorder.isRecording {
            recordStart = nil
            Task { @MainActor in
                if let url = await recorder.stop() {
                    recordedClip = RecordedClip(url: renamedForShare(url))
                }
            }
        } else {
            recordStart = Date()
            recorder.start(audio: audioEngine)
        }
    }

    /// Start/stop a LOSSLESS WAV recording of the live performance. Uses RetroCapture's
    /// live-file write (independent of the MP4 path, which snapshots the ring at stop — so
    /// both can be armed for one take), then converts the float32 CAF to a .wav via
    /// SingleExport (PCM out, LUFS gain only — the natural character is preserved, founder:
    /// "Natürlichkeit … erkennbar"). On stop, present the share sheet.
    private func toggleWavRecording() {
        if wavRecording {
            wavRecording = false
            wavRecordStart = nil
            audioEngine.retroCapture.stopRecording { url in
                Task { @MainActor in await exportWav(from: url) }
            }
        } else {
            // A studio export (LoopExporter) also drives RetroCapture's live file; if one is
            // mid-capture, don't start a second (it would no-op in RetroCapture anyway).
            guard !audioEngine.retroCapture.isRecording else { return }
            audioEngine.retroCapture.startRecording(preRoll: 0)   // live from NOW, arbitrary length
            wavRecording = true
            wavRecordStart = Date()
        }
    }

    /// Convert the captured CAF to a shareable, naturally-preserved .wav.
    private func exportWav(from cafURL: URL) async {
        wavExporting = true
        defer { wavExporting = false }
        let ex = audioEngine.singleExport
        ex.reset()
        ex.outputFormat = .wav          // lossless PCM — no codec artifacts
        // The SAME delivery target the Master panel shows — nil ("No target") means no
        // normalisation. This was hardcoded to −14 until 2026-07-27, which made the
        // Master setting a lie one button over: the two Studio export buttons honoured
        // it while this one, in a window visible by default, always normalised to −14.
        ex.targetLUFS = LoudnessTarget.resolvedLUFS(rawValue: loudnessTargetRaw)
        ex.trimLengthSeconds = nil      // keep the WHOLE take (no bar-grid trim here)
        await ex.export(sourceURL: cafURL)
        if let url = ex.exportState.exportedURL {
            wavClip = RecordedClip(url: renamedForShare(url))
        }
    }

    /// Give the recorded clip a fitting name — same convention as the WAV export:
    /// `Echoel_<date>_<Key>_<bpm>_A440_<Genre>.mp4` (key + tempo + tuning + genre). Copies
    /// to a temp file with that name for the share sheet; falls back to the original on
    /// failure so a recording is never lost.
    private func renamedForShare(_ url: URL) -> URL {
        let raw = "\(session.sessionName(bpm: transport.tempo))_\(genre.displayName)"
        let safe = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>| "))
            .filter { !$0.isEmpty }.joined(separator: "-")
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return url
        }
    }
    #endif

    // MARK: - Geometry

    /// Card size for the current step. Every rule — aspect band, chrome added rather than
    /// carved out, minimum picture, the drag-travel cap, fit-with-margins on every path
    /// including degenerate input — lives in `FloatingVisualLayout`, which is pure and
    /// unit-tested on CI. This is only the hand-off (founder 2026-07-27: "auch das Fenster,
    /// es soll adaptiv sein").
    private func size(in bounds: CGSize) -> CGSize {
        if windowSize.isFullscreen { return bounds }   // edge-to-edge, no margin
        return FloatingVisualLayout.cardSize(in: bounds,
                                             fraction: windowSize.fraction,
                                             margin: margin,
                                             chromeHeight: handleHeight)
    }

    /// Where a NON-fullscreen card parks before the user has dragged it.
    ///
    /// It sits above the control band, not on it. #157 moved the primary button to the
    /// bottom of the studio and #197 made this card claim more of the box; each change
    /// was right on its own, and together they parked the card on top of the app's most
    /// important control — roughly its right-hand 40 %. That is worse than an ordinary
    /// overlap, because this card is the PLAY SURFACE: a tap in the covered strip did not
    /// miss the button, it played a synth note instead of starting biofeedback. And it was
    /// the FIRST thing you met, since leaving fullscreen drops straight to `.small`.
    ///
    /// Only the DEFAULT moves. The drag clamp is untouched, so parking the card back over
    /// the button stays the user's choice — this just stops the app from choosing it for
    /// them. `clamp(_:in:card:)` still runs afterwards, so on a container too short to
    /// afford the band the offset is absorbed rather than pushing the card off-screen — the
    /// clamp can only move the card UP to `minY`, never back down onto the button.
    ///
    /// Measured clearance on a 393 × 852 portrait iPhone at the `.small` step: 16 pt, and it
    /// is container-independent (`margin 12 + band 70 − card-half-offset 66`). Two limits
    /// stated honestly: at the LARGE step in landscape the height cap can leave a few points
    /// of residual overlap, and any card the user has ALREADY dragged keeps its position —
    /// deliberately, since repositioning is theirs to decide.
    private func defaultCenter(in bounds: CGSize, card: CGSize) -> CGPoint {
        CGPoint(x: bounds.width - card.width / 2 - margin,
                y: bounds.height - card.height / 2 - margin
                    - FloatingVisualLayout.studioControlBandHeight)
    }

    /// Keep the whole card on screen (with the margin) whatever the size/drag.
    private func clamp(_ p: CGPoint, in bounds: CGSize, card: CGSize) -> CGPoint {
        let minX = card.width / 2 + margin
        let maxX = bounds.width - card.width / 2 - margin
        let minY = card.height / 2 + margin
        let maxY = bounds.height - card.height / 2 - margin
        return CGPoint(x: min(max(p.x, minX), max(minX, maxX)),
                       y: min(max(p.y, minY), max(minY, maxY)))
    }
}

/// First-run invitation on the instrument home (vision Step 2b). Teaches the two
/// core gestures — finger on the (back) camera to bring it to life, touch the image
/// to play — then fades and NEVER returns (persisted `onboard.instrumentHintSeen`).
/// A self-contained leaf: reads only @AppStorage (freeze rule), never a bio value;
/// `allowsHitTesting(false)` so it can never swallow the first play-touch; one opacity
/// ramp (far under the 3 Hz flash rule), reduce-motion aware. Whisper styling per
/// Uncodixfy — a subtle dark chip, no glow, accent green stays reserved for live bio.
@MainActor
private struct InstrumentHintOverlay: View {
    let reduceMotion: Bool
    @AppStorage("onboard.instrumentHintSeen") private var seen = false
    @State private var visible = false

    var body: some View {
        Group {
            if !seen {
                VStack(spacing: 7) {
                    // ⛔ These two were GERMAN until 2026-07-29 — on the immersive visual, the
                    // most-seen surface in the app, and the FIRST thing a new user reads.
                    // English is the bundle's declared development region; German returns
                    // through a String Catalog as a translation, not as a stray literal.
                    //
                    // ⛔ AND THE FIRST LINE WAS UNTRUE UNTIL #351. It read "A finger on the
                    // camera brings it to life" — a promise the app cannot keep at the moment
                    // it is shown. The camera has exactly ONE owner, `startBioSource()`, and
                    // its only caller is the start path in `EchoelStudioView`; before the user
                    // starts the music there is no capture session, so a finger on the lens
                    // does nothing at all. The very first instruction the instrument gives is
                    // the worst possible place for an instruction that does not work: a new
                    // user who follows it and sees nothing concludes the app is broken, not
                    // that they missed a step. Naming the precondition costs four words.
                    //
                    // The founder's law #1 quoted below ("app open, finger on camera, in 3
                    // seconds it lives") is the INTENT, and it is not what ships — bio is
                    // user-armed by design (silent until started). Making the promise true
                    // would mean auto-starting capture at launch, which is a permission
                    // dialog on first render and a behaviour change nobody asked for. So the
                    // copy follows the code, not the other way round.
                    Label("Start the music, then a finger on the back camera",
                          systemImage: "camera")
                    Label("Touch the image to play notes", systemImage: "hand.point.up.left")
                }
                .font(EchoelTheme.font(13))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge).fill(Color.black.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusLarge).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                // One-line literal on purpose: the sibling comment in `WorkspaceView` records
                // that a bare literal here resolves to the `LocalizedStringKey` overload, and
                // a String Catalog key is what carries this to the German build. A multi-line
                // literal would still localise, but it makes the key harder to match by eye
                // against the catalog — and this string has now been wrong once (#351).
                .accessibilityLabel("Start the music, then put a finger on the back camera. Touch the image to play notes.")
                .task {
                    // Show once, hold ~4.5 s, fade out, then mark seen so it never returns.
                    // No animation under Reduce Motion (a hard cut, still flash-safe).
                    // ONCE-EVER CONTRACT (do not weaken): `seen = true` MUST run even when the
                    // task is cancelled early (user flicks out of fullscreen mid-hold). The
                    // `try?` (not `try`) swallows the sleep's CancellationError and falls
                    // through to the write, so the hint never re-shows on return to fullscreen.
                    // Do NOT add `guard !Task.isCancelled` or move `seen = true` before the
                    // sleeps — that would re-arm the hint on a fullscreen toggle. The only
                    // path leaving seen=false is app termination before the write (correct:
                    // an unseen hint re-shows next launch).
                    if reduceMotion { visible = true }
                    else { withAnimation(.easeIn(duration: 0.45)) { visible = true } }
                    try? await Task.sleep(nanoseconds: 4_500_000_000)
                    if reduceMotion { visible = false }
                    else { withAnimation(.easeOut(duration: 0.6)) { visible = false } }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    seen = true
                }
            }
        }
    }
}
#endif
