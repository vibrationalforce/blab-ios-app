#if canImport(SwiftUI)
import SwiftUI

// WaveformView.swift
// Echoel — Stage 2c: the professional waveform rendering (research-validated):
// per pixel column a min/max extremes bar with an RMS "body" core on top —
// extremes never vanish, energy stays readable. Draws reduced buckets only
// (WaveformCache tiers), never raw PCM.
//
// Render safety: pure leaf — draws from immutable value data, reads no
// observables, no timers. A redraw happens only when the data or size changes.

/// Draws one tier of reduced waveform buckets. Picks the coarser tier
/// automatically when the fine tier would burn >8 buckets per pixel column.
struct WaveformView: View {
    let data: WaveformData
    var tint: Color = EchoelTheme.text

    var body: some View {
        Canvas { ctx, size in
            guard size.width >= 1, size.height >= 2 else { return }
            let cols = max(1, Int(size.width))
            let buckets = data.fine.count > cols * 8 ? data.coarse : data.fine
            guard !buckets.isEmpty else { return }

            let mid = size.height / 2
            var extremes = Path()
            var core = Path()
            for x in 0..<cols {
                let b0 = x * buckets.count / cols
                let b1 = max(b0 + 1, (x + 1) * buckets.count / cols)
                var lo: Float = buckets[b0].min
                var hi: Float = buckets[b0].max
                var rms: Float = buckets[b0].rms
                var b = b0 + 1
                while b < b1 {
                    lo = min(lo, buckets[b].min)
                    hi = max(hi, buckets[b].max)
                    rms = max(rms, buckets[b].rms)
                    b += 1
                }
                let yHi = mid - CGFloat(min(1, max(-1, hi))) * (mid - 1)
                let yLo = mid - CGFloat(min(1, max(-1, lo))) * (mid - 1)
                extremes.addRect(CGRect(x: CGFloat(x), y: yHi,
                                        width: 1, height: max(1, yLo - yHi)))
                let r = CGFloat(min(1, max(0, rms))) * (mid - 1)
                core.addRect(CGRect(x: CGFloat(x), y: mid - r,
                                    width: 1, height: max(1, r * 2)))
            }
            ctx.fill(extremes, with: .color(tint.opacity(0.38)))
            ctx.fill(core, with: .color(tint.opacity(0.85)))
        }
        .accessibilityHidden(true)   // the numbers next to it carry the meaning
    }
}

/// Async wrapper: loads the reduced waveform for a file URL via WaveformCache
/// and renders it; a quiet placeholder while reducing (first open of a long
/// file) or when the file is unreadable.
struct FileWaveformView: View {
    let url: URL
    var tint: Color = EchoelTheme.text

    @State private var data: WaveformData?

    var body: some View {
        ZStack {
            if let data {
                WaveformView(data: data, tint: tint)
            } else {
                Rectangle()
                    .fill(EchoelTheme.fill)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(EchoelTheme.dim)
                    )
            }
        }
        .task(id: url) { data = await WaveformCache.shared.waveform(for: url) }
    }
}
#endif
