// BeatTab.swift
// Echoel — Beat tab UI: 16-step × 8-track grid + tempo + transport + pads.
//
// All audio lives in the BeatPlayer (injected via .environment). This view
// is purely a control surface — no engine state, no audio thread, no FX.
//
// UI rules per CLAUDE.md:
// - Solid fills only (no glassmorphism, no glow, no neon)
// - Corner radius ≤ 8 pt
// - No transform/scale on tap — opacity/fill only
// - Step-cell flash on currentStep is a fill change, not an animation loop

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BeatTab: View {

    @Environment(BeatPlayer.self) private var beatPlayer

    private let columnsPerGroup = 4
    private let groupCount = 4

    var body: some View {
        // Cycle 3 restoration: full BeatTab UI — transport + step grid + pads.
        // Pads trigger \`beatPlayer.playPad(track)\` which fires the matching
        // SamplerVoice (lock-free trigger counter on the audio thread).
        VStack(spacing: 16) {
            transportRow(player: beatPlayer)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            stepGrid(player: beatPlayer)
                .padding(.horizontal, 12)
            padRow
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    // MARK: - Transport

    @ViewBuilder
    private func transportRow(player: BeatPlayer) -> some View {
        HStack(spacing: 12) {
            Button {
                if player.pattern.isPlaying {
                    player.pattern.stop()
                } else {
                    player.pattern.play()
                }
            } label: {
                Image(systemName: player.pattern.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(player.pattern.isPlaying ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tempo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { player.pattern.tempo },
                            set: { player.pattern.setTempo($0) }
                        ),
                        in: PatternEngine.minTempo...PatternEngine.maxTempo
                    )
                    Text("\(Int(player.pattern.tempo)) BPM")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 80, alignment: .trailing)
                }
            }

            Button {
                player.pattern.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.white.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Step grid

    @ViewBuilder
    private func stepGrid(player: BeatPlayer) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<PatternEngine.trackCount, id: \.self) { track in
                trackRow(track: track, player: player)
            }
        }
    }

    @ViewBuilder
    private func trackRow(track: Int, player: BeatPlayer) -> some View {
        HStack(spacing: 4) {
            Text(BeatPlayer.trackNames[track].prefix(4))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 36, alignment: .leading)

            ForEach(0..<groupCount, id: \.self) { group in
                HStack(spacing: 3) {
                    ForEach(0..<columnsPerGroup, id: \.self) { col in
                        let step = group * columnsPerGroup + col
                        stepCell(track: track, step: step, player: player)
                    }
                }
                if group < groupCount - 1 {
                    Spacer().frame(width: 6)
                }
            }
        }
    }

    @ViewBuilder
    private func stepCell(track: Int, step: Int, player: BeatPlayer) -> some View {
        let isOn = player.pattern.steps[track][step]
        let isCurrent = player.pattern.isPlaying && player.pattern.currentStep == step
        Button {
            player.pattern.toggleStep(track: track, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellFill(isOn: isOn, isCurrent: isCurrent))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(isCurrent ? 0.55 : 0.08), lineWidth: 1)
                )
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Track \(BeatPlayer.trackNames[track]) step \(step + 1)")
        .accessibilityValue(isOn ? "on" : "off")
    }

    private func cellFill(isOn: Bool, isCurrent: Bool) -> Color {
        switch (isOn, isCurrent) {
        case (true, true):   return Color.green.opacity(0.85)
        case (true, false):  return Color.green.opacity(0.55)
        case (false, true):  return Color.white.opacity(0.18)
        case (false, false): return Color.white.opacity(0.06)
        }
    }

    // MARK: - Drum pads

    private var padRow: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<PatternEngine.trackCount, id: \.self) { track in
                pad(track: track)
            }
        }
    }

    @ViewBuilder
    private func pad(track: Int) -> some View {
        Button {
            beatPlayer.playPad(track)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                Text(BeatPlayer.trackNames[track])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pad \(BeatPlayer.trackNames[track])")
    }
}
#endif
