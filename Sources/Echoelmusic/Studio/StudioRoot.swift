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

    var body: some View {
        @Bindable var navigator = navigator
        return VStack(spacing: 0) {
            BioStripView()
            TabView(selection: $navigator.selected) {
                BeatTab()
                    .tabItem { Label("Tools", systemImage: "square.grid.4x3.fill") }
                    .tag(StudioNavigator.Tab.tools)

                ClipsTab()
                    .tabItem { Label("Clips", systemImage: "square.grid.3x3.fill") }
                    .tag(StudioNavigator.Tab.clips)

                WorksView()
                    .tabItem { Label("Works", systemImage: "waveform") }
                    .tag(StudioNavigator.Tab.works)

                ModulationView()
                    .tabItem { Label("Sync", systemImage: "link") }
                    .tag(StudioNavigator.Tab.sync)

                WellView()
                    .tabItem { Label("Well", systemImage: "heart.fill") }
                    .tag(StudioNavigator.Tab.well)
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
