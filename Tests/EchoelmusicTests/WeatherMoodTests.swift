// WeatherMoodTests.swift
// Ecosystem plan E3a — the pure weather → composition/visual mapping.
// Guards determinism (reproducible skeletons), distinctness, and the
// VisualPreset value ranges.

import XCTest
@testable import Echoelmusic

final class WeatherMoodTests: XCTestCase {

    private func snap(_ c: WeatherSnapshot.Condition, temp: Double = 15,
                      day: Bool = true) -> WeatherSnapshot {
        WeatherSnapshot(temperatureC: temp, condition: c, isDaylight: day)
    }

    // MARK: - Determinism (the whole point of the salt)

    func testSameSnapshotYieldsSameContribution() {
        let a = WeatherMood.contribution(for: snap(.rain, temp: 8, day: true))
        let b = WeatherMood.contribution(for: snap(.rain, temp: 8, day: true))
        XCTAssertEqual(a, b)
    }

    func testSameWeatherSituationIsStableAcrossSmallTempChanges() {
        // 5°C and 9°C are the same "cold" band — the skeleton must not jump
        // between takes because the thermometer moved a degree.
        let a = WeatherMood.contribution(for: snap(.rain, temp: 5))
        let b = WeatherMood.contribution(for: snap(.rain, temp: 9))
        XCTAssertEqual(a.structureSalt, b.structureSalt)
    }

    // MARK: - Distinctness

    func testConditionsProduceDistinctSalts() {
        let salts = WeatherSnapshot.Condition.allCases.map {
            WeatherMood.contribution(for: snap($0)).structureSalt
        }
        XCTAssertEqual(Set(salts).count, salts.count,
                       "every condition must flavour the skeleton differently")
    }

    func testDaylightChangesTheSalt() {
        let day = WeatherMood.contribution(for: snap(.clear, day: true))
        let night = WeatherMood.contribution(for: snap(.clear, day: false))
        XCTAssertNotEqual(day.structureSalt, night.structureSalt)
    }

    func testTemperatureBandsChangeTheSalt() {
        let cold = WeatherMood.contribution(for: snap(.clear, temp: 5))
        let hot = WeatherMood.contribution(for: snap(.clear, temp: 35))
        XCTAssertNotEqual(cold.structureSalt, hot.structureSalt)
    }

    // MARK: - Temperature bands

    func testTemperatureBandEdges() {
        XCTAssertEqual(WeatherMood.temperatureBand(-5), "freezing")
        XCTAssertEqual(WeatherMood.temperatureBand(0), "cold")
        XCTAssertEqual(WeatherMood.temperatureBand(9.9), "cold")
        XCTAssertEqual(WeatherMood.temperatureBand(10), "mild")
        XCTAssertEqual(WeatherMood.temperatureBand(20), "warm")
        XCTAssertEqual(WeatherMood.temperatureBand(30), "hot")
    }

    // MARK: - Visual ranges (VisualPreset contract: hue 0…1, saturation 0…2)

    func testPaletteStaysInVisualPresetRanges() {
        for c in WeatherSnapshot.Condition.allCases {
            for day in [true, false] {
                let contrib = WeatherMood.contribution(
                    for: WeatherSnapshot(temperatureC: 15, condition: c, isDaylight: day))
                XCTAssertTrue((0...1).contains(contrib.hue), "\(c) hue out of range")
                XCTAssertTrue((0...2).contains(contrib.saturation), "\(c) saturation out of range")
            }
        }
    }

    func testFogIsTheMostDesaturated() {
        let fog = WeatherMood.contribution(for: snap(.fog)).saturation
        for c in WeatherSnapshot.Condition.allCases where c != .fog {
            XCTAssertLessThan(fog, WeatherMood.contribution(for: snap(c)).saturation)
        }
    }

    func testDescriptorIsHonestAndLogSafe() {
        let d = WeatherMood.contribution(for: snap(.storm, temp: -3, day: false)).descriptor
        XCTAssertEqual(d, "storm-night-freezing")
    }
}
