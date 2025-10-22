import XCTest
@testable import Blab

@MainActor
final class GenerativeVisualComposerTests: XCTestCase {

    func testDefaultMediumsCoversImmersivePipeline() {
        let composer = GenerativeVisualComposer()
        let request = GenerativeVisualRequest(
            prompt: "Mystical aurora temple",
            importedAssets: [],
            targetMediums: [],
            preferredTechnologies: [],
            enableAudioReactivity: true,
            enableBioSignalModulation: true
        )

        let experience = composer.composeExperience(from: request)
        XCTAssertEqual(Set(experience.summary.mediums), Set(OutputMedium.allCases))
        XCTAssertEqual(experience.mediumInstructions.count, OutputMedium.allCases.count)
    }

    func testArchitecturalAssetPrefersProjectionMapping() {
        let composer = GenerativeVisualComposer()
        let asset = GenerativeVisualRequest.ImportedAsset(
            kind: .image,
            traits: [.architectural],
            dominantColors: [],
            metadata: ["subject": "opera house"]
        )
        let request = GenerativeVisualRequest(
            prompt: "Projection show",
            importedAssets: [asset],
            targetMediums: [.facadeProjection],
            preferredTechnologies: [],
            enableAudioReactivity: false,
            enableBioSignalModulation: false
        )

        let experience = composer.composeExperience(from: request)
        let instruction = experience.mediumInstructions.first(where: { $0.medium == .facadeProjection })
        XCTAssertEqual(instruction?.technology.displayTechnology, .projectionMapping)
        XCTAssertTrue(instruction?.mappingNotes.contains(where: { $0.contains("Projection map") }) ?? false)
    }

    func testReactiveStateClampsValues() {
        let composer = GenerativeVisualComposer()
        let request = GenerativeVisualRequest()
        composer.composeExperience(from: request)

        composer.updateReactiveState(audioLevel: 2.5, bioSignal: -0.5)

        guard let experience = composer.currentExperience else {
            return XCTFail("Expected experience to be available after update")
        }

        XCTAssertEqual(experience.reactiveState.audioLevel, 1.0, accuracy: 0.0001)
        XCTAssertEqual(experience.reactiveState.bioSignalStrength, 0.0, accuracy: 0.0001)
    }
}
