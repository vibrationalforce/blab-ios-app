#if canImport(UIKit)
import UIKit
import CoreAudioKit
import SwiftUI
import Observation
import os

/// File-scope log handle: `createAudioUnit` runs nonisolated (host thread), so it
/// must not touch MainActor-isolated statics of the view controller.
private let auv3FactoryLog = OSLog(
    subsystem: "com.echoelmusic.app.auv3",
    category: "ViewController"
)

/// Minimal Sendable box to carry the (non-Sendable) freshly built AU across the
/// nonisolated-factory → MainActor-UI hop. Single producer, single consumer.
private struct AUBox: @unchecked Sendable { let value: EchoelmusicAudioUnit }

/// View controller for the AUv3 plugin UI in DAW hosts.
public final class AudioUnitViewController: AUViewController {

    private var audioUnit: EchoelmusicAudioUnit?
    private var parameterObservationToken: AUParameterObserverToken?
    private var hostingController: UIHostingController<AUv3PluginView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        preferredContentSize = CGSize(width: 400, height: 520)
        if let audioUnit { setupUI(audioUnit: audioUnit) }
    }

    /// Called from `createAudioUnit`'s MainActor hop once the AU exists.
    private func adopt(_ au: EchoelmusicAudioUnit) {
        audioUnit = au
        if isViewLoaded { setupUI(audioUnit: au) }
    }

    private func setupUI(audioUnit: EchoelmusicAudioUnit) {
        guard let tree = audioUnit.parameterTree else { return }
        let vm = AUv3ViewModel(parameterTree: tree)

        parameterObservationToken = tree.token(
            byAddingParameterObserver: { [weak vm] (address, value) in
                Task { @MainActor in vm?.parameterChanged(address: address, value: value) }
            }
        )

        let pluginView = AUv3PluginView(viewModel: vm)
        let hosting = UIHostingController(rootView: pluginView)
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }
}

// MARK: - AUAudioUnitFactory (the extension's actual vending point)

/// REGISTRATION LAW twin (device log 2026-07-16, "ownAUv3 false"): the principal
/// class MUST conform to `AUAudioUnitFactory`, and the protocol's requirement is
/// SYNCHRONOUS `createAudioUnit(with:) throws`. The previous `async` method never
/// satisfied it — even a registered component could not be instantiated by any
/// host. The host may call this on any thread, so it is `nonisolated`; the AU
/// itself is a plain (nonisolated) AUAudioUnit subclass, and only the UI adoption
/// hops to the MainActor.
extension AudioUnitViewController: AUAudioUnitFactory {
    public nonisolated func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        let au = try EchoelmusicAudioUnit(
            componentDescription: componentDescription, options: []
        )
        let box = AUBox(value: au)
        Task { @MainActor in self.adopt(box.value) }
        os_log(.info, log: auv3FactoryLog, "Audio unit created via factory")
        return au
    }
}

// MARK: - ViewModel

@MainActor @Observable
final class AUv3ViewModel {
    var coherence: Float = 0.5
    var hrv: Float = 0.5
    var heartRate: Float = 0.5
    var breathPhase: Float = 0.5
    var baseFrequency: Float = 220
    var textureAmount: Float = 0.3
    var reverbMix: Float = 0.3
    var masterGain: Float = 0.7

    private let parameterTree: AUParameterTree

    init(parameterTree: AUParameterTree) {
        self.parameterTree = parameterTree
        syncFromTree()
    }

    private func syncFromTree() {
        typealias Addr = EchoelmusicAudioUnit.ParameterAddress
        if let p = parameterTree.parameter(withAddress: Addr.coherence.rawValue) { coherence = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.hrv.rawValue) { hrv = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.heartRate.rawValue) { heartRate = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.breathPhase.rawValue) { breathPhase = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.baseFrequency.rawValue) { baseFrequency = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.textureAmount.rawValue) { textureAmount = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.reverbMix.rawValue) { reverbMix = p.value }
        if let p = parameterTree.parameter(withAddress: Addr.masterGain.rawValue) { masterGain = p.value }
    }

    func parameterChanged(address: AUParameterAddress, value: AUValue) {
        typealias Addr = EchoelmusicAudioUnit.ParameterAddress
        switch address {
        case Addr.coherence.rawValue: coherence = value
        case Addr.hrv.rawValue: hrv = value
        case Addr.heartRate.rawValue: heartRate = value
        case Addr.breathPhase.rawValue: breathPhase = value
        case Addr.baseFrequency.rawValue: baseFrequency = value
        case Addr.textureAmount.rawValue: textureAmount = value
        case Addr.reverbMix.rawValue: reverbMix = value
        case Addr.masterGain.rawValue: masterGain = value
        default: break
        }
    }

    func setParameter(address: UInt64, value: Float) {
        parameterTree.parameter(withAddress: address)?.value = value
    }
}

// MARK: - SwiftUI Plugin View

struct AUv3PluginView: View {
    @Bindable var viewModel: AUv3ViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Echoelmusic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 12)
                Text("Bio-Reactive Instrument")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))

                parameterSection("Bio-Reactive") {
                    paramSlider("Coherence", value: $viewModel.coherence, range: 0...1,
                                address: 0, format: "%.0f%%") { $0 * 100 }
                    paramSlider("HRV", value: $viewModel.hrv, range: 0...1,
                                address: 1, format: "%.0f%%") { $0 * 100 }
                    paramSlider("Heart Rate", value: $viewModel.heartRate, range: 0...1,
                                address: 2, format: "%.0f%%") { $0 * 100 }
                    paramSlider("Breath", value: $viewModel.breathPhase, range: 0...1,
                                address: 3, format: "%.0f%%") { $0 * 100 }
                }

                parameterSection("Sound") {
                    paramSlider("Frequency", value: $viewModel.baseFrequency, range: 40...440,
                                address: 4, format: "%.0f Hz") { $0 }
                    paramSlider("Texture", value: $viewModel.textureAmount, range: 0...1,
                                address: 5, format: "%.0f%%") { $0 * 100 }
                    paramSlider("Reverb", value: $viewModel.reverbMix, range: 0...1,
                                address: 6, format: "%.0f%%") { $0 * 100 }
                    paramSlider("Gain", value: $viewModel.masterGain, range: 0...1,
                                address: 7, format: "%.0f%%") { $0 * 100 }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.05))
    }

    @ViewBuilder
    private func parameterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(white: 0.35))
                .kerning(1.5)
                .padding(.leading, 4)
            VStack(spacing: 6) { content() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.1)))
        }
    }

    @ViewBuilder
    private func paramSlider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>,
                             address: UInt64, format: String, display: ((Float) -> Float)? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(white: 0.6))
                .frame(width: 80, alignment: .leading)
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; viewModel.setParameter(address: address, value: $0) }
            ), in: range)
            .tint(Color(white: 0.4))
            Text(String(format: format, display?(value.wrappedValue) ?? value.wrappedValue))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.4))
                .frame(width: 56, alignment: .trailing)
        }
    }
}
#endif
