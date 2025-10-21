import SwiftUI

/// Effects parameter editor for fine-tuning audio node parameters
struct EffectParametersView: View {
    let node: BlabNode
    @ObservedObject var nodeGraph: NodeGraph

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Node info header
                    nodeHeaderView

                    // Bio-reactive indicator
                    if node.isBioReactive {
                        bioReactiveInfoView
                    }

                    // Parameters based on node type
                    parametersView

                    // Bypass toggle
                    bypassToggleView
                }
                .padding()
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Parameters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Header

    private var nodeHeaderView: some View {
        VStack(spacing: 12) {
            Image(systemName: nodeIcon)
                .font(.system(size: 48))
                .foregroundColor(nodeColor)

            Text(node.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Text(nodeType)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(nodeColor.opacity(0.1))
        )
    }

    // MARK: - Bio-Reactive Info

    private var bioReactiveInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundColor(.pink)
                Text("Bio-Reactive Parameters")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text(bioReactiveDescription)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.pink.opacity(0.1))
        )
    }

    // MARK: - Parameters

    @ViewBuilder
    private var parametersView: some View {
        let nodeName = node.name.lowercased()

        if nodeName.contains("filter") {
            filterParametersView
        } else if nodeName.contains("reverb") {
            reverbParametersView
        } else if nodeName.contains("delay") {
            delayParametersView
        } else if nodeName.contains("compressor") {
            compressorParametersView
        } else {
            genericParametersView
        }
    }

    // MARK: - Filter Parameters

    private var filterParametersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            parameterSection(title: "Filter Settings") {
                VStack(spacing: 12) {
                    parameterSlider(
                        label: "Cutoff Frequency",
                        value: .constant(1000),
                        range: 20...20000,
                        unit: "Hz",
                        format: "%.0f"
                    )

                    parameterSlider(
                        label: "Resonance (Q)",
                        value: .constant(1.0),
                        range: 0.1...20,
                        unit: "",
                        format: "%.1f"
                    )

                    parameterSlider(
                        label: "Gain",
                        value: .constant(0),
                        range: -24...24,
                        unit: "dB",
                        format: "%.1f"
                    )
                }
            }

            parameterSection(title: "Bio-Reactive Mapping") {
                VStack(alignment: .leading, spacing: 8) {
                    bioMappingRow(
                        input: "Heart Rate",
                        output: "Cutoff Frequency",
                        range: "40-120 BPM → 200-8000 Hz"
                    )

                    bioMappingRow(
                        input: "HRV Coherence",
                        output: "Resonance",
                        range: "0-100% → 0.5-5.0"
                    )
                }
            }
        }
    }

    // MARK: - Reverb Parameters

    private var reverbParametersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            parameterSection(title: "Reverb Settings") {
                VStack(spacing: 12) {
                    parameterSlider(
                        label: "Wet/Dry Mix",
                        value: .constant(0.5),
                        range: 0...1,
                        unit: "%",
                        format: "%.0f",
                        multiplier: 100
                    )

                    parameterSlider(
                        label: "Room Size",
                        value: .constant(0.5),
                        range: 0...1,
                        unit: "",
                        format: "%.2f"
                    )

                    parameterSlider(
                        label: "Decay Time",
                        value: .constant(2.0),
                        range: 0.1...10,
                        unit: "s",
                        format: "%.1f"
                    )

                    parameterSlider(
                        label: "Damping",
                        value: .constant(0.5),
                        range: 0...1,
                        unit: "%",
                        format: "%.0f",
                        multiplier: 100
                    )
                }
            }

            parameterSection(title: "Bio-Reactive Mapping") {
                VStack(alignment: .leading, spacing: 8) {
                    bioMappingRow(
                        input: "HRV Coherence",
                        output: "Wet/Dry Mix",
                        range: "0-100% → 10-80%"
                    )

                    bioMappingRow(
                        input: "HRV",
                        output: "Room Size",
                        range: "Low-High → Small-Large"
                    )
                }
            }
        }
    }

    // MARK: - Delay Parameters

    private var delayParametersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            parameterSection(title: "Delay Settings") {
                VStack(spacing: 12) {
                    parameterSlider(
                        label: "Delay Time",
                        value: .constant(0.5),
                        range: 0.01...2,
                        unit: "s",
                        format: "%.3f"
                    )

                    parameterSlider(
                        label: "Feedback",
                        value: .constant(0.3),
                        range: 0...0.9,
                        unit: "%",
                        format: "%.0f",
                        multiplier: 100
                    )

                    parameterSlider(
                        label: "Wet/Dry Mix",
                        value: .constant(0.5),
                        range: 0...1,
                        unit: "%",
                        format: "%.0f",
                        multiplier: 100
                    )
                }
            }

            parameterSection(title: "Bio-Reactive Mapping") {
                VStack(alignment: .leading, spacing: 8) {
                    bioMappingRow(
                        input: "Heart Rate",
                        output: "Delay Time",
                        range: "Tempo-synced to BPM"
                    )

                    bioMappingRow(
                        input: "HRV Coherence",
                        output: "Feedback",
                        range: "0-100% → 10-70%"
                    )
                }
            }
        }
    }

    // MARK: - Compressor Parameters

    private var compressorParametersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            parameterSection(title: "Compressor Settings") {
                VStack(spacing: 12) {
                    parameterSlider(
                        label: "Threshold",
                        value: .constant(-20),
                        range: -60...0,
                        unit: "dB",
                        format: "%.1f"
                    )

                    parameterSlider(
                        label: "Ratio",
                        value: .constant(4),
                        range: 1...20,
                        unit: ":1",
                        format: "%.1f"
                    )

                    parameterSlider(
                        label: "Attack",
                        value: .constant(10),
                        range: 0.1...100,
                        unit: "ms",
                        format: "%.1f"
                    )

                    parameterSlider(
                        label: "Release",
                        value: .constant(100),
                        range: 10...1000,
                        unit: "ms",
                        format: "%.0f"
                    )

                    parameterSlider(
                        label: "Makeup Gain",
                        value: .constant(0),
                        range: 0...24,
                        unit: "dB",
                        format: "%.1f"
                    )
                }
            }

            parameterSection(title: "Bio-Reactive Mapping") {
                VStack(alignment: .leading, spacing: 8) {
                    bioMappingRow(
                        input: "Respiratory Rate",
                        output: "Threshold",
                        range: "Slow/Normal/Fast → Light/Balanced/Heavy"
                    )

                    bioMappingRow(
                        input: "HRV Coherence",
                        output: "Attack/Release",
                        range: "High → Fast attack, Low → Slow release"
                    )
                }
            }
        }
    }

    // MARK: - Generic Parameters

    private var genericParametersView: some View {
        VStack(alignment: .leading, spacing: 16) {
            parameterSection(title: "Settings") {
                Text("No adjustable parameters available")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Bypass Toggle

    private var bypassToggleView: some View {
        HStack {
            Text("Bypass Effect")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .tint(.cyan)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Helper Components

    private func parameterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            content()
        }
    }

    private func parameterSlider(
        label: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        unit: String,
        format: String,
        multiplier: Float = 1.0
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                Text(String(format: format, value.wrappedValue * multiplier) + unit)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan)
            }

            Slider(value: value, in: range)
                .tint(.cyan)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func bioMappingRow(input: String, output: String, range: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.pink.opacity(0.6))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(input)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.pink)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))

                    Text(output)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.cyan)
                }

                Text(range)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var nodeIcon: String {
        let name = node.name.lowercased()

        if name.contains("filter") {
            return "waveform.path"
        } else if name.contains("reverb") {
            return "music.note.house"
        } else if name.contains("delay") {
            return "arrow.triangle.2.circlepath"
        } else if name.contains("compressor") {
            return "waveform.path.ecg"
        } else {
            return "waveform"
        }
    }

    private var nodeColor: Color {
        let name = node.name.lowercased()

        if name.contains("filter") {
            return .purple
        } else if name.contains("reverb") {
            return .blue
        } else if name.contains("delay") {
            return .orange
        } else if name.contains("compressor") {
            return .green
        } else {
            return .cyan
        }
    }

    private var nodeType: String {
        let name = node.name.lowercased()

        if name.contains("filter") {
            return "Frequency Filter"
        } else if name.contains("reverb") {
            return "Reverb Effect"
        } else if name.contains("delay") {
            return "Delay Effect"
        } else if name.contains("compressor") {
            return "Dynamic Compressor"
        } else {
            return "Audio Effect"
        }
    }

    private var bioReactiveDescription: String {
        let name = node.name.lowercased()

        if name.contains("filter") {
            return "This filter automatically adjusts its cutoff frequency based on your heart rate and resonance based on HRV coherence, creating a sound that responds to your physiological state."
        } else if name.contains("reverb") {
            return "The reverb wetness and room size adapt to your HRV coherence level, creating more spacious sounds during high coherence states."
        } else if name.contains("delay") {
            return "Delay time synchronizes with your heart rate for musical timing, while feedback amount responds to your HRV coherence level."
        } else if name.contains("compressor") {
            return "Compression threshold follows your respiratory rate, and attack/release times adapt to your HRV coherence for natural dynamics."
        } else {
            return "This effect responds to your biometric data in real-time."
        }
    }
}
