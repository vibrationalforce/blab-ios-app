import Foundation

/// Generates captions, hashtags, and cover metadata for social distribution.
struct PromotionArtifact: Codable {
    let caption: String
    let hashtags: [String]
    let coverTitle: String
    let palette: [String]
}

@MainActor
final class PromotionManager {
    func generateArtifacts(from metadata: BlabMetadata) -> PromotionArtifact {
        let bpmDescriptor: String
        switch metadata.bpm {
        case ..<70: bpmDescriptor = "slow-breath"
        case ..<110: bpmDescriptor = "meditative-flow"
        case ..<140: bpmDescriptor = "focused-groove"
        default: bpmDescriptor = "peak-energy"
        }

        let caption = "\(metadata.title) — a \(metadata.emotion.lowercased()) journey at \(Int(metadata.bpm)) BPM"
        let hashtags = buildHashtags(metadata: metadata, bpmDescriptor: bpmDescriptor)
        let palette = paletteForEmotion(metadata.emotion)

        return PromotionArtifact(
            caption: caption,
            hashtags: hashtags,
            coverTitle: metadata.title,
            palette: palette
        )
    }

    private func buildHashtags(metadata: BlabMetadata, bpmDescriptor: String) -> [String] {
        var tags: Set<String> = ["#blab", "#biofeedback", "#soundhealing", "#\(bpmDescriptor)"]
        tags.insert("#\(metadata.emotion.lowercased().replacingOccurrences(of: " ", with: ""))")
        tags.formUnion(metadata.instruments.map { "#\($0.lowercased())" })
        if metadata.spatial.lowercased() == "3d" { tags.insert("#spatialaudio") }
        return Array(tags).sorted()
    }

    private func paletteForEmotion(_ emotion: String) -> [String] {
        switch emotion.lowercased() {
        case let label where label.contains("calm"):
            return ["#0f172a", "#1d3557", "#457b9d"]
        case let label where label.contains("energy"):
            return ["#ff7b00", "#ffb700", "#ffda77"]
        case let label where label.contains("euphoric"):
            return ["#6a00f4", "#8e5cff", "#f72585"]
        default:
            return ["#1b1b2f", "#3d2c8d", "#916dd5"]
        }
    }
}
