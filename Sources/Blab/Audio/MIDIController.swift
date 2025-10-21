import Foundation
import CoreMIDI
import Combine

/// MIDI controller support for external hardware control
@MainActor
class MIDIController: ObservableObject {

    // MARK: - Published Properties

    @Published var isConnected: Bool = false
    @Published var connectedDevices: [MIDIDevice] = []
    @Published var lastMIDIMessage: MIDIMessage?

    // MARK: - MIDI Device Model

    struct MIDIDevice: Identifiable, Equatable {
        let id: MIDIEndpointRef
        let name: String
        let manufacturer: String
        let isOnline: Bool
    }

    // MARK: - MIDI Message Model

    struct MIDIMessage {
        let timestamp: Date
        let type: MessageType
        let channel: UInt8
        let data1: UInt8
        let data2: UInt8

        enum MessageType {
            case noteOn
            case noteOff
            case controlChange
            case pitchBend
            case programChange
            case aftertouch
            case unknown
        }

        var controllerNumber: UInt8? {
            type == .controlChange ? data1 : nil
        }

        var controllerValue: UInt8? {
            type == .controlChange ? data2 : nil
        }

        var noteNumber: UInt8? {
            (type == .noteOn || type == .noteOff) ? data1 : nil
        }

        var velocity: UInt8? {
            (type == .noteOn || type == .noteOff) ? data2 : nil
        }
    }

    // MARK: - MIDI Mapping

    struct MIDIMapping {
        let controllerNumber: UInt8
        let parameter: MIDIParameter
        let minValue: Float
        let maxValue: Float

        func map(midiValue: UInt8) -> Float {
            let normalized = Float(midiValue) / 127.0
            return minValue + normalized * (maxValue - minValue)
        }
    }

    enum MIDIParameter {
        case volume
        case pan
        case filterCutoff
        case filterResonance
        case reverbMix
        case reverbSize
        case delayTime
        case delayFeedback
        case compressorThreshold
        case compressorRatio
        case tempo
        case loopVolume(UUID)
        case trackVolume(UUID)
    }

    // MARK: - Private Properties

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var mappings: [MIDIMapping] = []
    private var messageHandlers: [(MIDIMessage) -> Void] = []

    // MARK: - Initialization

    init() {
        setupMIDI()
    }

    deinit {
        cleanup()
    }

    // MARK: - MIDI Setup

    private func setupMIDI() {
        var status: OSStatus

        // Create MIDI client
        status = MIDIClientCreate("BLAB" as CFString, nil, nil, &midiClient)
        guard status == noErr else {
            print("❌ Failed to create MIDI client: \(status)")
            return
        }

        // Create input port
        status = MIDIInputPortCreate(
            midiClient,
            "BLAB Input" as CFString,
            { packetList, refCon, srcConnRefCon in
                // Handle MIDI packets
                guard let controller = refCon?.assumingMemoryBound(to: MIDIController.self).pointee else { return }
                Task { @MainActor in
                    controller.handleMIDIPackets(packetList)
                }
            },
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &inputPort
        )

        guard status == noErr else {
            print("❌ Failed to create MIDI input port: \(status)")
            return
        }

        // Connect to all sources
        connectToAllSources()

        print("🎹 MIDI controller initialized")
    }

    // MARK: - MIDI Connection

    private func connectToAllSources() {
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let status = MIDIPortConnectSource(inputPort, source, nil)

            if status == noErr {
                let device = getDeviceInfo(for: source)
                connectedDevices.append(device)
                print("🎹 Connected to MIDI device: \(device.name)")
            }
        }

        isConnected = !connectedDevices.isEmpty
    }

    private func getDeviceInfo(for endpoint: MIDIEndpointRef) -> MIDIDevice {
        var name: Unmanaged<CFString>?
        var manufacturer: Unmanaged<CFString>?

        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &manufacturer)

        return MIDIDevice(
            id: endpoint,
            name: name?.takeRetainedValue() as String? ?? "Unknown",
            manufacturer: manufacturer?.takeRetainedValue() as String? ?? "Unknown",
            isOnline: true
        )
    }

    // MARK: - MIDI Message Handling

    private func handleMIDIPackets(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        let packetCount = packetList.pointee.numPackets

        for _ in 0..<packetCount {
            handleMIDIPacket(&packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func handleMIDIPacket(_ packet: UnsafePointer<MIDIPacket>) {
        let data = Mirror(reflecting: packet.pointee.data).children.map { $0.value as! UInt8 }

        guard data.count >= 3 else { return }

        let status = data[0]
        let messageType = getMessageType(from: status)
        let channel = status & 0x0F

        let message = MIDIMessage(
            timestamp: Date(),
            type: messageType,
            channel: channel,
            data1: data[1],
            data2: data[2]
        )

        lastMIDIMessage = message

        // Call registered handlers
        for handler in messageHandlers {
            handler(message)
        }

        // Handle control changes with mappings
        if message.type == .controlChange,
           let ccNumber = message.controllerNumber,
           let ccValue = message.controllerValue {
            handleControlChange(ccNumber: ccNumber, value: ccValue)
        }
    }

    private func getMessageType(from status: UInt8) -> MIDIMessage.MessageType {
        let type = status & 0xF0

        switch type {
        case 0x80: return .noteOff
        case 0x90: return .noteOn
        case 0xB0: return .controlChange
        case 0xC0: return .programChange
        case 0xD0: return .aftertouch
        case 0xE0: return .pitchBend
        default: return .unknown
        }
    }

    // MARK: - Control Change Handling

    private func handleControlChange(ccNumber: UInt8, value: UInt8) {
        for mapping in mappings where mapping.controllerNumber == ccNumber {
            let mappedValue = mapping.map(midiValue: value)
            handleParameterChange(parameter: mapping.parameter, value: mappedValue)
        }
    }

    private func handleParameterChange(parameter: MIDIParameter, value: Float) {
        print("🎹 MIDI parameter: \(parameter) = \(value)")
        // This would be handled by specific parameter callbacks
    }

    // MARK: - Mapping Management

    /// Add MIDI CC mapping
    func addMapping(_ mapping: MIDIMapping) {
        mappings.append(mapping)
        print("🎹 Added MIDI mapping: CC\(mapping.controllerNumber) → \(mapping.parameter)")
    }

    /// Remove all mappings
    func clearMappings() {
        mappings.removeAll()
        print("🎹 Cleared all MIDI mappings")
    }

    /// Register message handler
    func onMIDIMessage(_ handler: @escaping (MIDIMessage) -> Void) {
        messageHandlers.append(handler)
    }

    // MARK: - Default Mappings

    /// Setup default control mappings
    func setupDefaultMappings() {
        clearMappings()

        // Standard MIDI CC mappings
        addMapping(MIDIMapping(controllerNumber: 1, parameter: .volume, minValue: 0, maxValue: 1))           // Modulation → Volume
        addMapping(MIDIMapping(controllerNumber: 7, parameter: .volume, minValue: 0, maxValue: 1))           // Volume
        addMapping(MIDIMapping(controllerNumber: 10, parameter: .pan, minValue: -1, maxValue: 1))            // Pan
        addMapping(MIDIMapping(controllerNumber: 71, parameter: .filterResonance, minValue: 0.5, maxValue: 10)) // Resonance
        addMapping(MIDIMapping(controllerNumber: 74, parameter: .filterCutoff, minValue: 20, maxValue: 20000)) // Cutoff
        addMapping(MIDIMapping(controllerNumber: 91, parameter: .reverbMix, minValue: 0, maxValue: 1))       // Reverb
        addMapping(MIDIMapping(controllerNumber: 92, parameter: .delayTime, minValue: 0.01, maxValue: 2))    // Delay Time
        addMapping(MIDIMapping(controllerNumber: 93, parameter: .delayFeedback, minValue: 0, maxValue: 0.9)) // Delay Feedback

        print("🎹 Setup default MIDI mappings")
    }

    // MARK: - Cleanup

    private func cleanup() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }
}

// MARK: - MIDI Learn Mode

extension MIDIController {
    /// Start MIDI learn mode for parameter
    func startLearnMode(for parameter: MIDIParameter, minValue: Float, maxValue: Float, timeout: TimeInterval = 10.0) async -> UInt8? {
        print("🎹 MIDI Learn: Waiting for controller input...")

        // Wait for next CC message
        return await withCheckedContinuation { continuation in
            var handler: ((MIDIMessage) -> Void)? = nil
            var timeoutTask: Task<Void, Never>? = nil

            handler = { [weak self] message in
                guard message.type == .controlChange,
                      let ccNumber = message.controllerNumber else { return }

                // Found CC controller
                print("🎹 MIDI Learn: Learned CC\(ccNumber)")

                // Add mapping
                let mapping = MIDIMapping(
                    controllerNumber: ccNumber,
                    parameter: parameter,
                    minValue: minValue,
                    maxValue: maxValue
                )
                self?.addMapping(mapping)

                // Cleanup
                timeoutTask?.cancel()
                if let handler = handler,
                   let index = self?.messageHandlers.firstIndex(where: { handler as AnyObject === $0 as AnyObject }) {
                    self?.messageHandlers.remove(at: index)
                }

                continuation.resume(returning: ccNumber)
            }

            messageHandlers.append(handler!)

            // Timeout
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

                print("🎹 MIDI Learn: Timeout")

                if let handler = handler,
                   let index = messageHandlers.firstIndex(where: { handler as AnyObject === $0 as AnyObject }) {
                    messageHandlers.remove(at: index)
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
