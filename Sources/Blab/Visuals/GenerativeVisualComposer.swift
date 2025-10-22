import Foundation

// MARK: - Generative Visual Types

/// Output mediums supported by the generative visual pipeline.
public enum OutputMedium: String, CaseIterable, Hashable {
    case immersive360 = "Immersive 360"
    case sculptural = "Sculptural Installation"
    case facadeProjection = "Façade Projection"
    case hologram = "Hologram"

    /// Display friendly title.
    public var displayName: String { rawValue }
}

/// Request describing how generative visual content should be produced.
public struct GenerativeVisualRequest: Equatable {

    /// User prompt describing the desired mood, scene and narrative.
    public var prompt: String?

    /// Imported media assets that should be analysed and incorporated.
    public var importedAssets: [ImportedAsset]

    /// Explicit target mediums. When empty the composer infers a full multimodal set.
    public var targetMediums: [OutputMedium]

    /// Preferred technologies (e.g. LED dome vs projection).
    public var preferredTechnologies: Set<GenerativeVisualExperience.DisplayTechnology>

    /// Whether audio energy should animate the generated visuals.
    public var enableAudioReactivity: Bool

    /// Whether bio-signals (HRV/heart rate) should drive modulation.
    public var enableBioSignalModulation: Bool

    public init(
        prompt: String? = nil,
        importedAssets: [ImportedAsset] = [],
        targetMediums: [OutputMedium] = [],
        preferredTechnologies: Set<GenerativeVisualExperience.DisplayTechnology> = [],
        enableAudioReactivity: Bool = true,
        enableBioSignalModulation: Bool = true
    ) {
        self.prompt = prompt
        self.importedAssets = importedAssets
        self.targetMediums = targetMediums
        self.preferredTechnologies = preferredTechnologies
        self.enableAudioReactivity = enableAudioReactivity
        self.enableBioSignalModulation = enableBioSignalModulation
    }

    /// Media asset delivered by the user.
    public struct ImportedAsset: Equatable {
        public let kind: Kind
        public let traits: Set<Trait>
        public let dominantColors: [ColorDescriptor]
        public let metadata: [String: String]

        public init(
            kind: Kind,
            traits: Set<Trait> = [],
            dominantColors: [ColorDescriptor] = [],
            metadata: [String: String] = [:]
        ) {
            self.kind = kind
            self.traits = traits
            self.dominantColors = dominantColors
            self.metadata = metadata
        }

        public enum Kind: String {
            case image
            case video
            case depthScan
            case mesh
            case pointCloud
        }

        public enum Trait: String, CaseIterable, Hashable {
            case panoramic
            case volumetric
            case architectural
            case holographic
            case motion
            case textureRich
            case sculptureReference
            case facadeReference
            case loopable
        }
    }

    /// Simple colour description used for palette reasoning without requiring SwiftUI.
    public struct ColorDescriptor: Equatable {
        public let hue: Double
        public let saturation: Double
        public let brightness: Double

        public init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.brightness = brightness
        }
    }
}

/// Resulting experience blueprint describing generated assets and mappings.
public struct GenerativeVisualExperience: Equatable {
    public var scenes: [SceneDescriptor]
    public var animationMappings: [AnimationMapping]
    public var mediumInstructions: [MediumInstruction]
    public var summary: Summary
    public var reactiveState: ReactiveState

    public struct SceneDescriptor: Equatable {
        public let name: String
        public let primaryMedium: OutputMedium
        public let mood: Mood
        public let lighting: Lighting
        public let motionStyle: MotionStyle

        public enum Mood: String {
            case calm
            case energetic
            case mystical
            case futuristic
            case organic
            case neutral
        }

        public enum Lighting: String {
            case softGradient
            case highContrast
            case volumetric
            case architecturalWash
            case holoBeam
        }

        public enum MotionStyle: String {
            case audioReactive
            case slowDrift
            case gestureResponsive
            case holographicParallax
            case breathing
        }
    }

    public struct AnimationMapping: Equatable {
        public var trigger: Trigger
        public var targetMedium: OutputMedium
        public var intensityRange: ClosedRange<Double>
        public var currentIntensity: Double
        public var description: String

        public enum Trigger: String {
            case audioLevel
            case bioSignal
            case gesture
            case tempo
            case timecode
        }
    }

    public struct MediumInstruction: Equatable {
        public let medium: OutputMedium
        public let technology: TechnologyProfile
        public let generatedAssets: [GeneratedAsset]
        public let mappingNotes: [String]
    }

    public struct GeneratedAsset: Equatable {
        public let type: AssetType
        public let identifier: String
        public let parameters: [String: String]

        public enum AssetType: String {
            case panoramicEnvironment
            case volumetricSculpture
            case facadeProjectionMap
            case hologramLayer
            case animationSequence
        }
    }

    public struct TechnologyProfile: Equatable {
        public let displayTechnology: DisplayTechnology
        public let recommendedHardware: [String]
        public let notes: String
    }

    public enum DisplayTechnology: String, CaseIterable, Hashable {
        case ledDome = "LED Dome"
        case projectionMapping = "Projection Mapping"
        case volumetricCapture = "Volumetric Capture"
        case holographicFan = "Holographic Fan Array"
        case mixedRealityHeadset = "Mixed Reality Headset"
        case cncFabrication = "CNC Fabrication"
        case threeDPrinting = "3D Printing"
        case laserScanning = "Laser Scanning"
    }

    public struct Summary: Equatable {
        public let keywords: [String]
        public let paletteDescription: String
        public let mediums: [OutputMedium]
    }

    public struct ReactiveState: Equatable {
        public var audioLevel: Double
        public var bioSignalStrength: Double
    }
}

// MARK: - Generative Visual Composer

@MainActor
public final class GenerativeVisualComposer: ObservableObject {

    @Published public private(set) var currentExperience: GenerativeVisualExperience?

    public init() {}

    /// Compose a full multimodal experience blueprint from the request data.
    @discardableResult
    public func composeExperience(from request: GenerativeVisualRequest) -> GenerativeVisualExperience {
        let mediums = sanitizedMediums(from: request)
        let promptSummary = analyzePrompt(request.prompt)
        let assetSummary = analyzeAssets(request.importedAssets)

        let scenes = buildScenes(
            for: mediums,
            promptSummary: promptSummary,
            assetSummary: assetSummary
        )

        let mediumInstructions = mediums.map { medium in
            createInstruction(
                for: medium,
                promptSummary: promptSummary,
                assetSummary: assetSummary,
                request: request
            )
        }

        let animationMappings = buildAnimationMappings(
            for: mediums,
            request: request,
            promptSummary: promptSummary,
            assetSummary: assetSummary
        )

        let paletteDescription = describePalette(
            assetSummary.palette,
            promptSummary: promptSummary
        )

        let summary = GenerativeVisualExperience.Summary(
            keywords: promptSummary.keywords,
            paletteDescription: paletteDescription,
            mediums: mediums
        )

        let experience = GenerativeVisualExperience(
            scenes: scenes,
            animationMappings: animationMappings,
            mediumInstructions: mediumInstructions,
            summary: summary,
            reactiveState: .init(audioLevel: 0, bioSignalStrength: 0)
        )

        currentExperience = experience
        return experience
    }

    /// Update the reactive state so downstream UIs reflect live modulation.
    public func updateReactiveState(audioLevel: Double, bioSignal: Double?) {
        guard var experience = currentExperience else { return }

        experience.reactiveState.audioLevel = clamp(audioLevel, min: 0, max: 1)
        if let bioSignal {
            experience.reactiveState.bioSignalStrength = clamp(bioSignal, min: 0, max: 1)
        }

        experience.animationMappings = experience.animationMappings.map { mapping in
            var updated = mapping
            let normalized: Double
            switch mapping.trigger {
            case .audioLevel:
                normalized = experience.reactiveState.audioLevel
            case .bioSignal:
                normalized = experience.reactiveState.bioSignalStrength
            case .gesture:
                normalized = clamp(experience.reactiveState.audioLevel * 0.75, min: 0, max: 1)
            case .tempo, .timecode:
                normalized = clamp((experience.reactiveState.audioLevel + experience.reactiveState.bioSignalStrength) / 2.0, min: 0, max: 1)
            }
            updated.currentIntensity = scale(normalized, into: mapping.intensityRange)
            return updated
        }

        currentExperience = experience
    }

    /// Clear the currently cached experience.
    public func reset() {
        currentExperience = nil
    }

    // MARK: - Medium Sanitisation

    private func sanitizedMediums(from request: GenerativeVisualRequest) -> [OutputMedium] {
        var mediums = request.targetMediums
        if mediums.isEmpty {
            // Default to the full suite requested by the product vision.
            mediums = OutputMedium.allCases
        }

        // Ensure unique ordering for deterministic UI.
        var seen = Set<OutputMedium>()
        let ordered = mediums.filter { medium in
            if seen.contains(medium) {
                return false
            }
            seen.insert(medium)
            return true
        }
        return ordered
    }

    // MARK: - Prompt + Asset Analysis

    private struct PromptSummary {
        let keywords: [String]
        let mood: GenerativeVisualExperience.SceneDescriptor.Mood
        let energy: Double
        let tone: Tone

        enum Tone {
            case mystical
            case futuristic
            case organic
            case energetic
            case calm
            case neutral
        }
    }

    private struct AssetSummary {
        var hasPanoramic = false
        var hasVolumetric = false
        var hasArchitectural = false
        var hasHolographic = false
        var hasMotionReferences = false
        var palette: [GenerativeVisualRequest.ColorDescriptor] = []
        var subjects: [String] = []
    }

    private func analyzePrompt(_ prompt: String?) -> PromptSummary {
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PromptSummary(
                keywords: [],
                mood: .neutral,
                energy: 0.5,
                tone: .neutral
            )
        }

        let cleaned = prompt.lowercased()
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }

        var mood: GenerativeVisualExperience.SceneDescriptor.Mood = .neutral
        var tone: PromptSummary.Tone = .neutral
        var energy: Double = 0.5

        if cleaned.contains("calm") || cleaned.contains("meditation") || cleaned.contains("serene") {
            mood = .calm
            tone = .calm
            energy = 0.35
        }

        if cleaned.contains("energetic") || cleaned.contains("vibrant") || cleaned.contains("dance") {
            mood = .energetic
            tone = .energetic
            energy = 0.8
        }

        if cleaned.contains("futuristic") || cleaned.contains("cyber") || cleaned.contains("neon") {
            mood = .futuristic
            tone = .futuristic
            energy = max(energy, 0.65)
        }

        if cleaned.contains("forest") || cleaned.contains("organic") || cleaned.contains("nature") {
            mood = .organic
            tone = .organic
            energy = min(energy, 0.55)
        }

        if cleaned.contains("mystic") || cleaned.contains("temple") || cleaned.contains("cosmic") {
            mood = .mystical
            tone = .mystical
            energy = max(energy, 0.6)
        }

        let keywords = Array(Set(words)).sorted()
        return PromptSummary(keywords: keywords, mood: mood, energy: energy, tone: tone)
    }

    private func analyzeAssets(_ assets: [GenerativeVisualRequest.ImportedAsset]) -> AssetSummary {
        guard !assets.isEmpty else { return AssetSummary() }

        var summary = AssetSummary()
        for asset in assets {
            if asset.traits.contains(.panoramic) { summary.hasPanoramic = true }
            if asset.traits.contains(.volumetric) { summary.hasVolumetric = true }
            if asset.traits.contains(.architectural) || asset.traits.contains(.facadeReference) { summary.hasArchitectural = true }
            if asset.traits.contains(.holographic) { summary.hasHolographic = true }
            if asset.traits.contains(.motion) { summary.hasMotionReferences = true }
            summary.palette.append(contentsOf: asset.dominantColors)

            if let subject = asset.metadata["subject"], !subject.isEmpty {
                summary.subjects.append(subject)
            }
        }
        return summary
    }

    // MARK: - Scene Construction

    private func buildScenes(
        for mediums: [OutputMedium],
        promptSummary: PromptSummary,
        assetSummary: AssetSummary
    ) -> [GenerativeVisualExperience.SceneDescriptor] {
        mediums.enumerated().map { index, medium in
            let name = sceneName(for: medium, index: index)
            return GenerativeVisualExperience.SceneDescriptor(
                name: name,
                primaryMedium: medium,
                mood: promptSummary.mood,
                lighting: lighting(for: medium, assets: assetSummary),
                motionStyle: motionStyle(for: medium, tone: promptSummary.tone)
            )
        }
    }

    private func sceneName(for medium: OutputMedium, index: Int) -> String {
        switch medium {
        case .immersive360:
            return "Immersive Sphere \(index + 1)"
        case .sculptural:
            return "Sonic Sculpture \(index + 1)"
        case .facadeProjection:
            return "Architectural Canvas \(index + 1)"
        case .hologram:
            return "Holographic Halo \(index + 1)"
        }
    }

    private func lighting(
        for medium: OutputMedium,
        assets: AssetSummary
    ) -> GenerativeVisualExperience.SceneDescriptor.Lighting {
        switch medium {
        case .immersive360:
            return assets.hasPanoramic ? .volumetric : .softGradient
        case .sculptural:
            return assets.hasVolumetric ? .volumetric : .highContrast
        case .facadeProjection:
            return .architecturalWash
        case .hologram:
            return .holoBeam
        }
    }

    private func motionStyle(
        for medium: OutputMedium,
        tone: PromptSummary.Tone
    ) -> GenerativeVisualExperience.SceneDescriptor.MotionStyle {
        switch medium {
        case .immersive360:
            return tone == .calm ? .slowDrift : .audioReactive
        case .sculptural:
            return tone == .organic ? .breathing : .gestureResponsive
        case .facadeProjection:
            return .audioReactive
        case .hologram:
            return .holographicParallax
        }
    }

    // MARK: - Medium Instructions

    private func createInstruction(
        for medium: OutputMedium,
        promptSummary: PromptSummary,
        assetSummary: AssetSummary,
        request: GenerativeVisualRequest
    ) -> GenerativeVisualExperience.MediumInstruction {
        let technology = selectTechnology(
            for: medium,
            preferred: request.preferredTechnologies,
            assets: assetSummary
        )
        let generatedAssets = generateAssets(
            for: medium,
            promptSummary: promptSummary,
            assetSummary: assetSummary
        )
        let notes = mappingNotes(
            for: medium,
            promptSummary: promptSummary,
            assetSummary: assetSummary,
            request: request
        )

        return GenerativeVisualExperience.MediumInstruction(
            medium: medium,
            technology: technology,
            generatedAssets: generatedAssets,
            mappingNotes: notes
        )
    }

    private func selectTechnology(
        for medium: OutputMedium,
        preferred: Set<GenerativeVisualExperience.DisplayTechnology>,
        assets: AssetSummary
    ) -> GenerativeVisualExperience.TechnologyProfile {
        let fallback: GenerativeVisualExperience.DisplayTechnology
        switch medium {
        case .immersive360:
            if preferred.contains(.ledDome) { fallback = .ledDome }
            else if preferred.contains(.mixedRealityHeadset) { fallback = .mixedRealityHeadset }
            else if preferred.contains(.projectionMapping) { fallback = .projectionMapping }
            else { fallback = assets.hasPanoramic ? .projectionMapping : .mixedRealityHeadset }
        case .sculptural:
            if preferred.contains(.threeDPrinting) { fallback = .threeDPrinting }
            else if preferred.contains(.cncFabrication) { fallback = .cncFabrication }
            else { fallback = assets.hasVolumetric ? .threeDPrinting : .cncFabrication }
        case .facadeProjection:
            fallback = preferred.contains(.projectionMapping) ? .projectionMapping : .projectionMapping
        case .hologram:
            if preferred.contains(.holographicFan) { fallback = .holographicFan }
            else if preferred.contains(.volumetricCapture) { fallback = .volumetricCapture }
            else { fallback = assets.hasHolographic ? .holographicFan : .volumetricCapture }
        }

        return GenerativeVisualExperience.TechnologyProfile(
            displayTechnology: fallback,
            recommendedHardware: recommendedHardware(for: fallback, medium: medium),
            notes: technologyNotes(for: fallback, medium: medium, assets: assets)
        )
    }

    private func recommendedHardware(
        for technology: GenerativeVisualExperience.DisplayTechnology,
        medium: OutputMedium
    ) -> [String] {
        switch technology {
        case .ledDome:
            return ["180° LED dome", "Realtime media server"]
        case .projectionMapping:
            return ["20K lumen laser projectors", "Spatial calibration rig"]
        case .volumetricCapture:
            return ["Depth camera array", "Volumetric reconstruction workstation"]
        case .holographicFan:
            return ["Holographic fan grid", "Playback controller"]
        case .mixedRealityHeadset:
            return ["Apple Vision Pro", "XR spatial anchors"]
        case .cncFabrication:
            return ["5-axis CNC", "Aluminium or acrylic blocks"]
        case .threeDPrinting:
            return ["Resin 3D printer", "Transparent resin materials"]
        case .laserScanning:
            return ["LIDAR scanning rig", "Point cloud cleaning workstation"]
        }
    }

    private func technologyNotes(
        for technology: GenerativeVisualExperience.DisplayTechnology,
        medium: OutputMedium,
        assets: AssetSummary
    ) -> String {
        switch technology {
        case .ledDome:
            return "Wrap-around 360° playback driven by audio-reactive shaders."
        case .projectionMapping:
            return assets.hasArchitectural ? "Uses façade reference meshes for distortion-free mapping." : "Requires onsite architectural scan for precise warping."
        case .volumetricCapture:
            return "Integrates volumetric footage with generative particle shells."
        case .holographicFan:
            return "Multi-layer fan array for floating holographic sculptures."
        case .mixedRealityHeadset:
            return "Spatial anchors sync holographic layers with physical space."
        case .cncFabrication:
            return "Toolpaths derived from generative field equations."
        case .threeDPrinting:
            return "Translucent prints illuminated with internal LED matrices."
        case .laserScanning:
            return "Capture existing sculptures for remix with generative layers."
        }
    }

    private func generateAssets(
        for medium: OutputMedium,
        promptSummary: PromptSummary,
        assetSummary: AssetSummary
    ) -> [GenerativeVisualExperience.GeneratedAsset] {
        switch medium {
        case .immersive360:
            return [
                .init(
                    type: .panoramicEnvironment,
                    identifier: "immersive_environment",
                    parameters: [
                        "mood": promptSummary.mood.rawValue,
                        "energy": String(format: "%.2f", promptSummary.energy),
                        "subject": assetSummary.subjects.first ?? "abstract"
                    ]
                ),
                .init(
                    type: .animationSequence,
                    identifier: "360_transition_layers",
                    parameters: ["layers": "aurora, bio-plasma", "loop": "true"]
                )
            ]
        case .sculptural:
            return [
                .init(
                    type: .volumetricSculpture,
                    identifier: "resonant_totem",
                    parameters: [
                        "structure": assetSummary.hasVolumetric ? "hybrid-scan" : "procedural",
                        "finish": "bioluminescent"
                    ]
                )
            ]
        case .facadeProjection:
            return [
                .init(
                    type: .facadeProjectionMap,
                    identifier: "facade_master_map",
                    parameters: [
                        "resolution": assetSummary.hasArchitectural ? "native" : "needs_scan",
                        "layers": "geometry, lightwaves, typography"
                    ]
                )
            ]
        case .hologram:
            return [
                .init(
                    type: .hologramLayer,
                    identifier: "floating_orbitals",
                    parameters: [
                        "parallax": assetSummary.hasHolographic ? "captured" : "synthetic",
                        "density": promptSummary.energy > 0.6 ? "high" : "medium"
                    ]
                )
            ]
        }
    }

    private func mappingNotes(
        for medium: OutputMedium,
        promptSummary: PromptSummary,
        assetSummary: AssetSummary,
        request: GenerativeVisualRequest
    ) -> [String] {
        var notes: [String] = []

        switch medium {
        case .immersive360:
            notes.append("360° shaders morph with audio amplitude in realtime.")
            if assetSummary.hasPanoramic {
                notes.append("Imported panoramic footage sets base horizon.")
            }
        case .sculptural:
            notes.append("Sculpture geometry breathes with biometric coherence.")
            if assetSummary.hasVolumetric {
                notes.append("Volumetric scans blended with neural field surfaces.")
            }
        case .facadeProjection:
            notes.append("Projection map locks to architectural edges for clarity.")
            if !assetSummary.hasArchitectural {
                notes.append("Requires onsite scan to finalise distortion mesh.")
            }
        case .hologram:
            notes.append("Layered particle shells create volumetric depth cues.")
            if assetSummary.hasHolographic {
                notes.append("Depth captures drive accurate parallax phase shifts.")
            }
        }

        if request.enableAudioReactivity {
            notes.append("Audio ↔ visual mapping emphasises \(promptSummary.mood.rawValue) energy.")
        }
        if request.enableBioSignalModulation {
            notes.append("Bio-signals modulate colour temperature and density.")
        }
        if !promptSummary.keywords.isEmpty {
            notes.append("Prompt keywords: \(promptSummary.keywords.joined(separator: ", ")).")
        }

        return notes
    }

    // MARK: - Animation Mapping

    private func buildAnimationMappings(
        for mediums: [OutputMedium],
        request: GenerativeVisualRequest,
        promptSummary: PromptSummary,
        assetSummary: AssetSummary
    ) -> [GenerativeVisualExperience.AnimationMapping] {
        var mappings: [GenerativeVisualExperience.AnimationMapping] = []

        if request.enableAudioReactivity {
            for medium in mediums {
                mappings.append(
                    GenerativeVisualExperience.AnimationMapping(
                        trigger: .audioLevel,
                        targetMedium: medium,
                        intensityRange: 0.2...1.0,
                        currentIntensity: 0.2,
                        description: "Audio amplitude drives luminosity envelopes"
                    )
                )
            }
        }

        if request.enableBioSignalModulation, mediums.contains(.sculptural) {
            mappings.append(
                GenerativeVisualExperience.AnimationMapping(
                    trigger: .bioSignal,
                    targetMedium: .sculptural,
                    intensityRange: 0.1...0.9,
                    currentIntensity: 0.1,
                    description: "HRV coherence modulates sculpture breathing cadence"
                )
            )
        }

        if assetSummary.hasMotionReferences, mediums.contains(.hologram) {
            mappings.append(
                GenerativeVisualExperience.AnimationMapping(
                    trigger: .gesture,
                    targetMedium: .hologram,
                    intensityRange: 0.3...1.0,
                    currentIntensity: 0.3,
                    description: "Motion capture gestures ripple through holographic trails"
                )
            )
        }

        // Tempo alignment for façade sequences keeps architectural rhythm.
        if mediums.contains(.facadeProjection) {
            mappings.append(
                GenerativeVisualExperience.AnimationMapping(
                    trigger: .tempo,
                    targetMedium: .facadeProjection,
                    intensityRange: 0.15...0.85,
                    currentIntensity: 0.15,
                    description: "Global tempo sync ensures façade beats align with audio BPM"
                )
            )
        }

        // Timecode anchors to orchestrate multi-medium cues.
        if mediums.contains(.immersive360) {
            mappings.append(
                GenerativeVisualExperience.AnimationMapping(
                    trigger: .timecode,
                    targetMedium: .immersive360,
                    intensityRange: 0.25...0.95,
                    currentIntensity: 0.25,
                    description: "Chapter cues transition immersive environment narratives"
                )
            )
        }

        return mappings
    }

    // MARK: - Palette Description

    private func describePalette(
        _ palette: [GenerativeVisualRequest.ColorDescriptor],
        promptSummary: PromptSummary
    ) -> String {
        guard !palette.isEmpty else {
            switch promptSummary.mood {
            case .calm:
                return "Soft teal gradients with gentle lavender accents"
            case .energetic:
                return "High-energy magenta and electric cyan waves"
            case .mystical:
                return "Iridescent violets with golden highlights"
            case .futuristic:
                return "Neon cyan beams on deep indigo backgrounds"
            case .organic:
                return "Bioluminescent greens fading into warm ambers"
            case .neutral:
                return "Balanced cool and warm neutrals"
            }
        }

        let averageHue = palette.map { $0.hue }.reduce(0, +) / Double(palette.count)
        let averageSaturation = palette.map { $0.saturation }.reduce(0, +) / Double(palette.count)
        let averageBrightness = palette.map { $0.brightness }.reduce(0, +) / Double(palette.count)

        let hueDescription: String
        switch averageHue {
        case 0..<0.1, 0.9...1:
            hueDescription = "crimson"
        case 0.1..<0.25:
            hueDescription = "ember"
        case 0.25..<0.45:
            hueDescription = "golden"
        case 0.45..<0.65:
            hueDescription = "teal"
        case 0.65..<0.85:
            hueDescription = "violet"
        default:
            hueDescription = "magenta"
        }

        let saturationDescription = averageSaturation > 0.6 ? "vivid" : (averageSaturation > 0.3 ? "balanced" : "muted")
        let brightnessDescription = averageBrightness > 0.6 ? "luminous" : (averageBrightness > 0.3 ? "soft" : "nocturnal")

        return "\(brightnessDescription.capitalized) \(hueDescription) spectrum with \(saturationDescription) highlights"
    }

    // MARK: - Helpers

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func scale(_ normalized: Double, into range: ClosedRange<Double>) -> Double {
        let clamped = clamp(normalized, min: 0, max: 1)
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + (span * clamped)
    }
}
