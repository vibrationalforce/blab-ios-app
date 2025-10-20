import SwiftUI

/// Visual effects chain editor with node routing
struct EffectsChainView: View {
    @ObservedObject var nodeGraph: NodeGraph

    @State private var selectedNode: UUID?
    @State private var showNodePicker = false
    @State private var showPresets = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Node Graph Visualization
                    nodeGraphView

                    // Node List
                    nodeListView

                    // Add Node Button
                    addNodeButton

                    // Presets Section
                    presetsSection
                }
                .padding()
            }
            .background(Color.black.opacity(0.9))
            .navigationTitle("Effects Chain")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showNodePicker) {
                nodePickerView
            }
            .sheet(isPresented: $showPresets) {
                presetsView
            }
        }
    }

    // MARK: - Node Graph Visualization

    private var nodeGraphView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signal Flow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Input
                    signalFlowBox("Input", color: .green, isInput: true)

                    ForEach(nodeGraph.nodes, id: \.id) { node in
                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.3))

                        signalFlowBox(node.name, color: nodeColor(for: node), isNode: true)
                            .onTapGesture {
                                selectedNode = node.id
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedNode == node.id ? Color.cyan : Color.clear, lineWidth: 2)
                            )
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(.white.opacity(0.3))

                    // Output
                    signalFlowBox("Output", color: .blue, isOutput: true)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func signalFlowBox(_ label: String, color: Color, isInput: Bool = false, isOutput: Bool = false, isNode: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.2))
                    .frame(width: 80, height: 60)

                if isInput {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24))
                        .foregroundColor(color)
                } else if isOutput {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 24))
                        .foregroundColor(color)
                } else {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 24))
                        .foregroundColor(color)
                }
            }

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    // MARK: - Node List

    private var nodeListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Nodes (\(nodeGraph.nodes.count))")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            if nodeGraph.nodes.isEmpty {
                emptyStateView
            } else {
                ForEach(nodeGraph.nodes, id: \.id) { node in
                    NodeRow(node: node, nodeGraph: nodeGraph, isSelected: selectedNode == node.id)
                        .onTapGesture {
                            selectedNode = node.id
                        }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))

            Text("No Effects Added")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            Text("Tap + to add your first audio effect node")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Add Node Button

    private var addNodeButton: some View {
        Button(action: { showNodePicker.toggle() }) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Effect Node")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.cyan.opacity(0.3))
            )
        }
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Presets")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Button(action: { showPresets.toggle() }) {
                    Text("View All")
                        .font(.system(size: 12))
                        .foregroundColor(.cyan)
                }
            }

            HStack(spacing: 12) {
                presetButton("Biofeedback", icon: "heart.fill") {
                    nodeGraph = NodeGraph.createBiofeedbackChain()
                }

                presetButton("Healing", icon: "leaf.fill") {
                    nodeGraph = NodeGraph.createHealingPreset()
                }

                presetButton("Energizing", icon: "bolt.fill") {
                    nodeGraph = NodeGraph.createEnergizingPreset()
                }
            }
        }
    }

    private func presetButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    // MARK: - Node Picker

    private var nodePickerView: some View {
        NavigationView {
            List {
                Section(header: Text("Filter Effects")) {
                    nodeTypeButton("Low-Pass Filter", icon: "waveform.path", description: "Bio-reactive frequency filter") {
                        addFilterNode()
                    }
                }

                Section(header: Text("Dynamics")) {
                    nodeTypeButton("Compressor", icon: "waveform.path.ecg", description: "Respiratory-controlled compression") {
                        addCompressorNode()
                    }
                }

                Section(header: Text("Time-Based")) {
                    nodeTypeButton("Reverb", icon: "music.note.house", description: "HRV-coherence reverb") {
                        addReverbNode()
                    }

                    nodeTypeButton("Delay", icon: "arrow.triangle.2.circlepath", description: "Heart rate synced delay") {
                        addDelayNode()
                    }
                }
            }
            .navigationTitle("Add Effect")
            .navigationBarItems(trailing: Button("Done") {
                showNodePicker = false
            })
        }
    }

    private func nodeTypeButton(_ title: String, icon: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            showNodePicker = false
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.cyan)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.cyan)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Presets View

    private var presetsView: some View {
        NavigationView {
            List {
                Section(header: Text("Bio-Reactive Presets")) {
                    presetRow("Biofeedback Chain", description: "Filter → Reverb optimized for biofeedback") {
                        nodeGraph = NodeGraph.createBiofeedbackChain()
                        showPresets = false
                    }

                    presetRow("Healing", description: "Deep reverb with gentle compression") {
                        nodeGraph = NodeGraph.createHealingPreset()
                        showPresets = false
                    }

                    presetRow("Energizing", description: "Bright filter with rhythmic delay") {
                        nodeGraph = NodeGraph.createEnergizingPreset()
                        showPresets = false
                    }
                }

                Section(header: Text("Actions")) {
                    Button(action: {
                        nodeGraph.nodes.removeAll()
                        nodeGraph.connections.removeAll()
                        showPresets = false
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Nodes")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationBarItems(trailing: Button("Done") {
                showPresets = false
            })
        }
    }

    private func presetRow(_ title: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Node Actions

    private func addFilterNode() {
        let node = FilterNode()
        nodeGraph.addNode(node)
    }

    private func addCompressorNode() {
        let node = CompressorNode()
        nodeGraph.addNode(node)
    }

    private func addReverbNode() {
        let node = ReverbNode()
        nodeGraph.addNode(node)
    }

    private func addDelayNode() {
        let node = DelayNode()
        nodeGraph.addNode(node)
    }

    // MARK: - Helpers

    private func nodeColor(for node: BlabNode) -> Color {
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
}

// MARK: - Node Row

struct NodeRow: View {
    let node: BlabNode
    @ObservedObject var nodeGraph: NodeGraph
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Node icon
                Image(systemName: nodeIcon)
                    .font(.system(size: 18))
                    .foregroundColor(nodeColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(nodeColor.opacity(0.2))
                    )

                // Node info
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(nodeDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                // Delete button
                Button(action: {
                    nodeGraph.removeNode(node.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.7))
                }
            }

            // Bio-reactive indicator
            if node.isBioReactive {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.pink)

                    Text("Bio-Reactive")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.pink)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.cyan.opacity(0.1) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.cyan : Color.clear, lineWidth: 1)
                )
        )
    }

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

    private var nodeDescription: String {
        let name = node.name.lowercased()

        if name.contains("filter") {
            return "Frequency filtering"
        } else if name.contains("reverb") {
            return "Spatial reverb effect"
        } else if name.contains("delay") {
            return "Time-delayed echo"
        } else if name.contains("compressor") {
            return "Dynamic range control"
        } else {
            return "Audio processing"
        }
    }
}
