# PLAN — DMMW-Shell v3 (Founder 2026-07-12, nach v175-Test)

**Founder (verbatim):** "Master, Export, Live und Learn kommt oben in die Leiste
neben das Schloss. Video ist eine eigene Spur Art, wo auch Video Capture und
voll Zugriff auf die Apple Mediathek gecheckt wird. Mix wird Teil der Spuren in
der Timeline (also Auflösung und neu organisieren). Comp, Session, Transpose,
Sound, FX, Mood, Synth, Word zu einem Eigenen AuV3 Plug In namens
EchoelBioSynth. Plugins wird aufgelöst und Teil der Funktionen in den Spuren.
Hier wollen wir auf alle Auv3 die auf dem Gerät installiert sind zugreifen.
Sowie auf unser eigenes auv3 EchoelBiosynth weitere eigene Plugins und externe
auv3 Plugins, die im AppStore angeboten werden."

("Word" = unklar, vermutlich Autokorrektur — gelesen als "alle übrigen
Instrument-Panels", Weather eingeschlossen. Bei Founder-Korrektur anpassen.)

## Zielbild

Echoel = **Host UND Instrument**: die Timeline-Spur ist die Einheit; ihre
Klangquelle ist ein AUv3 (unser EchoelBioSynth oder jedes installierte/Store-
Plugin); die Shell behält nur Chrome (Transport + globale Türen Master/Export/
Live/Learn). Das Bio-Instrument (Comp/Session/Transp/Sound/FX/Mood/Synth/
Weather) wandert als **EchoelBioSynth** in den (existierenden, dormanten)
AUv3-Target — nutzbar in Echoel selbst UND in AUM/Loopy/Logic etc.

## Phasen (je ≥1 Zyklus; Reihenfolge = Risiko aufsteigend)

- [x] **E1 — Chrome-Reorg (sofort, ein Zyklus):** Master · Export · Live · Learn
      als kleine Icon-Buttons in die TransportBar neben das Schloss
      (Notification-Muster wie der Puls-Knopf — Chrome kennt keine Studio-
      Bindings). Studio-Menüleiste verliert Master/Export-Chips + Live/Learn-
      Direktchips + Plugins-Chip (Plugins liegt seit 07810ba auf den Spur-
      Türen — "aufgelöst" damit erfüllt). Dropdown-Fälle .master/.export
      BLEIBEN im Enum (die Chrome-Buttons öffnen sie).
- [ ] **E2 — ALLE Panels vertikal auf die Spuren (Founder 2026-07-12,
      Screenshot v177/2283 mit eingekreister Chip-Leiste: "Das soll alles
      vertikal auf die Spuren verteilt werden bzw. in EchoelBioSynth
      zusammengefasst werden"):** Nicht nur Mix — die GANZE Studio-Leiste
      löst sich in Spur-Türen auf. Reihenfolge (je ein Zyklus, ehrlich):
      - E2a: MIDI-Spur-Tür trägt Comp · Transp · Sound · FX · Synth · Mood
        (ArrangeModal-Fälle im EINEN Timeline-Sheet-Slot — Muster 07810ba;
        Inhalte = dieselben Panel-Builder, "eine Quelle, zwei Türen").
        EHRLICHE GRENZE bleibt im Editor-Text: bis Multi-Roll (A4) formen
        diese Türen DAS eine melodische Instrument, nicht "nur diese Spur".
      - E2b: Mix → Spuren (Bus-Strips als Spur-Funktion; Drums-Kanäle über
        die Drum-Spur-Tür) — wie ursprünglich geplant.
      - E2c: Studio-Chip-Leiste SCHRUMPFT erst, wenn die Spur-Türen wirken
        (Founder-Test) — Chips fallen nie vor ihrem wirkenden Ersatz.
        Session (nicht spur-gebunden) bleibt vorerst in der Leiste; sein
        Endziel ist das EchoelBioSynth-Panel-Set (E4, mit "Word"-Frage).
- [ ] **E-Bio — Bio-Strip vereinfacht in den Header (Founder 2026-07-12,
      2. Screenshot: BioStrip eingekreist, Pfeil auf die Kopfzeile — "Diese
      Leiste soll in vereinfachter Form da oben landen"):** kompaktes
      BioHeaderLeaf NEBEN Logo/Titel (erweitert den PulseMonitorMiniLive-
      Slot): Trace + HR + Coh (vereinfachte Form; HRV/Br in der Detail-Tür),
      Read-pulse als Tap aufs Leaf. RENDER-GESETZ 10.76.50: alle Live-Reads
      NUR im eigenen Leaf-Body — der Header churnt nie. ACHTUNG Verdrahtung:
      die .onReceive-Anker (.echoelToggleBio/.echoelChromeDoor) hängen heute
      an der INNEREN BioStripView-Zeile — beim Auszug der Zeile müssen sie
      auf einen anderen stabilen inneren View umziehen (nie auf die
      Root-Modifier-Kette). Der alte Strip fällt erst, wenn der Header-
      Ersatz WIRKT (Founder-Test).
- [ ] **E3 — Video-Spur-Art:** "+"-Menü bietet Video-Spur (ClipKind.video
      existiert). Spur-Tür: Video aufnehmen (VisualRecorder-Pfad) · aus
      Mediathek importieren (PHPickerViewController — voller Mediathek-Zugriff
      ohne Blanket-Permission) · Clip-Bibliothek (heutiges Video-Fenster wird
      zur Spur-Funktion). Wiedergabe von Video-Regionen auf der Timeline =
      eigener Engine-Slice (AVPlayer-Sync zum Transport). DEVICE-GATED.
- [ ] **E4 — EchoelBioSynth (AUv3):** der dormante `Sources/EchoelmusicAUv3`-
      Target wird das Instrument: DDSP/Poly-Voices + Composition-Parameter
      (Genre/Key/Kammerton/Tempo-Follow) als AUParameter, Panels als Plugin-UI.
      MEHRWÖCHIG: eigener Plan + Council VOR Target-Umbau (project.yml/CI),
      Bio-Zugriff im Extension-Kontext klären (App-Group/Host-MIDI statt
      Kamera — eine Extension hat keinen Kamera-Zugriff wie die App!).
      Wichtig: die Panels verschwinden erst aus der App-Shell, wenn das
      Plugin sie WIRKLICH trägt — bis dahin bleiben die Chips (ehrlich).
- [ ] **E5 — Per-Spur-AUv3-Instanzen:** heute EIN Host-Instrument-Slot
      (AUv3Host.instrumentUnit); Ziel: Instanz PRO SPUR (AVAudioUnit je Lane,
      eigener Mixer-Send), inkl. EchoelBioSynth-in-Echoel. Baut auf A4
      (Multi-Roll) auf. DEVICE-GATED (CPU/Latenz mit mehreren Instanzen).

## Interlocks / Ehrlichkeit

- E4/E5 sind die großen Brocken — nichts davon als "shipping" kommunizieren,
  bevor es device-verifiziert ist. Die App bleibt in jeder Zwischenstufe voll
  bedienbar (Chips fallen erst, wenn ihr Ersatz WIRKT).
- Spatial-Expansion (S1–S4) läuft parallel weiter — pure Kerne, kein Konflikt;
  EchoelBioSynth wird später selbst SpatialScene-Quelle (ein Objekt pro Stimme).
- Photos/Mediathek: PHPicker = kein Permission-Prompt, out-of-process —
  privacy-sauber; "voller Zugriff" (PhotoKit-Library-Read) nur falls der
  Founder Browsing IN Echoel will → dann NSPhotoLibraryUsageDescription.
