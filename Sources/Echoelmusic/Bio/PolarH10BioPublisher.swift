//
//  PolarH10BioPublisher.swift
//  Echoelmusic
//
//  Universal low-latency BLE heart-rate source. Connects to ANY device
//  exposing the standard Bluetooth SIG Heart Rate Service (0x180D) with
//  the Heart Rate Measurement characteristic (0x2A37): Polar H10/H9/OH1/
//  Verity, Wahoo TICKR, Garmin/CooSpo/Magene/Decathlon chest straps,
//  and smartwatches in HR-broadcast mode. No SDK dependency.
//
//  Parses HR + RR-intervals, computes a normalized RMSSD HRV, publishes
//  BioSampleFrame at 1 Hz with source = .ble, AND emits a discrete
//  heartbeat bioEvent per RR-interval for beat-accurate low-latency sync.
//
//  NOTE on rings/watches without a BLE HR Service: the Oura Ring (incl.
//  Ring 4) pairs only with the Oura app and exposes NO real-time BLE to
//  third parties — its data reaches Echoel via Apple Health (delayed, not
//  beat-to-beat). For latency-free live use, pair a standard BLE HR
//  device here, use the Apple Watch, or the camera (rPPG). Polar H10 is
//  HRV ground-truth (Sensors 2026, Pearson r > 0.99 vs. ECG).
//

#if canImport(CoreBluetooth)
import Foundation
@preconcurrency import CoreBluetooth
#if canImport(Observation)
import Observation
#endif

@MainActor
@Observable
public final class PolarH10BioPublisher: NSObject {

    public enum ConnectionState: String, Sendable {
        case idle
        case bluetoothUnavailable
        case scanning
        case connecting
        case connected
        case disconnected
        /// The ~20 s scan watchdog fired with nothing discovered (BLE-2): chest
        /// straps do not advertise until the electrodes make skin contact, so
        /// "worn but dry" looks identical to "no strap" — the hint must say so.
        case notFound
    }

    public private(set) var state: ConnectionState = .idle

    public private(set) var isPublishing = false

    /// Name of the connected BLE HR device (e.g. "Polar H10", "TICKR"),
    /// for an honest UI label. Empty until a device connects.
    public private(set) var connectedDeviceName: String = ""

    /// Cross-fade for the published HRV coherence: 0 = Welch (resampled,
    /// Hann-windowed periodogram), 1 = Lomb–Scargle (direct estimate from the
    /// irregular RR series). Lomb–Scargle is the rigorous default for short
    /// beat-to-beat windows; a UI fader can bind this end-to-end.
    public var coherenceBlend: Double = 1.0

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var central: CBCentralManager?

    @ObservationIgnored
    private var peripheral: CBPeripheral?

    @ObservationIgnored
    private var publishTask: Task<Void, Never>?

    /// BLE-2 scan watchdog: `scanForPeripherals` runs FOREVER by default, and a
    /// strap with dry electrodes never advertises — without a timeout the scan is
    /// an eternal, invisible wait (device log 2361: the founder's first two strap
    /// attempts were aborted <5 s because nothing visibly happened). ~20 s is
    /// generous for BLE advertising intervals while short enough to coach.
    @ObservationIgnored
    private var scanWatchdog: Task<Void, Never>?

    @ObservationIgnored
    private static let scanTimeoutSeconds: Double = 20

    @ObservationIgnored
    private var latestHR: Int = 0

    @ObservationIgnored
    private var rrIntervals: [Double] = []

    /// Streaming artifact gate for the LIVE beat-event path. Kept separate from the
    /// windowed pass in the publish loop only because it must decide per arriving beat;
    /// both run the same `RRIntervalHygiene.Gate`, so they cannot drift apart.
    @ObservationIgnored
    private var beatGate = RRIntervalHygiene.Gate()

    // ~1 min of beats: long enough for a 0.04 Hz (LF) spectral resolution so
    // HRVCoherence can resolve the ~0.1 Hz resonance peak, the HRV-standard
    // short-term window. Also bounds the RMSSD/SDNN window.
    @ObservationIgnored
    private let maxRRIntervals = 64

    @ObservationIgnored
    private static let hrServiceUUID = CBUUID(string: "180D")

    @ObservationIgnored
    private static let hrMeasurementUUID = CBUUID(string: "2A37")

    public override init() {
        super.init()
    }

    public func start(publishing bus: EngineBus) {
        guard !isPublishing else { return }
        self.bus = bus
        isPublishing = true
        if let central {
            // BLE-4: REUSE the existing central. Constructing a second manager
            // orphaned the first (delegate still self) — a zombie that kept
            // scanning/connecting behind the app's back after a stop-during-
            // permission-prompt, draining phone + strap battery. A reused
            // central fires no fresh didUpdateState, so re-drive the handler:
            // .poweredOn starts scanning immediately, others surface honestly.
            handleCentralStateChange(central)
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    public func stop() {
        scanWatchdog?.cancel()
        scanWatchdog = nil
        publishTask?.cancel()
        publishTask = nil
        // Cancel unconditionally (review HIGH-1): a PENDING connect (.connecting,
        // from discovery or auto-reconnect) is exactly what cancelPeripheral-
        // Connection exists to cancel — the old `.connected`-only guard let a
        // stop-during-"Connecting…" leave the connect pending on the now-REUSED
        // central forever (strap connects while stopped, untracked → the next
        // scan can never find it → eternal "No strap" until app kill). Cancel
        // on an already-disconnected peripheral is a documented no-op.
        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        if let central, central.state == .poweredOn {
            central.stopScan()
        }
        peripheral = nil          // else a restart's rediscovery is blocked by the guard
        latestHR = 0
        rrIntervals.removeAll()
        beatGate = RRIntervalHygiene.Gate()   // a restart is a fresh anchor
        state = .idle
        isPublishing = false
        connectedDeviceName = ""
    }

    // MARK: - Publish loop

    private func startPublishing() {
        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                // Plausibility gate on the strap's own HR field, which is transmitted
                // separately from the RR intervals and can arrive corrupted on its own.
                // The old `> 0` test let a garbage packet through as a real pulse.
                if RRIntervalHygiene.isPlausibleBPM(self.latestHR) {
                    // ARTIFACT REJECTION before any HRV number is derived. The strap is
                    // the source we call most accurate — it was the only one with none.
                    // Segments, not a flat array: RMSSD and pNN50 read successive pairs,
                    // so closing the gap left by a rejected beat would manufacture the
                    // exact artifact the rejection removed (see RRIntervalHygiene).
                    let rawMs = self.rrIntervals.map { $0 * 1000.0 }   // s → ms
                    let segments = RRIntervalHygiene.acceptedSegments(rrMs: rawMs)
                    let cleanMs = segments.flatMap { $0 }
                    // HONESTY GATE. Filtering is not free: what survives had its LARGEST
                    // differences preferentially removed, and the spectrum below is built
                    // from a spliced record. Past a certain rejection rate the numbers stop
                    // meaning what they appear to mean — the sharpest case being atrial
                    // fibrillation, where RR steps routinely exceed the Malik threshold, so
                    // most beats are discarded and a LOW variability would be shown where
                    // the truth is extremely high. Publishing 0 makes the strip read "—".
                    let trustworthy = RRIntervalHygiene.canStateHRV(rrMs: rawMs)
                    let rmssd = trustworthy ? HRVMetrics.rmssd(segments: segments) : 0
                    // Real frequency-domain coherence from the trusted beat-to-beat
                    // RR series (BLE is the only source for which this is valid).
                    // 0 until enough beats / power for a spectrum.
                    //
                    // Honest limit, corrected: `HRVCoherence` rebuilds its time base by
                    // cumulative-summing the intervals, so a rejected beat does compress
                    // elapsed time — but that shift is negligible (one beat ≈ 1.6 % of a
                    // ~55 s record moves a 0.1 Hz peak by 0.0016 Hz against a 0.015 Hz
                    // half-width). The distortion that actually matters is the PHASE
                    // DISCONTINUITY: splicing two non-adjacent stretches of the RSA
                    // oscillation inserts a step, and a step is broadband, which inflates
                    // the denominator of peak/total and biases coherence DOWN. Still the
                    // better trade — an unremoved outlier is a near-delta impulse, i.e.
                    // FLAT broadband power, strictly worse for the same denominator.
                    let reading = trustworthy
                        ? HRVCoherence.compute(rrMs: cleanMs, blend: self.coherenceBlend)
                        : CoherenceReading.invalid
                    bus.publish(bio: BioSampleFrame(
                        timestamp: CFAbsoluteTimeGetCurrent(),
                        heartRateBPM: Float(self.latestHR),
                        hrvNormalized: Float(HRVNormalization.normalize(rmssd)),
                        breathRate: 0,
                        breathPhase: 0,
                        coherence: reading.valid ? reading.coherence : 0,
                        motionEnergy: 0,
                        source: .ble,
                        // Same honesty gate — these two leave the app over OSC to a
                        // lighting/AV rig, so a confident wrong number travels further
                        // here than on screen.
                        hrvRMSSDms: Float(rmssd),
                        hrvSDNNms: Float(trustworthy ? HRVMetrics.sdnn(segments: segments) : 0),
                        hrvPNN50: Float(trustworthy ? HRVMetrics.pnn50(segments: segments) : 0)
                    ))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// RMSSD in milliseconds from RR intervals given in **seconds**. Thin
    /// seconds→ms adapter over the shared `HRVMetrics` kernel; kept for tests
    /// and any seconds-native caller.
    nonisolated static func rmssdMs(fromRRSeconds rr: [Double]) -> Double {
        HRVMetrics.rmssd(rrMs: rr.map { $0 * 1000.0 })
    }

    // MARK: - Status label (testable kernel)

    /// The pill's honest strap status (BLE-1): `short` fits the header pill's tiny
    /// text slot, `full` is the VoiceOver / detail hint. `nil` = show the normal
    /// monitor (idle, or live frames flowing so the BPM number owns the slot).
    /// Pure + nonisolated → unit-testable without any BLE hardware. Device log
    /// 2361: the founder's first two strap sessions were aborted <5 s because
    /// the scan looked dead.
    nonisolated static func statusLabel(for state: ConnectionState, deviceName: String,
                                        hasLiveFrames: Bool) -> (short: String, full: String)? {
        let name = deviceName.isEmpty ? "Strap" : deviceName
        switch state {
        case .idle, .disconnected:
            return nil
        case .scanning:
            return ("Scanning…", "Searching for a Bluetooth heart-rate strap")
        case .connecting:
            return ("Connecting…", "Connecting to \(name)")
        case .connected:
            // Waiting for the first heart-rate notification; once frames flow the
            // BPM number takes over the slot.
            return hasLiveFrames ? nil : ("\(name)…", "\(name) connected — waiting for heart rate")
        case .bluetoothUnavailable:
            return ("BT off", "Bluetooth is off or access is denied — enable it in Settings")
        case .notFound:
            return ("No strap", "No strap found — moisten the electrodes, re-clip the strap, and pick Bluetooth again")
        }
    }

    // MARK: - BLE Heart Rate Measurement parsing (testable kernel)

    /// Parses one BLE Heart Rate Measurement payload per the
    /// Bluetooth SIG profile spec. Static + nonisolated so unit tests
    /// can feed canned Data without spinning up CoreBluetooth.
    ///
    /// Flags byte (data[0]):
    ///   bit 0: HR value format (0 = uint8, 1 = uint16)
    ///   bit 3: Energy expended field present
    ///   bit 4: RR-interval field present
    /// RR intervals are encoded in 1/1024 s units, little-endian uint16.
    nonisolated static func parseHRMeasurement(_ data: Data) -> (hr: Int, rrIntervals: [Double]) {
        guard !data.isEmpty else { return (0, []) }
        let flags = data[data.startIndex]
        let hr16 = (flags & 0x01) != 0
        let energyPresent = (flags & 0x08) != 0
        let rrPresent = (flags & 0x10) != 0

        var idx = data.startIndex + 1
        var hr = 0
        if hr16 {
            guard idx + 1 < data.endIndex else { return (0, []) }
            hr = Int(data[idx]) | (Int(data[idx + 1]) << 8)
            idx += 2
        } else {
            guard idx < data.endIndex else { return (0, []) }
            hr = Int(data[idx])
            idx += 1
        }
        if energyPresent {
            idx += 2
        }

        var rrs: [Double] = []
        if rrPresent {
            while idx + 1 < data.endIndex {
                let rr = Int(data[idx]) | (Int(data[idx + 1]) << 8)
                rrs.append(Double(rr) / 1024.0)
                idx += 2
            }
        }
        return (hr, rrs)
    }
}

// MARK: - CBCentralManagerDelegate

extension PolarH10BioPublisher: CBCentralManagerDelegate {

    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            self?.handleCentralStateChange(central)
        }
    }

    @MainActor
    private func handleCentralStateChange(_ central: CBCentralManager) {
        // BLE-4: a state change landing after stop() must be inert. The founder's
        // exact logged pattern: first BLE pick raises the iOS permission prompt →
        // user stops within seconds → prompt granted AFTER stop → .poweredOn fires
        // on a stopped publisher and (pre-guard) started a zombie scan.
        guard isPublishing else { return }
        switch central.state {
        case .poweredOn:
            state = .scanning
            central.scanForPeripherals(withServices: [Self.hrServiceUUID])
            armScanWatchdog()
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            state = .bluetoothUnavailable
        @unknown default:
            state = .bluetoothUnavailable
        }
    }

    /// If nothing is discovered within the timeout, stop the scan and surface an
    /// honest `.notFound` — the pill's status leaf shows the coaching hint. The
    /// user retries via the same source-dropdown pick (stop() → fresh start()).
    @MainActor
    private func armScanWatchdog() {
        scanWatchdog?.cancel()
        scanWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.scanTimeoutSeconds))
            guard !Task.isCancelled, let self,
                  self.isPublishing, self.state == .scanning else { return }
            if self.central?.state == .poweredOn { self.central?.stopScan() }
            self.state = .notFound
            log.log(.info, category: .biofeedback,
                    "BLE HR scan timeout (\(Int(Self.scanTimeoutSeconds)) s) — no strap found")
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // The scan already filters by the HR Service UUID, so every device
        // discovered here advertises standard heart rate — accept the first,
        // whatever the brand (Polar, Wahoo, Garmin, generic strap, watch).
        let name = peripheral.name ?? "BLE HR"
        Task { @MainActor [weak self] in
            self?.handleDiscovered(peripheral, named: name, on: central)
        }
    }

    @MainActor
    private func handleDiscovered(_ peripheral: CBPeripheral, named name: String, on central: CBCentralManager) {
        // BLE-4: a discovery landing after stop() must not connect (pre-guard, a
        // zombie scan's find issued connect() and shadowed the next session).
        guard isPublishing else { return }
        guard self.peripheral == nil else { return }
        scanWatchdog?.cancel()
        scanWatchdog = nil
        self.peripheral = peripheral
        self.connectedDeviceName = name
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        central.connect(peripheral)
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            // A connect that lands after stop() must be actively RELEASED, not just
            // ignored (review HIGH-2): silently returning left the established CB
            // link alive and orphaned (self.peripheral is nil — nothing could ever
            // cancel it, and a connected strap stops advertising → unfindable).
            guard let self, self.isPublishing else {
                central.cancelPeripheralConnection(peripheral)
                return
            }
            self.state = .connected
            peripheral.discoverServices([Self.hrServiceUUID])
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Flush the publish loop + stale beat history so a frozen HR is never
            // re-emitted and a reconnect doesn't compute RMSSD across the gap.
            self.publishTask?.cancel()
            self.latestHR = 0
            self.rrIntervals.removeAll()
            self.beatGate = RRIntervalHygiene.Gate()   // a reconnect is a fresh anchor
            // Auto-reconnect while the user still wants a signal: connect(_:) waits
            // indefinitely and fires didConnect when the strap powers on / returns
            // to range. Keep `peripheral` set so the discover guard blocks duplicates.
            if self.isPublishing, let p = self.peripheral {
                self.state = .connecting
                self.central?.connect(p)
            } else {
                // Stopped publisher: rest at .idle (review LOW-3 — .disconnected on a
                // stopped session was invisible but impure; .idle is the honest rest).
                self.state = self.isPublishing ? .disconnected : .idle
                self.connectedDeviceName = ""
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PolarH10BioPublisher: CBPeripheralDelegate {

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.hrServiceUUID }) else { return }
            peripheral.discoverCharacteristics([Self.hrMeasurementUUID], for: service)
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.isPublishing,
                  let char = service.characteristics?.first(where: { $0.uuid == Self.hrMeasurementUUID })
            else { return }
            peripheral.setNotifyValue(true, for: char)
            self.startPublishing()
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        let parsed = Self.parseHRMeasurement(data)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.latestHR = parsed.hr
            for rr in parsed.rrIntervals {
                self.rrIntervals.append(rr)
                if self.rrIntervals.count > self.maxRRIntervals {
                    self.rrIntervals.removeFirst()
                }
                // Only a beat that survives artifact rejection may fire the discrete
                // event: it drives the visual/light pulse and the beat-sync path, so a
                // dropped or doubled packet would show up as a phantom flash on stage.
                // The window kept above stays RAW — `acceptedSegments` re-runs the same
                // gate over it at publish time, which is what keeps the two paths from
                // drifting apart.
                guard self.beatGate.accept(intervalMs: rr * 1000.0) else { continue }
                // Each RR interval marks one completed beat. Emit a
                // discrete heartbeat event with real, low-latency
                // timing — unlike deriving beats from the averaged HR
                // value (which the master prompt warns is too laggy
                // for beat-sync). aux carries the RR interval in ms.
                // All bioEvent producers publish from @MainActor, so
                // enqueues to the SPSC bioEvents queue are serialized.
                self.bus?.publish(bioEvent: BioEvent(
                    timestamp: CFAbsoluteTimeGetCurrent(),
                    kind: .heartbeat,
                    confidence: 1,
                    aux: Float(rr * 1000)
                ))
            }
        }
    }
}
#endif
