# PLAN — UX/UI-Überarbeitung (Founder-Auftrag 2026-08-13, „ultradesign ultraplan ultracode")

> *"Überarbeite die gesamte User Experience und Interface Design."*
> Dazu die früheren Asks desselben Tages: *"alles optimieren von Performance über User
> Interface bis recource, Akku bis Qualität. accessibility, übersichtlich"* ·
> *"Guide der durch die Funktionen von Echoelmusic führt"* ·
> *"je intensiver das Erlebnis desto besser. Bunter, mehr Textur, Glitzer etc., Räumlichkeit."*

**Erzeugt von 13 Agenten in drei Teams** (Zustand & Erreichbarkeit · Design & Accessibility ·
Journey & IA), je drei Worker und ein Lead, der jeden Befund adversarisch gegen den Quelltext
nachgeprüft und Vorschläge verworfen hat, die ein hartes Gesetz brechen. Synthese durch
`planning-agent`. Gemessen gegen `ecfebc1`; jede Zeile mit `file:line`-Beleg.

⚠️ **STATUS: PLAN. Genau EIN Posten daraus ist gebaut** — S0 (die Flag-Registrierung, #580,
Commit `884102f`), weil er von der Founder-Geräte-Evidenz unabhängig bestätigt wurde und weil
er alles andere blockiert hat. Alles Übrige ist Vorschlag, nicht Zustand. Wer daraus baut,
misst zuerst nach: die Zeilennummern unten sind vom 2026-08-13 und altern (das ist die
Hausregel dieser Repo-Dokumente).

⚠️ **NICHT als Bestandsangabe lesen.** Der Plan enthält bewusst auch eine lange
Ablehnungsliste am Ende — was NICHT getan wird und warum. Die ist so verbindlich wie die
Vorschläge; mehrere Punkte darin sind Founder-Entscheidungen, die eine spätere Sitzung sonst
als „Lücke" reparieren würde.

---

## Ranked Overhaul-Plan — Echoel UX/UI, 2026-08-13

Branch: `claude/echoelmusic-neustart-auv3-6ri2ek`. Alle Zitate gegen den Baum nachgemessen (siehe „Nachgemessen" unten). Reihenfolge = (sichtbarer Schmerz × Founder-Ask) ÷ Größe.

---

### DIE EINE STRUKTURELLE VORAUSSETZUNG

**S0 muss zuerst laufen, und zwar nicht als Code-Abhängigkeit, sondern als MESSTOR.** `FeatureFlags.instrumentHome` wird in `WorkspaceView.onAppear` (`WorkspaceView.swift:305`) gelesen, aber erst im asynchronen Start-`.task` registriert (`EchoelmusicApp.swift:578`, geöffnet bei `:505`). `register(defaults:)` schreibt eine **prozess-flüchtige** Domain — nie persistiert, muss jeden Start neu laufen. Ergebnis ist deterministisch OFF, bei **jedem** Start: die dokumentierte Vordertür öffnet nie, `floatingSizeRaw` bleibt `.small`, und damit rendert der einzige First-Run-Lehrtext der App (`InstrumentHintOverlay`, `FloatingVisualWindow.swift:1283-1284`, gegated auf `windowSize.isFullscreen` bei `:770-772`) **nie**.

Solange das steht, entwerfen S6–S11, S17 und S23 einen Bildschirm, den niemand je gesehen hat. Kein anderer Posten hat diese Reichweite.

**Zweitrangige Voraussetzung, nur für den Guide-Strang:** S6 (Türtexte in eine Foundation-Quelle heben) — ohne sie wird der Guide eine zweite Kopie von `StudioMenu.fullName` (`EchoelStudioView.swift:806-847`), die schon einmal auseinandergelaufen ist.

**Die Präsentations-Decke ist KEINE Voraussetzung in diesem Plan.** Kein einziger Schnitt unten hängt einen 15. Modifier an. Sie wird erst Voraussetzung, wenn jemand eine echte neue Modalfläche will.

---

## WELLE 0 — Fundament

**S0 · Flag-Defaults vor die erste Ansicht registrieren** · XS
- Files: `Sources/Echoelmusic/EchoelmusicApp.swift`
- Ändert: die drei `register(defaults:)`-Aufrufe (`:559`, `:569`, `:578`) aus dem `.task` in `EchoelmusicApp.init()` (`:252-311`, ~20 Konstruktoren, kein I/O). Flag-WERT bleibt unverändert.
- Guard `TheFlagDefaultsAreRegisteredBeforeFirstAppearTests`: alle drei `FeatureFlags.Key.*.rawValue`-Registrierungen liegen im `init()`-Slice; **null** `register(defaults:` im `.task`-Slice.
- Gesetz: keins. **Founder-sichtbar** — ändert, worin die App startet ⇒ Geräteprobe, bevor irgendetwas darauf gebaut wird.

**S1 · Freeze-Wächter für den Instrumenten-Rumpf** · S · *test-only, null Risiko, schützt jeden folgenden Schnitt*
- Files: `Tests/CISmoke/TheInstrumentBodyReadsNothingLiveTests.swift` (neu)
- Ändert: nichts am Produktcode. Schneidet `var body`, `dropdownContent` (`EchoelStudioView.swift:2741`) und die neun `private var …Panel: some View` heraus.
- Guard: die Konstrukte `cameraRPPG.waveform|confidence|detectedBPM`, `latestBio`, `freshBio`, `freshMusical`, `pacer.guidance`, `audioEngine.masterLevel`, `pattern.currentStep` fehlen in allen Slices. Ausgenommen die zwei belegt sicheren Start/Stop-Formen `transport.isPlaying` (`:1307`) und `breathPacer.isRunning` (`:1366`), damit er GRÜN startet. Fehlermeldung nennt das Leaf-Muster.
- Gesetz 2. Heute deckt `TheHeaderShowsTheLoopTests:427` nur `WorkspaceView.topBar` ab — der Rumpf, in dem die Freezes tatsächlich passiert sind, hat null ausführbare Deckung.

---

## WELLE 1 — Sichtbarer Schmerz, kleinster Schnitt

**S2 · Transport LINE 1 bricht auf 375 pt um** · M · *der einzige Defekt bei DEFAULT-Textgröße auf einem lieferbaren Gerät*
- Files: `Sources/Echoelmusic/Studio/TransportLineOne.swift` (neu), `EchoelStudioView.swift`
- Ändert: `startControlRow`s erste Zeile (`:1809`) in ein Leaf mit eigenem `@Environment(\.dynamicTypeSize)` / `\.horizontalSizeClass`. Eine Reihe wenn das Budget reicht, sonst zwei (Transport-Paar / Tempo + Puls). 358 pt Hartminimum gegen 343 pt nutzbar (SE/13 mini); tritt nur auf, wenn `bus.instrumentRunning` true ist — also mitten in der Performance, und das Kind, das rausfliegt, ist die Puls-Spur.
- Guard `TheTransportFitsThreeSeventyFiveTests`: `TransportLineOne` existiert und enthält den Size-Class-Read; `EchoelStudioView.body`-Slice enthält ihn NICHT; `PulseMonitorMini`s `minWidth 60` (`HeaderMonitors.swift:120`) unverändert.
- Gesetze 2 (Leaf), 6 (Reflow). Kein Modifier. **Puls-`minWidth` NICHT senken** (`HeaderMonitors.swift:107-110`).

**S3 · Tür für das immersive Visual** · S · *größtes Erlebnis pro Diff-Zeile — Founder-Ask „bunter, Textur, Räumlichkeit"*
- Files: `EchoelStudioView.swift`, `Core/StudioDefaultKeys.swift`, `Studio/AnalysisSpectrumView.swift`
- Ändert: eine Zeile `Button { showVisual = true }` „Open immersive visual" in `visualPanel` unter `:4537-4552`. **Nachgemessen:** `showVisual = true` kommt in `Sources/` **null**mal vor; der einzige Schreiber ist der Close-Button `:1479`. Dahinter liegen fertig verdrahtet: Vollbild-`MetalBioView` (`:1420`), VJ-Overlay (`:1434`), `SpectralDonutView` (`:1417`), MP4-Aufnahme (`:1470`). Im selben Commit die sechs „kein Setter"-Prosastellen zurücknehmen: `:5158`, `:5174`, `:5200`, `:5297`, `:5646-5647`, `StudioDefaultKeys.swift:102`, `AnalysisSpectrumView.swift:18`.
- Guard `TheImmersiveVisualHasADoorTests`: genau EIN `showVisual = true` in `Sources/`; die Kette bleibt bei 14 Modifiern (dateiweit 16); keine Datei behauptet noch „no writer of true".
- Gesetz 1 — **Slot-WIEDERVERWENDUNG, kein Anhängen**; die Decke bewegt sich in die sichere Richtung. GPU-Kollision ist schon behandelt (`:1346`).
- ⚠️ **Dieser Cover wurde noch NIE von einem Nutzer geöffnet.** Geräteprobe des Metal-Pfads vor dem Ship.

**S4 · „Open project" bekommt einen Ausgang** · XS
- Files: `EchoelStudioView.swift`
- Ändert: ein `ToolbarItem(placement: .cancellationAction) { Button("Done") { showOpen = false } }` neben dem Import-Item (`:7876-7888`). Heute ist der einzige Ausgang ein Swipe-Down über eine `List`, deren Zeilen selbst einen Swipe tragen.
- Guard `EverySheetHasAnExitTests`: jede erreichbare Sheet-Content-Funktion trägt einen sichtbaren Exit.
- Gesetz: keins (ToolbarItem ist kein Presentation-Modifier).

**S5 · Projekt-Löschung umkehrbar** · S
- Files: `EchoelStudioView.swift`
- Ändert: `@State deletedProject: Project?`, vor `projects.delete` gefüllt (`:7839-7850`), „Undo delete of <name>" als Zeile am **ENDE** der Liste (Begründung: `VideoLibraryPanel.swift:155-167`). Bewusst **kein** `.confirmationDialog` — wäre ein Modifier, und „reversibel schlägt bestätigt" ist ratifiziert (`:374-389`).
- Guard `DeletingAProjectIsReversibleTests`: `deletedProject` wird vor `projects.delete` gesetzt und im Undo-Zweig via `projects.save(` zurückgegeben.
- Gesetz: keins.

**S6 · Kein Vollswipe zerstört Nutzerarbeit** · S
- Files: `Studio/EchoelFXView.swift`
- Ändert: `allowsFullSwipe: true` → `false` an `:1304` (Bio-Mod-Route, gleiche Liste enthält ziehbare `EchoelValueField`s) und `deletedPreset`-Undo für FX-Presets.
- Guard `NoFullSwipeDestroysUserWorkTests`: `allowsFullSwipe: true` = 0 Treffer in `Sources/`.
- Gesetz: keins.

---

## WELLE 2 — Guide (wörtlicher Founder-Ask, hängt an S0)

**S7 · Türbeschreibungen in EINE Foundation-Quelle** · M
- Files: `Core/StudioDoorCatalog.swift` (neu), `EchoelStudioView.swift`, `Studio/LearnLibrary.swift`
- Ändert: `id · label · fullName · detail` je Tür. `StudioMenu.label`/`.fullName` (`:798-847`) lesen daraus statt eigene Literale. Kein Verhalten. `StudioMenu` ist `private` (`:750`) und `LearnLibrary` Foundation-only — deshalb ist das der Blocker, nicht der Guide selbst.
- Guard `TheDoorCopyHasOneSourceTests`: `StudioMenu.fullName` enthält keine String-Literale mehr; der Katalog hat genau einen Eintrag je `StudioMenu`-Case.
- Gesetz: keins. >1 Datei + user-facing copy ⇒ Council.

**S8 · `LearnSection.functions` — der Guide** · M · *DIE Antwort auf „Guide fehlt noch"*
- Files: `Studio/LearnLibrary.swift`
- Ändert: sechster Case „How Echoelmusic works" neben `body, bodyScience, music, light, safety` (`LearnLibrary.swift:11`), ein Eintrag je Bedienelement: Transport-Zeile, die acht Kacheln, die Chip-Leiste, die Pulse-Pille + Long-Press, das Visual-Fenster, Save/Export. `LearnView.list` iteriert `LearnSection.allCases` (`LearnView.swift:44`) ⇒ **null neue Ansicht, null neuer Presentation-Modifier**, hinter der dauerhaft sichtbaren Buch-Kachel (`EchoelStudioView.swift:2034` → `.sheet($showLearn)` `:1400`).
- Guard `TheGuideNamesOnlyLivingControlsTests`: jeder Eintrag nennt ein Chip-Label oder einen Panel-Titel, der in `Sources/` existiert; kein Eintrag nennt eine türlose Fläche (bis S3 also **nicht** das immersive Visual).
- Gesetz 1 bleibt unberührt. Copy ⇒ Council.

**S9 · Learn-Tür lügt nicht mehr** · XS
- Files: `EchoelStudioView.swift:2039`
- Ändert: `.accessibilityHint("Opens the body-science library and release notes")` → „…the guide to Echoelmusic's functions and the body-science library". Release Notes existieren nirgends; der einzige Kandidat ist hinter `AnnouncementCenter.cloudKitConfigured == false`.
- Guard `LearnDoorHintTests`: der Hint nennt „release notes" nicht, solange die Konstante false ist.

**S10 · Onboarding-Seite 2: Fingerkuppe + Kamera statt Roadmap** · S
- Files: `Views/OnboardingView.swift:105-137`
- Ändert: die „wider vision"-Liste (DMX, ADM-OSC — drei Roadmap-Fähigkeiten, auf die ein Erstnutzer nicht handeln kann) durch die Kernbewegung: Finger auf die rückseitige Linse, und ein Satz, dass der nächste Bildschirm nach Kamerazugriff fragt. Gleiche Seitenzahl, gleiche Tap-Zahl. Die fünf Sicherheitszeilen bleiben unangetastet.
- Guard `OnboardingNamesTheCoreGestureTests`: „camera"/„finger" erscheinen vor der Consent-Seite; die fünf Sicherheitszeilen unverändert.
- Gesetz 7 (keine Health-Claims). Onboarding ist ein App-Root-**Zweig** (`EchoelmusicApp.swift:335-338`), kein Modal ⇒ Decke unberührt.

**S11 · „Replay the intro"** · XS · *ohne diese Zeile ist S10 für jeden bestehenden Tester und den Founder unsichtbar*
- Files: `Studio/LearnView.swift`
- Ändert: eine Zeile, die dieselbe `@AppStorage("hasCompletedOnboarding")` auf `false` schreibt. Nebenwirkung ehrlich benennen: das Consent-Gate erscheint erneut.
- Guard `TheIntroCanBeReplayedTests`: genau ein erreichbarer Schreiber von `false`.

---

## WELLE 3 — Accessibility (wörtlicher Founder-Ask)

**S12 · Die Textgrößen-Leiter bekommt eine Tür** · S
- Files: `EchoelStudioView.swift`
- Ändert: (a) `.accessibilityAdjustableAction` an `StudioZoom`s Body neben der `MagnifyGesture` (`:10052`) — dasselbe Idiom wie `EchoelValueField.swift:647`. (b) Eine Picker-Zeile „Text size" + „Follow system text size" (schreibt `-1`) **in das schon montierte Save/Export-Panel**. Nachgemessen: `zoomStep` (`:854`) hat genau zwei Referenzen, Deklaration und `:1102`; einziger Schreiber ist ein Zwei-Finger-Pinch, den VoiceOver reserviert. `-1` ist nach dem ersten Pinch unerreichbar.
- Guard `TheTextSizeLadderHasADoorTests`: `zoomStep` hat ≥2 Schreiber, einer davon keine `MagnifyGesture`; `-1` ist erreichbar.
- Gesetze 1 (**muss in ein VORHANDENES Panel** — kein neues Sheet), 4 (`.large … .accessibility5` sind NAMEN ⇒ **Picker**, niemals `EchoelValueField`).

**S13 · `.frame(height:)` → `.frame(minHeight:)`, Gruppe 1** · M · *größte mechanische A11y-Schuld im Studio*
- Files: `EchoelStudioView.swift`
- Ändert: 15 text-tragende Stellen (`:2886, :3468, :3627, :4256, :4373, :4407, :4548, :5073, :5133, :5262, :6016, :6587, :6818, :6906, :10421`). Nachgemessen: 21 harte Höhen in der Datei, davon 3 nicht text-tragend (`:2120, :2134, :3499` — **nicht anfassen**), 13 Stellen benutzen das korrekte Idiom bereits. Gesetz steht wörtlich in `EchoelTheme.swift:203-206`. Bei `:3627`/`:10421` nur die ZEILE auf `minHeight`, der Clear-Button bleibt 36×36.
- Guard: `TapTargetFloorTests` um die berührten Stellen **namentlich** erweitern. **Kein Blanket-Scan** — der Header dieses Tests warnt, dass ein pauschales „jeder Frame unter 44" auf Dekor-Glyphen feuert und ein Gate abgeschaltet wird.
- Gesetz 6. Strikte Relaxation, nichts schrumpft.

**S14 · Dieselbe Sweep, Gruppe 2** · S
- Files: `Studio/PatchbayView.swift` (`:241, :293, :333, :344, :393`), `Studio/FloatingVisualWindow.swift:870`, `Studio/LiveColaboView.swift:188`

**S15 · Neun Sub-44-pt-Ziele in `chipTapTarget`** · S
- Files: `EchoelStudioView.swift`
- Ändert: `:5073, :5262, :5133, :3468, :6587, :6016, :2886, :3320, :4548` in den vorhandenen Helper (`:2582-2586`) wickeln — ändert nichts am Aussehen der Pille. **Vorher lesen:** `:6088-6092` erklärt, warum die Ellipsen-Outset dort bewusst zurückgehalten wurde (4 pt Überlappung, und die überlappende Hälfte ist die destruktive).
- Guard: `TapTargetFloorTests` +9 benannte Fälle.

**S16 · Die drei stummen VoiceOver-Werte** · XS
- Files: `Studio/FloatingVisualWindow.swift`
- Ändert: (a) `liveVisual` (`:693`) bekommt `.accessibilityElement()` + Label „Immersive visual" + Value aus `LookBlendMap.nearestName(at:sequence:)` — `MetalBioView.swift` hat über 1846 Zeilen **null** `accessibility` (nachgemessen), während der Zweig „Visual ist auf dem externen Bildschirm" zwölf Zeilen weiter voll beschriftet ist. (b) `RecordingBadge` (`:42`): `.accessibilityElement(children: .ignore)` + `.accessibilityValue(timeString(elapsed))` — heute überschreibt das Container-Label die verstrichene Zeit. (c) `MiniTransportView` (`:86`): `.accessibilityValue("Bar … of …, beat …")`, wörtlich wie der Zwilling `WorkspaceView.swift:1074-1076`.
- Guard `TheVisualIsAnnouncedTests`: alle drei tragen Value.
- Gesetz 2 — **der Value darf NIE aus einem Bio-Wert kommen**, sonst wird `FloatingVisualWindow.body` ein 10-Hz-Beobachter.

**S17 · Tempo-Feld sagt die Wahrheit** · ⭐ **ERLEDIGT (#647) — aber NICHT so, wie dieser Eintrag es vorschrieb.**
- Gebaut: `TempoFollowLabel.spoken(for:)` in `Studio/BodyTempoField.swift`, drei Zustände, beide Label-Stellen gekeyt auf `bus.usableBio()`. Wächter: `TheSpokenTempoSaysWhoseBodyTests`.
- ⛔ **Der Vorschlag dieses Eintrags war die Über-Korrektur und steht hier stehen gelassen, damit niemand ihn nachträglich einbaut.** Er lautete: `liveBodyBPM > 0 ? "Tempo, driven by your body" : "Tempo, no body signal"` — mit der Begründung „kein neuer Read". Genau das ist der Fehler: `liveBodyBPM` ist **kamera-only** (`cameraRPPG.isRunning && displayBPM > 0`), hätte also einem Nutzer mit BLE-Gurt oder Apple Watch „kein Körpersignal" angesagt, während sein Gurt die Uhr treibt. Der billigste Read ist nicht der richtige Read; die Ersparnis war real und die Aussage falsch.
- ⛔ Zweitens deckte der Vorschlag nur ZWEI Zustände ab. Der dritte — „ein Frame kommt an, aber vom Demo-Generator" — ist genau der, den #644 einen Zyklus zuvor mit einem `Bool` nicht ausdrücken konnte.
- Der geplante Wächtername `TheTempoLabelTellsTheTruthTests` existiert nicht; er hätte die verworfene Verzweigung festgenagelt.
- Die genannten Zeilennummern (`:233`, `:254`, `:220`) sind durch den Eingriff verschoben — in diesem Repo ist eine zitierte Phrase belastbar und eine Zeilennummer ein Datum.

**S18 · Visual-Fenster per VoiceOver verschiebbar** · S
- Files: `Studio/FloatingVisualWindow.swift:847`
- Ändert: vier `.accessibilityAction(named:)` „Move left/right/up/down" (Präzedenz `MoodPads.swift:99-102`, die einzigen vier im Repo), Label auf „Echoelmusic — visual window position", Drag-Anweisung in einen `.accessibilityHint`. Heute nennt das Label genau die Geste, die seine Zielgruppe nicht ausführen kann.

---

## WELLE 4 — Ressource / Akku

**S19 · Reduce Motion stoppt den Timer, nicht nur die Bewegung** · XS
- Files: `Studio/HeaderMonitors.swift:409` (+ Prosa `:488`, `:519` im selben Commit)
- Ändert: `TimelineView(.animation(minimumInterval: 1/20))` in `if reduceMotion { statischer Gradient } else { TimelineView }` — exakt das Muster des Geschwisters `EchoelLuxMonitorMini` (`:513-529`). Heute flacht `:462` nur den WERT ab und lässt den 20-Hz-Repaint in der nie abgehängten Brand-Leiste laufen.
- Guard `ReduceMotionStopsTheTimerTests`: kein unbedingter `TimelineView(.animation` in der Datei.
- Gesetz 5. **Die 20 Hz im Nicht-Reduced-Zweig NICHT senken** — sie sind die Abtastung eines 2,5-Hz-Kosinus (`flashSafePulseRate`, `:453`), Senken macht die Kurve stufig.

**S20 · `BreathCircle` aus dem Strip herausheben** · XS
- Files: `Studio/BreathGuideView.swift:513`, `Tests/CISmoke/TheBreathingPracticeIsInTheMainViewTests.swift:176`
- Ändert: `let amp = pacer.guidance` in einen eigenen `private struct BreathCircle` — heute macht dieser eine Read den ganzen Strip zum 30-Hz-Beobachter und misst zwei umbrechende Captions plus vier Kontraindikationszeilen 30×/s neu, auf dem Bildschirm, dessen Zweck Stillstand ist.
- Guard: der bestehende Assert `strip.contains("pacer.guidance")` MUSS im selben Commit auf den neuen Struct zeigen, sonst wird ein korrekter Baum rot.
- Gesetze 5, 2.

**S21 · Meter-Timer benachrichtigt nicht im Leerlauf** · M
- Files: `Audio/AudioEngine.swift:1298-1322`
- Ändert: Ungleichheits-Guard auf die neun getrackten `@Observable`-Zuweisungen. Heute ~540 Observation-Notifications/s plus 60-Hz-Main-Thread-Timer, von Start bis Ende, bei geschlossenem Master-Panel.
- Guard `TheMeterTimerDoesNotNotifyOnIdleTests`: jede der neun Zuweisungen steht hinter einem `!=`.
- **TRAP:** `updateFeedbackGuard` hängt an `monitorPollTick % 4` (`:1327`) — hier NICHT anfassen. Die Ratenanpassung (1/60 s bei montiertem Meter, sonst 1/10 s) ist eine EIGENE Scheibe und braucht Geräteprobe des Duck-Loops.
- Kein Audio-Thread berührt (reine `@MainActor`-Ausleseseite).

---

## WELLE 5 — Lügende Bedienelemente (Ehrlichkeit)

**S22 · Apple-Health-Schalter meldet den echten Status** · S
- Files: `Bio/HealthKitWriter.swift:77`, `EchoelStudioView.swift:10267-10269`
- Ändert: `isAuthorized` aus `store.authorizationStatus(for: hr) == .sharingAuthorized` statt aus dem Ausbleiben eines `throw` — HealthKit wirft bei Verweigerung nicht. Caption dreistufig statt zweistufig; heute beschreibt der eingeschaltete Zustand sich selbst mit „Off by default".
- Guard `TheHealthSwitchReportsTheRealStatusTests`: `isAuthorized` wird nicht im `do`-Zweig hart auf `true` gesetzt; die Caption hat drei Zweige.
- Gesetz 7 — reine Mess-Sprache, kein Health-Claim. Wortlaut ⇒ Council.

**S23 · Video-Recorder bekommt Fehl- und Busy-Zustand** · S
- Files: `Studio/FloatingVisualWindow.swift` (`:26`, `:1117`), `Studio/VideoLibraryPanel.swift:245`
- Ändert: `videoFinishing` um das `await` (Label `VIDEO …`, Dimmen, `.disabled`) und ein `VIDEO FAILED`-Zweig im Badge, der `recorder.video.recordState` liest. Heute wird `.error` nirgends gerendert (`VideoRecorder.swift:163-169`), und ein zweiter Tap während `finishWriting` startet über eine unfertige Aufnahme. Der WAV-Zwilling 600 Zeilen darüber hat beides (`:471-482`, `:492-502`).
- Guard `TheVideoRecorderHasAFailureStateTests`: `recordState` wird an ≥1 Stelle gerendert; die Taste ist während `videoFinishing` disabled.
- Gesetz 2 — der `recordState`-Read bleibt im Badge-Leaf.

**S24 · Fünf stumme Fehlschläge bekommen eine Stimme** · S (zwei Commits, nach Datei getrennt)
- `EchoelStudioView.swift:3275-3303` — Mic-Monitor: dritter Caption-Zweig „The audio engine is not running — nothing is being monitored." (Der Pfad ist im Quelltext bei `:3249-3255` bereits vermessen.)
- `EchoelStudioView.swift:6638`, `:6066`, `EchoelFXView.swift:761` — „Submit to community": EIN Helper mit `openURL(_:completion:)`; nil-URL und `accepted == false` schreiben eine Notiz dorthin, wo das Panel Warnungen schon rendert.
- `Sync/MultipeerSession.swift:280-284` — „<name> did not join" statt stiller Rückfall auf den Idle-String.
- `EchoelStudioView.swift:10504` — `.onSubmit` an dieselbe Bedingung wie der Shape-Button (`:10535`); heute führt Return aus, wofür der Knopf daneben ausgegraut ist.
- Guard `NoSilentFailureTests`: kein `openURL(` ohne `completion:` in `Sources/`; `onSubmit`-Aktion und `.disabled`-Bedingung derselben Zeile stimmen überein.

**S25 · MIDI-Export sagt, warum nichts passiert** · M
- Files: `EchoelStudioView.swift`
- Ändert: (a) Kachel-Freigabe an die Notenzahl (in einem Leaf gelesen) statt an `hasComposed` (`:1946`) — der `guard !arrangedNotes.isEmpty else { return }` (`:9532`) ist heute ein stiller Rückkehrer. (b) `midiExportNote` neben `exportFailure` in `utilityRow` (`:7362`), Muster `importNote` (`:7805-7828`).
- Guard: die Kachel-`.disabled`-Bedingung nennt die Notenzahl; kein `.alert` hinzugefügt.
- Gesetz 1 ist der Grund, warum das **kein Alert** wird; Gesetz 2, warum der Zähl-Read in einem Leaf sitzt. Auch die stehende Entscheidung gegen eine vierte Zeile in `quickActionRow` (`:1895-1906`) respektieren.

**S26 · Delay-Picker kann nicht mehr lügen** · S
- Files: `EchoelStudioView.swift:6842`
- Ändert: den AUFGELÖSTEN Wert aus `chain.delay.timeSeconds` neben die Picker-Zeile stellen. `delaySync` (`:312`) ist `@State`, nicht persistiert, und `EchoelFXView.swift:536-537` schreibt dasselbe Feld ohne Rückmeldung. Die Zahl kommt damit immer aus der Kette. Die Verkabelung (`onDelayTimeChanged`) und das Persistieren von `delaySync` sind separate, größere Entscheidungen.
- Gesetz 4: `delayMode` und die Harmonie-Intervalle bleiben **Picker**.

---

## WELLE 6 — Reflow-Schuld (#292 fortführen, EIN Panel je Commit)

Heute reflowen 4 von 10 (`mixerPanel`, `soundPanel`, `moodPanel`, `visualPanel` — 12 `AdaptiveCardGrid`-Aufrufstellen, nachgemessen). Starr: `bioPanel`, `videoPanel`, `tempoToolsPanel`, `masterPanel`, `effectsPanel`, **`utilityRow`** (nicht `menuPanelHost` — das ist der ScrollView-Wirt und korrekt adaptiv).

- **S27 · `MasterLoudnessGrid`** (`MasterLoudnessGrid.swift:209`, `:213`): die zwei literalen HStacks durch `AdaptiveCardGrid` ersetzen, `.lineLimit(1).minimumScaleFactor(0.6)` auf den Wert-Text. Guard: `MasterLoudnessReflowsTests`. Datei ist bereits ein Leaf ⇒ Environment-Read freeze-sicher.
- **S28 · Master-Türpaar** (`EchoelStudioView.swift:4387-4396`, `:4407`): durch `AdaptiveCardGrid(spacing: 14)`, `.frame(minHeight: 34)`. Hinter „Audio input" liegt FeedbackGuard, hinter „Routing" das ganze OSC/ADM-OSC/Art-Net-Blatt — eine Tür, die „Audio inp…" durch ihren eigenen Rand liest, wird übersprungen.
- **S29 · `moodPresetBar`** (`:6012`): `.lineLimit(1)` + `.frame(maxWidth: .infinity, alignment: .leading)`, wörtlich wie der Zwilling `:6582`/`:6588`. Kein `minimumScaleFactor` (der Zwilling hat keins). Heute schiebt ein langer Mood-Name das „•••"-Menü — die einzige Tür zu save/favourite/delete — über die Panel-Kante.
- **S30 · Feste Zahlenbreiten** (`:4272` 84 pt, `:3491` 16 pt, `:3503` 40 pt): `minWidth` + `.lineLimit(1).minimumScaleFactor(0.7)`, Form wie `HeaderMonitors.swift:130-133`.
- **S31 · `bioPanel`** (`:2776`): **nicht** in `panel(...)` wickeln (umgeht eine Freeze-Frage, `:2740-2743`). Stattdessen zwei Gruppen in EIN `AdaptiveCardGrid(spacing: 10)` — GEMESSEN (`BioStripView` + `AlwaysOnBioPanelStrip` + die zwei Sätze) gegen GEÜBT/GEHANDELT (`BreathCoachStrip`, `BreathVoiceRow`, Open Routing, `HealthWriteOptInRow`). `spacing: 10` ⇒ Hochformat bit-identisch. Alle bio-lesenden Kinder sind bereits eigene Structs.
- **S32 · `AlwaysOnBioRow`** (`AlwaysOnBioRow.swift:96`): `channel.shapes` über der Accessibility-Schwelle in eine eigene Zeile, sonst `.minimumScaleFactor(0.8)`. Kohärenz treibt vier Parameter ⇒ 40 Zeichen bei font(11) mit `lineLimit(1)` ohne Scale-Faktor.
- **S33 · Video-Player** (`VideoLibraryPanel.swift:335`): `.frame(height: 190)` → `.aspectRatio(16.0/9.0, contentMode: .fit)`. Heute letterboxt die eigene Ausgabe auf jedem Telefon breiter als 375 pt.
- **S34 · Chip-Leiste lesbar überlaufen** (`:2484`): Trailing-Fade-Maske (Opazität — **kein** Blur, kein Shadow, Gesetz 3). Acht Chips × 44 pt Tap-Frame ≈ 540 pt auf 393 pt, `showsIndicators: false`, und `.export` ist der letzte Chip. **Reihenfolge NICHT ändern** (`:2474` founder-gated).
- **S35 · Over-Video-Token-Familie** (`EchoelTheme.swift` + `FloatingVisualWindow.swift`): `onVideo`, `onVideoDim`, `onVideoTrack`, `videoScrim`; die neun rohen Weiß/Schwarz-Stellen (`:36, :39, :74, :75, :80, :83, :488, :493, :1288, :1291, :1292`) darauf falten, `radiusSmall` statt der nackten `6`. Genau die Fläche, die durch den Founder-Ask bunter und texturierter wird und heute keinen Ort zum Nachjustieren hat. Die vier Stellen im `showVisual`-Cover erst NACH S3 anfassen.

---

## BLOCKIERT — und woran

| Posten | Blockiert auf |
|---|---|
| Jede NEUE Modalfläche | Konsolidierung der 14er-Kette in EIN `.sheet(item:)`-Enum. **Kein Schnitt in diesem Plan braucht das.** |
| S7–S11 (Guide, Onboarding) | **S0** + Geräteprobe: bis dahin ist unbekannt, worin die App öffnet |
| S8 (Guide-Inhalt) | **S7** (Copy-Hoist) — sonst zweite Kopie einer schon einmal driftenden Beschreibung |
| S10 (Onboarding-Text) | **S11** (Replay) — sonst für jeden bestehenden Tester unsichtbar |
| S3 (immersive Tür) | Geräteprobe des Metal-Pfads — der Cover wurde nie geöffnet |
| S21 (b) Ratenanpassung des Meter-Timers | Geräteprobe der FeedbackGuard-Reaktionszeit |
| `EchoelValueField` Drag-Rechteck verschmälern (`EchoelValueField.swift:709-713`) | Nur am Gerät beweisbar. ~24 von 40 Reglern in `soundPanel` sind drag-aktiv über die volle Breite, und `horizontalScrub` (`:480`) steht auf `true`, also ist KEIN Panel-Feld von der Achsen-Dominanz (`:979-982`) geschützt. **PLAUSIBEL, nicht bestätigt — zurückstellen.** |
| Field-Panel-Aufteilung, Bio-Chip, Chip-Reihenfolge, Wetter-Eigentum, ▶/■ nach unten | Founder-Entscheidung (siehe unten) |

---

## FOUNDER-FRAGEN (nicht von mir zu entscheiden)

1. **Vordertür.** Nach S0 könnte die App im Vollbild-Visual starten (`instrumentHome` registriert dann wirklich auf `true`). Soll das die Startansicht sein — oder soll die Flagge auf `false`? (Ein-Zeilen-Hebel, `FeatureFlags.set(.instrumentHome, false)`.)
2. **Erste Kachel beim Kaltstart.** Heute `soundPanel` — ~40 Regler — via `displayedMenu { activeMenu ?? .sound }` (`:2768`). Soll ein Erstnutzer stattdessen `bioPanel` sehen (3 Regler + der einzige Satz, der das Produkt erklärt)? Beide Hebel widersprechen aufgeschriebenen Entscheidungen (`:2757-2760`).
3. **Bio-Chip.** Soll `.bio` einen Chip in der Leiste bekommen? #290 lehnte das als „zweite Tür" ab (`:2412-2414`) — aber die eine Tür ist eine Anzeige-Pille, die nachträglich `.accessibilityAddTraits(.isButton)` brauchte.
4. **Field-Panel.** Der Chip „Field" enthält ~41 Regler aus drei Berufen: Projektor-Look, die Stimme der Spielfläche, ein Selbstspiel-Arpeggiator. Darf `touchSoundSection` + `fieldSelfPlaySection` unter `.bio`, und der Chip „Visual" heißen?
5. **Wetter.** Klang-Mixer in `moodPanel`, Bild-Mixer in `visualPanel`, plus ein Knopf, der zwischen beiden verweist (`:3735`). Eine Fläche oder zwei? (Unabhängig davon repariere ich unilateral nur den stummen Leerzustand von `weatherImageRow`.)
6. **Onboarding-Wiederholung** (S11) zeigt das Sicherheits-Consent-Gate erneut. Akzeptabel?

---

## WAS ICH BEWUSST NICHT MACHE

- **Keinen 15. Presentation-Modifier.** Nichts oben braucht einen. `showMeditation` wird **nicht** verbraucht (`MeditationView` verlöre die einzig mögliche Tür), `midiImportPresented` ist ein `.fileImporter` und kann gar keine Ansicht tragen.
- **Keine Coach-Mark-Tour als ersten Guide-Versuch.** Braucht Overlay-Maschinerie, die nicht existiert; der Learn-Abschnitt liefert denselben Ask für einen Bruchteil.
- **Kein First-Run-Filter, kein Ausblenden/Dimmen/Umsortieren von Chips.** Am Gerät getestet und vom Founder abgelehnt (#572, `:2440-2448`: „Du hast mega viel gelöscht"). Ein Guide **ergänzt** Erklärung über die unveränderte Fläche.
- **Kein neunter Chip.**
- **Kein Umbenennen von „Save/Export".** `SaveDoorNamingTests` pinnt Chip-Label, VoiceOver-Name und Panel-Überschrift als EINE Entscheidung — der Vorschlag „Loop & Setup" wäre auf korrektem Baum rot, und die Behauptung, Chip und Überschrift widersprächen sich, ist widerlegt.
- **Kein repo-weiter Regex auf `.frame(height:`.** 3 der 21 in `EchoelStudioView` sind nicht text-tragend; `TapTargetFloorTests` hält fest, dass ein pauschaler Scan Rauschen erzeugt, das ein Gate abschaltet.
- **Keine Umwandlung benannter Picker in `EchoelValueField`** (Filtermodus, Delay-Modus, Harmonie-Intervall, Zoom-Leiter). Gesetz 4 sagt NUMERISCH.
- **Kein Wieder-Anhängen der vier Analyse-Ansichten** (`AnalysisScope/Poincare/Spectrum/Wavefront`) — Founder-Screenshot 2026-08-13, „Das Brauch da nicht sein". Alle vier sind türlos **mit Absicht**; das gehört ins CLAUDE.md-Register, nicht in eine Reparatur.
- **Kein Senken der 20 Hz** in `ImmersiveMonitorMini`, **kein Verbreitern der 8-pt-Drag-Slop** in `EchoelValueField`, **kein Löschen** der neun inerten `isExpanded`-Bindungen oder der drei verwaisten `@AppStorage`-Keys (`studio.showComposition/showMix/showExport`).
- **Kein `.confirmationDialog`** für Löschungen — Modifier plus „reversibel schlägt bestätigt".
- **Und die wichtigste Ablehnung:** „bunter, mehr Textur, Glitzer, Räumlichkeit" wird **nicht** in der Chrome geliefert. Gesetz 3 verbietet Glassmorphism, Glow, Neon und große Schatten — und das Repo ist heute sauber (Radien >16 px = 0, `Material`/`.blur(` = 0, genau EIN Schatten bei Radius 8). Der Ask landet auf dem **immersiven Visual** (S3), den **Over-Video-Tokens** (S35) und der ADM-OSC-Raumstufe. Dort ist er Produkt; in der Chrome wäre er ein Gesetzesbruch.

---

**Nachgemessen für diesen Plan** (read-only): `showVisual`-Schreiber, `register(defaults:)`-Sitze und `instrumentHome`-Leser, `LearnSection`-Cases, `StudioMenu` `private` + `fullName`, `.frame(height:)` = 21 / `.frame(minHeight:)` = 13 in `EchoelStudioView.swift`, `AdaptiveCardGrid`-Aufrufstellen = 12, `accessibility` in `MetalBioView.swift` = 0, `accessibilityAdjustableAction` = 1 Produktionsstelle (`EchoelValueField.swift:647`), `zoomStep` = 2 Referenzen, `chipTapTarget` existiert (`:2582`).
