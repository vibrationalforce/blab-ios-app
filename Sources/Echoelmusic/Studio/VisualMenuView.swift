//
//  VisualMenuView.swift
//  Echoelmusic — Studio
//
//  ⚠️ PARKED / NOT WIRED (10.76.38): the call site in EchoelStudioView was removed by
//  the 10.76.36 launch-bisect revert. Kept (compiles clean, tested cores behind it) for
//  a careful re-wire — do NOT re-add by appending another `.sheet` to EchoelStudioView's
//  body (see CLAUDE.md "Presentation" note: that chain is at its metadata-overflow limit;
//  consolidate to a `.sheet(item:)` enum first). The Farboktave COLOURS are already live
//  in the shader (MetalBioView/ColorOctave) independent of this menu.
//
//  The reworked immersive-visual menu: looks grouped into CATEGORIES with design
//  emphasis, plus a Farboktave (Hans Cousto) reference wheel so the tone→colour
//  science is legible in the UI (not only in the shader). Founder ask (2026-06):
//  "Menüführung der visuals überarbeiten … Kategorien ausarbeiten und mehr
//  hervorheben durch Design … Farboktave nach Hans Cousto."
//
//  LAUNCH-SAFETY: presented from a LAZY `.sheet` (built only when opened, never in
//  the eager launch scroll). Uses only plain `Button`s, value `ForEach` over static
//  arrays, and a single `Canvas` for the wheel — none of the patterns that
//  black-screened (no Menu, no binding-ForEach over an @Observable array).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct VisualMenuView: View {
    /// Live look selection (same state the VJ strip drives). Donuts is a separate
    /// renderer; the Metal looks are selected by index.
    @Binding var spectralDonuts: Bool
    @Binding var visualStyle: Int
    /// The tone currently sounding (Hz) — marked on the colour wheel so the user sees
    /// "this note → this colour" live. 0 = nothing playing (no marker).
    var liveToneHz: Double = 0

    @Environment(\.dismiss) private var dismiss

    // MARK: - Look catalogue (static value types)

    private struct Look: Identifiable {
        let id: String          // == name
        let name: String
        let detail: String
        let isDonuts: Bool
        let style: Int          // metal-style index (ignored when isDonuts)
    }
    private struct Category: Identifiable {
        let id: String          // == title
        let title: String
        let subtitle: String
        let looks: [Look]
    }

    private let categories: [Category] = [
        Category(id: "Spectrum", title: "Spectrum", subtitle: "Frequency → light", looks: [
            Look(id: "Donuts", name: "Donuts", detail: "One ring per frequency band — colour is the tone transposed into visible light.", isDonuts: true, style: -1)
        ]),
        Category(id: "Interference", title: "Interference", subtitle: "Waves & plates", looks: [
            Look(id: "Rings", name: "Rings", detail: "Wave interference; a second ring system detuned by your coherence.", isDonuts: false, style: 0),
            Look(id: "Chladni", name: "Chladni", detail: "Vibrating-plate eigenmodes — the sounding tone sets the figure’s fineness.", isDonuts: false, style: 1)
        ]),
        Category(id: "Fields", title: "Fields", subtitle: "Flowing light", looks: [
            Look(id: "Plasma", name: "Plasma", detail: "Superposed plane waves; coherence sets the contrast.", isDonuts: false, style: 2),
            Look(id: "Water", name: "Water", detail: "Caustic water light — gentle, organic motion.", isDonuts: false, style: 3)
        ]),
        Category(id: "Prism", title: "Prism", subtitle: "Spectral dispersion · natural light", looks: [
            Look(id: "Prism", name: "Prism", detail: "Refracts the sounding tone across the frame like white light through glass — a rainbow centred on what you hear, rendered as warm daylight. Coherence narrows it to a purer spectrum.", isDonuts: false, style: 4)
        ])
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Choose a look, then shape it live in the Visual panel (Intensity · Detail · Motion · Colour) or let the body drive it via Bio → Visual.")
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(categories) { category in
                        categorySection(category)
                    }

                    Divider().overlay(EchoelTheme.border)
                    farboktaveSection
                }
                .padding(16)
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Visuals")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Category section

    private func categorySection(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category.title)
                    .font(EchoelTheme.font(16, .bold))
                    .foregroundStyle(EchoelTheme.text)
                Text(category.subtitle)
                    .font(EchoelTheme.font(11))
                    .foregroundStyle(EchoelTheme.dim)
            }
            ForEach(category.looks) { look in
                lookCard(look)
            }
        }
    }

    private func isSelected(_ look: Look) -> Bool {
        look.isDonuts ? spectralDonuts : (!spectralDonuts && visualStyle == look.style)
    }

    private func lookCard(_ look: Look) -> some View {
        Button {
            if look.isDonuts {
                spectralDonuts = true
            } else {
                spectralDonuts = false
                visualStyle = look.style
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(look.name)
                        .font(EchoelTheme.font(14, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text(look.detail)
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected(look) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected(look) ? EchoelTheme.accent : EchoelTheme.dim)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .stroke(isSelected(look) ? EchoelTheme.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(look.name) visual look")
        .accessibilityHint(isSelected(look) ? "Selected" : "Tap to select")
    }

    // MARK: - Farboktave (Cousto) reference

    private var farboktaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Farboktave (Hans Cousto)")
                .font(EchoelTheme.font(16, .bold))
                .foregroundStyle(EchoelTheme.text)
            Text("Raised ~40 octaves, every pitch class lands in the visible band — so each note has a colour. The immersive visual colours your sound by exactly this map; a glide slides smoothly along the wheel (a prism, not 12 steps).")
                .font(EchoelTheme.font(11))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)

            ColorOctaveWheel(liveToneHz: liveToneHz)
                .frame(height: 248)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

            if liveToneHz > 0 {
                let pc = Int(ColorOctave.pitchClass(ofFrequency: liveToneHz).rounded()) % 12
                HStack(spacing: 8) {
                    Circle()
                        .fill(swiftColor(ColorOctave.color(pitchClass: pc)))
                        .frame(width: 12, height: 12)
                    Text("Now: \(Self.noteNames[pc]) → \(ColorOctave.name(pitchClass: pc))")
                        .font(EchoelTheme.font(12, .medium))
                        .foregroundStyle(EchoelTheme.text)
                }
            }

            Text("Creative tuning / acoustics — a screen colour approximates a spectral light. No health, chakra or Solfeggio claims.")
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pitch-class note names (German H for B), aligned to ColorOctave's wheel index.
    static let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "H"]

    private func swiftColor(_ rgb: ColorOctave.RGB) -> Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

/// The Cousto 12-colour octave as a wheel — one `Canvas`, drawn from the canonical
/// `ColorOctave.wheel`. A single concrete view (launch-safe). Marks the live tone.
@MainActor
private struct ColorOctaveWheel: View {
    var liveToneHz: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 2
            // 12 wedges, each centred on its note's angle (top = C, clockwise).
            for i in 0..<12 {
                let mid = Double(i) * 30.0 - 90.0
                var path = Path()
                path.move(to: c)
                path.addArc(center: c, radius: r,
                            startAngle: .degrees(mid - 15), endAngle: .degrees(mid + 15),
                            clockwise: false)
                path.closeSubpath()
                let rgb = ColorOctave.wheel[i]
                ctx.fill(path, with: .color(Color(red: rgb.r, green: rgb.g, blue: rgb.b)))

                // Note label near the rim, in legible black/white per wedge luminance.
                let rad = mid * .pi / 180.0
                let lx = c.x + CGFloat(cos(rad)) * r * 0.74
                let ly = c.y + CGFloat(sin(rad)) * r * 0.74
                let lum = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
                let label = Text(VisualMenuView.noteNames[i])
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(lum > 0.6 ? .black : .white)
                ctx.draw(label, at: CGPoint(x: lx, y: ly))
            }
            // Dark hub so it reads as a wheel, not a pie.
            let hubR = r * 0.34
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - hubR, y: c.y - hubR, width: hubR * 2, height: hubR * 2)),
                     with: .color(.black))

            // Live-tone marker: a white ring on the rim at the current pitch class.
            if liveToneHz > 0 {
                let pc = ColorOctave.pitchClass(ofFrequency: liveToneHz)   // 0..<12 continuous
                let ang = (pc * 30.0 - 90.0) * .pi / 180.0
                let mx = c.x + CGFloat(cos(ang)) * r * 0.93
                let my = c.y + CGFloat(sin(ang)) * r * 0.93
                let dot = CGRect(x: mx - 6, y: my - 6, width: 12, height: 12)
                ctx.stroke(Path(ellipseIn: dot), with: .color(.white), lineWidth: 2)
            }
        }
        .accessibilityLabel("Cousto colour-octave wheel: twelve pitch classes mapped to colour")
    }
}
#endif
