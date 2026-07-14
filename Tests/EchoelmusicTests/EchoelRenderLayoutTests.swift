// EchoelRenderLayoutTests.swift
// Pure tests for the EchoelRender speaker-layout model (spec v1.0). No engine → every
// platform. Uses the three reference templates from docs/dev/ECHOEL_RENDER_LAYOUT.md.

import XCTest
@testable import Echoelmusic

final class EchoelRenderLayoutTests: XCTestCase {

    // MARK: Reference templates (verbatim from the spec)

    private let stereoJSON = """
    {
      "Name": "Echoel Stereo 2.1",
      "Description": "Startstufe, L/R + Sub",
      "LoudspeakerLayout": {
        "Name": "stereo",
        "Loudspeakers": [
          { "Azimuth":  30.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 1, "Gain": 1.0 },
          { "Azimuth": -30.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 2, "Gain": 1.0 }
        ]
      },
      "EchoelRender": {
        "specVersion": "1.0",
        "coordinateSystem": { "azimuthZero": "front", "azimuthPositive": "left", "rightHanded": true, "distanceUnit": "m" },
        "output": { "device": "any", "sampleRate": 48000, "channelMap": { "1": 1, "2": 2, "sub": 3 } },
        "groups": {
          "ring": { "channels": [1,2], "role": "spatial" },
          "subs": { "channels": ["sub"], "coupling": "mono", "crossoverHz": 90, "cardioid": false }
        },
        "speakers": {
          "1": { "distanceM": 2.5, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0 },
          "2": { "distanceM": 2.5, "delayMs": 0.0, "gainTrimDb": 0.0, "limiterPeakDb": -3.0 }
        },
        "render": { "panner": "vbap", "diffusionFloorHz": 120, "defaultFocus": 1.0 },
        "fallback": { "stereo": { "left": [1], "right": [2] } }
      }
    }
    """

    private let octaJSON = """
    {
      "Name": "Echoel Octa Ring 8",
      "Description": "8er Ground-Stack, 45deg-Raster",
      "LoudspeakerLayout": {
        "Name": "octa-ground",
        "Loudspeakers": [
          { "Azimuth":    0.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 1, "Gain": 1.0 },
          { "Azimuth":   45.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 2, "Gain": 1.0 },
          { "Azimuth":   90.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 3, "Gain": 1.0 },
          { "Azimuth":  135.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 4, "Gain": 1.0 },
          { "Azimuth":  180.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 5, "Gain": 1.0 },
          { "Azimuth": -135.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 6, "Gain": 1.0 },
          { "Azimuth":  -90.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 7, "Gain": 1.0 },
          { "Azimuth":  -45.0, "Elevation": 0.0, "Radius": 1.0, "IsImaginary": false, "Channel": 8, "Gain": 1.0 },
          { "Azimuth":    0.0, "Elevation": -90.0, "Radius": 1.0, "IsImaginary": true, "Channel": 9, "Gain": 0.0 }
        ]
      },
      "EchoelRender": {
        "specVersion": "1.0",
        "output": { "device": "Dante", "sampleRate": 48000,
          "channelMap": { "1":1,"2":2,"3":3,"4":4,"5":5,"6":6,"7":7,"8":8,"subA":9,"subB":10 } },
        "groups": {
          "ring": { "channels": [1,2,3,4,5,6,7,8], "role": "spatial" },
          "subs": { "channels": ["subA","subB"], "coupling": "mono", "crossoverHz": 90, "cardioid": true },
          "shakers": { "channels": [], "lowpassHz": 80 }
        },
        "render": { "panner": "vbap", "ambisonicsOrder": 3, "diffusionFloorHz": 120, "defaultFocus": 1.0,
          "distanceModel": { "gain": true, "airAbsorption": true, "delayBasedDistance": false } },
        "fallback": { "stereo": { "left": [1,2,3,8], "right": [4,5,6,7] } }
      }
    }
    """

    private func parse(_ json: String) throws -> EchoelRenderLayout {
        try EchoelRenderLayout.decode(from: Data(json.utf8))
    }

    // MARK: Base parsing

    func testStereoParsesAndValidates() throws {
        let layout = try parse(stereoJSON)
        XCTAssertEqual(layout.name, "Echoel Stereo 2.1")
        XCTAssertEqual(layout.loudspeakerLayout.loudspeakers.count, 2)
        XCTAssertEqual(layout.loudspeakerLayout.loudspeakers[0].azimuth, 30, accuracy: 0.001)
        XCTAssertEqual(layout.loudspeakerLayout.loudspeakers[1].azimuth, -30, accuracy: 0.001)
        XCTAssertEqual(layout.ringChannels, [1, 2])
        XCTAssertEqual(layout.echoelRender?.output?.channelMap?["sub"], 3)
        XCTAssertEqual(layout.echoelRender?.groups?.subs?.channels, [.named("sub")])
        XCTAssertEqual(layout.echoelRender?.fallback?.stereo?.left, [1])
        XCTAssertTrue(layout.validate().isEmpty, "\(layout.validate())")
        XCTAssertTrue(layout.isValid)
    }

    func testOctaParsesAndValidates() throws {
        let layout = try parse(octaJSON)
        XCTAssertEqual(layout.loudspeakerLayout.realSpeakers.count, 8)
        XCTAssertTrue(layout.loudspeakerLayout.hasImaginarySpeaker)
        XCTAssertTrue(layout.loudspeakerLayout.isPlanar)
        XCTAssertEqual(layout.echoelRender?.render?.ambisonicsOrder, 3)
        XCTAssertEqual(layout.echoelRender?.groups?.subs?.cardioid, true)
        // subs are NAMED (subA/subB) → no integer channels, so no LoudspeakerLayout clash.
        XCTAssertEqual(layout.echoelRender?.groups?.subs?.indexChannels, [])
        XCTAssertTrue(layout.validate().isEmpty, "\(layout.validate())")
    }

    // MARK: Coordinate convention (left = +90 preserved, not mirrored)

    func testLeftIsPositiveNinetyPreserved() throws {
        let layout = try parse(octaJSON)
        let left = layout.loudspeakerLayout.loudspeakers.first { $0.channel == 3 }
        XCTAssertEqual(left?.azimuth, 90, accuracy: 0.001)   // channel 3 sits at LEFT = +90
        let right = layout.loudspeakerLayout.loudspeakers.first { $0.channel == 7 }
        XCTAssertEqual(right?.azimuth, -90, accuracy: 0.001)  // channel 7 = right = -90
    }

    // MARK: Round-trip (IEM base survives encode→decode)

    func testRoundTripPreservesGeometryAndExtension() throws {
        let layout = try parse(stereoJSON)
        let data = try layout.encoded()
        let back = try EchoelRenderLayout.decode(from: data)
        XCTAssertEqual(back, layout)
    }

    func testChannelRefDecodesIntAndString() throws {
        let layout = try parse(stereoJSON)
        let ring = layout.echoelRender?.groups?.ring?.channels
        XCTAssertEqual(ring, [.index(1), .index(2)])
        XCTAssertEqual(ring?.first?.intValue, 1)
        XCTAssertEqual(ChannelRef.named("sub").mapKey, "sub")
        XCTAssertEqual(ChannelRef.index(7).mapKey, "7")
    }

    // MARK: A bare IEM layout (no EchoelRender block) is valid

    func testPlainIEMLayoutIsValid() throws {
        let json = """
        { "Name": "Bare", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [
            { "Azimuth": 30, "Channel": 1 },
            { "Azimuth": -30, "Channel": 2 } ] } }
        """
        let layout = try parse(json)
        XCTAssertNil(layout.echoelRender)
        XCTAssertEqual(layout.loudspeakerLayout.loudspeakers[0].radius, 1)   // default
        XCTAssertEqual(layout.loudspeakerLayout.loudspeakers[0].gain, 1)     // default
        XCTAssertTrue(layout.isValid)
    }

    // MARK: Negative validation

    func testDuplicateAzimuthFlagged() throws {
        let json = """
        { "Name": "Dup", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [ { "Azimuth": 30, "Channel": 1 }, { "Azimuth": 30, "Channel": 2 } ] } }
        """
        let issues = try parse(json).validate()
        XCTAssertTrue(issues.contains { $0.message.contains("azimuth") })
    }

    func testRingChannelWithoutLoudspeakerFlagged() throws {
        let json = """
        { "Name": "X", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [ { "Azimuth": 30, "Channel": 1 } ] },
          "EchoelRender": { "groups": { "ring": { "channels": [1,2] } },
            "output": { "channelMap": { "1": 1, "2": 2 } } } }
        """
        let issues = try parse(json).validate()
        XCTAssertTrue(issues.contains { $0.message.contains("channel 2") && $0.message.contains("Loudspeaker") })
    }

    func testSubChannelInLoudspeakerLayoutFlagged() throws {
        let json = """
        { "Name": "X", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [ { "Azimuth": 30, "Channel": 1 }, { "Azimuth": -30, "Channel": 2 } ] },
          "EchoelRender": { "groups": { "ring": { "channels": [1] }, "subs": { "channels": [2] } },
            "output": { "channelMap": { "1": 1, "2": 2 } } } }
        """
        let issues = try parse(json).validate()
        XCTAssertTrue(issues.contains { $0.message.contains("sub") && $0.message.contains("2") })
    }

    func testPlanarRingAmbisonicsWithoutImaginaryFlagged() throws {
        let json = """
        { "Name": "X", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [ { "Azimuth": 90, "Channel": 1 }, { "Azimuth": -90, "Channel": 2 } ] },
          "EchoelRender": { "groups": { "ring": { "channels": [1,2] } },
            "output": { "channelMap": { "1": 1, "2": 2 } },
            "render": { "panner": "ambisonics" } } }
        """
        let issues = try parse(json).validate()
        XCTAssertTrue(issues.contains { $0.message.contains("imaginary floor") })
    }

    func testFallbackReferencingNonRingChannelFlagged() throws {
        let json = """
        { "Name": "X", "LoudspeakerLayout": { "Name": "s",
          "Loudspeakers": [ { "Azimuth": 30, "Channel": 1 }, { "Azimuth": -30, "Channel": 2 } ] },
          "EchoelRender": { "groups": { "ring": { "channels": [1,2] } },
            "output": { "channelMap": { "1": 1, "2": 2 } },
            "fallback": { "stereo": { "left": [1], "right": [9] } } } }
        """
        let issues = try parse(json).validate()
        XCTAssertTrue(issues.contains { $0.message.contains("channel 9") })
    }
}
