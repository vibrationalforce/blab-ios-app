//
//  VisualBioModulator.swift
//  Echoelmusic — the body sculpting the immersive visual.
//
//  Holds the user's Bio→Visual routes and turns the user's BASE visual parameters +
//  the live bio snapshot into the modulated parameters handed to MetalBioView each
//  refresh. Non-destructive: the base (the EchoelValueField values) is never
//  overwritten, so manual edits and bio-modulation compose instead of fighting.
//
//  Why no timer (unlike FXBioModulator's ~30 Hz tick): the visual params are SLOW and
//  MetalBioView's renderer already eases every parameter change over ~0.4–0.7 s. The
//  view recomputes `effective(...)` whenever the bus publishes a new bio frame, and the
//  renderer glides between updates — smooth without an extra control-rate timer.
//
//  Routes persist (JSON in UserDefaults) so a performer's "bio light scene" survives
//  relaunch. Pure mapping lives in `VisualModulation` (Linux-testable); this is just
//  the @MainActor state + persistence + the convenience that stamps the LFO clock.
//

import Foundation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class VisualBioModulator {

    /// The active Bio→Visual routes. Mutating persists them.
    public var routes: [VisualModRoute] = [] {
        didSet { save() }
    }

    @ObservationIgnored private let startTime = CFAbsoluteTimeGetCurrent()
    @ObservationIgnored private static let storeKey = "visual.bioRoutes"

    public init() {
        load()
    }

    /// Whether any route is currently enabled (the visual is being bio-shaped).
    public var isActive: Bool { routes.contains { $0.enabled } }

    /// The modulated parameters to hand the renderer: the user's `base` shaped by the
    /// live `bio` and the routes. LFO phase comes from this object's own clock.
    public func effective(base: VisualParams, bio: BioSampleFrame?) -> VisualParams {
        guard isActive else { return base }
        let lfoTime = Float(CFAbsoluteTimeGetCurrent() - startTime)
        return VisualModulation.apply(routes: routes, base: base, bio: bio, lfoTime: lfoTime)
    }

    /// Add a route for `target`, defaulting the carrier to coherence (the calmest,
    /// most "Echoel" body channel). Bipolar off so it adds upward from the base.
    public func addRoute(target: VisualModTarget) {
        routes.append(VisualModRoute(carrier: .bio(.coherence), target: target))
    }

    public func removeRoute(id: UUID) {
        routes.removeAll { $0.id == id }
    }

    /// Replace a route in place (matched by id). Used by the editor's explicit
    /// per-field bindings so we never bind a `ForEach` directly to the `@Observable`
    /// array (that pattern black-screened at launch in 10.76.20).
    public func updateRoute(_ route: VisualModRoute) {
        guard let i = routes.firstIndex(where: { $0.id == route.id }) else { return }
        routes[i] = route
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storeKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([VisualModRoute].self, from: data) else { return }
        routes = decoded
    }
}
