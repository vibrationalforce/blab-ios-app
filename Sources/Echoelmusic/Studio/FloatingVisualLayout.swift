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
    public static let startButtonHeight: CGFloat = 56
    public static let startButtonTopPadding: CGFloat = 4
    public static let startButtonBottomPadding: CGFloat = 10
    /// Total height the studio's primary control claims at the bottom of the window.
    public static var studioControlBandHeight: CGFloat {
        startButtonHeight + startButtonTopPadding + startButtonBottomPadding
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
