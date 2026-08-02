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
//  Render-safety: presented ONLY inside the studio's chip dropdown (no new sheet;
//  the presentation chain is untouched — its COUNTED size is 14, per CLAUDE.md, and
//  the "~18" that stood here was a guess that outlived the thing it guessed at, in a
//  file whose whole point is that this surface adds no modal). Inline playback is
//  AVKit's VideoPlayer — not a second MTKView, so the one-Metal-view law holds.
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

    #if canImport(Metal)
    /// ⭐ #387 — THE WAY OUT OF A RECORDING, and it belongs HERE because this is where the
    /// header's REC tile already sends you. `EchoelClipsMonitorMini` turns red while a clip is
    /// capturing and taps through to this panel; until now the panel answered that with a door
    /// labelled "Record in the visual window" — an invitation to start what was already
    /// running, and no way to end it. The only Stop lived on the visual window's own toolbar,
    /// so hiding the picture (which #319 made a supported thing to do mid-take: the renderer
    /// deliberately stays alive) left the take running with its stop button off-screen.
    ///
    /// ⚠️ WHY THIS IS NOT THE LYING-CONTROL SHAPE (#164). That class is a control whose label
    /// promises something the code does not do. This row changes its LABEL, its ACTION and its
    /// COLOUR together with one visible state, and the state it reports is the same
    /// `recorder.isRecording` the header tile reports. A control that says "Stop recording"
    /// only while a recording exists is the honest version, not the counter-example.
    ///
    /// The read is safe under the freeze law: `isRecording` derives from `video.recordState`,
    /// which changes on start and on stop and at no other time — it is not a 10 Hz source.
    @Environment(VisualRecorder.self) private var recorder
    #endif

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
    /// ⚠️ HONEST LIMIT — THE PARK IS SESSION-SHAPED, AND THAT COSTS SOMETHING REAL. This is
    /// `@State`, and this panel is rebuilt from scratch whenever the chip strip switches: leave
    /// the Video panel and the offer is gone. The file it pointed at is then unreachable, which
    /// is why `sweepStaleParks` exists — without it Delete would have quietly stopped freeing
    /// storage, and the first version of this paragraph called that a solved lifecycle. It is
    /// not solved by `tmp`; it is solved by the sweep.
    ///
    /// ⚠️ AND iOS MAY RECLAIM `tmp` ON ITS OWN SCHEDULE, so a restore is best-effort: if the
    /// park is gone `restore()` withdraws the offer rather than leaving a button that cannot
    /// keep its word. The undo is for the tap you just made, not for last week.
    @State private var deletedClip: ParkedClip?

    /// A removed clip waiting in `tmp`: where it came from, where it sits, what to call it.
    private struct ParkedClip {
        let original: URL
        let parked: URL
        let title: String
    }

    /// Filename prefix every parked clip carries, so `reload()` can find the ones this session
    /// no longer holds a reference to. It is the ONLY link between a stranded file and the
    /// sweep — change it in one place or the sweep silently stops finding anything.
    private static let parkPrefix = "echoel-deleted-"

    /// Unlink every parked clip except the one currently on offer.
    ///
    /// ⛔ THIS IS NOT HOUSEKEEPING, IT IS THE FEATURE'S OTHER HALF, and shipping without it was
    /// a functional regression the first version described as solved. Before the park, Delete
    /// freed the bytes at once. After it, the offer lives in `@State` and this panel is rebuilt
    /// from scratch every time the chip strip switches — so the ordinary path (delete, close the
    /// panel) dropped the reference and left a full-size clip in `tmp` that nothing in the app
    /// could ever reach again. A user deleting ten recordings to make room reclaimed NOTHING
    /// until iOS decided to purge, which Apple only promises "occasionally, when the app is not
    /// running". The doc that called that a solved lifecycle was the optimistic reading of the
    /// failure mode, under a heading that said HONEST LIMIT.
    ///
    /// Called from `reload()`, which runs on appear and after every delete/restore — so the
    /// stranded file from a previous visit is gone the next time the panel opens.
    private func sweepStaleParks() {
        let fm = FileManager.default
        let keep = deletedClip?.parked.lastPathComponent
        let urls = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory,
                                                includingPropertiesForKeys: nil,
                                                options: .skipsHiddenFiles)) ?? []
        for url in urls where url.lastPathComponent.hasPrefix(Self.parkPrefix) {
            guard url.lastPathComponent != keep else { continue }
            try? fm.removeItem(at: url)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if canImport(Metal)
            if recorder.isRecording {
                stopRow
            } else {
                openVisualRow
            }
            #else
            openVisualRow
            #endif

            if clips.isEmpty {
                Text("No clips yet. The record button in the visual window captures the bio-reactive visual together with your master mix — finished clips appear here.")
                    .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(clips) { clip in
                    clipRow(clip)
                }
            }

            // The way back from the last Delete — BELOW the list, deliberately.
            //
            // ⛔ THE FIRST VERSION PUT IT ON TOP AND SAID IT "can sit where the deleted clip
            // was so the eye finds it without hunting". Both halves were wrong: it was
            // unconditionally the third child of this stack, above the whole list, so deleting
            // the sixth clip in a scrolled panel rendered the offer off-screen — and inserting
            // ~49 pt above every remaining row pushed the clips ABOVE the deleted one downward
            // by close to a full row, at the instant a finger sat over a 32x32 trash glyph in a
            // strip of three look-alikes. That is the #382 defect on the one control in this app
            // that destroys something unrepeatable, and the same comment waved it away
            // ("a row that shifts a LIST is not the same defect") — the list reflow is expected
            // because the tapped row vanishes; the extra push is neither expected nor harmless.
            // At the bottom it displaces nothing above it.
            if let d = deletedClip {
                Button { restore() } label: {
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
        }
        .onAppear(perform: reload)
        .onDisappear {
            player?.pause()
            player = nil
            playingURL = nil
        }
    }

    // MARK: - The top row: start there, or end what is running

    /// The one action that CREATES clips — a real door, not a dead hint.
    ///
    /// ⚠️ THE WRAPPING MODIFIERS ARE NOT DECORATION — and the #387 commit body claimed this row
    /// already "matched its new sibling" when it had only grown a `minHeight`. It had not: this
    /// row carries the LONGER string of the two ("Record in the visual window"), so it is the
    /// one that actually needs to wrap, and at accessibility text sizes it still could not.
    /// The reviewer caught the claim, and the honest repair is to make the claim true rather
    /// than to soften the sentence — the four modifiers below are the same set `stopRow` has
    /// (#262/#353 shape: minimum height, wrap allowed, leading alignment).
    private var openVisualRow: some View {
        Button(action: onOpenVisual) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                Text("Record in the visual window")
                    .font(EchoelTheme.font(13))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.dim)
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
        .accessibilityHint("Opens the floating visual window; its record button captures the visual plus your master mix")
    }

    #if canImport(Metal)
    /// End the take from here — see the `recorder` declaration for why this row exists.
    ///
    /// It does NOT open a share sheet, and that is a decision rather than an omission: the
    /// finished clip lands in `Documents/Videos`, which is the list directly below this row, so
    /// `reload()` makes it appear WHERE the user already is, with the Play, Share and Delete it
    /// would have got anyway. Presenting a modal on top of an open panel would also mean a
    /// second presentation on a chain the black-screen law (10.76.34) says not to grow.
    private var stopRow: some View {
        Button {
            Task { @MainActor in
                _ = await recorder.stop()
                reload()
            }
        } label: {
            HStack(spacing: 8) {
                // Steady, never blinking — the flash law is a hard ceiling and a "recording"
                // dot is exactly the element that tempts an animation.
                Circle().fill(EchoelTheme.recording).frame(width: 8, height: 8)
                Text("Recording — tap to stop")
                    .font(EchoelTheme.font(13))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "stop.fill")
                    .font(.system(size: 11)).foregroundStyle(EchoelTheme.recording)
            }
            .foregroundStyle(EchoelTheme.text)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .fill(EchoelTheme.fill))
            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                .strokeBorder(EchoelTheme.recording.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop recording")
        .accessibilityHint("Ends the clip and puts it in the library below")
    }
    #endif

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
    /// ⚠️ ON FAILURE THE CLIP STAYS — AND SO DOES ITS PLAYBACK. `removeItem` was the previous
    /// body and could only fail by leaving the file where it was; `moveItem` is the same shape.
    /// If the move throws, nothing is parked, `deletedClip` is left alone and `reload()` will
    /// show the clip still there — which is the honest outcome, because it IS still there. The
    /// playback teardown therefore sits in the SUCCESS branch: stopping a clip that then turns
    /// out not to have been removed is a second unexplained thing happening to the user.
    ///
    /// ⚠️ ONE SLOT, AND THE SECOND DELETE DROPS THE FIRST OFFER. Delete A then B and only B can
    /// be taken back; A's file is swept by `sweepStaleParks` on the next `reload()` — which is
    /// the same moment, so A is gone for good the instant B is deleted. That is a deliberate
    /// pair: a one-step offer and a sweep that leaves nothing stranded. A deeper history would
    /// need a real trash with its own purge policy, which is a separate decision.
    /// The one thing not to do is clear `deletedClip` on the way IN: that would drop a
    /// still-restorable park on a delete that did not happen.
    private func delete(_ clip: EchoelVideoClip) {
        let parked = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Self.parkPrefix)\(UUID().uuidString).mp4")
        do {
            try FileManager.default.moveItem(at: clip.url, to: parked)
            if playingURL == clip.url {
                player?.pause()
                player = nil
                playingURL = nil
            }
            let title = Self.title(for: clip)
            deletedClip = ParkedClip(original: clip.url, parked: parked, title: title)
            // VoiceOver would otherwise never learn the way back exists: focus was on the row
            // that just vanished, and the offer now sits below the list where nobody has a
            // reason to swipe. The announcement is the only thing that makes it discoverable
            // to the user most likely to have hit the wrong glyph of three look-alikes.
            AccessibilityNotification.Announcement("Deleted \(title). Undo is at the end of the list.")
                .post()
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
            // ⛔ THE FIRST VERSION SAID "the park may simply have been reclaimed from `tmp`" —
            // a cause the guard eighteen lines up already returns for, and clears the offer
            // for, on the OPPOSITE principle. Two branches of one function asserting
            // contradictory laws; only a TOCTOU race reaches this one that way.
            //
            // What actually reaches here: `Documents/Videos` gone, the disk full, permissions,
            // or `<stem>-restored.mp4` also occupied. All four are transient or user-fixable,
            // so the offer STAYS — the park is still on disk and a second tap can succeed.
            // That is the one place this file deliberately leaves a button that just failed:
            // not because failing silently is fine, but because withdrawing the only way back
            // to a performance while the file still exists is worse.
            //
            // ⚠️ AND THE USER IS TOLD NOTHING TODAY. `log.log` reaches a device log, not a
            // person; a tap that does nothing is indistinguishable from a broken button. This
            // panel has no toast surface and inventing one is a bigger decision than this
            // slice. Written down rather than dressed up as "reported".
            log.log(.error, category: .video, "Video library restore failed: \(error.localizedDescription)")
        }
        reload()
    }

    /// Enumerate Documents/Videos, newest first. Cheap sync file metadata only
    /// (no AVAsset loads) — runs on appear and after delete, never per frame.
    private func reload() {
        sweepStaleParks()
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
