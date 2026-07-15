#if canImport(SwiftUI) && canImport(AVKit) && canImport(AVFoundation)
import SwiftUI
import AVKit
import AVFoundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// VideoClipView.swift
// Echoel — import a video file from the media library and LAND it on a video lane
// as a timeline region. The DAW#4 twin of AudioClipView: pick → inline AVKit
// preview → "Add to timeline" copies the file into the App Group and places a
// region through the same PURE seams (MediaLibrary + VideoClipFactory +
// firstEmptySlotIndex + nextStartTick). Transport-synced video PLAYBACK
// (VideoLanePlayer) is a later slice — this door imports + previews only, and is
// only offered from a video-lane head (landingLaneID set).

@MainActor
struct VideoClipView: View {

    /// The video lane this import lands on (set from the lane head). Non-nil here
    /// by construction (the door is only offered for a video lane), but optional
    /// keeps the signature symmetric with AudioClipView.
    var landingLaneID: UUID? = nil

    @Environment(ClipStore.self) private var clips
    @Environment(TimelineStore.self) private var timeline
    @Environment(BeatPlayer.self) private var beatPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var importerPresented = false
    @State private var scopedURL: URL?
    @State private var sourceURL: URL?
    @State private var player: AVPlayer?
    @State private var durationSeconds: Double = 0
    @State private var landingError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fileRow
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                                .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        if let laneID = landingLaneID { landRow(laneID) }
                    } else {
                        Text("Import a video (MP4 · MOV · …) from your library to place it on this track. It previews here; transport-synced playback follows in a later update.")
                            .font(EchoelTheme.font(13))
                            .foregroundStyle(EchoelTheme.dim)
                            .padding(.top, 4)
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Video Clip")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #if canImport(UniformTypeIdentifiers)
            .fileImporter(isPresented: $importerPresented,
                          allowedContentTypes: [.movie, .video],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { load(url) }
            }
            #endif
            .onDisappear {
                player?.pause()
                player = nil
                if let s = scopedURL { s.stopAccessingSecurityScopedResource(); scopedURL = nil }
            }
        }
    }

    private var fileRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "film").foregroundStyle(EchoelTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceURL?.lastPathComponent ?? "No file")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text).lineLimit(1)
                if durationSeconds > 0 {
                    Text(String(format: "%.2f s", durationSeconds))
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

    private func landRow(_ laneID: UUID) -> some View {
        VStack(spacing: 8) {
            Button { addToTimeline(laneID) } label: {
                Label("Add to timeline", systemImage: "plus.rectangle.on.rectangle")
                    .font(EchoelTheme.font(14, .semibold))
                    .foregroundStyle(EchoelTheme.onPrimary)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(durationSeconds > 0 ? EchoelTheme.text : EchoelTheme.dim))
            }
            .buttonStyle(.plain)
            .disabled(durationSeconds <= 0)   // wait until the duration is measured
            if let landingError {
                Text(landingError)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Load + measure

    private func load(_ url: URL) {
        if let s = scopedURL { s.stopAccessingSecurityScopedResource() }
        let scoped = url.startAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        sourceURL = url
        durationSeconds = 0
        landingError = nil
        player = AVPlayer(url: url)
        // Measure duration asynchronously (the asset is created inside the task so
        // no non-Sendable value crosses the boundary), then publish on the main actor.
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            let measured = try? await asset.load(.duration)
            // Ignore a stale measurement if the user re-imported meanwhile — only
            // publish when this URL is still the loaded one.
            guard url == sourceURL, let cm = measured, cm.seconds.isFinite, cm.seconds > 0 else { return }
            durationSeconds = cm.seconds
        }
    }

    // MARK: - Land onto the timeline

    /// Copy the picked video into the App Group and place a region on `laneID`,
    /// sized to the (whole-file) duration at the current tempo, after the lane's
    /// existing content. Pure placement; the only impure step is the file copy.
    private func addToTimeline(_ laneID: UUID) {
        landingError = nil
        guard let source = sourceURL, durationSeconds > 0 else { return }
        guard let slot = clips.firstEmptySlotIndex else {
            landingError = "Clip-Raster voll (8 Slots) — leere zuerst einen Slot."
            return
        }
        let dest: URL
        do {
            dest = try MediaLibrary.importVideo(from: source)
        } catch {
            landingError = "Video konnte nicht importiert werden."
            return
        }
        let bpm = beatPlayer.pattern.tempo
        let name = source.deletingPathExtension().lastPathComponent
        let clip = VideoClipFactory.clip(name: name, mediaRef: dest.path, colorIndex: slot)
        let startTick = timeline.document.nextStartTick(inLane: laneID)
        let placed = VideoClipFactory.region(forDurationSeconds: durationSeconds, bpm: bpm,
                                             laneID: laneID, clipID: clip.id,
                                             startTick: startTick)
        clips.setClip(at: slot, clip)
        timeline.addRegion(placed)
        dismiss()
    }
}
#endif
