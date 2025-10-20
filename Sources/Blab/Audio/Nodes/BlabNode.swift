import Foundation
import AVFoundation

/// Protocol for all audio processing nodes in BLAB
/// Every audio effect, generator, or processor must conform to this protocol
///
/// Design Philosophy:
/// - Each node is a self-contained audio processor
/// - Nodes can react to bio-signals in real-time
/// - Nodes are chain-able for complex signal flows
/// - Thread-safe for real-time audio processing
protocol BlabNode: AnyObject {

    // MARK: - Identity

    /// Unique identifier for this node
    var id: UUID { get }

    /// Human-readable name
    var name: String { get }

    /// Node type (effect, generator, analyzer, etc.)
    var type: NodeType { get }


    // MARK: - State

    /// Whether this node is currently bypassed
    var isBypassed: Bool { get set }

    /// Whether this node is currently active/running
    var isActive: Bool { get }


    // MARK: - Audio Processing

    /// Process an audio buffer
    /// - Parameters:
    ///   - buffer: Input audio buffer (may be modified in-place)
    ///   - time: Audio time for synchronization
    /// - Returns: Processed audio buffer
    func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AVAudioPCMBuffer


    // MARK: - Bio-Reactivity

    /// React to bio-signal changes (HRV, heart rate, etc.)
    /// This method is called on main thread, must be non-blocking
    /// - Parameter signal: Bio-signal data
    func react(to signal: BioSignal)


    // MARK: - Configuration

    /// Get all parameters for this node
    var parameters: [NodeParameter] { get }

    /// Set parameter value by name
    /// - Parameters:
    ///   - name: Parameter name
    ///   - value: New value
    func setParameter(name: String, value: Float)

    /// Get parameter value by name
    /// - Parameter name: Parameter name
    /// - Returns: Current value or nil if parameter doesn't exist
    func getParameter(name: String) -> Float?


    // MARK: - Lifecycle

    /// Prepare node for processing (allocate resources)
    func prepare(sampleRate: Double, maxFrames: AVAudioFrameCount)

    /// Start processing
    func start()

    /// Stop processing
    func stop()

    /// Reset node state
    func reset()
}


// MARK: - Supporting Types

/// Node type classification
enum NodeType: String, Codable {
    case generator  // Generates audio (oscillators, samplers)
    case effect     // Processes audio (reverb, delay, filter)
    case analyzer   // Analyzes audio (FFT, pitch detection)
    case mixer      // Mixes multiple audio sources
    case utility    // Utility functions (gain, pan, etc.)
}


/// Bio-signal data for node reactivity
struct BioSignal {
    /// Heart rate variability (ms)
    var hrv: Double

    /// Heart rate (BPM)
    var heartRate: Double

    /// HRV coherence score (0-100, HeartMath)
    var coherence: Double

    /// Respiratory rate (breaths per minute)
    var respiratoryRate: Double?

    /// Audio level (0.0 - 1.0)
    var audioLevel: Float

    /// Voice pitch (Hz)
    var voicePitch: Float

    /// Custom data for extensibility
    var customData: [String: Any]

    init(
        hrv: Double = 0,
        heartRate: Double = 60,
        coherence: Double = 50,
        respiratoryRate: Double? = nil,
        audioLevel: Float = 0,
        voicePitch: Float = 0,
        customData: [String: Any] = [:]
    ) {
        self.hrv = hrv
        self.heartRate = heartRate
        self.coherence = coherence
        self.respiratoryRate = respiratoryRate
        self.audioLevel = audioLevel
        self.voicePitch = voicePitch
        self.customData = customData
    }
}


/// Node parameter definition
struct NodeParameter: Identifiable {
    let id = UUID()

    /// Parameter name (unique within node)
    let name: String

    /// Display label
    let label: String

    /// Current value
    var value: Float

    /// Minimum value
    let min: Float

    /// Maximum value
    let max: Float

    /// Default value
    let defaultValue: Float

    /// Unit (Hz, dB, ms, %, etc.)
    let unit: String?

    /// Whether this parameter can be automated
    let isAutomatable: Bool

    /// Parameter type for UI rendering
    let type: ParameterType

    enum ParameterType {
        case continuous  // Slider
        case discrete    // Stepped values
        case toggle      // On/off switch
        case selection   // Dropdown/picker
    }
}


/// Node manifest for serialization and loading
struct NodeManifest: Codable {
    /// Node ID
    let id: String

    /// Node type
    let type: NodeType

    /// Node class name (for dynamic loading)
    let className: String

    /// Version
    let version: String

    /// Parameters and their current values
    let parameters: [String: Float]

    /// Is bypassed
    let isBypassed: Bool

    /// Custom metadata
    let metadata: [String: String]?
}


// MARK: - Base Implementation

/// Base class for nodes with common functionality
@MainActor
class BaseBlabNode: BlabNode {

    // MARK: - BlabNode Protocol

    let id: UUID
    let name: String
    let type: NodeType

    var isBypassed: Bool = false
    var isActive: Bool = false

    var parameters: [NodeParameter] = []


    // MARK: - Initialization

    init(name: String, type: NodeType) {
        self.id = UUID()
        self.name = name
        self.type = type
    }


    // MARK: - Audio Processing (to be overridden)

    func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AVAudioPCMBuffer {
        // Base implementation: pass-through
        // Subclasses should override
        return buffer
    }


    // MARK: - Bio-Reactivity (to be overridden)

    func react(to signal: BioSignal) {
        // Base implementation: no reaction
        // Subclasses can override to implement bio-reactivity
    }


    // MARK: - Parameters

    func setParameter(name: String, value: Float) {
        if let index = parameters.firstIndex(where: { $0.name == name }) {
            let parameter = parameters[index]
            // Clamp value to range
            let clampedValue = max(parameter.min, min(parameter.max, value))
            parameters[index].value = clampedValue
        }
    }

    func getParameter(name: String) -> Float? {
        return parameters.first(where: { $0.name == name })?.value
    }


    // MARK: - Lifecycle (to be overridden)

    func prepare(sampleRate: Double, maxFrames: AVAudioFrameCount) {
        // Base implementation: no-op
        // Subclasses should override to allocate resources
    }

    func start() {
        isActive = true
    }

    func stop() {
        isActive = false
    }

    func reset() {
        // Reset all parameters to default
        for i in 0..<parameters.count {
            parameters[i].value = parameters[i].defaultValue
        }
    }


    // MARK: - Serialization

    /// Create manifest for this node
    func createManifest() -> NodeManifest {
        let parameterDict = parameters.reduce(into: [String: Float]()) { dict, param in
            dict[param.name] = param.value
        }

        return NodeManifest(
            id: id.uuidString,
            type: type,
            className: String(describing: Swift.type(of: self)),
            version: "1.0",
            parameters: parameterDict,
            isBypassed: isBypassed,
            metadata: nil
        )
    }
}
