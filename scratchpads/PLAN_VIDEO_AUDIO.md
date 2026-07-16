# PLAN — Video-Sound (Founder 2026-07-16: „Video Sound … mit den selben Algorithmen")

**Explore-Audit 2026-07-16 (a6b74edb).** Der Founder hat **nie Video-Ton gehört** — und das
ist KEIN Bug im Player, sondern eine bewusst offene Design-Lücke: der Timeline-Video-Monitor
läuft **`AVPlayer.isMuted = true`** (`FloatingVideoMonitor.swift:41`, „picture-only by design").
Der Ton des Video-Clips wird **nie extrahiert, nie geroutet**. Die vom Code selbst
vorgesehene Architektur: **Monitor bleibt Bild-only; der TON kommt aus einer Audio-Spur.**
Das deckt sich exakt mit dem Founder-Satz „mit den selben Algorithmen" — extrahierter
Video-Ton = ein normaler Audio-Clip, der durch `AudioLanePlayer → masterMixer` läuft und
damit Warp (#54) + FX + Master erbt.

## Warum nicht einfach unmuten?
Der Monitor-`AVPlayer` hat seinen EIGENEN Audio-Ausgang, der `AudioEngine` komplett umgeht
(kein Master-Trim, kein Warp, kein FX, doppelter Signalweg). Unmuten wäre der falsche,
engine-umgehende Pfad. Die Naht gehört an den **Import**, nicht an den Player.

## Ist-Zustand (verifiziert, file:line)
- Timeline-Video = stumm: `FloatingVideoMonitor.swift:41` (`isMuted = true`).
- Import-Preview (Sheet) hat Ton, aber via AVPlayer-Eigenausgang (`VideoClipView.swift:57-58`).
- Kamera-Capture schreibt GAR keine Audiospur (`VideoRecorder.swift:193`, nur `.video`-Input).
- Audio-Extraktion existiert schon als Muster: `SingleExport.swift:143-160` (AVAssetReader,
  `loadTracks(withMediaType: .audio)`).
- Landing-Zwilling existiert: `AudioClipFactory.clip/region` + `TimelineStore.addLane(kind:.audio)`
  (`TimelineStore.swift:424`) + Default-„Audio 1"-Lane (`:59`).

## Scheiben (test-first wo pur; Review Pflicht)

### Slice 1a — Pure Pairing-Core (✅ GEBAUT 2026-07-16, test-first)
`VideoAudioPairing` (`Sequencer/VideoAudioPairing.swift`): `plan(videoStartTick:
videoLengthTicks:existingAudioLaneIDs:contentOffsetSeconds:gain:)` → `Plan{lane, startTick,
lengthTicks, contentOffsetSeconds, gain}`. Lock-Gesetz: der Audio-Clip erbt **identischen
startTick + lengthTicks** des Video-Regions (nie Drift), Trim-In-Point = contentOffset.
LaneChoice = erste non-bio `.audio`-Lane sonst `.createNew`. `hasRoom(freeSlotCount:)` ≥ 2.
NaN/negativ sanitisiert, Länge ≥ 1 Bar. `VideoAudioPairingTests` (10 Tests). Rein — keine
AVFoundation, keine Stores. Der korrektheits-kritische Teil, bevor der async-Rand kommt.

### Slice 1b — Async-Extraktion + Wiring (NÄCHSTE Scheibe, audio-review Pflicht)
- Naht: `VideoClipView.addToTimeline` (`VideoClipView.swift:236-271`), nach `importVideo`.
- **Impure Rand:** `VideoAudioExtractor` — `AVAssetExportSession(preset: AppleM4A)` (oder
  AVAssetReader-Muster aus SingleExport) → m4a; async, injizierbar (Test-Stub). Guard
  `loadTracks(.audio).first != nil` → **kein Ton? nur Video landen** (keine leere Spur).
- **Wiring:** `VideoAudioPairing.plan(...)` liest die vorhandenen Audio-Lanes + `videoStartTick/
  LengthTicks` der eben gelandeten Video-Region; `.createNew` → `timeline.addLane(kind:.audio)`
  dann `document.lanes.last`. TimelineRegion DIREKT mit `plan.lengthTicks` bauen (NICHT
  `AudioClipFactory.region`, das re-derived die Länge → Drift). `MediaLibrary.importAudio` +
  `AudioClipFactory.clip` + `clips.setClip`.
- **Slot-Haushalt:** `VideoAudioPairing.hasRoom(freeSlotCount:)` VOR dem Landen — < 2 freie
  Slots → ehrliche `landingError`, nicht halb landen.
- **Review-Verträge (Slice-1a-LOWs) für 1b:** (1) an `plan()` den **bar-gefloorten
  `lengthTicks` der GELANDETEN Video-Region** übergeben, NIE eine rohe Media-Dauer — sonst
  greift der 1-Bar-Floor und Ton (1 Bar) ≠ Bild (Sub-Bar). (2) `existingAudioLaneIDs` am
  Call-Site auf **non-bio, non-master `.audio`-Lanes** filtern (der pure Core prüft das nicht)
  — sonst landet der Ton auf der falschen Spur. Beide mit 1b-Test absichern.

### Slice 2 — Bild + Ton bewegen sich zusammen (Pairing-Link)
- Ein optionales `pairedRegionID` (Video↔Audio), damit Move/Trim/Delete des einen den
  anderen mitzieht. decodeIfPresent-back-compat. (Slice 1 ohne Link ist schon hörbar —
  Link ist die Politur.)

### Slice 3 — Warp erbt automatisch (nach #54 Slice B)
- Der gepaarte Audio-Clip nutzt denselben `warpEnabled`/`nativeBPM`-Pfad — bei tempo-
  konformem Ausgangsmaterial zieht der Video-Ton auf Projekt-Tempo mit (die „selben
  Algorithmen" wörtlich). Kein Extra-Code, fällt aus #54 heraus.

## Erste Scheibe = Slice 1 (Import-Extraktion + gepaarter Audio-Clip).
## NICHT den Monitor unmuten (engine-umgehend). Review + CI grün; Hörtest = Geräte-Session.
