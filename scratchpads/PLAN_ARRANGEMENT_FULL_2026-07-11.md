# PLAN — Arrangement-View komplett (Founder-Zielbild 2026-07-11)

**Founder (verbatim-Kern):** „Überall noch Debugging. Gesamte Arrangement View
braucht MIDI/MPE; Audio mit direkt die WAV-Dateien vorhören; Audio-FX; Video-
Schnitt, Video-FX; alle FX können automatisiert werden und moduliert durch
Biofeedback."

## Ist/Fehlt-Matrix (ehrlich, Stand v10.79.149)

| Ziel | Existiert schon | Fehlt (→ Zyklus) |
|---|---|---|
| **MIDI/MPE in der Arrangement-View** | MPE-Eingang live (CoreMIDI→controllerEvents→Synth, Performer-Priorität); MPE-OUT mit 5D-Expression (MPEExpression aus Bio); MIDI-Lanes als Spur-Typ; Piano-Roll-Tür pro MIDI-Spur | **A1:** Pro-MIDI-Spur eigenes Notenmaterial (heute EIN geteiltes PianoRollModel für alle MIDI-Lanes) · **A2:** MPE-Eingang auf Spur ROUTEN + in die Spur AUFNEHMEN (Record-Arm) |
| **Audio: WAVs direkt vorhören** | ✅ SHIPPED in diesem Zyklus: Audio-Region antippen = sofort hören (Preview-Voice); Sample-Browser ▶; AudioClipView-Player | Wellenform-Scrub in der Region (später, K3-Editing) |
| **Audio-FX (pro Spur)** | ChannelFX pro Drum-Kanal (EQ etc., persistiert); EchoelFX-Masterkette (Bitcrush/Widener/…, Presets) | **B1 = K2-Kern:** Insert-FX pro Timeline-LANE (TimelineLane braucht die Engine-Referenz — die bekannte Audit-Lücke); Mixer-Strip im Spur-Kopf (Level/Mute/Solo/FX) |
| **Video-Schnitt + Video-FX** | ChromaKey.metal; CameraSession/VideoRecorder-Gerüste; Video-Lane-Typ (ehrlich „engine coming"); PLAN_VIDEO_PAGE (deferred) | **C (P3, eigener Block):** Aufnahme gegen Transport-Clock → Schnitt-Lane → Export; Video-FX als Metal-Pass (ChromaKey existiert als erster) |
| **Alle FX automatisierbar** | AutomationLane + AutomationPlayer (laufen auf dem EINEN Takt, applyStep pro Step) — heute nur Master-Level/Tempo als Ziele | **B2:** Automations-ZIELE generalisieren: jeder FX-Parameter (FXModulation-Keys) als Lane-Ziel; UI = Lane in der Timeline |
| **Alle FX bio-moduliert** | ✅ FXBioModulator (~30 Hz, Körper→FX-Param-Routing, UI-Sektion); ModulationEngine (bio→tempo); DDSP-Bio-Mappings | **B3:** dieselben Routing-Keys auf die künftigen Per-Lane-FX ausweiten (ein Registry-Schritt, kein neues System) |
| **Debugging überall** | 154 Testdateien; CI-Gates; Beweis-Log v149 (Bio-Schleife end-to-end) | **D:** systematischer Review-Sweep (code-reviewer-Agents) über Arrange/Audio/FX-Pfad + Founder-Gerätetests pro Zyklus |

**Kernerkenntnis:** „Alle FX automatisiert + bio-moduliert" ist KEIN neues System —
AutomationPlayer (Zeit-Achse) und FXBioModulator (Körper-Achse) existieren und
laufen; es fehlt die GENERALISIERUNG der Ziele (per-Lane-FX-Parameter) sobald K2
die Lane-Engine-Bindung schafft. K2 ist damit der Schlüsselstein für fast alles.

## Bau-Reihenfolge (ein Zyklus = ein Schritt, Gerätetest dazwischen)

1. ✅ **Audio vorhören** (dieser Commit)
2. **K2a — Lane-Engine-Bindung:** TimelineLane ↔ Engine-Referenz (MIDI-Lane→Roll-
   Slot, Audio-Lane→AudioClipPlayer); Mixer-Strip (Level/Mute/Solo) im Spur-Kopf
3. **K2b — Insert-FX pro Lane** (ChannelFX-Muster generalisieren) + FXBioModulator-
   Keys darauf
4. **A1 — Multi-Roll:** ein PianoRollModel-Slot PRO MIDI-Lane (Store-Schritt)
5. **B2 — Automations-Ziel-Registry:** FX-Parameter als AutomationLane-Ziele
6. **A2 — MPE-Record auf Spur** (Record-Arm; nutzt bestehenden controllerEvents-Pfad)
7. **K3 — Regionen drag/move/resize + Timeline treibt Playback** (magneticSnap+Store-APIs liegen bereit)
8. **C — Video-Block** (P3 nach Plan, eigener Meilenstein)
9. **D — Review-Sweep** läuft parallel als Agents nach jedem Block

Guardrails unverändert: Render-Safety (kein neues Sheet an EchoelStudioView, kein
10-Hz-Read in Ancestor-Bodies), Audio-Thread-Regeln, Rausch-Triade read-only,
EchoelValueField für jede Parameter-UI, ein Zyklus pro Commit.
