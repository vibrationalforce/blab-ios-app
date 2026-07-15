#if canImport(SwiftUI) && canImport(AVKit) && canImport(AVFoundation)
import SwiftUI
import AVKit
import AVFoundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(PhotosUI)
import PhotosUI
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
    /// V3: the picked source is a STILL IMAGE (Bild) — it previews as a picture and
    /// lands as a one-bar clip at the current tempo (stretch it on the timeline with
    /// the trim handles; a still has no native duration to respect).
    @State private var stillImage = false
    #if canImport(PhotosUI)
    /// Mediathek pick (founder 2026-07-15B: "Bei Video soll der volle Zugriff auf die
    /// Mediathek abgefragt werden") — the SwiftUI PhotosPicker shows the user's WHOLE
    /// photo library via the out-of-process system picker (no permission dialog
    /// needed for picking; the Info.plist string covers later in-app library reads).
    @State private var photoItem: PhotosPickerItem?
    #endif

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
                    } else if stillImage, let url = sourceURL {
                        // V3 Bild-Vorschau: AsyncImage renders the local file; the
                        // still lands as a one-bar clip (trim to any length after).
                        AsyncImage(url: url) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit()
                            } else {
                                EchoelTheme.fill
                            }
                        }
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                        if let laneID = landingLaneID { landRow(laneID) }
                    } else {
                        Text("Import a video (MP4 · MOV · …) or an image from your library to place it on this track. It previews here; transport-synced playback follows in a later update. An image lands one bar long — stretch it on the timeline.")
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
                          allowedContentTypes: [.movie, .video, .image],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    if let type = UTType(filenameExtension: url.pathExtension),
                       type.conforms(to: .image) {
                        loadImage(url)
                    } else {
                        load(url)
                    }
                }
            }
            #endif
            #if canImport(PhotosUI)
            // Mediathek pick → copy to a temp file we own (no security scope needed),
            // then the exact same load/measure/land path as a Files pick.
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                landingError = nil
                Task { @MainActor in
                    // Try VIDEO first, then IMAGE (V3) — the picker allows both.
                    if let video = try? await item.loadTransferable(type: PickedVideo.self) {
                        load(video.url)
                    } else if let image = try? await item.loadTransferable(type: PickedImage.self) {
                        loadImage(image.url)
                    } else {
                        landingError = "Dieses Element konnte nicht geladen werden."
                    }
                    photoItem = nil   // re-picking the same asset fires onChange again
                }
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
            #if canImport(PhotosUI)
            // PRIMARY: the photo library — where people's videos actually live
            // (founder: the old door only reached Files, never the Mediathek).
            PhotosPicker(selection: $photoItem, matching: .any(of: [.videos, .images]),
                         photoLibrary: .shared()) {
                Text("Mediathek")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(EchoelTheme.onPrimary)
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.text))
            }
            .buttonStyle(.plain)
            #endif
            Button("Dateien") { importerPresented = true }
                .font(EchoelTheme.font(13, .semibold))
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
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
                        .fill(durationSeconds > 0 || stillImage ? EchoelTheme.text : EchoelTheme.dim))
            }
            .buttonStyle(.plain)
            // Video waits until its duration is measured; a still has none to wait for.
            .disabled(durationSeconds <= 0 && !stillImage)
            if let landingError {
                Text(landingError)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Load + measure

    /// V3: a still image — preview as picture; lands as a one-bar clip.
    private func loadImage(_ url: URL) {
        if let s = scopedURL { s.stopAccessingSecurityScopedResource() }
        let scoped = url.startAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        player?.pause()
        player = nil
        sourceURL = url
        durationSeconds = 0
        stillImage = true
        landingError = nil
    }

    private func load(_ url: URL) {
        if let s = scopedURL { s.stopAccessingSecurityScopedResource() }
        let scoped = url.startAccessingSecurityScopedResource()
        scopedURL = scoped ? url : nil
        sourceURL = url
        durationSeconds = 0
        stillImage = false
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
        guard let source = sourceURL, durationSeconds > 0 || stillImage else { return }
        guard let slot = clips.firstEmptySlotIndex else {
            landingError = "Clip-Raster voll (8 Slots) — leere zuerst einen Slot."
            return
        }
        let bpm = beatPlayer.pattern.tempo
        let dest: URL
        // A STILL (V3) has no native duration — it lands one bar long at the current
        // tempo (stretch it afterwards with the trim handles; nothing clamps a still).
        let placedSeconds: Double
        do {
            if stillImage {
                dest = try MediaLibrary.importImage(from: source)
                placedSeconds = TimelineTime.seconds(fromTicks: TimelineTime.ticksPerBar, bpm: bpm)
            } else {
                dest = try MediaLibrary.importVideo(from: source)
                placedSeconds = durationSeconds
            }
        } catch {
            landingError = stillImage ? "Bild konnte nicht importiert werden."
                                      : "Video konnte nicht importiert werden."
            return
        }
        let name = source.deletingPathExtension().lastPathComponent
        let clip = VideoClipFactory.clip(name: name, mediaRef: dest.path, colorIndex: slot,
                                         nativeDurationSeconds: stillImage ? nil : durationSeconds)
        let startTick = timeline.document.nextStartTick(inLane: laneID)
        let placed = VideoClipFactory.region(forDurationSeconds: placedSeconds, bpm: bpm,
                                             laneID: laneID, clipID: clip.id,
                                             startTick: startTick)
        clips.setClip(at: slot, clip)
        timeline.addRegion(placed)
        dismiss()
    }
}

#if canImport(PhotosUI)
/// A video picked from the photo library, received as a FILE copied into our own
/// temp directory — so downstream (preview + App-Group import) treats it exactly
/// like a Files pick, without any security-scoped bookkeeping.
private struct PickedVideo: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { picked in
            SentTransferredFile(picked.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("mediathek-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

/// A still image picked from the photo library (V3) — same temp-copy contract as
/// PickedVideo, so downstream treats it like any local file.
private struct PickedImage: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { picked in
            SentTransferredFile(picked.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("mediathek-\(UUID().uuidString)-\(received.file.lastPathComponent)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedImage(url: dest)
        }
    }
}
#endif
#endif
