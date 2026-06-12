#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct StudioRoot: View {

    @Environment(EngineBus.self) private var bus
    // Always available: drives the arrangement engine off the shared transport.
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(ArrangementPlayer.self) private var arranger
    @Environment(LaunchQuantizer.self) private var quantizer
    @Environment(StudioNavigator.self) private var navigator
    #if canImport(CoreHaptics)
    @Environment(HapticController.self) private var haptics
    #endif

    /// Opt-in demo bio source (labeled "Demo"). Owned here, toggled from the
    /// bio strip's source tag so the instrument is playable without hardware.
    @State private var demoSource = BioSimulator()

    /// Reduced-by-default surface: first-time users see only the core USP —
    /// heartbeat → music → meditate/export. Pro tabs (Sessions + Connect) are
    /// revealed by the "Advanced tools" toggle in the Meditate tab. Nothing is
    /// removed; the depth is one switch away.
    @AppStorage("echoel.advancedMode") private var advancedMode = false

    var body: some View {
        @Bindable var navigator = navigator
        return VStack(spacing: 0) {
            BioStripView()
            TabView(selection: $navigator.selected) {
                BeatTab()
                    .tabItem { Label("Create", systemImage: "waveform.path.ecg") }
                    .tag(StudioNavigator.Tab.tools)

                WellView()
                    .tabItem { Label("Meditate", systemImage: "heart.fill") }
                    .tag(StudioNavigator.Tab.well)

                ClipsTab()
                    .tabItem { Label("Songs", systemImage: "square.grid.3x3.fill") }
                    .tag(StudioNavigator.Tab.clips)

                if advancedMode {
                    WorksView()
                        .tabItem { Label("Sessions", systemImage: "waveform") }
                        .tag(StudioNavigator.Tab.works)

                    ModulationView()
                        .tabItem { Label("Connect", systemImage: "link") }
                        .tag(StudioNavigator.Tab.sync)
                }
            }
            // If advanced is switched off while on a pro tab, fall back to Create
            // so the selection never points at a hidden tab (blank screen).
            .onChange(of: advancedMode) { _, isOn in
                if !isOn, navigator.selected == .works || navigator.selected == .sync {
                    navigator.selected = .tools
                }
            }
        }
        // Demo source available to the whole subtree (was scoped to the strip
        // alone) so any tab can read it without a missing-environment crash.
        .environment(demoSource)
        // Arrangement follow: feed every transport step to the song engine so it
        // can swap clips at bar boundaries. No-op unless an arrangement is
        // playing; observes the step (never touches BeatPlayer's onStep closure).
        .onChange(of: beatPlayer.pattern.currentStep) { _, step in
            arranger.transportStep(step)
        }
        // Bar-quantized Session launches: fire any queued clip on the bar wrap.
        .onChange(of: beatPlayer.pattern.currentStep) { _, step in
            quantizer.transportStep(step)
        }
        #if canImport(CoreHaptics)
        // Eyes-free transport pulse: fire a haptic tap on quarter-note steps
        // (no-op unless armed in Well). Observes the shared transport's step —
        // never touches the audio-trigger closure (BeatPlayer owns onStep).
        .onChange(of: beatPlayer.pattern.currentStep) { _, step in
            haptics.tapBeat(step: step)
        }
        #endif
        .task {
            #if DEBUG
            // Dev: demo on immediately so the bus is live in Simulator/Xcode.
            demoSource.start(publishing: bus)
            #else
            // Release / TestFlight: give real sensors (HealthKit / Polar H10) a
            // few seconds to produce a frame; if none arrives, auto-start the
            // clearly-labeled "Demo" source so EVERY tester experiences the
            // bio-reactive instrument without paired hardware. BioSimulator
            // publishes source=.fallback (always labeled "Demo") and defers the
            // moment a real source connects — so this never masks real data.
            try? await Task.sleep(for: .seconds(4))
            let live = bus.latestBio
            if live == nil || live?.source == .fallback {
                demoSource.start(publishing: bus)
            }
            #endif
        }
    }
}
#endif
