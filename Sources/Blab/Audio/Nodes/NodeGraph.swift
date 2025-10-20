import Foundation
import AVFoundation
import Combine

/// Manages a graph of interconnected audio processing nodes
/// Handles signal routing, parameter automation, and bio-reactivity
@MainActor
class NodeGraph: ObservableObject {

    // MARK: - Published Properties

    /// All nodes in the graph
    @Published var nodes: [BlabNode] = []

    /// Active connections between nodes
    @Published var connections: [NodeConnection] = []

    /// Whether the graph is currently processing
    @Published var isProcessing: Bool = false


    // MARK: - Private Properties

    /// Cancellables for Combine
    private var cancellables = Set<AnyCancellable>()

    /// Current bio-signal for reactivity
    private var currentBioSignal = BioSignal()

    /// Processing queue (audio thread)
    private let audioQueue = DispatchQueue(
        label: "com.blab.nodegraph.audio",
        qos: .userInteractive
    )


    // MARK: - Node Management

    /// Add a node to the graph
    func addNode(_ node: BlabNode) {
        nodes.append(node)
        print("📊 Added node: \(node.name) (\(node.type.rawValue))")
    }

    /// Remove a node from the graph
    func removeNode(id: UUID) {
        // Remove connections involving this node
        connections.removeAll { connection in
            connection.sourceNodeID == id || connection.destinationNodeID == id
        }

        // Remove node
        nodes.removeAll { $0.id == id }
    }

    /// Get node by ID
    func node(withID id: UUID) -> BlabNode? {
        return nodes.first { $0.id == id }
    }


    // MARK: - Connection Management

    /// Connect two nodes
    func connect(from sourceID: UUID, to destinationID: UUID) throws {
        guard let source = node(withID: sourceID),
              let destination = node(withID: destinationID) else {
            throw NodeGraphError.nodeNotFound
        }

        // Check for circular dependencies
        if wouldCreateCycle(connecting: sourceID, to: destinationID) {
            throw NodeGraphError.circularDependency
        }

        let connection = NodeConnection(
            sourceNodeID: sourceID,
            destinationNodeID: destinationID
        )

        connections.append(connection)

        print("📊 Connected: \(source.name) → \(destination.name)")
    }

    /// Disconnect two nodes
    func disconnect(from sourceID: UUID, to destinationID: UUID) {
        connections.removeAll { connection in
            connection.sourceNodeID == sourceID &&
            connection.destinationNodeID == destinationID
        }
    }

    /// Check if connecting two nodes would create a cycle
    private func wouldCreateCycle(connecting sourceID: UUID, to destinationID: UUID) -> Bool {
        // Simple cycle detection: check if destination has path back to source
        var visited = Set<UUID>()
        var queue = [destinationID]

        while !queue.isEmpty {
            let current = queue.removeFirst()

            if current == sourceID {
                return true  // Cycle detected
            }

            if visited.contains(current) {
                continue
            }

            visited.insert(current)

            // Find all nodes connected from current
            let outgoing = connections
                .filter { $0.sourceNodeID == current }
                .map { $0.destinationNodeID }

            queue.append(contentsOf: outgoing)
        }

        return false
    }


    // MARK: - Audio Processing

    /// Process audio buffer through the node graph
    func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) -> AVAudioPCMBuffer {
        guard isProcessing else { return buffer }

        // Get processing order (topological sort)
        let orderedNodes = topologicalSort()

        var currentBuffer = buffer

        // Process through each node in order
        for nodeID in orderedNodes {
            guard let node = node(withID: nodeID) else { continue }

            // Skip bypassed nodes
            if node.isBypassed || !node.isActive {
                continue
            }

            // Process buffer
            currentBuffer = node.process(currentBuffer, time: time)
        }

        return currentBuffer
    }

    /// Topological sort for processing order
    private func topologicalSort() -> [UUID] {
        var result: [UUID] = []
        var visited = Set<UUID>()
        var temp = Set<UUID>()

        func visit(_ nodeID: UUID) {
            if temp.contains(nodeID) {
                // Cycle detected - shouldn't happen with our checks
                return
            }

            if visited.contains(nodeID) {
                return
            }

            temp.insert(nodeID)

            // Visit all dependencies (incoming connections)
            let dependencies = connections
                .filter { $0.destinationNodeID == nodeID }
                .map { $0.sourceNodeID }

            for depID in dependencies {
                visit(depID)
            }

            temp.remove(nodeID)
            visited.insert(nodeID)
            result.append(nodeID)
        }

        // Visit all nodes
        for node in nodes {
            visit(node.id)
        }

        return result
    }


    // MARK: - Bio-Reactivity

    /// Update all nodes with new bio-signal data
    func updateBioSignal(_ signal: BioSignal) {
        currentBioSignal = signal

        // Update all nodes
        for node in nodes {
            node.react(to: signal)
        }
    }


    // MARK: - Lifecycle

    /// Start processing
    func start(sampleRate: Double, maxFrames: AVAudioFrameCount) {
        // Prepare all nodes
        for node in nodes {
            node.prepare(sampleRate: sampleRate, maxFrames: maxFrames)
            node.start()
        }

        isProcessing = true
        print("📊 NodeGraph started (\(nodes.count) nodes)")
    }

    /// Stop processing
    func stop() {
        // Stop all nodes
        for node in nodes {
            node.stop()
        }

        isProcessing = false
        print("📊 NodeGraph stopped")
    }

    /// Reset all nodes
    func reset() {
        for node in nodes {
            node.reset()
        }
    }


    // MARK: - Presets

    /// Load a preset node configuration
    func loadPreset(_ preset: NodeGraphPreset) {
        // Clear existing
        nodes.removeAll()
        connections.removeAll()

        // Load nodes from preset
        for nodeManifest in preset.nodes {
            // Create node based on type
            // (In full implementation, use factory pattern or reflection)
            // For now, placeholder
        }

        print("📊 Loaded preset: \(preset.name)")
    }

    /// Save current configuration as preset
    func savePreset(name: String) -> NodeGraphPreset {
        let nodeManifests = nodes.map { node in
            (node as? BaseBlabNode)?.createManifest()
        }.compactMap { $0 }

        return NodeGraphPreset(
            name: name,
            nodes: nodeManifests,
            connections: connections
        )
    }


    // MARK: - Errors

    enum NodeGraphError: Error, LocalizedError {
        case nodeNotFound
        case circularDependency
        case invalidConnection

        var errorDescription: String? {
            switch self {
            case .nodeNotFound:
                return "Node not found in graph"
            case .circularDependency:
                return "Connection would create circular dependency"
            case .invalidConnection:
                return "Invalid node connection"
            }
        }
    }
}


// MARK: - Supporting Types

/// Connection between two nodes
struct NodeConnection: Identifiable {
    let id = UUID()
    let sourceNodeID: UUID
    let destinationNodeID: UUID
}

/// Node graph preset
struct NodeGraphPreset: Codable, Identifiable {
    let id = UUID()
    let name: String
    let nodes: [NodeManifest]
    let connections: [ConnectionManifest]

    struct ConnectionManifest: Codable {
        let sourceNodeID: String
        let destinationNodeID: String
    }
}


// MARK: - Preset Factory

extension NodeGraph {

    /// Create default biofeedback processing chain
    static func createBiofeedbackChain() -> NodeGraph {
        let graph = NodeGraph()

        // Create nodes
        let filter = FilterNode()
        let reverb = ReverbNode()

        // Add to graph
        graph.addNode(filter)
        graph.addNode(reverb)

        // Connect: Input → Filter → Reverb → Output
        try? graph.connect(from: filter.id, to: reverb.id)

        return graph
    }

    /// Create ambient healing preset
    static func createHealingPreset() -> NodeGraph {
        let graph = NodeGraph()

        let reverb = ReverbNode()
        reverb.setParameter(name: "wetDry", value: 60.0)  // More wet

        graph.addNode(reverb)

        return graph
    }

    /// Create energizing preset
    static func createEnergizingPreset() -> NodeGraph {
        let graph = NodeGraph()

        let filter = FilterNode()
        filter.setParameter(name: "cutoffFrequency", value: 4000.0)  // Brighter

        graph.addNode(filter)

        return graph
    }
}
