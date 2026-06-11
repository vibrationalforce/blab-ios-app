//
//  EchoelTheme.swift
//  Echoelmusic — Studio
//
//  App design tokens that MIRROR the website CI (docs/shared.css :root), so the
//  app and echoelmusic.com share one visual language: black ground, muted
//  #e0e0e0 text, subtle borders, small radii, a single bio-green accent.
//  Plus size-class-aware metrics so the interface scales on every device
//  (compact iPhone ↔ regular iPad) and stays legible.
//

#if canImport(SwiftUI)
import SwiftUI

enum EchoelTheme {
    // MARK: Palette (matches docs/shared.css :root)
    static let bg      = Color.black                                          // --bg #000
    static let surface = Color(red: 0.055, green: 0.055, blue: 0.070)         // panel fill
    static let text    = Color(red: 0.878, green: 0.878, blue: 0.878)         // --text #e0e0e0
    static let dim     = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(0.55) // --dim
    static let border  = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(0.10) // subtle
    static let fill    = Color(red: 0.878, green: 0.878, blue: 0.878).opacity(0.06) // --glass-ish
    static let accent  = Color(red: 0.30, green: 0.85, blue: 0.55)            // bio-green
    static let danger  = Color(red: 0.90, green: 0.30, blue: 0.30)

    // MARK: Radii (≤ 12 per CLAUDE.md UI constraints)
    static let radius:      CGFloat = 8
    static let radiusLarge: CGFloat = 12

    // MARK: Size-class-adaptive metrics — so everything is visible on all devices
    /// Pass `horizontalSizeClass`; `.regular` (iPad / large) gets the bigger set.
    struct Metrics {
        let stepCellHeight: CGFloat
        let trackLabelWidth: CGFloat
        let controlSize: CGFloat
        let padHeight: CGFloat
        let padColumns: Int
        let bodySpacing: CGFloat

        /// - Parameters:
        ///   - h: horizontal size class (`.regular` = iPad / large → bigger set).
        ///   - v: vertical size class. `.compact` on a phone means **landscape**,
        ///        where vertical room is scarce — tighten heights/spacing and
        ///        lay the pads out in a single wide row to use the width.
        static func of(_ h: UserInterfaceSizeClass?, _ v: UserInterfaceSizeClass? = nil) -> Metrics {
            let regular = (h == .regular)
            // Compact height on a non-iPad device = landscape phone.
            let landscapePhone = (v == .compact && !regular)
            return Metrics(
                stepCellHeight:  regular ? 44 : (landscapePhone ? 24 : 30),
                trackLabelWidth: regular ? 56 : 38,
                controlSize:     regular ? 56 : (landscapePhone ? 38 : 44),
                padHeight:       regular ? 96 : (landscapePhone ? 50 : 64),
                padColumns:      regular ? 8  : (landscapePhone ? 8  : 4),
                bodySpacing:     regular ? 22 : (landscapePhone ? 8  : 14)
            )
        }
    }
}
#endif
