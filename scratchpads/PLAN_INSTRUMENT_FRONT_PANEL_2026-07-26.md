# PLAN — Hauptfenster wird Instrumenten-Frontplatte (Founder 2026-07-26)

Founder, wörtlich: *"Genre ist gut. User Interface überarbeiten so dass alles besser
erreichbar ist und mehr wie ein Instrument wahrgenommen wird. Export settings für Loops?
Alles soll mehr so aussehen wie früher also im hauptfenster sinnvoll angeordnet"*

## IST (verifiziert 2026-07-26 am Code, nicht aus Erinnerung)

| Ort | Inhalt |
|---|---|
| `WorkspaceView` | Brand-Header (Logo · Pulse-Pill · Monitor-Tiles · Key/Scale/**Genre**-Strip) + `TransportBar` (Play/Stop · Tempo-Lock · `BodyTempoField` · Position) |
| `EchoelStudioView.menuBar:1249` | Chips: **Notes · Sound · Mix · FX · Mood · Synth** (master/export/bio/tempo/session/video sind aus `studioChips:1244` gefiltert und nur über Chrome-Türen erreichbar) |
| `:590` | `startButton` — die Generate-Mitte |
| `:601` | Instrument-Zone — **`if activeMenu != nil || presentSession != nil`**, also im Ruhezustand LEER. Der Kommentar dort rechnet noch damit, dass "die arrange TIMELINE den Schirm füllt" — die ist mit #130 weg. Seitdem: Leerraum. |
| `:1354 menuDropdownHost` | schwarzer Scrim (0.45) + Karte über der Zone, `maxHeight: 480`, `.isModal` |

Damit ist der Founder-Befund exakt reproduzierbar: **erreichbar ist alles nur über
je einen Chip, sichtbar ist immer genau eines, und darüber liegt ein Scrim.** Das ist
die Anmutung einer Einstellungs-App. "Wie früher" = die Panels lagen im Fluss des
Hauptfensters (Kartenstapel, 2026-07-12 in die Menüs verschoben) — sie waren DA,
nicht hinter einem Vorhang.

## ENTSCHEIDUNG

Nicht ein neues Panel *hinzufügen* (das wäre ein Duplikat und würde den Root-Body-Typ
wachsen lassen = Black-Screen-Gesetz), sondern die vorhandene Zone **dauerhaft
sichtbar und inline** machen. Die Chip-Leiste wird damit vom Menü zur **Reiterleiste
einer Frontplatte**.

## SLICE 1 (dieser Zyklus) — Zone immer sichtbar, Panel inline statt Overlay

1. `displayedMenu: StudioMenu { activeMenu ?? .sound }` — die Zone zeigt IMMER etwas;
   alle bestehenden `activeMenu = nil`-Stellen (Zwei-Modale-Gesetz) bleiben gültig und
   fallen auf Sound zurück statt ins Leere.
2. Zonen-Bedingung `:601` fällt — die Zone ist immer da; die Session-Karte bleibt
   intern bedingt.
3. `menuDropdownHost` → `menuPanelHost`: **Scrim weg**, `ZStack`-Branch weg,
   `.isModal` weg (es ist kein Modal mehr), `maxHeight: 480` weg (die Frontplatte
   darf den freien Raum füllen, den die Timeline hinterlassen hat).
4. Chip-Aktiv-Zustand liest `displayedMenu` statt `activeMenu`, Tap = auswählen
   (kein Toggle-Off mehr — eine Frontplatte hat keinen "nichts"-Zustand).

**Metadata-Bilanz: der Body-Typ SCHRUMPFT** (ein `if`-Branch und der ZStack-Scrim-Branch
fallen weg, es kommt kein Modifier hinzu). Kein neues `.sheet`. Kein neuer 10-Hz-Read.

**Risiko, das geprüft werden MUSS (ui-state-reviewer):** Panel-Inhalt wird jetzt
DAUERHAFT im Root-Body ausgewertet, nicht nur solange ein Dropdown offen ist. Der
Kommentar bei `:1388` fordert schon heute, dass jeder live-Readout in einem Panel ein
eigenes Leaf ist — mit Slice 1 wird aus "solange offen" ein "immer". Insbesondere
`bioPanel` (Kamera ~10 Hz) über die Header-Bio-Tür.

## SLICE 2 (nächster Zyklus, nach Geräte-Verify von Slice 1)

Anordnung *innerhalb* der Frontplatte: die Performance-Griffe (Sound-Preset, FX-Character,
Loop-Länge) in eine feste obere Reihe der Platte, die unabhängig vom gewählten Reiter
stehen bleibt — "sinnvoll angeordnet" im zweiten Sinn: das, was man beim Spielen anfasst,
ist immer unter dem Daumen. Erst nachdem Slice 1 auf dem Gerät bestätigt ist (Launch +
kein Menü-Freeze), weil Slice 2 auf der neuen Platte aufsetzt.

## LOOP-EXPORT (Founder-Frage, Antwort steht — kein Bau in diesem Slice)

Existiert, mit echten Einstellungen: Loop-Länge 1/2/4/8/16 Takte (`loopBars`, Export-Panel
`:3344`), Loudness-Ziel Streaming −14 / Podcast −16 / Broadcast −23 / Cinema −24
(`:2221`, Master-Panel) → `exportTargetLUFS:4310`, taktgenauer Bar-Align, Dateiname mit
Tonart + BPM + Kammerton + Genre (`renamedForShare:4338`), zusätzlich "Keep last N bars"
retroaktiv (`keepLastLoop:4325`) und MIDI-Export (`exportMIDI:4359`).
**Echte Lücke:** `LoopExporter.swift:140` setzt `outputFormat = .wav` hart, obwohl
`SingleExport` `.aac`/m4a kann — es gibt also keine Format-Wahl für den Loop. Das ist ein
eigener, kleiner Slice (Format-Auswahl im Export-Panel), bewusst NICHT in diesen gebündelt.
