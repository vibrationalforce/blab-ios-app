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

### Slice 1 — Import extrahiert Ton → gepaarter Audio-Clip (die Kern-Naht)
- Naht: `VideoClipView.addToTimeline` (`VideoClipView.swift:236-271`), direkt nach
  `MediaLibrary.importVideo`.
- **Pure Core (test-first):** `VideoAudioPairing` — entscheidet Ziel-Audio-Lane (erste
  `.audio`-Lane, sonst „neu anlegen"), Start-Tick = identisch zum Video-Region-Start,
  Länge = Video-Dauer. Reine Werte (LaneID-Wahl, Tick, Dauer) → Unit-Test ohne AVFoundation.
- **Impure Rand:** `AVAssetExportSession(preset: AppleM4A)` (oder AVAssetReader-Muster aus
  SingleExport) → m4a; `MediaLibrary.importAudio`; `AudioClipFactory.clip/region` auf der
  Audio-Lane platzieren. Async (Export) — Fortschritt/Fehler wie `landingError`.
- **Kein Ton im Video? → nur Video landen** (guard `loadTracks(.audio).first != nil`),
  keine leere Audio-Spur.
- **Slot-Haushalt:** Video + Audio verbrauchen je einen `clips`-Slot — bei < 2 freien Slots
  ehrliche `landingError` („2 Slots frei nötig"), nicht halb landen.

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
