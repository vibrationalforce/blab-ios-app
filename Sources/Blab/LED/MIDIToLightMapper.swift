import Foundation
import Network
import CoreMIDI
import Combine

/// MIDI to DMX/LED Strip Controller
/// Maps MIDI/MPE parameters to DMX lighting and addressable LED strips
/// Supports Art-Net, sACN (E1.31), and serial LED protocols
/// Bio-reactive lighting for live performances and installations
@MainActor
class MIDIToLightMapper: ObservableObject {

    // MARK: - Published State

    @Published var isActive: Bool = false
    @Published var currentScene: LightScene = .ambient
    @Published var dmxUniverse: [UInt8] = Array(repeating: 0, count: 512)
    @Published var ledStrips: [LEDStrip] = []

    // MARK: - DMX Configuration

    private let dmxUniverseSize = 512
    private var artNetSocket: UDPSocket?
    private var artNetAddress: String = "192.168.1.100"
    private var artNetPort: UInt16 = 6454

    // MARK: - LED Strip Configuration

    struct LEDStrip: Identifiable {
        let id: UUID = UUID()
        let name: String
        let startAddress: Int       // DMX start address
        let pixelCount: Int          // Number of pixels/LEDs
        var pixelFormat: PixelFormat = .rgb
        var pixels: [RGB] = []

        enum PixelFormat {
            case rgb    // 3 bytes per pixel
            case rgbw   // 4 bytes per pixel
            case grb    // 3 bytes (Green-Red-Blue order, WS2812)
        }

        var dmxChannelCount: Int {
            switch pixelFormat {
            case .rgb, .grb: return pixelCount * 3
            case .rgbw: return pixelCount * 4
            }
        }
    }

    struct RGB {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var w: UInt8 = 0  // White channel (for RGBW)

        static let black = RGB(r: 0, g: 0, b: 0)
        static let white = RGB(r: 255, g: 255, b: 255)
        static let red = RGB(r: 255, g: 0, b: 0)
        static let green = RGB(r: 0, g: 255, b: 0)
        static let blue = RGB(r: 0, g: 0, b: 255)
        static let cyan = RGB(r: 0, g: 255, b: 255)
        static let magenta = RGB(r: 255, g: 0, b: 255)
        static let yellow = RGB(r: 255, g: 255, b: 0)
    }

    // MARK: - Light Scenes

    enum LightScene: String, CaseIterable {
        case ambient = "Ambient"
        case performance = "Performance"
        case meditation = "Meditation"
        case energetic = "Energetic"
        case reactive = "Reactive"  // Full bio-reactive mode
        case strobeSync = "Strobe Sync"  // Sync with beats

        var description: String {
            switch self {
            case .ambient: return "Soft ambient lighting"
            case .performance: return "High-energy performance mode"
            case .meditation: return "Calming meditation lights"
            case .energetic: return "Dynamic energetic colors"
            case .reactive: return "Full bio-reactive control"
            case .strobeSync: return "Strobe synced to beats"
            }
        }
    }

    // MARK: - Fixture Definitions

    /// DMX fixture (moving heads, PARs, etc.)
    struct DMXFixture: Identifiable {
        let id: UUID = UUID()
        let name: String
        let startAddress: Int
        let channelMap: ChannelMap

        enum ChannelMap {
            case rgbPar(r: Int, g: Int, b: Int, dimmer: Int?)
            case movingHead(pan: Int, tilt: Int, dimmer: Int, r: Int, g: Int, b: Int)
            case strobe(strobe: Int, speed: Int)
        }
    }

    private var fixtures: [DMXFixture] = []

    // MARK: - Initialization

    init() {
        setupDefaultLEDStrips()
    }

    deinit {
        stop()
    }

    // MARK: - Setup

    private func setupDefaultLEDStrips() {
        // Example: 3 LED strips
        ledStrips = [
            LEDStrip(
                name: "Front Strip",
                startAddress: 1,
                pixelCount: 60,
                pixelFormat: .grb,
                pixels: Array(repeating: RGB.black, count: 60)
            ),
            LEDStrip(
                name: "Back Strip",
                startAddress: 181,
                pixelCount: 60,
                pixelFormat: .grb,
                pixels: Array(repeating: RGB.black, count: 60)
            ),
            LEDStrip(
                name: "Ceiling Strip",
                startAddress: 361,
                pixelCount: 50,
                pixelFormat: .rgbw,
                pixels: Array(repeating: RGB.black, count: 50)
            )
        ]
    }

    func addFixture(_ fixture: DMXFixture) {
        fixtures.append(fixture)
        print("💡 Added fixture: \(fixture.name) @ DMX \(fixture.startAddress)")
    }

    // MARK: - Start/Stop

    func start() {
        guard !isActive else { return }

        // Initialize Art-Net socket
        do {
            artNetSocket = try UDPSocket(address: artNetAddress, port: artNetPort)
            isActive = true
            print("✅ DMX/LED Mapper started (Art-Net → \(artNetAddress):\(artNetPort))")
        } catch {
            print("⚠️ Failed to start Art-Net: \(error)")
        }
    }

    func stop() {
        guard isActive else { return }

        blackoutAll()
        artNetSocket?.close()
        artNetSocket = nil
        isActive = false

        print("🛑 DMX/LED Mapper stopped")
    }

    // MARK: - MIDI → Light Mapping

    /// Map MIDI note to lights
    func handleNoteOn(note: UInt8, velocity: Float, channel: UInt8) {
        let hue = Float(note % 12) / 12.0
        let brightness = UInt8(velocity * 255.0)

        let color = hueToRGB(hue: hue, value: brightness)

        // Update LED strips based on note
        if let stripIndex = Int(channel) % ledStrips.count as Int?,
           stripIndex < ledStrips.count {
            fillStrip(index: stripIndex, color: color)
        }

        sendDMX()
    }

    /// Map MIDI note off
    func handleNoteOff(note: UInt8, channel: UInt8) {
        // Fade out LEDs
        if let stripIndex = Int(channel) % ledStrips.count as Int?,
           stripIndex < ledStrips.count {
            fadeStrip(index: stripIndex, fadeFactor: 0.5)
        }

        sendDMX()
    }

    /// Map per-note brightness to light intensity
    func handleBrightness(note: UInt8, brightness: Float, channel: UInt8) {
        let intensity = UInt8(brightness * 255.0)

        // Update fixture dimmer
        for fixture in fixtures {
            switch fixture.channelMap {
            case .rgbPar(_, _, _, let dimmer):
                if let dimmerChannel = dimmer {
                    dmxUniverse[fixture.startAddress + dimmerChannel - 1] = intensity
                }
            case .movingHead(_, _, let dimmer, _, _, _):
                dmxUniverse[fixture.startAddress + dimmer - 1] = intensity
            case .strobe:
                break
            }
        }

        sendDMX()
    }

    /// Map pitch bend to moving head pan/tilt
    func handlePitchBend(note: UInt8, bend: Float, channel: UInt8) {
        // Map bend to pan (-1 to +1 → 0 to 255)
        let panValue = UInt8((bend + 1.0) * 0.5 * 255.0)

        for fixture in fixtures {
            if case .movingHead(let pan, _, _, _, _, _) = fixture.channelMap {
                dmxUniverse[fixture.startAddress + pan - 1] = panValue
            }
        }

        sendDMX()
    }

    // MARK: - Biometric → Light Mapping

    /// Update lights based on HRV coherence and heart rate
    func updateFromBioSignals(hrvCoherence: Double, heartRate: Double) {
        let hue = Float(hrvCoherence) / 100.0
        let intensity = UInt8(min(100.0, heartRate) / 100.0 * 255.0)

        let color = hueToRGB(hue: hue, value: intensity)

        switch currentScene {
        case .ambient:
            fillAllStrips(color: color)

        case .meditation:
            // Slow breathing pattern
            let breathCycle = sin(Date().timeIntervalSinceReferenceDate * 0.3)
            let breathIntensity = UInt8((breathCycle + 1.0) * 0.5 * 255.0)
            let breathColor = hueToRGB(hue: 0.55, value: breathIntensity)  // Blue-green
            fillAllStrips(color: breathColor)

        case .energetic:
            // Fast pulsing
            let pulseCycle = sin(Date().timeIntervalSinceReferenceDate * 2.0)
            let pulseIntensity = UInt8((pulseCycle + 1.0) * 0.5 * 255.0)
            let pulseColor = hueToRGB(hue: hue, value: pulseIntensity)
            fillAllStrips(color: pulseColor)

        case .reactive:
            // Full bio-reactive control
            applyBioReactivePattern(coherence: hrvCoherence, heartRate: heartRate)

        case .performance:
            // High-intensity lighting
            fillAllStrips(color: RGB.white)

        case .strobeSync:
            // Strobe synced to heart rate
            let beatInterval = 60.0 / heartRate
            let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: beatInterval) / beatInterval
            let strobeOn = phase < 0.1
            fillAllStrips(color: strobeOn ? RGB.white : RGB.black)
        }

        sendDMX()
    }

    private func applyBioReactivePattern(coherence: Double, heartRate: Double) {
        // Create wave pattern across strips based on HRV
        let time = Date().timeIntervalSinceReferenceDate

        for (stripIndex, strip) in ledStrips.enumerated() {
            for pixelIndex in 0..<strip.pixelCount {
                let position = Float(pixelIndex) / Float(strip.pixelCount)
                let wave = sin(position * 2.0 * .pi + Float(time) * 2.0)

                let hue = (Float(coherence) / 100.0 + wave * 0.2).truncatingRemainder(dividingBy: 1.0)
                let brightness = UInt8((wave + 1.0) * 0.5 * 255.0)

                let color = hueToRGB(hue: hue, value: brightness)
                ledStrips[stripIndex].pixels[pixelIndex] = color
            }

            updateStripInDMX(strip: ledStrips[stripIndex])
        }
    }

    // MARK: - LED Strip Operations

    private func fillStrip(index: Int, color: RGB) {
        guard index < ledStrips.count else { return }

        for i in 0..<ledStrips[index].pixelCount {
            ledStrips[index].pixels[i] = color
        }

        updateStripInDMX(strip: ledStrips[index])
    }

    private func fadeStrip(index: Int, fadeFactor: Float) {
        guard index < ledStrips.count else { return }

        for i in 0..<ledStrips[index].pixelCount {
            let pixel = ledStrips[index].pixels[i]
            ledStrips[index].pixels[i] = RGB(
                r: UInt8(Float(pixel.r) * fadeFactor),
                g: UInt8(Float(pixel.g) * fadeFactor),
                b: UInt8(Float(pixel.b) * fadeFactor),
                w: UInt8(Float(pixel.w) * fadeFactor)
            )
        }

        updateStripInDMX(strip: ledStrips[index])
    }

    private func fillAllStrips(color: RGB) {
        for i in 0..<ledStrips.count {
            fillStrip(index: i, color: color)
        }
    }

    private func updateStripInDMX(strip: LEDStrip) {
        var address = strip.startAddress - 1  // DMX is 1-indexed

        for pixel in strip.pixels {
            guard address + 2 < dmxUniverseSize else { break }

            switch strip.pixelFormat {
            case .rgb:
                dmxUniverse[address] = pixel.r
                dmxUniverse[address + 1] = pixel.g
                dmxUniverse[address + 2] = pixel.b
                address += 3

            case .grb:  // WS2812 order
                dmxUniverse[address] = pixel.g
                dmxUniverse[address + 1] = pixel.r
                dmxUniverse[address + 2] = pixel.b
                address += 3

            case .rgbw:
                dmxUniverse[address] = pixel.r
                dmxUniverse[address + 1] = pixel.g
                dmxUniverse[address + 2] = pixel.b
                dmxUniverse[address + 3] = pixel.w
                address += 4
            }
        }
    }

    private func blackoutAll() {
        dmxUniverse = Array(repeating: 0, count: 512)
        sendDMX()
    }

    // MARK: - DMX Output (Art-Net)

    private func sendDMX() {
        guard isActive, let socket = artNetSocket else { return }

        // Build Art-Net packet
        var packet: [UInt8] = []

        // Art-Net header
        packet.append(contentsOf: "Art-Net\0".utf8)  // 8 bytes
        packet.append(contentsOf: [0x00, 0x50])      // OpCode: ArtDMX (0x5000)
        packet.append(contentsOf: [0x00, 0x0E])      // Protocol version 14
        packet.append(0)                              // Sequence (0 = no sequencing)
        packet.append(0)                              // Physical port
        packet.append(contentsOf: [0x00, 0x00])      // Universe (0)
        packet.append(contentsOf: [0x02, 0x00])      // Length (512 bytes, MSB first)

        // DMX data (512 channels)
        packet.append(contentsOf: dmxUniverse)

        // Send via UDP
        socket.send(data: Data(packet))
    }

    // MARK: - Utility Functions

    private func hueToRGB(hue: Float, value: UInt8) -> RGB {
        let h = hue * 6.0
        let sector = Int(h)
        let fraction = h - Float(sector)

        let p: UInt8 = 0
        let q = UInt8(Float(value) * (1.0 - fraction))
        let t = UInt8(Float(value) * fraction)

        switch sector % 6 {
        case 0: return RGB(r: value, g: t, b: p)
        case 1: return RGB(r: q, g: value, b: p)
        case 2: return RGB(r: p, g: value, b: t)
        case 3: return RGB(r: p, g: q, b: value)
        case 4: return RGB(r: t, g: p, b: value)
        case 5: return RGB(r: value, g: p, b: q)
        default: return RGB.black
        }
    }

    // MARK: - Scene Management

    func setScene(_ scene: LightScene) {
        currentScene = scene
        print("💡 Light scene: \(scene.rawValue)")
    }

    // MARK: - Debug Info

    var debugInfo: String {
        """
        MIDIToLightMapper:
        - Active: \(isActive ? "✅" : "❌")
        - Scene: \(currentScene.rawValue)
        - LED Strips: \(ledStrips.count)
        - DMX Fixtures: \(fixtures.count)
        - Art-Net: \(artNetAddress):\(artNetPort)
        """
    }
}

// MARK: - UDP Socket (Art-Net UDP Implementation)

class UDPSocket {
    private let address: String
    private let port: UInt16
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.blab.udp", qos: .userInitiated)

    init(address: String, port: UInt16) throws {
        self.address = address
        self.port = port

        // Create UDP connection
        let host = NWEndpoint.Host(address)
        let port = NWEndpoint.Port(integerLiteral: port)

        connection = NWConnection(
            to: .hostPort(host: host, port: port),
            using: .udp
        )

        // Setup state handler
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("💡 UDP Socket connected: \(address):\(port)")
            case .failed(let error):
                print("❌ UDP Socket failed: \(error)")
            case .cancelled:
                print("🔌 UDP Socket cancelled")
            default:
                break
            }
        }

        // Start connection
        connection?.start(queue: queue)
    }

    func send(data: Data) {
        guard let connection = connection else {
            print("⚠️ UDP Socket not connected")
            return
        }

        connection.send(
            content: data,
            completion: .contentProcessed { error in
                if let error = error {
                    print("❌ UDP send error: \(error)")
                }
            }
        )
    }

    func close() {
        connection?.cancel()
        connection = nil
        print("🔌 UDP Socket closed")
    }
}
