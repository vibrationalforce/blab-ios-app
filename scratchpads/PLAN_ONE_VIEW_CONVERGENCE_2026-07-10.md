# PLAN — One-View-Konvergenz (die alles vereinende Main View)

Founder 2026-07-10: „Überprüfe ganz genau mit allen Fähigkeiten ob alles was wir
uns vorgenommen haben realistisch und sinnvoll ist. Natürlich will ich gerne
alles auf einem Hackbrett haben und möglichst zugänglich. Strukturiere um, damit
wir eine alles vereinende Main View haben."
Reaffirmiert 2026-07-09: „Die Arrangementview ist die einzige Ansicht die wir
noch brauchen — alles andere läuft über die Spuren."

## Realism-Audit-Ergebnis (2 Explore-Agents, 2026-07-10)

**Arrange-Ist-Stand:** Stage 0 (SurfaceSwitcher) + 1a/b/c (Timeline-Modell,
Store+Migration, Beat-Grid-View) + 2a/b/c (WAV-Waveform-Kette) = FERTIG.
ArrangeTimelineView war bis heute ein **reiner Viewer** (zoombar, Playhead,
Regionen) — keine Spur-Türen, kein Editing, keine Engine-Bindung, Playback
weiter über den bar-granularen ArrangementPlayer. Default-Surface = Studio
(.compose); der geplante Flip auf .arrange „bei Stage 2" ist bewusst NICHT
passiert (Viewer als Home wäre eine Regression).

**Struktur-Kernlücke (das eigentliche Umbau-Werk):** `TimelineLane` hat KEINE
Verbindung zu BeatPlayer-Kanälen, Melodie-Instrument/Patch oder FX — Spuren
sind heute rein visuell (Name + Kind). „Alles über die Spuren" = Lanes an
Engine-Slots binden + Spur-Kopf-Affordanzen.

**Mix** (ChannelRackView) ist bereits voll per-Track (aber Drum-Kanäle, nicht
Lanes) → am leichtesten in Spur-Köpfe auflösbar. **Clips** sind das Payload-
Modell der Regionen (gleiche `Clip`-Typen) → Clips fallen in Lanes, die Surface
löst sich als Grid auf.

## Konvergenz-Stufen (Ralph-Zyklen, je ≤3 Dateien, launch-safe: v140/v143 bleiben Kandidaten)

- **K1 — Spur-Köpfe werden Türen** ✅ (dieser Zyklus): Lane-Header = Menu
  (MIDI → Piano Roll, Audio → Audio-Editor, Rename, Delete-if-empty);
  Toolbar „+" = Add Track (MIDI/Audio). EIN .sheet(item:) + EIN Alert auf
  ArrangeTimelineView (NICHT EchoelStudioView — Metadaten-Regel gewahrt).
- **K2 — Lane↔Engine-Bindung:** TimelineLane bekommt optionale Engine-Referenz
  (Drum-Kanal-Index / Melodie-Slot); Spur-Kopf zeigt Mute/Solo/Level des
  gebundenen Kanals (löst Mix in die Spuren auf). Reine Modell-Erweiterung +
  Header-UI; BeatPlayer unangetastet.
- **K3 — Region-Editing + Timeline treibt Playback:** Drag/Move/Resize mit
  magneticSnap (Store-APIs existieren), Tap-to-select; ArrangementPlayer liest
  die Timeline statt der Legacy-Sections (Migration ist verlustfrei, reversibel).
- **K4 — Compose wird Drawer der Timeline:** Composition/Session/FX/Export-
  Karten als einklappbarer Bereich ÜBER den Spuren (eine Scroll-Fläche);
  Default-Surface-Flip auf .arrange; Switcher-Chips entfallen. ERST wenn K3
  spielt — vorher wäre der Flip eine Regression.
- **K5+ — Video-/Bio-Lane:** Video-Capture gegen die Transport-Clock (Stage V),
  Bio-Automation-Lane rendert (isBio existiert im Modell), MPE-Lanes (P).

## Realism-Verdikt aller offenen Vorhaben (Inventar-Agent, komprimiert)

| Arc | Verdikt |
|---|---|
| A v1.0-Launch-Rest (Listing, CloudKit-Schema, Device-Verify) | REALISTISCH, Tage — nur Founder-Aktionen offen |
| B One-View/Timeline | REALISTISCH, gestuft (K1–K5); XL nur als Ganzes, nie als Zyklus |
| C v1.1 Echoel Live (Abo-Umwidmung, SharePlay-Sessions, Tempo-Sync) | REALISTISCH — SharePlay = kostenlose Apple-Infra; ASC-Abo = Founder |
| D v1.2 Broadcast (HaishinKit, Host-Fee, Cause-Events) | REALISTISCH mit der EINEN erlaubten Dependency; Partner-Modell statt eigener Server |
| E Extras (E3c Wetter-Palette S, E7 Health-Write M, AX-Audit M) | SINNVOLL, klein, nach Launch |
| Riff-Exchange / Collab-Board / Avatare / Marketplace | Erst mit Community-Masse (v1.2+); nicht vorziehen |
| Worldwide-Realtime-Jam | North Star; als Puls+Partitur (taktquantisiert) via SharePlay EHRLICH machbar — nie „Audio-Jam" versprechen |
| FEATURE_MATRIX-Langliste (visionOS/tvOS/NDI/EEG…) | GEPARKT — kein Commitment, nur Ideenraum |

## Sequenz-Entscheid (Council, launch-safe)
Launch-Gesicht v1.0 = heutiges Studio-Home (founder-getestet, „das Instrument
war perfekt — erstmal launchen"). Die One-View konvergiert PARALLEL auf dem
Branch (K1…) und wird Home, sobald K3/K4 sie zum spielbaren Instrument machen —
kein Launch-Risiko, kein Feature-Verlust, jede Stufe einzeln testbar.
