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

    // MARK: - WeatherKit raw-value mapping (E3b — pure, no WeatherKit import)

    func testKnownWeatherKitRawsMap() {
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "clear"), .clear)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "mostlyClear"), .clear)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "partlyCloudy"), .partlyCloudy)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "cloudy"), .overcast)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "foggy"), .fog)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "drizzle"), .drizzle)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "heavyRain"), .rain)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "thunderstorms"), .storm)
        XCTAssertEqual(WeatherSnapshot.Condition(weatherKitRaw: "blizzard"), .snow)
    }

    func testUnknownRawIsNilNotAGuess() {
        XCTAssertNil(WeatherSnapshot.Condition(weatherKitRaw: "sharknado"))
        XCTAssertNil(WeatherSnapshot.Condition(weatherKitRaw: ""))
    }

    func testEveryConditionIsReachableFromSomeRaw() {
        let raws = ["clear", "partlyCloudy", "cloudy", "foggy", "drizzle",
                    "rain", "thunderstorms", "snow"]
        let reached = Set(raws.compactMap { WeatherSnapshot.Condition(weatherKitRaw: $0) })
        XCTAssertEqual(reached, Set(WeatherSnapshot.Condition.allCases))
    }

    // MARK: - Multi-parameter targets (P5: sound + image, each mixable)

    func testAllTargetsStayInTheirNaturalRanges() {
        for c in WeatherSnapshot.Condition.allCases {
            for day in [true, false] {
                for temp in [-10.0, 5.0, 15.0, 25.0, 40.0] {
                    for wind in [0.0, 12.0, 30.0, 60.0] {
                        let x = WeatherMood.contribution(for: WeatherSnapshot(
                            temperatureC: temp, condition: c, isDaylight: day, windKph: wind))
                        XCTAssertTrue((0...1).contains(x.darknessTarget), "\(c) darkness")
                        XCTAssertTrue((0...1).contains(x.livelinessTarget), "\(c) liveliness")
                        XCTAssertTrue((0...1).contains(x.tensionTarget), "\(c) tension")
                        XCTAssertTrue((0...1).contains(x.hue), "\(c) hue")
                        XCTAssertTrue((0...2).contains(x.saturation), "\(c) saturation")
                        XCTAssertTrue((0...1.5).contains(x.glowTarget), "\(c) glow")
                        XCTAssertTrue((0...1.5).contains(x.motionTarget), "\(c) motion")
                    }
                }
            }
        }
    }

    func testWarmIsBrighterThanCold() {
        let hot = WeatherMood.contribution(for: snap(.clear, temp: 35)).darknessTarget
        let cold = WeatherMood.contribution(for: snap(.clear, temp: -5)).darknessTarget
        XCTAssertLessThan(hot, cold, "warm weather must be brighter (lower darkness)")
    }

    func testStormIsTheMostTense() {
        let storm = WeatherMood.contribution(for: snap(.storm)).tensionTarget
        for c in WeatherSnapshot.Condition.allCases where c != .storm {
            XCTAssertLessThan(WeatherMood.contribution(for: snap(c)).tensionTarget, storm)
        }
    }

    func testWindDrivesLivelinessAndMotion() {
        let calm = WeatherMood.contribution(for:
            WeatherSnapshot(temperatureC: 15, condition: .clear, isDaylight: true, windKph: 2))
        let windy = WeatherMood.contribution(for:
            WeatherSnapshot(temperatureC: 15, condition: .clear, isDaylight: true, windKph: 55))
        XCTAssertLessThan(calm.livelinessTarget, windy.livelinessTarget)
        XCTAssertLessThan(calm.motionTarget, windy.motionTarget)
    }

    func testFogIsTheDimmestGlow() {
        let fog = WeatherMood.contribution(for: snap(.fog)).glowTarget
        for c in WeatherSnapshot.Condition.allCases where c != .fog {
            XCTAssertLessThan(fog, WeatherMood.contribution(for: snap(c)).glowTarget)
        }
    }

    // MARK: - blend() crossfade (the intensity mixer)

    func testBlendAtZeroIsBitIdentical() {
        XCTAssertEqual(WeatherMood.blend(base: 0.82, target: 1.4, intensity: 0), 0.82)
        XCTAssertEqual(WeatherMood.blend(base: 0.0, target: 0.72, intensity: 0), 0.0)
    }

    func testBlendAtOneReachesTarget() {
        XCTAssertEqual(WeatherMood.blend(base: 0.2, target: 0.9, intensity: 1), 0.9, accuracy: 1e-6)
    }

    func testBlendAtHalfIsMidpoint() {
        XCTAssertEqual(WeatherMood.blend(base: 0.2, target: 0.8, intensity: 0.5), 0.5, accuracy: 1e-6)
    }

    func testBlendClampsIntensityAndGuardsNonFinite() {
        XCTAssertEqual(WeatherMood.blend(base: 0.3, target: 0.9, intensity: 5), 0.9, accuracy: 1e-6)
        XCTAssertEqual(WeatherMood.blend(base: 0.3, target: 0.9, intensity: -2), 0.3)
        XCTAssertEqual(WeatherMood.blend(base: 0.5, target: .nan, intensity: 0.5), 0.5)
    }

    // MARK: - Param metadata (UI contract)

    func testParamDomainsSplitFourAndFour() {
        let sound = WeatherMood.Param.allCases.filter { $0.domain == .sound }
        let visual = WeatherMood.Param.allCases.filter { $0.domain == .visual }
        XCTAssertEqual(sound.count, 4)
        XCTAssertEqual(visual.count, 4)
    }

    func testEveryParamHasLabelExplanationAndUniqueMixKey() {
        let keys = WeatherMood.Param.allCases.map { $0.mixKey }
        XCTAssertEqual(Set(keys).count, keys.count, "mix keys must be unique")
        for p in WeatherMood.Param.allCases {
            XCTAssertFalse(p.label.isEmpty)
            XCTAssertFalse(p.explanation.isEmpty)
            XCTAssertTrue(p.mixKey.hasPrefix("weather.mix."))
        }
    }

    func testStructureHasNoCrossfadeTargetButOthersDo() {
        let x = WeatherMood.contribution(for: snap(.rain))
        XCTAssertNil(x.target(for: .structure))
        for p in WeatherMood.Param.allCases where p != .structure {
            XCTAssertNotNil(x.target(for: p), "\(p) must expose a crossfade target")
        }
    }

    func testStructureDefaultsFullOthersHalf() {
        XCTAssertEqual(WeatherMood.Param.structure.defaultIntensity, 1.0)
        for p in WeatherMood.Param.allCases where p != .structure {
            XCTAssertEqual(p.defaultIntensity, 0.5)
        }
    }

    func testCurrentIntensityUnsetIsDefaultSetIsStored() {
        guard let defaults = UserDefaults(suiteName: "weather.mix.test") else {
            return XCTFail("could not create a volatile defaults suite")
        }
        defaults.removePersistentDomain(forName: "weather.mix.test")
        // Unset → the parameter's own default (never a raw 0.0).
        XCTAssertEqual(WeatherMood.Param.glow.currentIntensity(defaults), 0.5, accuracy: 1e-6)
        XCTAssertEqual(WeatherMood.Param.structure.currentIntensity(defaults), 1.0, accuracy: 1e-6)
        // Set → exactly what was written, including a real 0 (off).
        defaults.set(0.0, forKey: WeatherMood.Param.glow.mixKey)
        XCTAssertEqual(WeatherMood.Param.glow.currentIntensity(defaults), 0.0, accuracy: 1e-6)
        defaults.set(0.73, forKey: WeatherMood.Param.hue.mixKey)
        XCTAssertEqual(WeatherMood.Param.hue.currentIntensity(defaults), 0.73, accuracy: 1e-6)
        defaults.removePersistentDomain(forName: "weather.mix.test")
    }
}
