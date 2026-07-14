#if canImport(SwiftUI)
import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// AudioClipView.swift
// Echoel — import an audio file and play it as a CLIP: trim in/out, loop, gain,
// with Play/Stop. Drives a self-contained AudioClipPlayer attached additively to
// the master mix (no master-output surgery). First real, playable audio-clip
// surface; the timeline/ClipStore wiring builds on the same player next.

@MainActor
struct AudioClipView: View {

    /// When set (the door was opened from an AUDIO LANE HEAD), the imported file
    /// can be LANDED onto that lane as a timeline region — the "Add to timeline"
    /// button appears. Opened from an existing region (or with no lane), it stays
    /// a pure preview/trim editor (button hidden). Default keeps `AudioClipView()`.
    var landingLaneID: UUID? = nil

    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ClipStore.self) private var clips
    @Environment(TimelineStore.self) private var timeline
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var player = AudioClipPlayer()
    @State private var region = AudioClipRegion()
    @State private var importerPresented = false
    @State private var scopedURL: URL?
    /// Non-nil while a landing failed (grid full / copy error) — shown inline.
    @State private var landingError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fileRow
                    if let url = player.loadedURL {
                        WaveformTrimEditor(url: url, region: $region)
                        regionControls
                        transport
                        if let laneID = landingLaneID { landRow(laneID) }
                    } else {
                        Text("Import an audio file (WAV · AIFF · MP3 · M4A · …) to play it as a clip — trim, loop and set its level.")
                            .font(EchoelTheme.font(13))
                            .foregroundStyle(EchoelTheme.dim)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Audio Clip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(isPresented: $importerPresented,
                          allowedContentTypes: [.audio],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { load(url) }
            }
            #endif
            .onDisappear {
                player.detach()
                if let s = scopedURL { s.stopAccessingSecurityScopedResource(); scopedURL = nil }
            }
        }
    }

    private var fileRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").foregroundStyle(EchoelTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.loadedURL?.lastPathComponent ?? "No file")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                if player.durationSeconds > 0 {
                    Text(String(format: "%.2f s", player.durationSeconds))
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
            }
            Spacer(minLength: 0)
            Button("Import") { importerPresented = true }
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(EchoelTheme.onPrimary)
                .padding(.horizontal, 14).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private var regionControls: some View {
        VStack(spacing: 10) {
            EchoelValueField(label: "Start", value: secondsBinding(\.startSeconds),
                             range: 0...Float(max(0.01, player.durationSeconds)), unit: "s", decimals: 2)
            EchoelValueField(label: "End", value: secondsBinding(\.endSeconds),
                             range: 0...Float(max(0.01, player.durationSeconds)), unit: "s", decimals: 2)
            EchoelValueField(label: "Gain", value: gainBinding, range: 0...2, unit: "", decimals: 2)
            // Fades (founder "Fades bei Audio auch möglich?"): 0…region length.
            // Baked into the buffer on Play; disabled visual hint for a looping clip
            // (fades apply to clip edges, not each loop iteration).
            EchoelValueField(label: "Fade in", value: secondsBinding(\.fadeInSeconds),
                             range: 0...Float(max(0.01, region.durationSeconds)), unit: "s", decimals: 2)
            EchoelValueField(label: "Fade out", value: secondsBinding(\.fadeOutSeconds),
                             range: 0...Float(max(0.01, region.durationSeconds)), unit: "s", decimals: 2)
            Toggle(isOn: loopBinding) {
                Text("Loop").font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.text)
            }
            .tint(EchoelTheme.accent)
            if region.loop, region.fadeInSeconds > 0 || region.fadeOutSeconds > 0 {
                Text("Fades apply to a one-shot clip's edges — a looping clip plays seamlessly (fades are skipped while Loop is on).")
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button { player.play(region: region) } label: {
                Label("Play", systemImage: "play.fill")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.onPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.accent))
            }
            .buttonStyle(.plain)
            Button { player.stop() } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!player.isPlaying)
        }
    }

    // MARK: - Land onto the timeline (import into the audio lane)

    /// "Add to timeline" — copies the loaded file into the App Group and places
    /// it as a region on `laneID`, sized to the trimmed selection, after the
    /// lane's existing content. The button is only shown for a lane-head door.
    private func landRow(_ laneID: UUID) -> some View {
        VStack(spacing: 8) {
            Button { addToTimeline(laneID) } label: {
                Label("Add to timeline", systemImage: "plus.rectangle.on.rectangle")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.onPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
            }
            .buttonStyle(.plain)
            if let landingError {
                Text(landingError)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Copy the file into durable storage and add a region on the lane. Pure
    /// placement (AudioClipFactory + firstEmptySlotIndex + nextStartTick); the
    /// only impure step is the file copy. On no free clip slot or a copy failure
    /// it sets `landingError` and does not touch the stores.
    private func addToTimeline(_ laneID: UUID) {
        landingError = nil
        guard let source = player.loadedURL else { return }
        guard let slot = clips.firstEmptySlotIndex else {
            landingError = "Clip-Raster voll (8 Slots) — leere zuerst einen Slot."
            return
        }
        let dest: URL
        do {
            dest = try MediaLibrary.importAudio(from: source)
        } catch {
            landingError = "Datei konnte nicht importiert werden."
            return
        }
        // Land the TRIMMED selection: the region starts at the trim's in-point
        // (contentOffset) and is sized to the trimmed duration; falls back to the
        // whole file if the trim collapsed.
        let duration = region.durationSeconds > 0 ? region.durationSeconds : player.durationSeconds
        let offset = region.startSeconds
        let bpm = beatPlayer.pattern.tempo
        let name = source.deletingPathExtension().lastPathComponent
        let clip = AudioClipFactory.clip(name: name, mediaRef: dest.path, colorIndex: slot)
        let native = AudioClipFactory.nativeBPM(forDurationSeconds: duration, bpm: bpm)
        let startTick = timeline.document.nextStartTick(inLane: laneID)
        let placed = AudioClipFactory.region(forDurationSeconds: duration, bpm: bpm,
                                             laneID: laneID, clipID: clip.id,
                                             startTick: startTick, nativeBPM: native,
                                             contentOffsetSeconds: offset)
        clips.setClip(at: slot, clip)
        timeline.addRegion(placed)
        dismiss()
    }

    private func load(_ url: URL) {
        // Release any previous scope, claim the new one for the player's lifetime.
        if let s = scopedURL { s.stopAccessingSecurityScopedResource() }
        let scoped = url.startAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        player.attach(to: audioEngine)
        if player.load(url: url) {
            region = AudioClipRegion(startSeconds: 0, endSeconds: player.durationSeconds, loop: false)
        }
    }

    // MARK: Bindings (Double seconds ↔ Float field), re-applied to `region`.

    private func secondsBinding(_ keyPath: WritableKeyPath<AudioClipRegion, Double>) -> Binding<Float> {
        Binding(
            get: { Float(region[keyPath: keyPath]) },
            set: { region[keyPath: keyPath] = Double($0) }
        )
    }
    private var gainBinding: Binding<Float> {
        Binding(get: { region.gain }, set: { region.gain = $0 })
    }
    private var loopBinding: Binding<Bool> {
        Binding(get: { region.loop }, set: { region.loop = $0 })
    }
}

// MARK: - Waveform + trim handles (Stage 2c: "Wellenform + Trim-Griffe statt
// Blind-Zahlen" — the EchoelValueFields below stay for tick-precise entry)

/// The loaded file's waveform with the trimmed region highlighted and two
/// draggable trim handles. Drags rebuild the region through
/// `AudioClipRegion.init` so its clamping (start ≥ 0, end > start) holds.
@MainActor
private struct WaveformTrimEditor: View {
    let url: URL
    @Binding var region: AudioClipRegion

    @State private var data: WaveformData?
    private static let height: CGFloat = 96
    private static let handleHitWidth: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let dur = max(0.0001, data?.durationSeconds ?? 0)
            let x0 = min(w, CGFloat(region.startSeconds / dur) * w)
            let x1 = min(w, CGFloat(region.endSeconds / dur) * w)

            ZStack(alignment: .topLeading) {
                if let data {
                    WaveformView(data: data, tint: EchoelTheme.text)
                    // Dim everything OUTSIDE the trimmed region.
                    Rectangle().fill(EchoelTheme.bg.opacity(0.65))
                        .frame(width: max(0, x0))
                    Rectangle().fill(EchoelTheme.bg.opacity(0.65))
                        .frame(width: max(0, w - x1))
                        .offset(x: x1)
                    handle(x: x0, width: w, duration: dur, isStart: true)
                    handle(x: x1, width: w, duration: dur, isStart: false)
                } else {
                    Rectangle().fill(EchoelTheme.fill)
                        .overlay(Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(EchoelTheme.dim))
                }
            }
            .coordinateSpace(name: "waveform-trim")   // drag maps to waveform x
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
        .task(id: url) { data = await WaveformCache.shared.waveform(for: url) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waveform, trim \(String(format: "%.2f", region.startSeconds)) to \(String(format: "%.2f", region.endSeconds)) seconds")
    }

    private func handle(x: CGFloat, width: CGFloat, duration: Double, isStart: Bool) -> some View {
        Rectangle()
            .fill(EchoelTheme.text)
            .frame(width: 2, height: Self.height)
            .overlay(   // fat-finger hit area, invisible
                Color.clear
                    .frame(width: Self.handleHitWidth, height: Self.height)
                    .contentShape(Rectangle())
                    .gesture(drag(width: width, duration: duration, isStart: isStart))
            )
            .offset(x: x - 1)
    }

    private func drag(width: CGFloat, duration: Double, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("waveform-trim"))
            .onChanged { value in
                let seconds = Double(min(max(0, value.location.x), width) / width) * duration
                if isStart {
                    region = AudioClipRegion(startSeconds: min(seconds, region.endSeconds - 0.01),
                                             endSeconds: region.endSeconds,
                                             loop: region.loop, gain: region.gain,
                                             fadeInSeconds: region.fadeInSeconds,
                                             fadeOutSeconds: region.fadeOutSeconds)
                } else {
                    region = AudioClipRegion(startSeconds: region.startSeconds,
                                             endSeconds: max(seconds, region.startSeconds + 0.01),
                                             loop: region.loop, gain: region.gain,
                                             fadeInSeconds: region.fadeInSeconds,
                                             fadeOutSeconds: region.fadeOutSeconds)
                }
            }
    }
}
#endif
