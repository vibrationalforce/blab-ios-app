// FloatingVisualLayout.swift
// Echoel — pure layout math behind the floating visual window's ADAPTIVE size
// (founder 2026-07-27: "Optimiere das alles und auch das Fenster, es soll adaptiv
// sein"). Foundation-only, same law as RollFitMath / AutomationCanvasMath /
// LookBlendMap: the view feeds a measured container size IN and gets a card size
// OUT, and every boundary is unit-tested on CI without a SwiftUI host.
//
// WHAT WAS WRONG. The window sized itself as two INDEPENDENT fractions of the
// container — small was 0.38 × width by 0.30 × height. Independent fractions do not
// adapt, they inherit: the card's aspect ratio became whatever the container's aspect
// happened to be, times a constant — and on a LANDSCAPE phone not even that: the pair
// carried `max(120, …)` floors, and there it was the FLOOR, not the 0.30 fraction, that
// set the height. "Small" came out 324 × 120 pt, and 44 pt of that is the chrome bar,
// so the picture itself was 324 × 76 — a letterbox sliver. That picture is also the
// PLAY SURFACE (touch instrument at every size, founder 2026-07-07), so the sliver was
// not merely ugly: it collapsed the axis that carries octave height into 76 pt.
//
// THE RULE HERE. The picture keeps the container's ORIENTATION but not its extremes:
// its aspect follows the available box, CLAMPED into a usable band, and the size step
// then scales that shape to fit. Portrait stays portrait-ish, landscape becomes
// properly landscape instead of a strip, and no container — including an iPad or a
// split-screen slice — can produce a degenerate card. This is what "adaptiv" has to
// mean for a window that is simultaneously a picture and an instrument.
//
// …and one consequence that had to be capped. Claiming `f` of the box along BOTH edges
// keeps the aspect fixed only because one edge normally binds first. On a container
// whose own aspect already sits inside the band — a near-square iPad — NEITHER binds,
// both hit `f` at once, and "large" came out at 92% of the height: ~67 pt of drag
// travel left, i.e. fullscreen with a border. `maxCardHeightFraction` bounds that. It
// is not taste: this window's stated job is to be a picture-in-picture you can MOVE.
//
// Deliberately NOT here: fullscreen (the view short-circuits to the full bounds before
// calling this), the docked default centre, and the drag clamp — those are position,
// not size, and they were never the defect.

import Foundation

public enum FloatingVisualLayout {

    /// Narrowest picture the card may take (w/h). 0.75 = 3:4 portrait. Below this the
    /// picture reads as a column and the play surface loses pitch width.
    public static let minPictureAspect: CGFloat = 0.75
    /// Widest picture the card may take. 1.6 ≈ 16:10 — wide enough to feel like a
    /// landscape image, short of the 2.4:1+ strips the old fraction pair produced.
    public static let maxPictureAspect: CGFloat = 1.6

    /// Tallest a FLOATING card may be, as a fraction of the container. See the header:
    /// without it a near-square container leaves ~67 pt of drag travel at the large step.
    /// 0.80 is chosen to bind ONLY where the near-square case needs it — a portrait phone's
    /// large card (≈72% of the height) is untouched.
    public static let maxCardHeightFraction: CGFloat = 0.80

    /// The three floating steps, as the scale each claims of the available box. They live
    /// HERE, not in the view's `WindowSize` enum, so the tests pin the numbers that
    /// actually ship: `WindowSize` is nested inside a `#if canImport(SwiftUI) &&
    /// canImport(MetalKit) && canImport(UIKit)` file, which a Foundation-level test cannot
    /// reach — so a test owning its own copy of these would keep passing while the shipped
    /// steps drifted back. (Fullscreen is short-circuited by the view and has no entry.)
    public static let smallStep: CGFloat = 0.42
    public static let mediumStep: CGFloat = 0.66
    public static let largeStep: CGFloat = 0.94

    // MARK: The studio's bottom control band
    //
    // ⛔ THE BUTTON IS NOT DOWN THERE ANY MORE (#288, founder 2026-07-31: "Create from within
    // sollte über Sound, FX, Mood und Field sein"). It is now the FIRST child of
    // `EchoelStudioView`'s root stack, above the chip bar. The three constants below are
    // therefore NO LONGER a collision guard, and the paragraph that follows — kept because it
    // is the whole reason this indirection exists — describes a hazard that has moved:
    //
    // What they still do, stated honestly so the next reader is not misled by the name:
    //   · `startButtonHeight` + the two paddings still SIZE the button. That is unchanged and
    //     still belongs in the pure, CI-tested type.
    //   · `studioControlBandHeight` is still the lift `FloatingVisualWindow.defaultCenter`
    //     applies to the docked card — but it now buys a bottom MARGIN, not clearance over a
    //     control. The value is left exactly as it was so this slice moves ONE thing (the
    //     button) and the docked visual does not silently jump on the founder's device in the
    //     same build. Whether the card should now drop those ~70 pt is a look decision that
    //     belongs to the founder, and it is filed rather than taken here.
    //   · The name is now wider than the truth. NOT renamed on purpose: the rename would
    //     touch `FloatingVisualWindow` and `FloatingVisualLayoutTests` in a UI-placement
    //     commit, and a rename is exactly the kind of churn that hides a real change.
    //
    // These three own the primary "Create from Within"/"Stop" button's vertical footprint,
    // and they live HERE — in the pure, CI-tested type — rather than as literals in the two
    // views that need them to AGREE. `EchoelStudioView` builds the button from them; this
    // file's `studioControlBandHeight` is what `FloatingVisualWindow.defaultCenter` lifts
    // the docked card by, so the card cannot park on the button.
    //
    // WHY THE INDIRECTION IS WORTH IT. The card once covered ~40 % of that button, and
    // because the card is the PLAY SURFACE, a tap in the covered strip played a synth note
    // instead of starting biofeedback. The first fix hardcoded 70 in the window file with a
    // comment asking the next person to keep it in step — but that comment sits in the file
    // nobody opens when they restyle a button. Now the dependency is a compile-time one and
    // `FloatingVisualLayoutTests` pins the sum, so a restyle that would re-create the overlap
    // cannot pass silently.
    //
    // Safe as a constant: `StudioZoom` scales via `dynamicTypeSize`, not `scaleEffect`, and
    // the button's height is a hard `.frame(height:)` — so the band does NOT grow at
    // accessibility text sizes. If that ever changes, this is the thing to make dynamic.
    // ⛔ SECOND WIDENING OF THE SAME GAP (#481, founder 2026-08-07 *"die sollen immer
    // gleichgroß sein"*). `startButtonHeight` no longer sizes the start button either — the
    // button now reads `EchoelTheme.controlHeight` / `controlTapHeight` like every other
    // chrome control. So of the two jobs the block above lists, the FIRST one is gone too,
    // and all three constants exist for exactly one purpose now: to sum to
    // `studioControlBandHeight`, the docked card's bottom margin.
    //
    // WHY THEY ARE NOT COLLAPSED TO A SINGLE `70`. Two reasons, and the second is the one
    // that decides it. (1) `FloatingVisualLayoutTests` pins the SUM, so the arithmetic is the
    // thing under test; replacing it with a literal would delete the test's subject. (2) The
    // number must not move in a commit about button size — feeding the new 32 into the sum
    // would slide the docked visual up 24 pt on the founder's device as a side effect of a
    // chrome tidy-up. Whether the card should now drop those points is a LOOK decision and
    // belongs to the founder; it is filed, not taken.
    //
    // ⚠️ THE NAME IS NOW WRONG AND IS KEPT ANYWAY — same reasoning as the block above, one
    // step further along: a rename touches `FloatingVisualWindow` and the test in a commit
    // that is not about either, and churn is what hides a real change. This paragraph is the
    // compensation. Do NOT read the name as "the start button is 56 tall"; it is 32.
    public static let startButtonHeight: CGFloat = 56
    public static let startButtonTopPadding: CGFloat = 4
    public static let startButtonBottomPadding: CGFloat = 10
    /// Total height the studio's primary control claims at the bottom of the window.
    public static var studioControlBandHeight: CGFloat {
        startButtonHeight + startButtonTopPadding + startButtonBottomPadding
    }

    // MARK: - VoiceOver snap positions (#619, GUI-Board Zeile 9 / A11y#4)
    //
    // The floating card moved ONLY by a DragGesture on the logo handle — a gesture a
    // VoiceOver user cannot perform, so for them the window was pinned wherever it spawned
    // (possibly over the control they need next). These four snap targets back the named
    // rotor actions the handle now offers. The DRAG STAYS — actions add a second door to
    // the same `center` state, they replace nothing.
    //
    // The maths deliberately mirrors the view's own laws rather than inventing new ones:
    //   · left/right/top edges keep the card `margin` clear of the container edge — the
    //     same bound `FloatingVisualWindow.clamp` enforces on every drag;
    //   · the BOTTOM corners additionally lift by `studioControlBandHeight`, exactly like
    //     `FloatingVisualWindow.defaultCenter` — so the bottom-right action lands on the
    //     dock spot the card starts at, not a few points lower than any drag would rest.
    //     (Named limit, #619b review: on a container short enough that this lift folds
    //     into the top margin, the "bottom" actions park where the dock itself would —
    //     verified byte-equal to `clamp(defaultCenter)` — so the spoken name over-promises
    //     only in extreme landscape/large-card combinations the dock shares.)
    // The `max(min…, …)` folds guard a degenerate container (card wider than bounds):
    // the near edge wins, matching `clamp`'s ordering, and the result stays finite.
    //
    // Names live HERE as rawValues — one definition (#416): the view builds its action
    // buttons from `allCases`. A RENAME is one edit; a FIFTH corner is two, deliberately —
    // the guard (`TheFloatingWindowMovesWithoutADragTests`) pins the set's count, so
    // growing it means saying so where the set is proven. (#619b: the first version of
    // this sentence claimed both were one edit, contradicting the guard seven files away.)
    public enum SnapCorner: String, CaseIterable, Sendable {
        case topLeft = "Move to top left"
        case topRight = "Move to top right"
        case bottomLeft = "Move to bottom left"
        case bottomRight = "Move to bottom right"
    }

    /// Centre point that puts the card in the given corner of `bounds`, honouring the
    /// same margin the drag clamp uses and the same control-band lift the default dock
    /// applies to the bottom edge. Pure; the view still runs its render-time clamp over
    /// the result, so even a hostile size cannot push the card off screen.
    public static func snapCenter(_ corner: SnapCorner,
                                  in bounds: CGSize,
                                  card: CGSize,
                                  margin: CGFloat) -> CGPoint {
        let minX = card.width / 2 + margin
        let maxX = Swift.max(minX, bounds.width - card.width / 2 - margin)
        let minY = card.height / 2 + margin
        let maxY = Swift.max(minY, bounds.height - card.height / 2 - margin
                                    - studioControlBandHeight)
        switch corner {
        case .topLeft:     return CGPoint(x: minX, y: minY)
        case .topRight:    return CGPoint(x: maxX, y: minY)
        case .bottomLeft:  return CGPoint(x: minX, y: maxY)
        case .bottomRight: return CGPoint(x: maxX, y: maxY)
        }
    }

    // MARK: - Chrome bar budget (#365)
    //
    // ⛔ THE WINDOW WAS ADAPTIVE ON ONE AXIS ONLY, and that is the whole bug the founder
    // reported ("im großen Zustand nicht adaptiv sondern geht über den Rand hinaus. Man
    // sieht Echoel Icon dann nicht mehr richtig"). `cardSize` above adapts the PICTURE to
    // the container and is provably correct — every branch returns `w ≤ availW`, `h ≤
    // availH`. The CHROME BAR was never measured by anything. It is an `HStack` of
    // RIGID-width children ending in `.frame(maxWidth: .infinity)`, which clamps a bar UP
    // to the proposal but never DOWN past its children — so the bar reports its own
    // oversize width, the enclosing `VStack` adopts it, and the background, border and
    // `.clipShape` are all drawn at that width. The outer `.frame(width:height:)` does not
    // clip in SwiftUI, so the too-wide bar is then CENTRED and sticks out on both sides,
    // past the card and past the screen. The logo is first in the row, so it goes first.
    // Both halves of the founder's sentence fall out of that one cause.
    //
    // HOW BAD, computed with every `Text` assumed ZERO width — a bound no font metric can
    // undercut. On a 393 pt portrait iPhone: small needs ≥248 pt for a 155 pt card,
    // medium ≥302 for 243.5, fullscreen ≥491 for 393. Only the LARGE step (302 vs 346.9)
    // can fit at all, and only while every label is empty. Re-derived independently on
    // 375/393/440 pt widths — small, medium and fullscreen overflow on EVERY iPhone.
    //
    // ⚠️ THESE ARE RESERVES, NOT MEASUREMENTS, and that distinction is the honest limit of
    // this type. Foundation cannot measure a `Text`, so the text-bearing items carry a
    // conservative constant. Being conservative is the safe direction: it sheds one item
    // too early rather than one too late, and shedding early is invisible while shedding
    // late is the bug. Every constant is pinned by a source scan in the guard test, so the
    // view and this file cannot drift apart silently.

    /// Widths the chrome bar's items claim. Names match the view's controls one-to-one.
    public enum ChromeCost {
        /// `EchoelLogoMark`'s hit frame — also the drag handle. Never shed.
        public static let logo: CGFloat = 40
        /// Every icon-only toolbar button (`.frame(width: 28)`).
        ///
        /// ⚠️ 28 + the view's −5 outset = a 38 pt effective TARGET WIDTH (height is 44) —
        /// clear of WCAG 2.5.8's 24, short of HIG's 44, and that shortfall is a MEASURED
        /// geometric ceiling, not an oversight (#617, the A11y#8 audit case): the
        /// never-shed floor is logo 40 + 2 × iconButton + 3 gaps (24) + padding (20) =
        /// 140 pt against a ≈147 pt small card on a 375 pt phone. Widening to a
        /// 44-effective button (34 wide + −5) makes that floor 152 and overflows the
        /// smallest card; deepening the outset instead overlaps the neighbour across
        /// the 8 pt gap (already −5 + −5 = 10 > 8, a 2 pt overlap between icon pairs).
        /// Re-open only with a redesign of the small card's width — not by nudging
        /// this constant, which `ChromeBudgetFitsTests` re-derives independently.
        public static let iconButton: CGFloat = 28
        /// `HStack(spacing: 8)`.
        public static let gap: CGFloat = 8
        /// `.padding(.horizontal, 10)`, both sides.
        public static let horizontalPadding: CGFloat = 20
        /// The look `Slider`'s `minWidth: 90` — rigid, it cannot compress below this.
        public static let lookSlider: CGFloat = 90
        /// "Studio" chip: symbol + label + 10 pt padding each side. Text reserve.
        public static let studioChip: CGFloat = 83
        /// `MiniTransportView`: capsule + spacing + two labels. Text reserve.
        public static let miniTransport: CGFloat = 84
        /// The WAV control while it shows a running time ("WAV 0:12"). Text reserve.
        public static let wavRecording: CGFloat = 104
    }

    /// Which OPTIONAL chrome items survive at a given card width. The three that never
    /// shed — logo, resize, close — are not represented: they are the identity of the bar
    /// (brand + the two ways out) and their floor is 96 pt of content, which even the
    /// smallest card (≈147 pt on a 375 pt phone) affords.
    public struct ChromeFit: Equatable, Sendable {
        public var lookSlider = false
        public var studioChip = false
        public var miniTransport = false
        public var gridToggle = false
        public var videoRecord = false
        public var wavRecord = false
        /// The still shutter (#1063). FULLSCREEN-ONLY, like `lookSlider` and `studioChip`:
        /// it is the picture's own control and the small card's never-shed floor (140 pt
        /// against a ≈147 pt card) has no room for a seventh item. Costs one
        /// `iconButton` + one gap, the same as `gridToggle` and `videoRecord`.
        public var stillShutter = false
        public init() {}
    }

    /// May a FULLSCREEN picture bleed into the left and right safe areas? #583.
    ///
    /// ⛔ THE DEFECT THIS ANSWERS. The window bled `[.bottom, .horizontal]` at fullscreen in every
    /// orientation, and the comment above that modifier justified it with: keep the TOP safe area
    /// so the toolbar never hides under the notch — you must still be able to manipulate the
    /// visual (founder). That reasoning is PORTRAIT-ONLY. In portrait the sensor housing is a
    /// `.top` inset, which is the one edge the modifier keeps. Rotate the phone and the housing
    /// becomes a HORIZONTAL inset — the exact edge the modifier deliberately bleeds into. And the
    /// two controls it lands on are not decorative: `ChromeFit` above calls resize and close
    /// "the two ways out", and they are the LAST two items of the bar, i.e. the ones nearest the
    /// trailing edge, ~10–38 pt and ~46–74 pt in against a landscape housing inset of ~59 pt.
    ///
    /// So in one of the two landscape orientations the app opened edge-to-edge into the picture
    /// with the exit under the cutout. #580 made that reachable by default, because since that
    /// slice fullscreen IS the launch state rather than something the user chose.
    ///
    /// ⭐ WHY THE ANSWER IS "PORTRAIT ONLY" AND NOT A PADDING. Padding the bar back out of the
    /// safe area is the prettier fix and it is the one I could not verify: `.ignoresSafeArea` is
    /// applied to the `GeometryReader`, so what a child's `safeAreaPadding` or a proxy's
    /// `safeAreaInsets` reports INSIDE that reader is exactly the semantics no test in this repo
    /// can settle — there is no simulator here. A static edge set has no such ambiguity. Portrait,
    /// the orientation the founder has actually used and approved, is left byte-identical; only
    /// landscape trades an edge-to-edge picture for a reachable way out. That is the right trade
    /// even if it were close, and it is not close.
    ///
    /// - Parameter isLandscape: on iPhone this is `verticalSizeClass == .compact`, which is the
    ///   established spelling in this codebase (`AdaptiveCardGrid` decides its column count the
    ///   same way). Passed in rather than derived so this stays Foundation-only and drivable.
    public static func fullscreenBleedsHorizontally(isLandscape: Bool) -> Bool { !isLandscape }

    /// The shed ORDER, first to go. It is a product ranking, not an arbitrary list, and it
    /// is stated here so a future change argues with it instead of quietly reordering:
    /// a look slider and a "Studio" door are convenience; the transport readout is
    /// information; the grid toggle is a display aid; the two RECORDERS are the only
    /// items whose loss can cost a performer a take, so they shed last.
    ///
    /// ⭐ #1063 PUT THE STILL SHUTTER BETWEEN THE DISPLAY AID AND THE IDLE VIDEO BUTTON,
    /// and the reason is the ranking's own principle rather than a free slot. A still and
    /// an idle video button are both "start a capture" doors, so neither is a display aid
    /// and neither is a stop button — the tie-breaker is what a lost door COSTS. A still is
    /// one frame of a picture that is still on screen: the same frame class is there a
    /// second later, so losing the shutter costs a convenience. A video take is a DURATION,
    /// and the seconds you did not start are gone — so the idle video button outranks it.
    /// Below both sits the grid toggle, which changes only what you SEE.
    ///
    /// It is FULLSCREEN-ONLY (`fit.stillShutter = isFullscreen`), so the small card's
    /// never-shed floor — the 140 pt against a ≈147 pt card that `ChromeCost.iconButton`
    /// spells out — is byte-identical to before this item existed.
    ///
    /// - Parameters:
    ///   - cardWidth: the card the bar must fit inside — `cardSize(...).width`, or the
    ///     full bounds width in fullscreen.
    ///   - isFullscreen: the slider and the Studio chip only exist in fullscreen; the
    ///     budget can only take them away, never add them to a floating card.
    ///   - showsTransport: the view already hides `MiniTransportView` at the small step
    ///     and while nothing is presented. Pass that condition through rather than
    ///     duplicating it here, so there is one owner of "may it appear at all".
    ///   - wavBusy: the WAV control carries a running time, which roughly quadruples it.
    ///   - videoBusy: a video capture is running.
    ///
    /// ⛔ A BUSY RECORDER IS PINNED, and finding that out is why the shed order alone was
    /// not enough. The first version of this function shed by rank only, and the
    /// simulation across three device widths showed the consequence immediately: at the
    /// medium step with a WAV take running, the budget dropped the WAV control — **which
    /// is the take's only STOP button**. A control that is the sole way to end an
    /// in-progress action must never be the thing that disappears to make room; that is
    /// worse than the overflow it was solving, because the overflow is ugly and this
    /// loses a recording. Rank decides what goes; being the exit decides that it stays.
    public static func chromeFit(cardWidth: CGFloat,
                                 isFullscreen: Bool,
                                 showsTransport: Bool,
                                 wavBusy: Bool,
                                 videoBusy: Bool) -> ChromeFit {
        var fit = ChromeFit()
        fit.lookSlider = isFullscreen
        fit.studioChip = isFullscreen
        fit.miniTransport = showsTransport
        fit.gridToggle = true
        fit.videoRecord = true
        fit.wavRecord = true
        fit.stillShutter = isFullscreen

        // A degenerate width must not silently return "everything fits" — that is the
        // failure this whole type exists to stop. Shed to the floor instead, but keep a
        // running recorder even there: its stop button outranks a clean layout.
        guard cardWidth.isFinite, cardWidth > 0 else {
            var floor = ChromeFit()
            floor.wavRecord = wavBusy
            floor.videoRecord = videoBusy
            return floor
        }

        func width(_ f: ChromeFit) -> CGFloat {
            // Always present: logo, resize, close.
            var total = ChromeCost.logo + 2 * ChromeCost.iconButton
            var items = 3
            if f.lookSlider    { total += ChromeCost.lookSlider;    items += 1 }
            if f.studioChip    { total += ChromeCost.studioChip;    items += 1 }
            if f.miniTransport { total += ChromeCost.miniTransport; items += 1 }
            if f.gridToggle    { total += ChromeCost.iconButton;    items += 1 }
            if f.videoRecord   { total += ChromeCost.iconButton;    items += 1 }
            if f.stillShutter  { total += ChromeCost.iconButton;    items += 1 }
            if f.wavRecord {
                total += wavBusy ? ChromeCost.wavRecording : ChromeCost.iconButton
                items += 1
            }
            // The `Spacer(minLength: 0)` contributes no width but still takes a gap on
            // each side; counting one gap per item is the same total and is what the
            // guard test re-derives, so keep the two spellings identical.
            return total + ChromeCost.gap * CGFloat(items) + ChromeCost.horizontalPadding
        }

        // ⭐ #1036 — THE LABELLED WAY BACK SHEDS LAST. The founder asked for the visual to
        // become "eine Einheit zum steuern … kompakter und übersichtlicher", and
        // `ChromeBudgetFitsTests.testFullscreenFitsAtEveryShippedWidth` had ALREADY measured
        // why it was not one: in fullscreen the "Studio" chip needs 431 pt and the widest
        // phone in `devices` is 440, so on 375 / 390 / 393 / 402 / 430 pt phones the only
        // LABELLED door back to the instrument was shed. What survived were two glyphs whose
        // words exist only in VoiceOver. That guard wrote the repair down as a product
        // question it could not answer alone (NEEDS-FOUNDER-VERIFY); the ask answers it.
        //
        // The repair is a RE-RANK, not a new control: `studioChip` moves from second-cheapest
        // to last among the non-recorder items. The ranking's own principle decides it —
        // "rank decides what goes; being the exit decides that it stays" is already the law
        // three paragraphs up, written for a recorder's stop button. The Studio chip is an
        // exit too: it is the only labelled way out of a surface the app COLD-LAUNCHES into
        // (`WorkspaceView` sets fullscreen at start), and the bar's own comments cite WCAG 2.2
        // against gating controls behind something with no words.
        //
        // WHAT IT COSTS, named rather than glossed: `miniTransport` and `gridToggle` now shed
        // earlier. Both are INFORMATION or a display aid; neither is a way out of anything.
        //
        // MEASURED across the guard's three widths (375 / 393 / 440) × wavBusy × videoBusy —
        // 12 states: the chip shed in 10 of them BEFORE this change and sheds in 1 after. The
        // one exception is 375 pt with BOTH a WAV take and a video capture running, where the
        // two pinned stop buttons leave no room and a running take's only stop button outranks
        // even the exit. That is the existing law applied consistently, not a hole in it; the
        // resize glyph still leaves fullscreen. Claim
        // `testTheLabelledExitSurvivesEveryShippedWidth` pins both halves.
        //
        // ⛔ THIS PARAGRAPH FIRST SAID "six shipped widths … 24 states … survives in 23" and
        // every one of those three numbers was invented. `ChromeBudgetFitsTests.devices` holds
        // THREE widths, so the sweep is 12 states and the survival is 11 of 12. The shape of
        // the finding was right and the arithmetic around it was decoration — which is the
        // failure this repo keeps paying for, and the reason the numbers here now name the
        // array they come from instead of a remembered device list.
        var shed: [(inout ChromeFit) -> Void] = [
            { $0.lookSlider = false },
            { $0.miniTransport = false },
            { $0.gridToggle = false },
            { $0.stillShutter = false }
        ]
        // The recorders shed only when they are IDLE. Busy, each one is its own take's
        // stop button (`stop.circle.fill`) and is pinned — see the ⛔ note on the
        // signature. Video sheds before WAV because a lost video take is a lost file,
        // while a lost WAV take is a lost performance.
        if !videoBusy { shed.append { $0.videoRecord = false } }
        shed.append { $0.studioChip = false }
        if !wavBusy   { shed.append { $0.wavRecord = false } }

        for drop in shed {
            if width(fit) <= cardWidth { return fit }
            drop(&fit)
        }
        return fit
    }

    /// Floor on the picture itself (NOT the card): below this a concentric visual has no
    /// room and the play surface is untappable. It is a floor, never an override — the
    /// lift is capped by what the available box can hold, so a container too small to
    /// afford it gets the largest card that still fits rather than one that overflows.
    public static let minPicture = CGSize(width: 130, height: 100)

    /// The aspect the picture should take for a given AVAILABLE box (container minus
    /// margins and chrome). Follows the box's own orientation, clamped to the band.
    /// A non-positive or non-finite box falls back to 1:1 rather than dividing.
    public static func pictureAspect(forAvailable available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0,
              available.width.isFinite, available.height.isFinite else { return 1 }
        let raw = available.width / available.height
        return Swift.min(maxPictureAspect, Swift.max(minPictureAspect, raw))
    }

    /// Card size (picture PLUS the chrome bar) for one size step.
    ///
    /// - Parameters:
    ///   - bounds: the container the card floats in.
    ///   - fraction: the step's scale, 0…1 — how much of the available box the picture
    ///     may claim along its binding edge.
    ///   - margin: gap kept to every container edge.
    ///   - chromeHeight: the handle/toolbar bar's height, which is part of the card but
    ///     not of the picture. Sizing the picture and then ADDING this is the half the
    ///     old code got wrong — it sized the whole card, so the bar ate a fixed 44 pt out
    ///     of whatever fell out, and ate proportionally more the smaller the step.
    public static func cardSize(in bounds: CGSize,
                                fraction: CGFloat,
                                margin: CGFloat,
                                chromeHeight: CGFloat) -> CGSize {
        let safeMargin = Swift.max(0, margin.isFinite ? margin : 0)
        let safeChrome = Swift.max(0, chromeHeight.isFinite ? chromeHeight : 0)
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else { return .zero }

        let availW = bounds.width - 2 * safeMargin
        let availH = bounds.height - 2 * safeMargin - safeChrome
        // A container too small to hold even the chrome plus a margin pair: fall back to
        // the margined box, so the fit-with-margins invariant holds on EVERY path. (The
        // old code produced a NEGATIVE width here for a container under 24 pt; returning
        // `bounds` unshrunk, as a first draft of this did, breaks `clamp(_:in:card:)`'s
        // maxX ≥ minX assumption and parks the card offset past the bottom-right edge.)
        guard availW > 0, availH > 0 else {
            return CGSize(width: Swift.max(1, bounds.width - 2 * safeMargin),
                          height: Swift.max(1, bounds.height - 2 * safeMargin))
        }

        let available = CGSize(width: availW, height: availH)
        let aspect = pictureAspect(forAvailable: available)
        let f = Swift.min(1, Swift.max(0.05, fraction.isFinite ? fraction : 0.5))

        // Claim `f` of the box along BOTH edges and keep whichever binds — that is what
        // holds the aspect fixed while the step still scales.
        var w = Swift.min(availW * f, availH * f * aspect)
        var h = w / aspect

        // Lift a too-small picture back to the floor, but never past what fits.
        if w < minPicture.width || h < minPicture.height {
            let lift = Swift.max(minPicture.width / Swift.max(w, 0.001),
                                 minPicture.height / Swift.max(h, 0.001))
            let capped = Swift.min(lift, Swift.min(availW / Swift.max(w, 0.001),
                                                   availH / Swift.max(h, 0.001)))
            w *= capped
            h *= capped
        }

        // Keep real drag travel (see `maxCardHeightFraction`). Scaling BOTH axes by the
        // same factor is what preserves the aspect the whole type exists to hold — a
        // height-only clamp would reintroduce the letterbox from the other direction.
        let maxCardH = bounds.height * maxCardHeightFraction
        if h + safeChrome > maxCardH {
            let shrink = Swift.max(0, maxCardH - safeChrome) / Swift.max(h, 0.001)
            w *= shrink
            h *= shrink
        }

        return CGSize(width: w, height: h + safeChrome)
    }
}
