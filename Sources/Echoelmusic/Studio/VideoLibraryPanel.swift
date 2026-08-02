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

    /// The clip removed by the last Delete, PARKED rather than erased, so the removal can be
    /// taken back. Nil = nothing to restore.
    ///
    /// ⭐ WHY PARKING AND NOT A CONFIRMATION. Every other destructive control in this app was
    /// made reversible in #357 rather than confirmed, on one argument: a prompt can only warn,
    /// a way back gives the thing back. That argument was easy for a preset (keep the value in
    /// `@State`) and looked impossible here, because the thing is a FILE and `removeItem` is
    /// final. It is not impossible: `Documents` and `tmp` are the same volume inside the app
    /// container, so `moveItem` is a rename — constant time regardless of how many hundred
    /// megabytes the clip is — and a rename is undone by renaming back.
    ///
    /// This is the most irreplaceable thing the app can destroy. A preset can be dialled again
    /// and a take regenerated; a recorded performance cannot be performed again. The button
    /// that destroyed it was a 32×32 trash glyph ten points from Share, in a row of three
    /// look-alike icons, with no prompt and no way back.
    ///
    /// ⚠️ HONEST LIMIT — THE PARK IS SESSION-SHAPED, IN TWO WAYS, AND BOTH ARE DELIBERATE.
    /// This is `@State`: leave the Video panel and the offer is gone, while the parked file
    /// stays in `tmp` where the system reclaims it. That is what `tmp` is for, and it is the
    /// reason nothing here has to invent a trash folder with its own purge policy — a second
    /// lifecycle to get wrong. And iOS may reclaim `tmp` on its own schedule, so a restore is
    /// offered on a best-effort basis: `restore()` reports the failure instead of pretending.
    /// The undo is for the tap you just made, not for last week.
    @State private var deletedClip: ParkedClip?

    /// A removed clip waiting in `tmp`: where it came from, where it sits, what to call it.
    private struct ParkedClip: Equatable {
        let original: URL
        let parked: URL
        let title: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The one action that CREATES clips — a real door, not a dead hint.
            Button(action: onOpenVisual) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Record in the visual window")
                        .font(EchoelTheme.font(13))
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

            // The way back from the last Delete. An inline row, not a modal: it costs no
            // presentation slot, and it can sit where the deleted clip was so the eye finds it
            // without hunting. Shown only while there is something to restore — a row that
            // shifts a LIST is not the same defect as an arrow that shifts a control the user
            // is aiming at (#382), because the list has just reflowed anyway.
            if let d = deletedClip {
                Button(action: restore) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Undo delete of \(d.title)")
                            .font(EchoelTheme.font(13))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(EchoelTheme.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .fill(EchoelTheme.fill))
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                        .strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Puts the recording back into the library")
            }

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

    // ⚠️ NO `@ViewBuilder` HERE, DELIBERATELY. The body is a single `VStack` (its own builder
    // handles the conditional player), so the attribute bought nothing — and it forbids the
    // explicit `return` this function now needs after binding `name`. Dropping it is the
    // smaller change of the two available; the alternative, a bare `let` inside a builder
    // block, is legal but reads as an accident to the next author.
    private func clipRow(_ clip: EchoelVideoClip) -> some View {
        // ⭐ EVERY BUTTON IN THIS ROW NAMES ITS CLIP. They used to read "Play clip", "Share
        // clip", "Delete clip" — correct for ONE row and useless in a list, which is the only
        // shape this surface has: a VoiceOver user swiping through six recordings heard the
        // same three words six times and had no way to tell which one the trash belonged to.
        // The visible label is the recording's date and time, so that is what each control is
        // named after; the sighted reading and the spoken one are then the same sentence.
        let name = Self.title(for: clip)
        return VStack(alignment: .leading, spacing: 8) {
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
                .accessibilityLabel(playingURL == clip.url ? "Stop \(name)" : "Play \(name)")

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
                .accessibilityLabel("Share \(name)")

                Button(role: .destructive) { delete(clip) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(EchoelTheme.danger)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(name)")
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

    /// Move the clip out of the library into `tmp`, keeping it restorable.
    ///
    /// ⚠️ ON FAILURE THE CLIP STAYS. `removeItem` was the previous body and could only fail by
    /// leaving the file where it was; `moveItem` is the same shape. If the move throws, nothing
    /// is parked, `deletedClip` is left alone and `reload()` will show the clip still there —
    /// which is the honest outcome, because it IS still there. The one thing not to do is clear
    /// `deletedClip` on the way in: that would drop a previous, still-restorable park on a
    /// delete that did not happen.
    private func delete(_ clip: EchoelVideoClip) {
        if playingURL == clip.url {
            player?.pause()
            player = nil
            playingURL = nil
        }
        let parked = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoel-deleted-\(UUID().uuidString).mp4")
        do {
            try FileManager.default.moveItem(at: clip.url, to: parked)
            deletedClip = ParkedClip(original: clip.url,
                                     parked: parked,
                                     title: Self.title(for: clip))
        } catch {
            log.log(.error, category: .video, "Video library delete failed: \(error.localizedDescription)")
        }
        reload()
    }

    /// Move the parked clip back into the library.
    ///
    /// ⚠️ THE DESTINATION IS CHECKED FIRST. `moveItem` throws if something already occupies the
    /// path, and a recording made after the delete could in principle carry the same name. In
    /// that case the clip comes back beside it under a `-restored` name rather than failing or
    /// — far worse — overwriting the newer file. A restore that destroys something else is not
    /// a restore.
    private func restore() {
        guard let d = deletedClip else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: d.parked.path) else {
            // The park is gone — iOS reclaims `tmp` on its own schedule. Withdraw the offer
            // rather than leaving a button that cannot do what it says; a control that fails
            // silently on every tap is worse than one that is no longer there.
            log.log(.error, category: .video, "Video library restore: parked clip no longer present")
            deletedClip = nil
            return
        }
        var target = d.original
        if fm.fileExists(atPath: target.path) {
            let stem = target.deletingPathExtension().lastPathComponent
            target = target.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-restored.\(target.pathExtension)")
        }
        do {
            try fm.moveItem(at: d.parked, to: target)
            deletedClip = nil
        } catch {
            // Keep the offer standing: the park may simply have been reclaimed from `tmp`, and
            // a row that vanishes without saying anything is how a user learns not to trust it.
            log.log(.error, category: .video, "Video library restore failed: \(error.localizedDescription)")
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
        //
        // TWO CONSEQUENCES THE FIRST VERSION OF THIS COMMENT LEFT OUT, and leaving them out is
        // the same defect class as the bug — an incomplete note written to explain a
        // correctness fix reads as if nothing else moved:
        //  · `.file` counts in DECIMAL (1000-based), the old maths divided by 1_048_576 (MiB).
        //    Every size now prints ~4.8 % larger per magnitude — a clip that read "400.0 MB"
        //    reads "419.4 MB". That is not a regression: it is what Finder and the Files app
        //    show for the same file, so the number finally agrees with the rest of the system.
        //  · a 0-byte clip (a failed recording, or `resourceValues` failing at the `try?` in
        //    `reload`) now reads "Zero KB" instead of "0.0 MB", because
        //    `allowsNonnumericFormatting` defaults on. Kept at the default deliberately —
        //    Apple recommends it for languages where a bare "0" reads badly, and a conspicuous
        //    row is the honest presentation of a clip that has no content.
        let size = ByteCountFormatter.string(fromByteCount: clip.bytes, countStyle: .file)
        return "\(size) · MP4 · visual + master mix"
    }
}
#endif
