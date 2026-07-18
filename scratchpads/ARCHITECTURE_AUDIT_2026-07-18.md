# ARCHITEKTUR- + ADAPTIVE-DESIGN-AUDIT — 2026-07-18 (ultracode, 54 Agenten)

> Multi-Agent-Workflow (7 Subsysteme × Map→Audit→Verify→Synthese). Befunde: 39 total, 32 CONFIRMED, 4 PLAUSIBLE, 0 Agenten-Fehler.
> Jeder Befund adversarial mit Datei:Zeile verifiziert. Quelle: w9yizrz7y.

## 1. Architektur-Gesamtbild

Die tragende Struktur ist gesund und ehrlich einfach: **EngineBus ist die eine Kopplungs-Spine** — jedes Modul spricht nur über ihn (Snapshot-Kontrollebene `latestBio`/`latestMusical` bei 10 Hz + lock-free SPSCQueue für `controllerEvents`), und das trägt. Darunter ein sauberer, tracks-zentrischer DAW-Kern (`PatternEngine` = die eine Uhr → `TimelineRegionPlayer` → Voices über `attachSourceNode`), reine testbare Theorie-/DSP-Cores, und eine funktionierende Bio-Pipeline aus vier echten Quellen. **Wo es ächzt: die Spine ist konzeptionell doppelt** — der dokumentierte `bioFrames`-Datenplane ist tot (nie dequeued), und die Routing-Logik existiert zweimal parallel (`ModulationMatrix` in `modulationMatrix.v1` vs. `SignalGraph` in `signalGraph.routes.v1`) ohne Abgleich. Dazu ein **Ehrlichkeitsproblem**: viele Flächen sind „gebaut-aber-abgeschaltet" (Pro-Flow, Broadcast, FaceExpression/BodyVibe, halbe Rausch-Triade), und die Adaptive-Quality-Politik ist zu 4/7 tot verdrahtet. Der Kern hält; die Ränder erzählen mehr, als der Code tut.

## 2. Adaptive-Design-Gesundheit

**UI-Adaptivität — halb verdrahtet (bestätigt HIGH).** `AdaptiveQuality`/`ResourceGovernor` berechnen 7 Regler, aber nur `visualDetailScale` und `reduceMotion` werden je gelesen (`MetalBioView.swift:727-728`). `bioHz`, `oscHz`, `allowSpectralDonuts` haben **null Konsumenten** (grep-bestätigt), `targetFPS` wird von einem hart gepinnten `preferredFramesPerSecond=60` (`MetalBioView.swift:373`) überschrieben. Der Governor-Doc-Kommentar (`ResourceGovernor.swift:8-9`) behauptet fälschlich, Spectral-Donuts/Bio/OSC läsen `.settings`. Folge: unter Thermal-/Akku-Druck degradiert **nur das Visual-Detail**; die 10-Hz-Bio-Poll, die OSC-Emit-Rate, die Synth-Stimmkosten (`PolySynthVoice` fix 8×32 Harmonische, `EchoelDDSP.swift:1571`) und der teure Spectral-Donut (nur an `@AppStorage` gegated, `EchoelStudioView.swift:717`) laufen ungebremst weiter — genau der Lastpfad, den der Code selbst für „Knistern"/Aussetzer verantwortlich macht. Der Founder-Wunsch „adaptive Formate für Akku/CPU/GPU" ist real nur zur Hälfte gebaut.

**Uncodixfy-Konformität — überwiegend sauber, eine echte Abweichung.** `EchoelValueField` ist konsequent die eine Parameter-Steuerung. Ausnahme: der Visual-Look-Scrub nutzt rohe `Slider` (`EchoelStudioView.swift:2362`, `FloatingVisualWindow.swift:478`) — der Slider-Teil ist als VJ-Kontrolle founder-gesegnet, aber die `.accent`-Tönung (`:2363`) widerspricht dem eigenen Kommentar 13 Zeilen darüber, der Bio-Grün exklusiv fürs Live-Bio-Signal reserviert. Kleiner, echter, unsanktionierter Bruch. Radien/Glass/Neon: keine Befunde — sauber.

**Layout-Adaptivität — die tote-Flächen-Schuld ist real und groß.** SurfaceHost/Identitäts-Invariante (H7) hält korrekt. Aber der **doorless-Reservoir** ist erheblich: `toolsSection`/`openTool` ist komplett unreferenziert (`EchoelStudioView.swift:912`), und ist der **einzige** Setter für drei Root-Chain-Modifier — der Vollbild-VJ-Visual (`showVisual`, `:711`), Meditation (`:793`) und **MIDI-Import** (`:703`) haben heute keine lebende Tür. Pro-Flow (`ProUnlockView` nirgends präsentiert, `WorkspaceView.swift:102`), Broadcast, FeedbackGuard/AudioInputPicker, SpectralDonut — alle gebaut, unerreichbar. Das ist Task #66 im Kern.

**Bio-Adaptivität — funktioniert für Puls, ist aber blind für Mimik (bestätigt MEDIUM).** Der Live-Pfad Bio→Sound/Visual ist echt und reagiert. **Aber**: `BioReactiveSynthVoice.applyLatestIfFresh` (`:323`) liest nur coherence/hrv/heartRate/breathPhase — die `faceSmile/faceBrow/faceJaw`-Kanäle werden nie gelesen. Ein `.faceCam`-Frame trägt HR=0/coh=0, also kollabiert die eine Bio-Audio-Stimme bei aktiver Gesichtsquelle zu **flachem Neutralton**. Zweitens: `ModulationEngine.tick` (`:144`) liest `latestBio` **ohne Freshness-Gate** — fällt der Gurt/Finger weg, friert der letzte Tempo-/OSC-Mod-Wert unbegrenzt ein statt neutral zu lösen (jeder andere Renderer nutzt `freshBio`/`freshMusical`).

## 3. Top-Befunde (ranked)

**HIGH**
- **AUv3 Cross-Thread-Race** · `EchoelmusicAudioUnit.swift:226` — Parameter-Observer ruft `synth.applyBioReactive()` vom KVO/Host-Thread, während `internalRenderBlock` (`:396`) dieselben Harmonik-Arrays auf dem Audio-Thread liest, **ohne SPSC-Serialisierung**. Echte Data-Race in der ausgelieferten Extension. Gesetz 3/11. Blockiert saubere AUv3-Arbeit.
- **AUv3 malloc im Render-Block** · `EchoelmusicAudioUnit.swift:391` — `var pad = padRef` bleibt via `self.padScratch` mehrfach referenziert → COW alloziert bei **jedem** Render-Callback frischen 4096-Float-Puffer. Kommentar „COW safe" ist invertiert. Gesetz 3.
- **EchoelDDSP-Invariante ist falsch** · `EchoelDDSP.swift:48` — `@unchecked Sendable`-Begründung behauptet „exclusively from MainActor", aber alle echten Aufrufer laufen off-main (Audio-Thread + AUv3-KVO). Der Doc maskiert die zwei Races oben und irreführt jede künftige Edit dieser 2057-Zeilen-Datei. Gesetz 3/5/11. Blockiert #59/#61.
- **Toter bioFrames-Datenplane** · `EngineBus.swift:353` — jedes `publish(bio:)` enqueued in `bioFrames`, **niemand dequeued** (nur `controllerEvents`/`bioEvents`). Perpetuelles drop-oldest-Churn, Falle für den nächsten Dev, der einen Konkurrenz-Consumer verdrahtet. Gesetz 6. Blockiert #60/#61.
- **AdaptiveQuality 4/7 tot** · `AdaptiveQuality.swift:96` — siehe §2. Gesetz/Adaptive-Lens (a). Blockiert #60/#61 (Bio/OSC-Throttle).
- **FaceExpression: Permission würde lügen** · `FaceExpressionBioPublisher.swift:90` — ARKit nutzt Front-Kamera, aber `NSCameraUsageDescription` (`Info.plist:72`) beschreibt nur Rück-Linsen-Puls → App Store 5.1.1/GDPR-Bruch beim Aktivieren. Publisher nirgends instanziiert, Flag gated nichts. **Info.plist-Edit braucht Founder-OK.** Blockiert #67/#68/#66.
- **Colab umgeht Egress-Gate** · `LiveColaboView.swift:78` — sendet bpm/coh/hrv/breath an Peers **ohne** `BioEgressPolicy.allowsEgress(source)`. Bei HealthKit/Watch/Oura verlässt Store-Daten das Gerät, die OSC/ADM blockieren würden. App Store 5.1.3.
- **Synthesized Codable = stiller Song-Verlust** · `Arrangement.swift:13` — kein `decodeIfPresent` (anders als `Clip.swift:167`). Neues Pflichtfeld → jeder alte Song scheitert am Decode → `ArrangementStore` schluckt Fehler → `?? Arrangement()` verwirft die ganze Anordnung lautlos. Gesetz 9. Blockiert #39/#40/#11.
- **AudioEngine 60-Hz-Observable ohne Schild** · `AudioEngine.swift:59` — neun Meter-Props (60×/s neu geschrieben) + `currentLevel`/`currentPitch` (Buffer-Rate) ohne `@ObservationIgnored`; ein Ancestor/HUD, der einen liest, reißt offene Menüs (Freeze-Law bei 60 Hz statt 10). Latent, aber schärfer als der dokumentierte Fall. Gesetz 1. Blockiert #11.
- **MicrophoneManager: kein Re-Entry-Guard + globaler Session-Teardown** · `MicrophoneManager.swift:194` — `startRecording()` ohne `guard !isRecording` überschreibt `audioEngine` ohne Teardown; `stopRecording()` deaktiviert prozessweite `AVAudioSession` (`:269`) vor `masterEngine.pause()`. „Alles ist still"-Klasse (#22). Gesetz 11. Blockiert #13/#39.

**MEDIUM**
- **ModulationEngine ohne Freshness** · `ModulationEngine.swift:144` — siehe §2 Bio. Blockiert #60/#61.
- **Zwei Route-Stores ohne Abgleich** · `ModulationEngine.swift:66` vs. `SignalRouter.swift:28` — Mod-Matrix und Patchbay divergieren still. Gesetz 6. Blockiert #53/#37.
- **BioReactiveSynthVoice ignoriert Face** · `BioReactiveSynthVoice.swift:323` — inert bei Gesichtsquelle. Blockiert #67/#68.
- **Rausch-Triade dormant** · `BioEventPublisher.swift:85` — HeartbeatDetector mit `cleanedHeart:0` gefüttert (feuert nie), `BioSignalDeconvolver` ohne Live-Producer, `HilbertSensorMapper` null Konsumenten. Als aktive Cleaning-Pipeline präsentiert, ist Fundament. Blockiert #61/#60.
- **Region-Gain-Drag = Relocate-Storm** · `Timeline.swift:557` — `structurallyEqual` klassiert Region-Instanz-Gain/warp als strukturell → `refreshStructure` flusht Pumps + re-attackt Segment (hörbarer Glitch), während Lane-Gain glatt durchläuft. Blockiert #39/#40.
- **Roll- vs. Sekundär-Launch desynct um ganze Bar** · `TimelineRegionPlayer.swift:811` — Roll startet auf Nicht-Top-Content-Bar, Sekundär auf 0; dokumentierter „sub-bar"-Caveat unterschätzt einen Ganz-Bar-Versatz. Blockiert #66/#67.
- **Zwei divergente Launch-Cores** · `LaneLaunchLatch.swift:114` — toter Latch nutzt STRICTLY-AFTER-Mathe, lebender `ClipLaunchEngine` AT-OR-AFTER; künftiger Audio/Video-Launch auf `LaunchTiming` desynct von MIDI. Blockiert #66/#11.
- **persist() flutet Main-Thread** · `ArrangementStore.swift:84` — synchroner atomarer, verschlüsselter JSON-Write pro Gesten-Tick beim Drag (nur Composer-Pfad hat No-op-Guard). Blockiert #39/#56/#40.
- **ArtNet/sACN: nur Dimmer slew-limitiert** · `ArtNetSender.swift:187` — RGB roh bei ~30 Hz, Hue kann >3 Hz schwingen. „Epilepsie-safe by construction" gilt nur fürs Dimmer. Gesetz 8. (sACN dupliziert bei `:179`.)
- **AppGroupStore verschluckt Fehler** · `AppGroupStore.swift:30` — stiller Fallback auf app-private Location bei Entitlement-Drift; AUv3/Widget sehen Daten nicht mehr, nichts geloggt. Blockiert #50/#39.
- **DDSP formant malloc** · `EchoelDDSP.swift:664` — `.formant` baut Array-Literal auf Audio-Thread; still, weil Default `.dark`. Gesetz 3.

**LOW** (kurz): `EchoelStore`/`ProUnlockView`-Triangle app-unwired (`WorkspaceView.swift:102`, #66) · `currentTick` ungeschütztes 8-Hz-Observable (`TimelineRegionPlayer.swift:59`, Gesetz 1) · News-Toggle hinter `cloudKitConfigured=false` + load-bearing Crash-Guard (`LearnView.swift:61`, #66) · `PolySynthVoice.setPan/Gain` ohne attach-Guard (`:492`) · HRV-Trust-Gate von Synth umgangen (`BioReactiveSynthVoice.swift:334`) · `BioDataQueue`/`VideoFrameQueue` legacy-tot (`SPSCQueue.swift:378`).

**PLAUSIBLE — Gerät-Verify nötig:** SPSCQueue head torn/racing bei Overflow+Dequeue auf deprecated `OSAtomic*` (`SPSCQueue.swift:153`) — die ganze lock-free Spine ruht auf dieser unverifizierbaren Datei; **höchstes latentes Risiko, aber nur unter echtem Concurrency-Stress beweisbar**. FeatureFlags-Default-Lüge (`register(defaults:true)` in App-Root statt Enum, `:82`). EchoelStudioView-Chain bei 16 Modifiern am Metadata-Ceiling (`:690`) — jede neue `.sheet` erst konsolidieren.

## 4. Offene Tasks × Architektur-Bereitschaft

Die „Open tasks"-Liste im Input ist leer, aber die Subsystem-Maps + Befunde referenzieren durchgängig #-Tasks. Bewertung je Task:

| Task | Status | Konkreter Blocker (Datei) |
|---|---|---|
| **#66** Modus-Wechsel: „gebaut-aber-abgeschaltet" beenden | 🟡 gelb | Kein harter Blocker, aber viel Fläche: `toolsSection` tot (`EchoelStudioView.swift:912`), Pro-Triangle (`WorkspaceView.swift:102`), News-Crash-Guard (`LearnView.swift:61`), FeatureFlags-Default-Lüge (`FeatureFlags.swift:82`). Reine Aufräum-/Ehrlichkeitsarbeit — Architektur bereit. |
| **#60** Bio-Session → Modulations-Brain | 🔴 rot | `ModulationEngine.tick` ohne Freshness (`:144`) + toter `bioFrames` (`EngineBus.swift:353`). Das Mod-Brain würde auf eingefrorenem Bio laufen. Erst Freshness-Gate. |
| **#61** EEG/Gehirnwellen als Modulationsquelle | 🔴 rot | Braucht neuen `ModSource`-Case + `BioSampleFrame`-Kanal + Bus-Plumbing, UND die Rausch-Triade (`HilbertSensorMapper`/coherenceShift-Detektoren) ist dormant (`BioEventPublisher.swift:85`). Plus DDSP-Invariante falsch (`:48`). |
| **#68/#67** EchoelBodyVibe Kamera-Modulator | 🔴 rot | `FaceExpressionBioPublisher.swift:90` — Permission-String lügt (Info.plist-Edit braucht Founder-OK, App Store 5.1.1), Publisher nie instanziiert, Synth ignoriert Face-Kanäle (`BioReactiveSynthVoice.swift:323`). |
| **#39/#40** DAW Audio/MIDI + Automation | 🟡 gelb | Kern wired, aber: Codable-Song-Verlust bei neuem Feld (`Arrangement.swift:13`), Region-Gain-Relocate-Storm (`Timeline.swift:557`), persist()-Main-Flut (`ArrangementStore.swift:84`), zwei Route-Stores (`ModulationEngine.swift:66`). |
| **#11** Adaptive/Video-Modal + Home | 🟡 gelb | 60-Hz-Observable in AudioEngine (`:59`), Sheet-Chain am Ceiling (`EchoelStudioView.swift:690`), `currentTick`-Freeze-Risiko (`TimelineRegionPlayer.swift:59`). Freeze-Law-Disziplin vor jeder neuen HUD/Modal. |
| **#13** Device-Audio-Loop-Import | 🔴 rot | `MicrophoneManager.swift:194` Re-Entry/Session-Teardown-Race („alles still"-Klasse). Erst Mic-Lifecycle härten. |
| **#53** DMMW-Ultrascan / Routing-Backbone | 🟡 gelb | Zwei divergente Route-Stores (`ModulationEngine.swift:66` vs. `SignalRouter.swift:28`) + AdaptiveQuality tot (`:96`). SignalGraph selbst tragfähig. |
| **#50** Third-party AUv3 end-to-end | 🟡 gelb | AppGroupStore verschluckt Entitlement-Drift still (`:30`) — AUv3 sieht Daten evtl. nicht; plus AUv3-Race/malloc (`EchoelmusicAudioUnit.swift:226/391`) falls eigenes Plugin. |
| **#55/#58/#56** Video-Page / Clip-Launch-Polish | 🟡 gelb | Video-Tür tot (`showVisual`/MIDI-Import unerreichbar, `EchoelStudioView.swift:703/711`), Launch-Bar-Desync (`TimelineRegionPlayer.swift:811`), toter zweiter Launch-Core (`LaneLaunchLatch.swift:114`). |
| **#59** EchoelWeather-Synth (neue DDSP-Stimme) | 🔴 rot | DDSP-`@unchecked Sendable`-Invariante falsch (`EchoelDDSP.swift:48`) — jede neue Stimme erbt die Thread-Lüge. Erst Header/Contract korrigieren. |
| **#23** Per-instrument EchoelSynth | 🟢 grün | `BioReactiveSynthVoice` abonniert Bus sauber; FeatureFlags default-ON. Nur HRV-Trust-Umgehung (`:334`) als LOW-Politur. |
| **#7** Multi-Roll per-lane routing | 🟢 grün | `multiRoll`-Flag + LaneVoiceRack wired und aktiv. |
| **#37** Automation → Router-Bind | 🟡 gelb | Zwei Route-Stores ohne Reconcile (`ModulationEngine.swift:66`). |

**Muster:** Alle Bio-nächsten Tasks (#60/#61/#68/#67/#59) sind **rot** und teilen zwei Wurzeln — die tote/eingefrorene Bio-Freshness-Disziplin und die falsch dokumentierte DSP-Thread-Invariante. Die DAW-Tasks sind **gelb** mit einer gemeinsamen Wurzel — Codable-/Persist-/Relocate-Fragilität. Das ist die eigentliche Botschaft: **zwei Wurzeln entriegeln fast alles Rote/Gelbe.**

## 5. Die 3-5 billigsten nächsten Schritte

Nach Hebel geordnet, jeder klein & reversibel:

1. **Freshness-Gate in `ModulationEngine.tick`** (`:144`, ~1 Zeile: `bus.usableBio()` statt `bus.latestBio`). Entriegelt **#60** direkt, halbiert das Risiko in **#61**, macht Bio-Modulation ehrlich (löst zu neutral bei Gurt-/Finger-Verlust). Höchster Hebel/Kosten-Ratio.

2. **DDSP-Header-Invariante korrigieren** (`EchoelDDSP.swift:44-48`, Doc-Fix + präziser `@unchecked`-Kommentar, kein Verhaltens-Change). Stoppt die Irreführung, die #59/#61/AUv3-Arbeit gefährdet. Reiner Kommentar — null Regressionsrisiko, entriegelt **#59** und schützt jeden künftigen DSP-Edit.

3. **`decodeIfPresent`-Init für `Arrangement`/`ArrangementSection`** (`Arrangement.swift:13`, Muster von `Clip.swift:167` kopieren). Verhindert stillen Song-Verlust beim ersten neuen DAW-Feld — Voraussetzung, bevor **#39/#40** überhaupt ein Feld hinzufügen dürfen. Deterministisch, testbar.

4. **`guard !isRecording` in `MicrophoneManager.startRecording`** (`:194`) + Session-Teardown-Reihenfolge in `stopRecording` fixen (`:269`). Entriegelt **#13**, adressiert die „alles still"-Klasse (#22). Kleiner Guard, große Stabilität.

5. **AudioEngine-Meter-Props mit `@ObservationIgnored` schilden** (`:59-67`, + Leaf für `currentLevel`/`currentPitch`). Nimmt die 60-Hz-Freeze-Landmine aus dem Weg, bevor **#11** neue HUD/Header-Kacheln baut. Mechanisch, dem `launchGeneration`-Muster folgend.

Bewusst **nicht** zuerst: SPSCQueue-`OSAtomic`-Race (`:153`) — höchstes latentes Risiko, aber PLAUSIBLE, nur unter Gerät-Concurrency-Stress verifizierbar und ein Umbau der lock-free Spine ist NICHT Ralph-Wiggum-klein. Separat einplanen, mit Device-Verify. Ebenso Task #66 (Aufräumen der toten Türen) — wichtig für Ehrlichkeit, aber breit; als eigener Closeout-Loop (`baustellen`-Skill), nicht als Quick-Win.
