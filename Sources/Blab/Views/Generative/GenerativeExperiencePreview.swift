import SwiftUI

/// Renders a summary of the generative visual blueprint so creators can preview
/// how prompts, imported media and live signals map to different mediums.
struct GenerativeExperiencePreview: View {
    let experience: GenerativeVisualExperience?
    let highlightedMedium: OutputMedium?
    let regenerateAction: (() -> Void)?

    private var highlightedInstruction: GenerativeVisualExperience.MediumInstruction? {
        guard let experience else { return nil }
        if let medium = highlightedMedium,
           let instruction = experience.mediumInstructions.first(where: { $0.medium == medium }) {
            return instruction
        }
        return experience.mediumInstructions.first
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.05))

            if let experience {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(experience)
                        mediumStrip(experience)
                        Divider().background(Color.white.opacity(0.1))
                        instructionSection(experience)
                        sceneSection(experience)
                        animationSection(experience)
                        reactiveSection(experience)

                        if let regenerateAction {
                            Button(action: regenerateAction) {
                                Label("Refresh Blueprint", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.top, 12)
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Generative visuals ready")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Select a generative mode to synthesise 360° domes, sculptures, façades or holograms from prompts, videos and images.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if let regenerateAction {
                        Button(action: regenerateAction) {
                            Text("Generate Blueprint")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }
                    }
                }
                .padding(40)
            }
        }
    }

    // MARK: - Sections

    private func header(_ experience: GenerativeVisualExperience) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generative Visual Blueprint")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(experience.summary.paletteDescription)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            if !experience.summary.keywords.isEmpty {
                Text("Keywords: \(experience.summary.keywords.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private func mediumStrip(_ experience: GenerativeVisualExperience) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(experience.summary.mediums, id: \.self) { medium in
                    let isActive = medium == highlightedInstruction?.medium
                    Text(medium.displayName)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isActive ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
        }
    }

    private func instructionSection(_ experience: GenerativeVisualExperience) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medium Mapping")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            if let instruction = highlightedInstruction {
                VStack(alignment: .leading, spacing: 8) {
                    Text(instruction.medium.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                    Text("Technology: \(instruction.technology.displayTechnology.rawValue)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    if !instruction.technology.recommendedHardware.isEmpty {
                        Text("Hardware: \(instruction.technology.recommendedHardware.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    if !instruction.technology.notes.isEmpty {
                        Text(instruction.technology.notes)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }

                    if !instruction.generatedAssets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Generated Assets")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            ForEach(instruction.generatedAssets, id: \.identifier) { asset in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                    if !asset.parameters.isEmpty {
                                        Text(asset.parameters.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.45))
                                    }
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                            }
                        }
                    }

                    if !instruction.mappingNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mapping Notes")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            ForEach(instruction.mappingNotes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.6))
                                        .frame(width: 5, height: 5)
                                    Text(note)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.55))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Select a generative mode to view mapping details.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    private func sceneSection(_ experience: GenerativeVisualExperience) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scenes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            ForEach(experience.scenes, id: \.name) { scene in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(scene.primaryMedium == highlightedInstruction?.medium ? 0.3 : 0.12))
                        .frame(width: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scene.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Mood: \(scene.mood.rawValue.capitalized) • Lighting: \(scene.lighting.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                        Text("Motion: \(scene.motionStyle.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private func animationSection(_ experience: GenerativeVisualExperience) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Modulation")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            ForEach(experience.animationMappings, id: \.description) { mapping in
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trigger: \(mapping.trigger.rawValue.capitalized) → \(mapping.targetMedium.displayName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                    ProgressView(value: normalizedProgress(for: mapping))
                        .accentColor(Color.accentColor)
                    Text(intensityLabel(for: mapping))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.35))
                    Text(mapping.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            }
        }
    }

    private func reactiveSection(_ experience: GenerativeVisualExperience) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Realtime State")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            HStack(spacing: 16) {
                reactiveTile(
                    title: "Audio Energy",
                    value: experience.reactiveState.audioLevel,
                    color: Color.cyan
                )
                reactiveTile(
                    title: "Bio Signal",
                    value: experience.reactiveState.bioSignalStrength,
                    color: Color.pink
                )
            }
        }
    }

    private func reactiveTile(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            ProgressView(value: value)
                .accentColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Helpers

private func normalizedProgress(for mapping: GenerativeVisualExperience.AnimationMapping) -> Double {
    let span = mapping.intensityRange.upperBound - mapping.intensityRange.lowerBound
    guard span > 0 else { return 0 }
    let normalized = (mapping.currentIntensity - mapping.intensityRange.lowerBound) / span
    return max(0, min(1, normalized))
}

private func intensityLabel(for mapping: GenerativeVisualExperience.AnimationMapping) -> String {
    String(
        format: "Intensity %.2f (range %.2f–%.2f)",
        mapping.currentIntensity,
        mapping.intensityRange.lowerBound,
        mapping.intensityRange.upperBound
    )
}

struct GenerativeExperiencePreview_Previews: PreviewProvider {
    static var previews: some View {
        GenerativeExperiencePreview(
            experience: nil,
            highlightedMedium: nil,
            regenerateAction: {}
        )
        .frame(height: 320)
        .padding()
        .background(Color.black)
    }
}
