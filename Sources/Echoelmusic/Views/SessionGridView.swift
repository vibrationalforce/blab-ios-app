#if canImport(SwiftUI)
import SwiftUI

/// Ableton-style scene launcher — 2×3 grid on iPhone portrait, list on landscape.
/// Each cell is a named scene preset. Tap = smooth morph over 2 seconds.
struct SessionGridView: View {

    @Environment(SoundscapeEngine.self) private var engine
    let clipEngine: ClipEngine

    private let columns = [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            // Scene grid
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(clipEngine.scenes) { scene in
                    SceneButton(
                        scene: scene,
                        isActive: clipEngine.activeSceneID == scene.id,
                        isQueued: clipEngine.queuedSceneID == scene.id,
                        isMorphing: clipEngine.isMorphing && clipEngine.activeSceneID == scene.id
                    ) {
                        clipEngine.launch(scene)
                    } onDelete: {
                        clipEngine.remove(scene)
                    }
                }

                // Add scene button
                Button {
                    clipEngine.captureCurrentState()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(.white.opacity(0.2))
                        Text("Capture")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.15))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture current state as new scene")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            // Mini coherence + pause at bottom
            HStack(spacing: 20) {
                // Coherence dot
                let coh = engine.state.coherence
                Circle()
                    .fill(coh > 0.6 ? Color.green : coh > 0.3 ? Color.yellow : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)

                Text(String(format: "%.0f%% coh", coh * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))

                Spacer()

                // Morph indicator
                if clipEngine.isMorphing {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.6).tint(.white.opacity(0.4))
                        Text("Morphing")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Scene Button

private struct SceneButton: View {

    let scene: ClipEngine.Scene
    let isActive: Bool
    let isQueued: Bool
    let isMorphing: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Scene name
                HStack {
                    Text(scene.name)
                        .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(isActive ? 0.9 : 0.45))
                        .lineLimit(1)
                    Spacer()
                    if isQueued {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if isActive {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(accentColor.opacity(0.8))
                    }
                }

                // Voice mix mini-bars
                HStack(spacing: 3) {
                    miniBar(value: scene.mixRoot,   label: "R")
                    miniBar(value: scene.mixFifth,  label: "5")
                    miniBar(value: scene.mixOctave, label: "8")
                    miniBar(value: scene.mixHigh,   label: "H")
                }

                // Harmonicity dot row
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(
                                scene.harmonicity > Float(i) * 0.2 ? 0.3 : 0.06
                            ))
                            .frame(width: 10, height: 2)
                    }
                    Text("tone")
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.12))
                        .padding(.leading, 2)
                }
            }
            .padding(10)
            .frame(height: 72)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? accentColor.opacity(0.08) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isActive ? accentColor.opacity(isMorphing ? 0.6 : 0.3) : Color.white.opacity(0.08),
                        lineWidth: isActive ? 1 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scene.name) scene\(isActive ? ", active" : "")")
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete Scene", systemImage: "trash")
            }
        }
    }

    private var accentColor: Color {
        switch scene.color {
        case .teal:   return Color(red: 0.2, green: 0.85, blue: 0.75)
        case .amber:  return Color(red: 1.0,  green: 0.75, blue: 0.2)
        case .rose:   return Color(red: 1.0,  green: 0.35, blue: 0.45)
        case .violet: return Color(red: 0.75, green: 0.4,  blue: 1.0)
        case .sky:    return Color(red: 0.35, green: 0.75, blue: 1.0)
        case .lime:   return Color(red: 0.6,  green: 0.95, blue: 0.3)
        }
    }

    private func miniBar(value: Float, label: String) -> some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.05))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(isActive ? 0.5 : 0.2))
                        .frame(height: geo.size.height * CGFloat(value / 0.6))
                }
            }
            .frame(width: 10)
            Text(label)
                .font(.system(size: 6, weight: .medium))
                .foregroundStyle(.white.opacity(0.15))
        }
        .frame(height: 20)
    }
}
#endif
