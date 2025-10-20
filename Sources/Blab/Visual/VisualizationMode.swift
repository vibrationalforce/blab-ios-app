import Foundation
import SwiftUI

/// Available visualization modes for BLAB
enum VisualizationMode: String, CaseIterable, Identifiable {
    case particles = "Particles"
    case cymatics = "Cymatics"
    case waveform = "Waveform"
    case spectral = "Spectral"
    case mandala = "Mandala"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .particles: return "sparkles"
        case .cymatics: return "waveform.circle"
        case .waveform: return "waveform.path"
        case .spectral: return "chart.bar"
        case .mandala: return "circle.hexagongrid"
        }
    }

    var description: String {
        switch self {
        case .particles:
            return "Bio-reactive particle field with physics simulation"
        case .cymatics:
            return "Water-like patterns driven by audio frequencies (Chladni plates)"
        case .waveform:
            return "Classic oscilloscope waveform display"
        case .spectral:
            return "Real-time frequency spectrum analyzer"
        case .mandala:
            return "Radial symmetry patterns with sacred geometry"
        }
    }

    var color: Color {
        switch self {
        case .particles: return .cyan
        case .cymatics: return .blue
        case .waveform: return .green
        case .spectral: return .purple
        case .mandala: return .pink
        }
    }
}


/// Visualization mode picker view
struct VisualizationModePicker: View {
    @Binding var selectedMode: VisualizationMode

    var body: some View {
        VStack(spacing: 12) {
            Text("Visualization Mode")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))

            // Mode buttons
            HStack(spacing: 8) {
                ForEach(VisualizationMode.allCases) { mode in
                    Button(action: {
                        selectedMode = mode
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 20))
                                .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.5))
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(selectedMode == mode ? mode.color.opacity(0.3) : Color.gray.opacity(0.2))
                                )

                            Text(mode.rawValue)
                                .font(.system(size: 9))
                                .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.5))
                        }
                    }
                }
            }

            // Description
            Text(selectedMode.description)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.4))
        )
    }
}
