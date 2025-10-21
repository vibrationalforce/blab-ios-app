import Foundation
import CoreMIDI

/// MIDI 2.0 Universal MIDI Packet (UMP) types and structures
///
/// **MIDI 2.0 Overview:**
/// - 32-bit or 64-bit or 128-bit packets (vs MIDI 1.0's 8-bit)
/// - Per-note controllers (PNC) for polyphonic expression
/// - 32-bit parameter resolution (vs 7-bit/14-bit)
/// - Backwards compatible with MIDI 1.0
///
/// **Packet Types:**
/// - Type 0: Utility messages
/// - Type 1: System real-time and common messages
/// - Type 2: MIDI 1.0 channel voice messages (32-bit UMP)
/// - Type 3: Data messages (SysEx)
/// - Type 4: MIDI 2.0 channel voice messages (64-bit UMP)
/// - Type 5: Data messages (128-bit UMP)

// MARK: - UMP Packet Structure

/// Universal MIDI Packet (32-bit base)
struct UMPPacket32 {
    let word1: UInt32

    init(messageType: UInt8, group: UInt8, status: UInt8, data1: UInt8, data2: UInt8 = 0) {
        // Bit layout: [MT:4][Group:4][Status:8][Data1:8][Data2:8]
        word1 = (UInt32(messageType & 0xF) << 28) |
                (UInt32(group & 0xF) << 24) |
                (UInt32(status) << 16) |
                (UInt32(data1) << 8) |
                UInt32(data2)
    }

    var messageType: UInt8 {
        UInt8((word1 >> 28) & 0xF)
    }

    var group: UInt8 {
        UInt8((word1 >> 24) & 0xF)
    }

    var status: UInt8 {
        UInt8((word1 >> 16) & 0xFF)
    }

    var data1: UInt8 {
        UInt8((word1 >> 8) & 0xFF)
    }

    var data2: UInt8 {
        UInt8(word1 & 0xFF)
    }

    var bytes: [UInt8] {
        [
            UInt8((word1 >> 24) & 0xFF),
            UInt8((word1 >> 16) & 0xFF),
            UInt8((word1 >> 8) & 0xFF),
            UInt8(word1 & 0xFF)
        ]
    }
}

/// Universal MIDI Packet (64-bit, for MIDI 2.0 messages)
struct UMPPacket64 {
    let word1: UInt32
    let word2: UInt32

    init(messageType: UInt8, group: UInt8, status: UInt8, channel: UInt8,
         index: UInt8, data: UInt32) {
        // Word 1: [MT:4][Group:4][Status:4][Channel:4][Index:8][Reserved:8]
        word1 = (UInt32(messageType & 0xF) << 28) |
                (UInt32(group & 0xF) << 24) |
                (UInt32(status & 0xF) << 20) |
                (UInt32(channel & 0xF) << 16) |
                (UInt32(index) << 8)

        // Word 2: 32-bit data value
        word2 = data
    }

    var messageType: UInt8 {
        UInt8((word1 >> 28) & 0xF)
    }

    var group: UInt8 {
        UInt8((word1 >> 24) & 0xF)
    }

    var status: UInt8 {
        UInt8((word1 >> 20) & 0xF)
    }

    var channel: UInt8 {
        UInt8((word1 >> 16) & 0xF)
    }

    var index: UInt8 {
        UInt8((word1 >> 8) & 0xFF)
    }

    var data: UInt32 {
        word2
    }

    var bytes: [UInt8] {
        [
            UInt8((word1 >> 24) & 0xFF),
            UInt8((word1 >> 16) & 0xFF),
            UInt8((word1 >> 8) & 0xFF),
            UInt8(word1 & 0xFF),
            UInt8((word2 >> 24) & 0xFF),
            UInt8((word2 >> 16) & 0xFF),
            UInt8((word2 >> 8) & 0xFF),
            UInt8(word2 & 0xFF)
        ]
    }
}

// MARK: - Message Type Constants

enum UMPMessageType: UInt8 {
    case utility = 0x0
    case systemRealTime = 0x1
    case midi1ChannelVoice = 0x2
    case sysEx = 0x3
    case midi2ChannelVoice = 0x4
    case data128 = 0x5
}

// MARK: - MIDI 2.0 Status Codes

enum MIDI2Status: UInt8 {
    // Channel voice messages (Type 4)
    case noteOff = 0x8
    case noteOn = 0x9
    case polyPressure = 0xA
    case controlChange = 0xB
    case programChange = 0xC
    case channelPressure = 0xD
    case pitchBend = 0xE

    // MIDI 2.0 specific
    case perNoteManagement = 0xF0
    case perNoteController = 0x20
    case perNotePitchBend = 0x60
}

// MARK: - Per-Note Controller IDs

/// Per-Note Controller numbers (MIDI 2.0)
enum PerNoteController: UInt8 {
    case modulation = 1          // CC 1
    case breath = 2              // CC 2
    case expression = 11         // CC 11
    case sound1Timbre = 70       // CC 70 - Timbre/Harmonic Content
    case sound2Brightness = 71   // CC 71 - Brightness
    case sound3Attack = 73       // CC 73 - Attack Time
    case sound4Cutoff = 74       // CC 74 - Filter Cutoff
    case sound5Decay = 75        // CC 75 - Decay Time
    case sound6VibDepth = 76     // CC 76 - Vibrato Depth
    case sound7VibRate = 77      // CC 77 - Vibrato Rate
    case sound8VibDelay = 78     // CC 78 - Vibrato Delay
    case sound9Undefined = 79    // CC 79
    case sound10Undefined = 80   // CC 80
}

// MARK: - MIDI 2.0 Message Builders

extension UMPPacket64 {

    /// Create a MIDI 2.0 Note On message
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - velocity: Velocity (0.0-1.0, mapped to 16-bit)
    ///   - attributeType: Attribute type (0 = none, 1 = manufacturer, 2 = profile, 3 = pitch)
    ///   - attributeData: Attribute data (16-bit)
    /// - Returns: 64-bit UMP packet
    static func noteOn(channel: UInt8, note: UInt8, velocity: Float,
                      attributeType: UInt8 = 0, attributeData: UInt16 = 0) -> UMPPacket64 {
        let velocity16 = UInt16(min(max(velocity, 0.0), 1.0) * 65535.0)

        let word1: UInt32 = (UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28) |
                           (UInt32(0) << 24) |  // Group 0
                           (UInt32(MIDI2Status.noteOn.rawValue) << 20) |
                           (UInt32(channel & 0xF) << 16) |
                           (UInt32(note) << 8) |
                           UInt32(attributeType)

        let word2: UInt32 = (UInt32(velocity16) << 16) | UInt32(attributeData)

        return UMPPacket64(word1: word1, word2: word2)
    }

    /// Create a MIDI 2.0 Note Off message
    static func noteOff(channel: UInt8, note: UInt8, velocity: Float = 0.0) -> UMPPacket64 {
        let velocity16 = UInt16(min(max(velocity, 0.0), 1.0) * 65535.0)

        let word1: UInt32 = (UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28) |
                           (UInt32(0) << 24) |  // Group 0
                           (UInt32(MIDI2Status.noteOff.rawValue) << 20) |
                           (UInt32(channel & 0xF) << 16) |
                           (UInt32(note) << 8)

        let word2: UInt32 = UInt32(velocity16) << 16

        return UMPPacket64(word1: word1, word2: word2)
    }

    /// Create a Per-Note Controller message (MIDI 2.0)
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - controller: Controller number
    ///   - value: Controller value (0.0-1.0, mapped to 32-bit)
    /// - Returns: 64-bit UMP packet
    static func perNoteController(channel: UInt8, note: UInt8,
                                  controller: PerNoteController, value: Float) -> UMPPacket64 {
        let value32 = UInt32(min(max(value, 0.0), 1.0) * 4294967295.0)

        return UMPPacket64(
            messageType: UMPMessageType.midi2ChannelVoice.rawValue,
            group: 0,
            status: 0x0,  // Per-note controller status
            channel: channel,
            index: controller.rawValue,
            data: value32
        )
    }

    /// Create a Per-Note Pitch Bend message (MIDI 2.0)
    /// - Parameters:
    ///   - channel: MIDI channel (0-15)
    ///   - note: Note number (0-127)
    ///   - bend: Pitch bend (-1.0 to +1.0, mapped to 32-bit)
    /// - Returns: 64-bit UMP packet
    static func perNotePitchBend(channel: UInt8, note: UInt8, bend: Float) -> UMPPacket64 {
        // Map -1.0...+1.0 to 0...4294967295 (center = 2147483648)
        let bendValue = min(max(bend, -1.0), 1.0)
        let bend32 = UInt32((bendValue + 1.0) * 2147483648.0)

        let word1: UInt32 = (UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28) |
                           (UInt32(0) << 24) |  // Group 0
                           (UInt32(0x6) << 20) | // Per-note pitch bend status
                           (UInt32(channel & 0xF) << 16) |
                           (UInt32(note) << 8)

        return UMPPacket64(word1: word1, word2: bend32)
    }

    /// Create a Channel Pressure (Aftertouch) message (MIDI 2.0)
    static func channelPressure(channel: UInt8, pressure: Float) -> UMPPacket64 {
        let pressure32 = UInt32(min(max(pressure, 0.0), 1.0) * 4294967295.0)

        let word1: UInt32 = (UInt32(UMPMessageType.midi2ChannelVoice.rawValue) << 28) |
                           (UInt32(0) << 24) |  // Group 0
                           (UInt32(MIDI2Status.channelPressure.rawValue) << 20) |
                           (UInt32(channel & 0xF) << 16)

        return UMPPacket64(word1: word1, word2: pressure32)
    }

    /// Create a MIDI 2.0 Control Change message
    static func controlChange(channel: UInt8, controller: UInt8, value: Float) -> UMPPacket64 {
        let value32 = UInt32(min(max(value, 0.0), 1.0) * 4294967295.0)

        return UMPPacket64(
            messageType: UMPMessageType.midi2ChannelVoice.rawValue,
            group: 0,
            status: MIDI2Status.controlChange.rawValue,
            channel: channel,
            index: controller,
            data: value32
        )
    }
}

// MARK: - Utility Extensions

extension Float {
    /// Convert normalized 0-1 value to MIDI 2.0 32-bit resolution
    var toMIDI2Value: UInt32 {
        UInt32(min(max(self, 0.0), 1.0) * 4294967295.0)
    }

    /// Convert normalized -1 to +1 value to MIDI 2.0 pitch bend
    var toMIDI2PitchBend: UInt32 {
        let clamped = min(max(self, -1.0), 1.0)
        return UInt32((clamped + 1.0) * 2147483648.0)
    }
}

extension UInt32 {
    /// Convert MIDI 2.0 32-bit value to normalized 0-1
    var fromMIDI2Value: Float {
        Float(self) / 4294967295.0
    }

    /// Convert MIDI 2.0 pitch bend to normalized -1 to +1
    var fromMIDI2PitchBend: Float {
        (Float(self) / 2147483648.0) - 1.0
    }
}
