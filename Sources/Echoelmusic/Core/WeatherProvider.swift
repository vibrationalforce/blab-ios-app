// WeatherProvider.swift
// Echoel — E3b: the ONE coarse WeatherKit fetch per session start that feeds
// the pure weather→music mapping (`WeatherMood`). Quota-friendly by design:
// a 30-minute cache means even long studio days stay in the low-hundreds of
// calls per month — far under Apple's free 500k tier.
//
// Privacy: uses the SAME opt-in coarse fix as the place token (LocationNamer.
// lastFix, city-level accuracy). Nothing is stored beyond the in-memory cache;
// offline / no fix / unknown condition → nil (the composition simply plays
// without a weather flavour).
//
// Apple requirement: any surface showing weather-derived state must carry the
// " Weather" attribution + legal link (done at the toggle in the UI, E3b-3).

#if canImport(WeatherKit) && canImport(CoreLocation)
import Foundation
import CoreLocation
import WeatherKit
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class WeatherProvider {

    /// Cache lifetime — long enough for a whole session block, short enough
    /// that an evening session after an afternoon one feels the sky change.
    /// (nonisolated: an immutable Sendable constant, read from the pure
    /// cache-policy helper.)
    public nonisolated static let cacheLifetime: TimeInterval = 30 * 60

    /// Last successful snapshot + when it was fetched (in-memory only).
    public private(set) var current: WeatherSnapshot?
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var inFlight: Task<WeatherSnapshot?, Never>?

    public init() {}

    /// Pure cache policy — testable without WeatherKit.
    nonisolated static func isCacheValid(fetchedAt: Date?, now: Date) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) < cacheLifetime
    }

    /// One coarse fetch (or the cached value). Never throws — weather is a
    /// bonus flavour, so every failure path returns nil quietly.
    public func snapshot(for location: CLLocation, now: Date = Date()) async -> WeatherSnapshot? {
        if Self.isCacheValid(fetchedAt: fetchedAt, now: now), let current {
            return current
        }
        if let inFlight { return await inFlight.value }   // dedupe concurrent starts

        let task = Task<WeatherSnapshot?, Never> { [weak self] in
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                let c = weather.currentWeather
                let condition = WeatherSnapshot.Condition(weatherKitRaw: c.condition.rawValue)
                    ?? .partlyCloudy
                let snap = WeatherSnapshot(
                    temperatureC: c.temperature.converted(to: .celsius).value,
                    condition: condition,
                    isDaylight: c.isDaylight,
                    windKph: c.wind.speed.converted(to: .kilometersPerHour).value
                )
                await MainActor.run { [weak self] in
                    self?.current = snap
                    self?.fetchedAt = Date()
                }
                log.log(.info, category: .system,
                        "Weather fetch: \(WeatherMood.contribution(for: snap).descriptor)")
                return snap
            } catch {
                log.log(.info, category: .system,
                        "Weather fetch skipped — \(error.localizedDescription)")
                return nil
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
#endif
