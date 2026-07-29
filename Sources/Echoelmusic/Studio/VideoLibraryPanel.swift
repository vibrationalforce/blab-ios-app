//
//  VideoLibraryPanel.swift
//  Echoelmusic — Studio
//
//  The Video window (founder 2026-07-12: "Ein Fenster für den Video Schnitt/
//  Mapping etc. Da brauchen wir noch insgesamt eine intelligente Lösung"),
//  built HONEST: everything on this surface works today. Clips recorded from
//  the visual window (bio-reactive Metal visual + the master mix, muxed) land
//  durably in Documents/Videos; this panel lists them, plays them inline,
//  shares through the studio's ONE existing share slot, and deletes. Trim /
//  mapping (P3) build on top of this library when they ship — no placeholder
//  buttons for them here ("Clear Software": every control does something).
//
//  Render-safety: presented ONLY inside the DMMW menu dropdown (no new sheet;
//  the ~18-modal chain is untouched). Inline playback is AVKit's VideoPlayer —
//  not a second MTKView, so the one-Metal-view law holds.
//

#if canImport(SwiftUI) && canImport(AVKit) && canImport(AVFoundation)
import SwiftUI
import AVKit
import AVFoundation

/// One recorded clip in the durable library (Documents/Videos).
struct EchoelVideoClip: Identifiable, Equatable {
    let url: URL
    let date: Date
    let bytes: Int64
    var id: URL { url }
}

/// The Video window's content: recordings library with inline playback.
@MainActor
struct VideoLibraryPanelContent: View {

    /// Hand a clip to the studio's EXISTING ShareSheet slot (no new sheet here).
    let onShare: (URL) -> Void
    /// Open the floating visual window — where the record button lives.
    let onOpenVisual: () -> Void

    @State private var clips: [EchoelVideoClip] = []
    @State private var playingURL: URL?
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The one action that CREATES clips — a real door, not a dead hint.
            Button(action: onOpenVisual) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Record in the visual window")
                        .font(EchoelTheme.font(13, .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
                }
                .foregroundStyle(EchoelTheme.text)
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the floating visual window; its record button captures the visual plus your master mix")

            if clips.isEmpty {
                Text("No clips yet. The record button in the visual window captures the bio-reactive visual together with your master mix — finished clips appear here.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(clips) { clip in
                    clipRow(clip)
                }
            }
        }
        .onAppear(perform: reload)
        .onDisappear {
            player?.pause()
            player = nil
            playingURL = nil
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func clipRow(_ clip: EchoelVideoClip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    togglePlay(clip)
                } label: {
                    Image(systemName: playingURL == clip.url ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 32, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                            .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playingURL == clip.url ? "Stop playback" : "Play clip")

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(for: clip))
                        .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    Text(Self.subtitle(for: clip))
                        .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                }
                Spacer(minLength: 8)

                Button { onShare(clip.url) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(EchoelTheme.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share clip")

                Button(role: .destructive) { delete(clip) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(EchoelTheme.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete clip")
            }
            if playingURL == clip.url, let player {
                VideoPlayer(player: player)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: EchoelTheme.radius))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    // MARK: - Actions

    private func togglePlay(_ clip: EchoelVideoClip) {
        if playingURL == clip.url {
            player?.pause()
            player = nil
            playingURL = nil
        } else {
            player?.pause()
            let p = AVPlayer(url: clip.url)
            player = p
            playingURL = clip.url
            p.play()
        }
    }

    private func delete(_ clip: EchoelVideoClip) {
        if playingURL == clip.url {
            player?.pause()
            player = nil
            playingURL = nil
        }
        do {
            try FileManager.default.removeItem(at: clip.url)
        } catch {
            log.log(.error, category: .video, "Video library delete failed: \(error.localizedDescription)")
        }
        reload()
    }

    /// Enumerate Documents/Videos, newest first. Cheap sync file metadata only
    /// (no AVAsset loads) — runs on appear and after delete, never per frame.
    private func reload() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            clips = []
            return
        }
        let dir = docs.appendingPathComponent("Videos", isDirectory: true)
        let urls = (try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles)) ?? []
        clips = urls
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .map { url in
                let vals = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return EchoelVideoClip(url: url,
                                       date: vals?.creationDate ?? .distantPast,
                                       bytes: Int64(vals?.fileSize ?? 0))
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Display helpers (pure)

    static func title(for clip: EchoelVideoClip) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: clip.date)
    }

    static func subtitle(for clip: EchoelVideoClip) -> String {
        // ⛔ WAS `String(format: "%.1f MB · …", Double(clip.bytes) / 1_048_576.0)`, wrong twice
        // over: `%.1f` writes a hardcoded "." decimal separator (a German reader expects
        // "12,4"), and forcing the MB unit printed a 400 KB clip as "0.4 MB". `ByteCountFormatter`
        // fixes both in one call — it picks the unit AND punctuates it in the reader's locale.
        // The sibling `title(for:)` above already uses a locale-aware `DateFormatter`, so this
        // line was the odd one out in its own file.
        let size = ByteCountFormatter.string(fromByteCount: clip.bytes, countStyle: .file)
        return "\(size) · MP4 · visual + master mix"
    }
}
#endif
