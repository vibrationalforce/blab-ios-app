//
//  PolarH10BioPublisher.swift
//  Echoelmusic
//
//  Direct CoreBluetooth connection to Polar H10 (and compatible BLE
//  HR-service devices). No SDK dependency. Subscribes to the standard
//  BLE Heart Rate Measurement characteristic (0x2A37 on service
//  0x180D), parses HR and RR-intervals, computes a normalized RMSSD
//  HRV, and publishes BioSampleFrame onto EngineBus at 1 Hz with
//  source = .ble.
//
//  Polar H10 is HRV ground-truth per Sensors 2026 (Pearson r > 0.99
//  vs. gold-standard ECG). This publisher exists so other bio sources
//  (Oura ring, Apple Watch HealthKit) can be cross-checked against
//  it on the same EngineBus.
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
    }

    public private(set) var state: ConnectionState = .idle

    public private(set) var isPublishing = false

    @ObservationIgnored
    private weak var bus: EngineBus?

    @ObservationIgnored
    private var central: CBCentralManager?

    @ObservationIgnored
    private var peripheral: CBPeripheral?

    @ObservationIgnored
    private var publishTask: Task<Void, Never>?

    @ObservationIgnored
    private var latestHR: Int = 0

    @ObservationIgnored
    private var rrIntervals: [Double] = []

    @ObservationIgnored
    private let maxRRIntervals = 30

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
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func stop() {
        publishTask?.cancel()
        publishTask = nil
        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
        if let central, central.state == .poweredOn {
            central.stopScan()
        }
        state = .idle
        isPublishing = false
    }

    // MARK: - Publish loop

    private func startPublishing() {
        publishTask?.cancel()
        publishTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let bus = self.bus else { break }
                if self.latestHR > 0 {
                    bus.publish(bio: BioSampleFrame(
                        timestamp: CFAbsoluteTimeGetCurrent(),
                        heartRateBPM: Float(self.latestHR),
                        hrvNormalized: Float(self.computeRMSSDNormalized()),
                        breathRate: 0,
                        breathPhase: 0,
                        coherence: 0,
                        motionEnergy: 0,
                        source: .ble
                    ))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func computeRMSSDNormalized() -> Double {
        guard rrIntervals.count >= 2 else { return 0.5 }
        var sumSquaredDiffs = 0.0
        for i in 1..<rrIntervals.count {
            let d = (rrIntervals[i] - rrIntervals[i - 1]) * 1000.0
            sumSquaredDiffs += d * d
        }
        let rmssdMS = sqrt(sumSquaredDiffs / Double(rrIntervals.count - 1))
        return min(max(rmssdMS / 100.0, 0.0), 1.0)
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
        switch central.state {
        case .poweredOn:
            state = .scanning
            central.scanForPeripherals(withServices: [Self.hrServiceUUID])
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            state = .bluetoothUnavailable
        @unknown default:
            state = .bluetoothUnavailable
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? ""
        guard name.contains("Polar") else { return }
        Task { @MainActor [weak self] in
            self?.handleDiscovered(peripheral, on: central)
        }
    }

    @MainActor
    private func handleDiscovered(_ peripheral: CBPeripheral, on central: CBCentralManager) {
        guard self.peripheral == nil else { return }
        self.peripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        central.connect(peripheral)
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            self?.state = .connected
            peripheral.discoverServices([Self.hrServiceUUID])
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.state = .disconnected
            self?.publishTask?.cancel()
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
            guard let self,
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
