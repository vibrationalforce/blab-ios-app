// LocationNamer.swift
// Echoel — opt-in, on-device locality for the session name (ecosystem plan E2):
// "Ort in Session-Namen, privat". When the user enables "Place in session name",
// ONE coarse location fix is resolved to a city token ("Hamburg") and fed into
// `SessionContext.placeToken`, so saves/exports read
// `Echoel_2026-07-10_Hamburg_Am_72bpm_A440`.
//
// Privacy by construction:
//  • whenInUse permission, city-level accuracy, one fix per activation/launch.
//  • The token is TRANSIENT (SessionContext never persists it); the only durable
//    trace is the toggle itself and the name of a session the user chose to save.
//  • Nothing leaves the device — CLGeocoder resolves locally/Apple-side like any
//    Maps lookup; Echoel stores and transmits nothing.

#if canImport(CoreLocation)
import Foundation
@preconcurrency import CoreLocation
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class LocationNamer: NSObject {

    private enum Key {
        static let enabled = "echoel.place.enabled"
        static let manual = "echoel.place.manual"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private let geocoder = CLGeocoder()
    /// Receives the resolved token so every session/export name carries it.
    @ObservationIgnored private weak var session: SessionContext?

    /// User toggle — default OFF (founder plan E2). Turning it on requests
    /// permission (first time) and resolves once; turning it off clears the token.
    public var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: Key.enabled)
            if enabled { resolve() } else { clear() }
        }
    }

    /// Last resolved locality ("Hamburg"); empty until resolved or when off.
    public private(set) var placeToken: String = ""

    /// User-typed place name — OVERRIDES the auto-resolved token when non-empty and
    /// works even when location is off/denied (founder 2026-07-14: "auch manuell
    /// eingeben … oder der Standort nicht funktioniert"). Persisted (unlike the
    /// transient GPS token, this is the user's own words). Sanitised downstream by
    /// SessionNaming when it lands in a filename.
    public var manualPlace: String {
        didSet {
            guard manualPlace != oldValue else { return }
            defaults.set(manualPlace, forKey: Key.manual)
            pushEffectivePlace()
        }
    }

    /// The place that actually stamps the session/export name: the manual override if
    /// the user typed one, else the resolved GPS locality.
    public var effectivePlace: String {
        SessionNaming.effectivePlace(manual: manualPlace, resolved: placeToken)
    }

    private func pushEffectivePlace() {
        session?.placeToken = effectivePlace
    }

    /// Last coarse fix (city-level accuracy), kept for same-session consumers
    /// that need a coordinate — today: the WeatherKit fetch (E3b). Transient
    /// like the place token: never persisted, cleared when the toggle goes off.
    @ObservationIgnored public private(set) var lastFix: CLLocation?

    /// True when the user denied/restricted location — the UI can say so
    /// honestly instead of silently showing no place.
    public private(set) var denied = false

    public init(session: SessionContext?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.session = session
        self.enabled = defaults.bool(forKey: Key.enabled)
        self.manualPlace = defaults.string(forKey: Key.manual) ?? ""
        super.init()
        // A stored manual place stamps the name immediately, even before/without GPS.
        if !manualPlace.isEmpty { pushEffectivePlace() }
        if enabled { resolve() }
    }

    /// Late wiring for the app shell (the @State defaults can't reference each
    /// other at init). Pushes the effective place (manual override or resolved token).
    public func attach(session: SessionContext) {
        self.session = session
        if !effectivePlace.isEmpty { session.placeToken = effectivePlace }
    }

    /// Request (if needed) and resolve one coarse fix → city token.
    public func resolve() {
        guard enabled else { return }
        denied = false
        let m = manager ?? {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyKilometer   // a city name needs no more
            manager = m
            return m
        }()
        switch m.authorizationStatus {
        case .notDetermined:
            m.requestWhenInUseAuthorization()   // continues in didChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways:
            m.requestLocation()
        default:
            denied = true
            clear(keepEnabled: true)
        }
    }

    private func clear(keepEnabled: Bool = false) {
        placeToken = ""
        session?.placeToken = effectivePlace   // keep a manual place if the user set one
        lastFix = nil
        if !keepEnabled { denied = false }
    }

    private func adopt(locality: String) {
        placeToken = locality
        session?.placeToken = effectivePlace   // manual override wins if present
        log.log(.info, category: .system, "Place token resolved: \(locality)")
    }
}

extension LocationNamer: CLLocationManagerDelegate {

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.enabled else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                self.denied = true
                self.clear(keepEnabled: true)
            default:
                break   // .notDetermined — waiting on the user
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager,
                                            didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            guard let self, self.enabled else { return }
            self.lastFix = location
            do {
                let placemarks = try await self.geocoder.reverseGeocodeLocation(location)
                // Locality (city) first; fall back to coarser admin area — never
                // street-level detail in a filename.
                let name = placemarks.first?.locality
                    ?? placemarks.first?.administrativeArea
                    ?? ""
                if name.isEmpty {
                    log.log(.info, category: .system, "Place lookup returned no locality")
                } else {
                    self.adopt(locality: name)
                }
            } catch {
                log.log(.error, category: .system,
                        "Place lookup failed — \(error.localizedDescription)")
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager,
                                            didFailWithError error: Error) {
        Task { @MainActor in
            log.log(.error, category: .system,
                    "Location fix failed — \(error.localizedDescription)")
        }
    }
}
#endif
