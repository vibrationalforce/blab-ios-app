# ULTRACHECK — Code · Design · Brand (Founder 2026-07-26: "ultracodecheck ultradesgincheck ultrabrandcheck")

Three sweeps. Findings land here; ONE slice ships per Ralph cycle. Everything below is
verified against the code/site at the cited path — no claim from memory.

---

## BRAND — verified 2026-07-26

### B-1 (SCHWERSTES) Die Website verkauft ein AUv3-Plugin, das seit 2026-07-24 nicht mehr existiert

Slice 1 des Reinen-Instrument-Epics (#122) hat das `EchoelmusicAUv3`-Target gelöscht
(`project.yml:160` trägt den Grabstein, `Sources/` enthält nur noch `Echoelmusic`,
`EchoelmusicWatch`, `EchoelmusicWidgets`). Die Website behauptet es weiter — **8 Dateien,
~25 Stellen**, darunter als **`LIVE`** getaggte Prosa und maschinenlesbares
schema.org-JSON (Google-sichtbar):

| Datei | Stelle | Claim |
|---|---|---|
| `docs/architecture.html` | 256 | `<h2>AUv3 Plugin <span class="tag">LIVE</span>` |
| `docs/architecture.html` | 257 | "ships a working **Audio Unit v3 instrument** (`aumu / echl / Echo`) that runs inside Logic Pro, GarageBand" |
| `docs/architecture.html` | 24, 27, 148, 376 | meta-description, og:description, Nav-Anker, Feature-Liste |
| `docs/index.html` | 102 | schema.org `description`: "Ships today: … AUv3 plugin" |
| `docs/index.html` | 110, 707, 796 | keywords, Capability-Kachel, "or run as an AUv3 plugin inside Logic Pro, GarageBand or AUM" |
| `docs/faq.html` | 44, 98 | FAQPage-JSON + Antwort: "At launch … an AUv3 plugin" |
| `docs/tools.html` | 24, 27, 37, 149, 204, 211 | meta ×3 + "Plugin & host-ready" + "Run Echoel as an AUv3 inside AUM, Cubasis, Drambo…" |
| `docs/overview.html` | 149, 200 | "plus an AUv3 plugin"; "AUv3 plugin **and host**" |
| `docs/press.html` | 102, 128 | Pressetext + Fact-Sheet |
| `docs/brainstorming.html` | 142 | "Pro connectivity: AUv3 plugin" |
| `docs/og-image.html` | 115 | Badge "AUv3" |

`docs/overview.html:200` ist doppelt falsch: AUv3-**Hosting** wurde mit #123 ebenfalls
entfernt. `fastlane/Deliverfile:11` warnt wörtlich vor genau diesem Fehler ("they claimed
an AUv3 plugin for a month") — die Store-Metadaten wurden korrigiert, die Website nicht.

### B-2 "Export to .wav and MIDI" — die MIDI-Hälfte hat keine Tür

`exportMIDI()` (`EchoelStudioView.swift:4235`) hat **keinen Aufrufer** — der einzige lag im
gelöschten Tools-Katalog (`:896` trägt den Grabstein). `MIDIFileExporter` ist intakt und
getestet, aber unerreichbar. Die Website verspricht MIDI-Export u. a. in
`docs/index.html:102` (schema.org), `docs/faq.html:44/98`, `docs/press.html:128`
("stamped MIDI export"), `docs/tools.html:204`.
→ Entweder die Tür zurückholen (ein Fall + ein Switch-Arm im EINEN `craftEditor`-Slot,
Modal-Decke bleibt unberührt) oder den Claim streichen. **Tür zurückholen ist richtig** —
der Exporter ist fertig, und "Body → DAW" ist die Positionierung.

### B-3 "stem export" ist nirgends gebaut

`docs/tools.html:24/27/204` versprechen "stem export"; es existiert keine
`exportStems`-Funktion (#105 ist offen/pending).

### B-4 OFFEN BEIM FOUNDER (gefragt, unbeantwortet): "a **safe** 3 Hz flash rate"

`OnboardingView.swift:128` / `BioSourceView.swift:175`. Der Aurora-Look landet formal auf
**exakt 3.00 Hz** (`FlashGuardTests`), es gibt nirgends einen Photosensitivitäts-Hinweis
und keinen In-App-Schalter, um das Helligkeits-Pulsieren abzuschalten (Reduce Motion wird
geehrt, ist aber eine System-Einstellung). Vorschlag: "safe" streichen, die Tatsache
nennen, eine Vorsichts-Zeile ergänzen, einen App-internen Aus-Schalter bauen.

### Sauber (geprüft, kein Befund)

Kein `BLAB` / `Vibrational Force` / Heilfrequenz / Chakra / Solfeggio / 432/528 Hz in
user-facing Copy. Alle `healing`-Treffer in `Sources/` sind interne Kommentare
(Arbeitspaket-Namen + der Self-Healing-Launch-Guard); alle `wellness`-Treffer sind
Negationen ("NOT wellness"); alle `therapeutic`-Treffer sind die von CLAUDE.md
**verlangten** Sicherheitshinweise. `vibrationalforce` erscheint nur als GitHub-Owner-Slug
in `communityIssueURL(...)` — eine echte Repo-Adresse, keine Marken-Copy.

---

## CODE — 3 Worker laufen (Live-Pfad-Crash/Stille · Audio-Thread+Swift-6 · Persistenz+lügende Controls)

### C-0 GESHIPPT `e1bb7f8` — Xcode-Gate war rot, seit `0f79a9e`

`MetalBioView:1044` las die gehoistete `Double`-Konstante neben `Float`-Uniforms →
`no exact matches in call to global function 'min'`. Fix: Cast an der Aufrufstelle.
(Ein `Float`-Zwilling in `FlashGuard` war mein erster Versuch — Review hat ihn zu Recht
gekillt: totes `.nextDown` bei jeder binärfreundlichen Obergrenze, Gewinn ~1e-7 Hz, und
ein zweites Symbol für eine Zahl baut genau die Drift-Fläche wieder auf, die der Hoist
beseitigen sollte.)

### C-1 GATE-INTEGRITÄT (aus dem Review, wichtiger als der Fix selbst)

Bei einem **Branch-Push** ist `xcode-compile-check.yml` der EINZIGE blockierende Gate,
der diese Datei überhaupt kompiliert:
- SwiftPM (Linux) schließt sie aus — `canImport(MetalKit) && canImport(UIKit) && canImport(SwiftUI)`.
- `ci.yml:147-166` baut/testet zwar für den iOS-Simulator (UIKit vorhanden), pipet aber
  durch `| xcpretty || cat build.log` bzw. `|| cat test.log` und **schluckt den
  Exit-Code** → meldet grün auf einem kaputten Build. Das ist #139, hier sichtbar geworden.
- `pr-check.yml` bricht hart ab (`exit 1`), läuft aber nur `on: pull_request` nach
  main/develop — auf diesem Branch also nie.

Konsequenz für die Ehrlichkeit der Status-Deltas: „CI/CD Pipeline grün" beweist auf einem
Branch-Push **nicht**, dass der iOS-Build kompiliert, und **nie**, dass Tests gelaufen sind.
Nur „Xcode Compile Check grün" ist eine Aussage. #139 hochziehen.

### C-2 CRITICAL Audio-Thread-Malloc bei jedem Drum-Reconfigure — IN ARBEIT

`DrumRenderState.applyPendingRequests` läuft im Render-Block (`DrumSynthVoice.swift:199`) und
setzt `modalBank.material = cfgMaterial`. Dessen `didSet` (`EchoelModalBank.swift:82`) hatte
KEINEN Gleichheits-Guard, und der `.drum`-Zweig baute ein 16-elementiges Array-Literal
(`EchoelModalBank.swift:304`) → **malloc im Render-Block**. `.drum` ist der Default jedes Pads
(`DrumSynthVoice.swift:125`, `DrumNoteMap.swift:64`), und `LaneDrumKitVoice.noteOn:54-55`
erhöht die Config-Version, sobald ein Pitch auf andere Drum-Params abbildet
(`DrumNoteMap.params(forPitch:)` variiert pro Pitch für Perc/Tom) → eine melodische
Tom-/Perc-Linie mallociert **pro Note** im Render-Block. Der Kommentar
„in-place reconfigure (allocation-free)" war falsch.
Fix: Gleichheits-Guard im didSet + Ratio-Tabelle als `static let` (Präzedenz
`EchoelDDSP.formantBands`, #84) + der Kommentar sagt jetzt, was die Allokationsfreiheit
tatsächlich trägt. Neuer Test `ModalMaterialReconfigureTests`.

### C-3 bis C-7 (aus dem Audio-Team, noch nicht gebaut — nach Schwere)

- **HIGH** File-I/O + String + `os_log` **im installTap-Callback**: `RetroCapture.swift:127-128`
  und `MultiTrackRecorder.swift:155-156` schreiben mit `try file.write(from:)` und loggen im
  catch-Arm `error.localizedDescription` (ObjC + String-Alloc) direkt im Echtzeit-Callback.
  Ein Fehler-Sturm (Disk voll, Route-Wechsel) macht aus einem Glitch dauerhafte Dropouts.
  Fix: Fehlerzähler hochzählen, der bestehende UI-Timer loggt.
- **HIGH** `weak`-Load + ARC im Render-Block, und der Render-Block kann `deinit` ausführen:
  `PolySynthVoice.swift:653`, `SubBassVoice.swift:232`, `BioReactiveSynthVoice.swift:381`,
  `MetronomeVoice.swift:137`. `swift_weakLoadStrong` materialisiert eine STARKE Referenz — fällt
  die letzte Control-Plane-Referenz dazwischen weg, gibt der Audio-Thread als Letzter frei, also
  `free()` des ganzen Graphen im Render-Block. Präzedenz für das richtige Muster liegt im Repo:
  `SamplerVoice.swift:338-340`.
- **HIGH (aber toter Code)** `Task { @MainActor }` im `scheduleBuffer`-Completion-Handler:
  `AudioClipPlayer.swift:198-205` + `:243-250`. Kein Instanziierungsort im Repo → heute
  unerreichbar, also kein shippendes Glitch, aber die Falle liegt scharf für den nächsten,
  der die Datei verdrahtet.
- **MEDIUM** `SPSCQueue.enqueue()` schreibt bei Overflow `head` (`SPSCQueue.swift:151-155`) —
  das Feld, das laut eigenem Vertrag (`:29-31`) allein dem Consumer gehört und von ihm
  nicht-atomar publiziert wird (`:226-228`). Realer Pfad: `EngineBus.swift:466`
  (`controllerEvents`, CoreMIDI-Thread) mit 10-Hz-Drain → Overflow bei einem Akkord-Schwall ist
  plausibel, Symptom ist eine doppelte Note-On/hängende Note. Fix: bei Overflow das NEUESTE
  verwerfen (`return false`, wie `tryEnqueue:181-184` es schon tut).
- **MEDIUM** Zwei `@unchecked Sendable` Render-States behaupten einen block-konsistenten
  FX-Parametersatz, den sie nicht halten: `DrumSynthVoice.swift:81` + `SamplerVoice.swift:231`.
  `configureInsertFX` schreibt vier unabhängige Felder, der Audio-Thread liest sie als Gruppe
  → ein Block kann Biquad-Koeffizienten aus neuem Cutoff + alter Resonance rechnen. Die
  Geschwister-Voices haben es korrekt gelöst (Ein-Element-Kommando-Queue,
  `PolySynthVoice.swift:78`, `SubBassVoice.swift:98`).

**Als sauber verifiziert** (nicht nur „sieht ok aus"): alle vier Voice-Render-Blöcke selbst,
`SamplerVoice.RenderState.render` (Slab-Handshake), der Master-Metering/FFT-Tap
(`AudioEngine.swift:392-454`), `EchoelDDSP.render`/`applyBioReactive`, `ResolvedPatch.apply`,
`EchoelFXChain.processBuffer`, `EchoelSVFilter`, `EchoelDelayLine`, `EchoelModalBank.render`
— alloc-, lock-, ObjC- und log-frei; jeder `nonisolated(unsafe)`-Spiegel wird in einem
MainActor-`didSet` geschrieben.

### C-10 LIVE-PFAD — 4 Befunde (Start → Klang → Stop)

1. **Der erste „Create from Within"-Tap ist stumm, bis der Kamera-Dialog beantwortet ist.**
   `EchoelStudioView.swift:3357`: `startBiofeedback()` setzt `running = true` synchron (`:3336`),
   dann wartet der Task `await startBioSource()` **vor** `generate(reason: "start")` (`:3369`) →
   `CameraRPPGBioPublisher.swift:496` → `CameraCapture.swift:79`
   `await AVCaptureDevice.requestAccess(for: .video)`, das bei `.notDetermined`
   **unbegrenzt** suspendiert. Frische Installation, Start drücken: Label springt auf „Stop",
   null Audio, kein Transport, keine visuelle Reaktion — bis Erlauben/Ablehnen getippt ist
   (unbegrenzt, wenn der Dialog ignoriert oder die App in den Hintergrund geschickt wird).
   Derselbe Pfad über die Transport-▶ (`WorkspaceView.swift:459`). Der Kommentar bei `:3369`
   („immediate first sound — no lock-wait stall") ist beim ersten Start falsch.
   **Erster Eindruck der App. Höchste Priorität der Live-Pfad-Liste.**
   Fix-Richtung: `generate()` VOR dem Permission-await, oder den await nicht auf dem
   Start-Pfad blockieren lassen.
2. **Das Stop im Notes-Editor beendet die ganze Bio-Session** — bestätigt per Code-Read, was in
   CLAUDE.md als NEEDS-FOUNDER-VERIFY steht. `PianoRollView.swift:1229` → `pattern.stop()` →
   `PatternEngine.swift:409 transport?.stop()` → `EchoelStudioView.swift:697`
   `.onChange(of: transport.isPlaying)` → `stopEverything(:3399)`: Kamera + Taschenlampe aus,
   `evolveTask`/`lockSnapTask` abgebrochen, `bioModulationEnabled` gelöscht, `running = false`.
   Das ▶ der Rolle startet danach nur `PatternEngine`, nie die Bio-Session → der Körper steuert
   nichts mehr, bis das Sheet zu ist und „Create from Within" neu gedrückt wird.
   **Ship-Gate-Punkt 2 „Kontrolle" ist als Transport damit unbenutzbar.**
3. **Eine persistierte MIDI-Spur mit Gain 0/Mute macht jede Rollen-Note stumm — und kein
   erreichbares Control kann das rückgängig machen.** `PianoRollView.swift:955`
   `let laneAudible = laneGain > 0.001` gated ALLE Note-Ons (`:957`, `:967`). Einziger Schreiber
   von `mixGain` ist `EchoelmusicApp.swift:665-668` aus `TimelineDocument.rollSlotGain`
   (`Timeline.swift:450`); die einzige Heilung `healRollSlotAudibility()` hängt an genau einer
   Stelle (`EchoelStudioView.swift:3334`, explizites Start), und
   `TimelineStore.unsilenceRollSlot()` (`:674`) hat **null** weitere Aufrufer — das „#22 Ton
   an"-Banner und der Timeline-Mixer sind mit #121 Slice 4 gelöscht. Ein Upgrader mit stummer
   Spur drückt ▶: Playhead läuft, `TimelineRegionPlayer.swift:642-648` verwirft die Note-Ons,
   totale Stille, kein Mute/Level-UI mehr da. Frische Installationen sind sicher
   (`Timeline.swift:451` gibt Unity zurück, wenn keine MIDI-Spur existiert).
4. **NaN-durchlassender Clamp an der Bio→Synth-Grenze, gegen die eigene Hausregel.**
   `PolySynthVoice.swift:646` `clampUnit` = `min(max(x,0),1)` lässt NaN durch, angewandt auf
   `frame.breathPhase` (`:605`) und `neutralCoherence` (`:629`); gleiches Muster
   `SubBassVoice.swift:67,72`, während das Geschwister-`subGain` bewusst das NaN-sichere
   `clamped(to:)` nutzt (`:48`). **Heute stromabwärts neutralisiert** (`EchoelDDSP.swift:1368-1373`
   re-sanitisiert alles, `AudioOutputGuard.silencingNonFinite` im Sub-Render), also latent, nicht
   live — aber genau die Klasse, die schon dauerhafte Stille geshippt hat.

**Als sauber verifiziert:** NULL Force-Unwraps/`try!`/`as!` auf dem ganzen Live-Pfad · jede
Division geguarded (Liste im Bericht) · keine ungeguardeten Subscripts · **kein 10-Hz-Read in
`WorkspaceView.body`** (liest nur `isRunning` + AppStorage; alle Live-Readouts sind echte Leaves)
· die neue Dauer-Frontplatte ist observationssicher, weil `EchoelPanel.swift:35` seinen Inhalt
als escaping `@ViewBuilder` hält und ihn im EIGENEN Body aufruft · kein `Task { @MainActor }`
pro Item mehr · drei Taps auf drei verschiedenen Nodes (keine Kollision) · Shader-Fehlschlag
gibt einen Clear-Colour-Puls, keinen Schwarzbild.

**WIDERSPRUCH zwischen zwei Workern, ungelöst — nicht als Fakt behandeln:** zum
`SPSCQueue`-Overflow-Pfad (`SPSCQueue.swift:144-155`) sagt das Audio-Team, der Producer bricht
den Single-Writer-Vertrag für `head` und kann Elemente doppeln/überschreiben; der Live-Pfad-Worker
sagt, `head` landet in jedem Fall auf `currentHead+1`, eine volle Queue kann also nicht als leer
gelesen werden. Beide zitieren dieselben Zeilen. Das braucht einen eigenen, gezielten Slice mit
einem Nebenläufigkeits-Reviewer, keinen Schnellschuss (#155).

### C-8 PERSISTENZ — vier echte Total-Verlust-Pfade (Reihenfolge = Schwere)

Das Muster ist überall dasselbe und deshalb gefährlich: `load` gibt bei JEDEM Throw `nil`
zurück (`AppGroupStore.swift:66-76`), der Store fällt auf Factory/leer, und der **nächste
Speichervorgang schreibt den leeren Stand zurück** — der Verlust wird permanent, ohne Fehler.

1. **`PatchStore` — die ganze Sound-Bibliothek an einem Element.** `PatchStore.swift:29` lädt
   `[SynthPatch]` als Alles-oder-nichts-Array; `persist()` (`:110-113`) überschreibt beim
   nächsten `save`/`saveAs`/`toggleFavorite`. Auslöser existiert HEUTE:
   `SynthPatch.swift:131` nutzt `decodeIfPresent(UUID.self, forKey: .id)` — das liefert nur bei
   **fehlendem** Key nil; eine vorhandene, kaputte `id`-String wirft `dataCorrupted`, und ein
   Throw nimmt das ganze Array. Community-/handgeschriebenes Patch-JSON ist ein realer
   Eingangspfad (`CommunityLibrary.swift:79`). Fix: das Muster liegt im Repo —
   `TimelineDocument.Lossy`/`lossyArray` (`Timeline.swift:392-405`).
2. **`ProjectStore` — dieselbe Zerbrechlichkeit plus Kaskade, bei jedem gespeicherten Take.**
   `ProjectStore.swift:19`/`:74-76`. `Project.init(from:)` ist pro FELD defensiv, aber
   `Project.swift:76` `decodeIfPresent([Note].self…)` wirft, wenn EIN Note-Element wirft
   (`Note.swift:209`, gleicher Malformed-UUID-Pfad) → Projekt wirft → `[Project]` wirft → die
   gesamte Take-Bibliothek ist weg.
3. **Die drei `Meta`-Beiwagen (Favoriten/Recents) sind die letzten synthetisierten Decoder.**
   `PatchStore.swift:26`, `FXPresetStore.swift:27`, `MoodPresetStore.swift:28` — identisch,
   beide Keys **required**. Die Nutzlast-Typen bekamen alle handgeschriebene defensive Decoder,
   der Beiwagen wurde übersehen. Ein Feld umbenennen → alle Sterne + die Recents-Reihenfolge
   verschwinden gemeinsam und werden leer zurückgeschrieben. Fix: 3× ein ~4-zeiliger Init.
4. **`TimelineLane`s Enum-Felder unterlaufen das defensive Gesetz der eigenen Datei — ein
   Case-Rename LÖSCHT ganze Spuren.** `Timeline.swift:145` `kind`, `:154` `builtinInstrument`,
   `:160` `genreOverride`, `:161` `mood`: `decodeIfPresent` auf `RawRepresentable` **wirft** bei
   unbekanntem rawValue, und `Lossy` verwirft dann die GANZE Lane (Name, Level, Pan, Patch,
   Transpose, Detune, samplePath) und lässt ihre Regionen als Waisen zurück. Case-Renames sind
   hier gelebte Praxis (`TrackInstrument.swift:34-37` dokumentiert einen). Hausregel steht
   schon geschrieben — `Project.swift:16-23`: „Enums are stored as raw strings".
5. **`ProjectStore`s Dateiname hat eine doppelte Endung** (`projects.json` + `.json` in
   `AppGroupStore.swift:53` → `projects.json.json`). Alle Geschwister übergeben endungslos, das
   ist also ein Versehen — und ein „Aufräumen" auf `"projects"` zeigt auf einen neuen leeren
   Pfad: alle Takes weg, ohne Fehler. Nicht umbenennen, nur kommentieren oder migrieren.

### C-9 LÜGENDE CONTROLS — 5 weitere (die 3 bekannten ausgenommen)

1. **„Silence — all notes off" bringt vier klingende Voices NICHT zum Schweigen.**
   `EchoelStudioView.swift:2119` → `panicAllNotesOff():2166-2170` ruft nur `synth`, `subBass`,
   `midiOut`. Dieselbe View hält `leadSynth:65`, `touchSynth:64`, `bioVoice:61`,
   `laneVoiceRack:80` — alle notenproduzierend. Eine hängende Lead-/Bio-/Spielfläche-Note, also
   genau der Grund, den Knopf zu drücken, überlebt ihn, während der Hinweistext „every
   sounding note on every voice" behauptet. `PolySynthVoice.allNotesOff()` existiert
   (`:370`), `LaneVoiceRack.allNotesOff(on:)` ist `private` (`:245`).
   **Höchste Priorität der ganzen Q2-Liste** — ein Notfall-Control, das lügt.
2. **„No target" im Master-Loudness-Picker ist byte-identisch mit „Streaming (−14)".**
   `:2098-2103` → Export liest `:4185-4187` mit `?? -14`, und `.off.integratedLUFS` ist nil
   (`LoudnessTarget.swift:34`). Fix: Normalisierung bei `.off` überspringen oder den Case löschen.
3. **Die Pro-Kanal-Drum-Filter/Cutoff/Drive-Zeilen werden von den Bus-Knöpfen direkt darüber
   gelöscht — im selben Panel.** `ChannelRackView.swift:150/159/163` schreibt pro Kanal;
   `setDrumsFX` (`EchoelStudioView.swift:1583-1594`) stempelt alle 8 Kanäle. `mixerPanel`
   zeigt Bus (`:1445-1448`) und wenige Zeilen darunter den Channel Rack (`:1477`).
4. **Pro-Kanal-„Level" erreicht nur die Sampler-Hälfte jedes Pads.**
   `ChannelRackView.swift:141` → `BeatPlayer.applyShape:144-148` → `configureShape`, das nur
   `SamplerVoice` hat (`:163`); `DrumSynthVoice` hat keins, und `trigger` feuert
   `synthVoices[track]` für `.synth`/`.blend` (`BeatPlayer.swift:256-265`). Fällt heute nicht
   auf, weil `setMode(track:)` keine Aufrufer hat — aber `restoreModesAndSynth():222-234` lädt
   einen von einem älteren Build persistierten Mode, und dann ist das Feld wirkungslos.
   (Derselbe Trace zeigt: die „hybrid sample/synth drums", die CLAUDE.md als geshippt führt,
   haben überhaupt keine Tür.)
5. **Die „Clip grid full"-Warnung verlangt eine Handlung, für die es kein Control gibt.**
   `:3087-3095` (gesetzt `:4086`) nennt das Freiräumen eines Slots; `ClipStore.clear(at:)`
   (`:119`) hat null Aufrufer, `ClipView` ist gelöscht, die genannte Timeline-Fläche ist mit
   #130 weg. Fix: die Meldung löschen.

**Als echt verdrahtet verifiziert** (Kette bis zum rendernden Elternteil verfolgt): alle 8
Chrome-Türen · die sechs Posts des `CompositionHeaderStrip` · Notes-Chip → der EINE
`craftEditor`-Slot (und `CraftEditor` hat keinen türlosen Case) · Master-Audio-Input +
Routing-Slot-Reuse · Mood-Knöpfe → `BioComposer.Input.mood` · Mixer-Level → `MixerStore.combined`
· Wetter-Toggle + alle Mix-Intensitäten · Loudness-Ziel → Export · alle Visual/Touch-AppStorage-Keys
werden von `FloatingVisualWindow` gelesen · `BioStripView`s fünf Knöpfe · `VisualRecorder` ist
über den Record-Knopf des schwebenden Fensters erreichbar (die Video-Bibliothek ist also nicht
dauerhaft leer). **Zusätzlich türlos** (nicht lügend, nur unerreichbar): der
Brainwave-Entrainment-Schalter — einziger Ort `BioSourceView.swift:151`, und `BioSourceView` hat
null Mounts, während `EchoelStudioView:2281` und `FloatingVisualWindow:273`
`entrainmentEnabled` lesen.

---

## DESIGN — 8 Befunde, verifiziert am Code (nicht neu hergeleitet, wo die Audits von heute schon lagen)

**Kernurteil: die Frontplatte ist gebaut, aber das Auge liest sie nicht als EIN Objekt.**

1. **Die Reiterleiste klebt am falschen Ding.** Root-VStack-Reihenfolge ist
   Chips → 1px-Vollbreiten-Linie (`EchoelStudioView.swift:1109-1111`) → 56 pt Hero-Button
   (`:587`) → Platte (`:607`). Eine Reiterleiste, die durch eine Haarlinie UND einen
   Hero-Button von ihrem Panel getrennt ist, liest als zweite Chrome-Menüleiste — genau der
   Eindruck, den Slice 1 beseitigen sollte. Fix: `startButton` als LETZTES Kind unter die
   Platte, die `.overlay(alignment: .bottom)`-Linie löschen.
2. **Die Standard-Platte ist ein 22-zeiliges Einstellungs-Formular, keine Frontplatte.**
   `soundPanel:2718-2783` + `EchoelValueField.swift:69-76`: jede Zeile
   `label · Spacer(minLength:8) · 150 pt Box` auf `maxWidth: .infinity` → ~140 pt toter
   Spacer pro Zeile, ~8 von 22 Zeilen sichtbar. Das ist das iOS-Settings-Idiom; eine
   Frontplatte ist ein 2-D-Feld. Fix: Panel-Inhalt in
   `LazyVGrid(columns: [GridItem(.adaptive(minimum: 260))])` — halbiert die Tiefe, füllt die
   Breite, kein neuer Modifier.
3. **UNCODIXFY-Verstoß: der letzte rohe `Slider` der App sitzt auf der Dauer-Platte.**
   `EchoelStudioView.swift:2353` (`visualLookStrip` im Synth-Reiter), Zwilling
   `FloatingVisualWindow.swift:522`. `lookScrub` ist ein kontinuierlicher `Double` — CLAUDE.md
   verbietet rohe `Slider` für Parameter, und es wird keine Zahl angezeigt (Verstoß gegen
   science-first). Fix: `EchoelValueField`.
4. **Der gewählte Reiter kann unsichtbar sein — die Leiste lügt.** `menuBar:1081` ist eine
   horizontale `ScrollView` ohne `ScrollViewReader`; 7 Chips × ≥44 pt ≈ 370 pt, auf 320 pt
   also abgeschnitten ohne Indikator. Schlimmer: eine Chrome-Tür (`:547-566`) hängt den
   gewählten Chip rechts an (`visibleChips:1074-1078`) und scrollt nie dorthin → Platte zeigt
   Bio, Leiste zeigt gar keine Auswahl. Fix: `ScrollViewReader` +
   `.onChange(of: displayedMenu) { proxy.scrollTo($1, anchor: .center) }`.
5. **Die Platte füllt die Platte nicht, und ein Reiter hat gar keine Platte.**
   `menuPanelHost:1238` ist `maxHeight: .infinity`, aber `EchoelPanel.swift:50-73` schmiegt
   sich an seinen Inhalt → kurze Reiter (Export, Effects, Mood, Bio) = kleine Karte auf
   großer schwarzer Leere, also wieder die Leere, über die der Founder sich beschwert hat,
   nur mit Karte drauf. Und `bioPanel:1285` ist der EINE Reiter, der nicht durch `panel(...)`
   läuft → beim Wechsel auf Bio verschwindet der Karten-Rahmen komplett.
   (Positiv verifiziert: die Plattenhöhe ist stabil, kein Seiten-Sprung beim Reiterwechsel.)
6. **Feste Chrome-Höhen brechen bei großer Dynamic Type.** `menuChip:1149` und
   `directChip:1175` haben `.frame(height: 26)`; `WorkspaceView.swift:147` klemmt die
   Chrome auf `xxLarge`, `EchoelStudioView` ist absichtlich NICHT geklemmt, und
   `EchoelTheme.font` ist `relativeTo: .body` → bei Accessibility-Größen laufen die Labels aus
   ihren 26-pt-Pillen. Dazu skaliert `EchoelValueField.swift:37` (`@ScaledMetric 150`) auf
   ~240–375 pt gegen ~272 pt Inhaltsbreite auf einem 320-pt-Gerät. Fix: `minHeight`, und die
   Wertbox deckeln oder Label-über-Box ab `xxLarge`.
7. **Am Regler drehen kann die Platte scrollen** (Geräte-Verify nötig).
   `EchoelValueField.swift:183` ist ein `DragGesture(minimumDistance: 8)` INNERHALB der
   jetzt dauerhaften vertikalen `ScrollView` (`menuPanelHost:1233`) — „einen Regler bedienen
   verschiebt die Seite" ist das Un-Instrumentalste, was es gibt. Kein Slice-1-Regress (das
   alte Dropdown scrollte auch), aber Slice 1 macht es zum Normalzustand.
   Fix: `.highPriorityGesture` auf `valueBox` oder `.scrollDisabled(scrubbing)`.
8. **A11y-Neues** (die bekannten Barrieren B1/B3/B4/D1 bleiben wie protokolliert):
   die Reiterleiste hat keine Container-Semantik (`menuBar:1080-1112`, kein
   `.accessibilityElement(children: .contain)`), der Panel-Wechsel wird nicht angesagt, und
   der angehängte Chrome-Tür-Chip erscheint für VoiceOver lautlos · neue Sub-44-pt-Ziele
   dauerhaft auf der Platte: `ellipsis.circle` 34×34 bei `:2687` und `:2878`, „Open Routing"
   34 pt bei `:1296` · `HeaderMonitors.swift:267` nutzt einen `RadialGradient` als ganze
   Kachelfläche — datengetrieben, aber der letzte dekorative Gradient in der Chrome.

**Höchster Hebel als nächster Design-Slice: 1 + 2 zusammen** — Chip-Leiste direkt auf die
Karte setzen (Hero-Button unter die Platte, Trennlinie weg) und die Panel-Zeilen in ein
2-spaltiges adaptives Grid. Das ist der ganze Unterschied zwischen „Menüleiste über einem
Formular" und „Reiterleiste auf einer Frontplatte", kostet keinen Präsentations-Modifier und
keinen 10-Hz-Read. Alles andere ist kosmetisch, bis das Auge die Platte als ein Objekt liest.
