# CLAIMS — was Echoel heute WIRKLICH kann

**Diese Datei ist die Quelle für jedes Skript, jede Caption, jedes Thumbnail.**
Sie steht bewusst VOR den Templates in dieser Pipeline, weil das Grundproblem von
Marketing-Content nicht das Format ist, sondern die Behauptung.

Zwei ganze Arbeitszyklen (#158, #192) wurden damit verbracht, EINE falsche Behauptung
wieder aus acht Dateien und ~25 Stellen der Website zu entfernen. Ein weiterer (#184)
entfernte zwölf falsche Behauptungen aus dem App-Store-Text — dort ist eine falsche
Behauptung ein 2.3-Ablehnungsgrund („Accurate Metadata"). Ein Skript, das eine
gestrichene Behauptung wieder einführt, macht diese Arbeit rückgängig.

Stand: 2026-08-28 (Brand-Audit: §12 korrigiert — Kohärenz-Trend ist seit #813 WAHR;
✅-Zeilen für Harmonizer/Granular/Feedback-Schutz/Visual-Aufnahme/Beamer/Texture+Glitter
ergänzt). **Vor jeder neuen Kampagne
gegen `CLAUDE.md` „CURRENT STATE" und `docs/dev/FEATURE_MATRIX.md` gegenprüfen.** (Die Versionsnummer stand hier früher
daneben und veraltete schneller als der Inhalt — sie belegte nichts, was das Datum
nicht besser belegt.)

**Zwei Behauptungen dieser Datei sind maschinell gepinnt** (`Tests/CISmoke/ContentPipelineClaimsTests.swift`,
im blockierenden Bundle): „Null externe Abhängigkeiten" und „kein AUv3". Beide sind
Tatsachen über das Repo, keine Formulierungen — wer sie ändert, färbt das Gate rot und
muss diese Datei im selben Commit mitziehen.

⚠️ **Wie weit der Zaun WIRKLICH reicht** — die erste Fassung dieses Absatzes versprach
mehr, als der Test hält, und ein zu weit versprochener Zaun ist schlimmer als keiner:
- **Abhängigkeiten:** geprüft werden `Package.swift` UND der `packages:`-Block in
  `project.yml` (die App wird über XcodeGen gebaut, nicht über SwiftPM — nur das
  Manifest zu prüfen hätte die Hälfte offen gelassen).
- **AUv3:** geprüft wird das TARGET, gebunden an den Namen `EchoelmusicAUv3`. Ein
  Target unter anderem Namen rutscht durch — das wäre eine laute, gewollte Änderung,
  aber der Test findet sie nicht. Und die HOSTING-Hälfte von §1 („kann keine fremden
  Plugins laden") ist gar nicht gepinnt.
- Alles andere hier ist **ungepinnt** und lebt von der Gegenprüfung oben. Urteilsfragen
  (Wellness-Ton, Watch-Formulierung, §10) kann kein Test entscheiden.

ℹ️ **Nebenwirkung, die man wissen muss:** #252 hält `ContentPipeline/**` bewusst aus
JEDEM Auto-Merge-Pfadfilter heraus, damit reine Pipeline-Commits nie automatisch nach
`main` wandern. Der Wächter liegt aber in `Tests/` — **ein Commit, der beide anfasst,
zieht diese Datei mit nach `main` und löst TestFlight aus.** Wer nur an dieser Datei
arbeitet, fasst `Tests/` nicht an und bleibt wie vorgesehen isoliert.

---

## ✅ DARF behauptet werden — gebaut, verdrahtet, am Gerät gesehen

| Behauptung | Beleg |
|---|---|
| Der Puls wird **mit der iPhone-Kamera** gemessen (Finger auf die Linse, rPPG) | live; Log 2477: Lock in 14 s, danach Minuten bei Confidence 0,8–0,96 |
| Herzschlag, HRV und Kohärenz **modulieren Klang in Echtzeit** | `EchoelDDSP` Bio-Mappings, `FXBioModulator` |
| **Generative Komposition** in gewählter Tonart/Skala/Genre, tonartrein | `BioComposer`, 57 Skalen, 15 Stimmungssysteme |
| **Bio-reaktive Visuals** live auf dem Gerät (Metal) | `MetalBioView`, `FloatingVisualWindow` |
| **Das Bild ist SPIELBAR**: Berühren des Visuals erzeugt tonartreine Noten auf dem Klang des Takes — im schwebenden Fenster UND im Vollbild, in jeder Größe, mit Wasserringen unter den Fingern | `TouchInstrumentView(` wird in `FloatingVisualWindow.swift:791` konstruiert, im `.overlay` des Visuals — also an der EINEN Stelle, die beim Start offen ist. Quantisierung: `MusicalKey(root: rootIndex, scale: touchScale)` + `touchQuantizer`. Founder-Auftrag 2026-07-07: »das Visual in ein Multi-Touch Instrument umwandeln … wie mit den Fingern durchs Wasser«. ⚠️ **Nicht als »Touch-Instrumente« schreiben** — Chord-Pad, XY-Pad, Keyboard und Strum-Pad sind Roadmap und stehen weiter unter ⛔; was existiert, ist DIESE eine Fläche. ⛔ Bis #999 war das in KEINER Akquise-Kopie und wurde in der FAQ aktiv VERNEINT (»Dedicated touch instruments … on the roadmap«), während die Fläche beim Start offen war |
| **Licht: Art-Net + sACN** (DMX über Netzwerk), Grand Master + Blackout | EchoelLux, unicast live |
| **Immersiver Raum: ADM-OSC** Objekt-Ausgabe (`/adm/obj/{n}/*`) | `ADMOSCSender` |
| **OSC-Ausgabe** des Bio-Signals an jede Software im Netz | `OSCSender`, Adressliste in `CLAUDE.md` |
| **MIDI-Export** der erzeugten Musik als `.mid` | `MIDIFileExporter`, Tür im Export-Schacht |
| **MIDI-Eingang**: ein externer Controller spielt EINE monophone Stimme — Noten, Pitch-Bend, Press (Channel Pressure, #939) und Slide (CC 74, #942) | `BioReactiveSynthVoice` ist der EINZIGE Verbraucher von `controllerEvents`; `apply(controller:)` ruft `playNote(` genau EINMAL, auf EIN `synth`. (⛔ #943b: hier stand «`heldByController` ist ein einzelner `Bool`» — mit #943 ist das ein BERECHNETER `Bool` über einen Tasten-STAPEL, der Beleg nannte also genau das, was aufgehört hatte, einzeln zu sein. Die Monophonie sitzt im einen `synth`, nicht im Riegel.) Wächter: `TheMPEInputHasNoZonesTests` |
| **MIDI-Ausgang live**: gespielte NOTEN an dein Rig (MIDI 1.0) | `MIDIOutput`, Schalter in der Routing-Fläche (`midi.out`), Default AUS |
| **MPE-AUSGANG an Dein Rig**: Zone angekündigt, Noten über Member-Kanäle 2–16, jede mit Glide (Pitch-Bend), Slide (CC 74) und Press (Channel Pressure) | `MIDIOutput.sendMPEConfiguration()` plus die drei Sendepfade; zwei Schalter in der erreichbaren Routing-Fläche (»MPE note layout«, »Per-note expression«), beide Default AUS. **Nur MIT Richtungswort schreiben** — warum, steht in §6 |
| **Dein Rig erfährt, ob ein Körper sendet oder der Demo-Generator**: auf OSC als eigene Adresse `/echoelmusic/bio/synthetic` (1 = Demo, 0 = echter Körper), auf sACN als Quellname »Echoelmusic (DEMO)« in der Quellenliste des Pults | #639 (Batch, der Flagge geht jedem Tick voran der mindestens einen Messwert sendet) · #785 (Ereignisse, Flagge unmittelbar VOR dem Ereignis, erneut nur bei Wechsel) · #789 (sACN, das 64-Byte-Source-Name-Feld von E1.31 — das eigene Feld des Standards, nichts erfunden). Wächter: `TheWireSaysWhoseBodyTests`, `TheLightRigSeesTheSimulatorTests`. ⛔ **NIE »alle Ausgänge« schreiben**: ADM-OSC und Art-Net tragen sie NICHT, und die Gründe sind verschieden (fremder Adressraum, dessen Erweiterungsregeln hinter einer AES-Paywall liegen · `ArtDMX` hat gar kein Namensfeld, `ArtPollReply` ist ungebaut). Die sACN-Hälfte: **Geräte-Verify offen — so kennzeichnen** (ob ein Pult den Namen mitten in der Sitzung neu zeichnet, ist im Repo nicht messbar) |
| **Universeller BLE-Herzgurt** (0x180D), z. B. Polar H10 | gebaut + verdrahtet, Geräte-Verify offen — **so kennzeichnen** |
| **Apple Health** als Pulsquelle | `HealthKitBioPublisher` |
| **Offene Standards, kein SDK-Lock-in** | OSC · ADM-OSC · MIDI · Art-Net/sACN · BLE HRS |
| **Null externe Abhängigkeiten**, alles on-device | `Package.swift: dependencies: []` UND `project.yml` ohne `packages:`-Block — beide, siehe Zaun-Absatz oben |
| **Barrierefrei spielbar**: Notennamen International/Deutsch/Solfège, VoiceOver auf der Spielfläche, Atkinson Hyperlegible | #232 C/E, `EchoelValueField` |
| **Deine Stimme wird die Klangfarbe des Instruments**: Ton halten („Voice timbre" → Capture), die gemessene Farbe spielt in den Synth-Stimmen; speicherbar im Patch UND im Take (Projekt-Save/Autosave/Live Colabo), immer MIT Namens-Label | EchoelVoice #591–#593 (ausgeliefert 10.79.391) + #600 Take-Hälfte (ausgeliefert 10.79.393, Build 2510, TestFlight-Lauf 31822323904 mit ASC-Verify), gebaut + verdrahtet + wächter-gepinnt, **Geräte-Verify offen — so kennzeichnen**. Formulierung siehe §11: MESSUNG, nie „Aufnahme" |
| **Tonart-Werkzeuge für die Stimme**: „Tune to key" zieht das Mic-Monitor-Signal optional in die Session-Tonart (nur der Monitor, nie die Musik); „Follow the key" macht die Harmonizer-Stimmen diatonisch (Terz atmet mit der Tonart) | #599/#599b (ausgeliefert 10.79.391/392), Default AUS, Kammerton-treu; **Geräte-Verify offen — so kennzeichnen** |
| **Harmoniestimmen auf deiner Stimme** (zwei benannte Intervalle + Mix, nur im Monitor, Default AUS) | #841, Tür im Input-Sheet („Harmony voices"); **Geräte-Verify offen — so kennzeichnen** |
| **Granular-Textur auf deiner Stimme** (Grain-Wolke unter dem trockenen Signal, Mix/Grain/Pitch, nur im Monitor, Default AUS) | #849, Tür im Input-Sheet („Granular texture"); **Geräte-Verify offen — so kennzeichnen** |
| **Feedback-Schutz, der Pfeifen VERHINDERT statt es wegzuducken**: vier dynamische Notch-Bänder greifen pro Frequenzband, bevor ein Howl hörbar wird; Breitband-Duck nur als letzte Verteidigung | #847/#848 (`HowlDetector` + Notch-Kette im Monitorpfad); **Geräte-Verify offen — so kennzeichnen** |
| **Visual-Aufnahme + mp4-Export**: das laufende Visual wird auf dem Gerät aufgezeichnet und aus der Video-Bibliothek geteilt | `VisualRecorder` + `videoPanel` → `VideoLibraryPanelContent` |
| **Beamer/Externer Bildschirm**: das Visual bespielt ein angeschlossenes Display als eigene Bühne, das Telefon bleibt Spielfläche | `ExternalDisplayScene` (#206) |
| **Texture- und Glitter-Regler im Visual** (Korn-Tiefe + Glitzer-Menge, 0–2, Default = bisheriger Look) | #853, Fine-tune-Fläche; **Geräte-Verify offen — so kennzeichnen** |

---

## ⛔ DARF NICHT behauptet werden — und warum genau

### 1. „AUv3-Plugin", „läuft in Logic/Ableton/GarageBand", „in Deiner DAW"
**Das AUv3-Target wurde am 2026-07-24 ENTFERNT** (#121 Slice 1+2, Founder-Verdikt
„reines Instrument"). Echoel ist eine eigenständige App und **kein Plugin**. Es kann
auch keine fremden Plugins laden — das Hosting ging im selben Schritt.
`project.yml` sagt es wörtlich: *„AUv3 REMOVED 2026-07-24 (founder verdict: Echoelmusic
= pure instrument, no AUv3)"*. (⛔ Hier stand `project.yml:177` — eine Zeilennummer.
`CLAUDE.md` verbietet das Muster in dieser Datei-Familie ausdrücklich: eine zitierte
Phrase überlebt jede Verschiebung, eine Nummer zeigt nach dem nächsten Einschub auf
etwas anderes und behauptet dabei weiter, ein Beleg zu sein.)
Ein AUv3-Claim ist doppelt falsch (Ziel + Host)
und war exakt der Claim, den #158 aus der Website entfernt hat.
*Wenn ein Bild eine DAW-Spur zeigt, ist es das falsche Bild.*

### 2. Wellness, Meditation, Schlaf, Fokus, Stressabbau, Longevity, „HealthTech"
`CLAUDE.md`: **„Biofeedback ist Kern, NICHT Wellness."** Echoel ist ausdrücklich kein
Wellness-, Soundscape- oder Therapieprodukt. Das ist keine Geschmacksfrage:
Heilungs-/Organ-/Frequenz-Claims sind Alt-Last aus einem Vorgängerprojekt und eine
permanente rote Linie, und in der App steht der Satz „für Selbstbeobachtung, nicht
für medizinische Diagnose". Ein Reel, das „nutze es für Meditation und
Schlafoptimierung" sagt, widerspricht dem Text in der eigenen App.
**Erlaubt** ist die Beschreibung des Mechanismus: *„ruhiger Puls → andere Musik."*
**Nicht erlaubt** ist die Wirkungsbehauptung: *„macht Dich ruhig / hilft beim Schlafen."*
Der Unterschied entscheidet auch über die App-Store-Kategorie.

### 3. Apple Watch misst und steuert
`Sources/EchoelmusicWatch/EchoelWatchApp.swift` ist eine **95-Zeilen-Anzeige**: sie
LIEST die Werte, die das iPhone in die App-Gruppe schreibt. Die Produzenten-Hälfte
(Puls am Handgelenk → App-Gruppe → Telefon) ist **nicht gebaut** und im Kopf der Datei
als offen markiert. Dazu die harte Grenze aus `CLAUDE.md`: Watch-HR hat 4–5 s Latenz,
**niemals** Beat-Sync. Ein Hook, der mit einer pulsierenden Watch aufmacht, verkauft
die Richtung falsch herum. **Der echte Hook ist der Finger auf der Kamera** — er ist
wahr, er braucht kein Zusatzgerät, und er sieht besser aus.

### 4. „Im App Store" / Store-Link
Es gibt heute **nur TestFlight**. Erst nach der ersten Freigabe umstellen.

### 5. Drums, Beats, Sampler, Sample-Import, Video-Schnitt, RTMP-Livestream, Mehrspur-Recorder
**Das VERBOT gilt unverändert — der Nutzer kann nichts davon aufrufen.** Die Begründung
war falsch und ist der Grund, warum dieser Abschnitt jetzt drei Fälle unterscheidet
statt einen: es stand hier *„Alles entfernt oder nie gebaut"*, und „nie gebaut" ist für
zwei der sieben Einträge per `git grep` widerlegbar. Das ist exakt der Defekt, den
derselbe Commit aus §8 entfernt hat: **eine widerlegbare Begründung entwertet ein
richtiges Verbot** — wer sie prüft und kippen sieht, kippt das Verbot gleich mit.

- **Gelöscht, existiert nicht mehr:** Drums/Beats (#166/#167 — `DrumSynthVoice`,
  `LaneDrumKitVoice`, `DrumNoteMap` sind als Dateien weg), Sample-Import/Browser
  (`SampleBrowserView` mit #167 gelöscht), Video-SCHNITT (#121 Slice 3).
- **Im Code, aber nicht verlinkt:** RTMP — `BroadcastPublisher` ist ein
  `#if canImport(HaishinKit)`-Gerüst, `Package.swift` hat `dependencies: []`.
- **Gebaut und konstruiert, aber für den Nutzer TÜRLOS:** `MultiTrackRecorder`
  (`Audio/MultiTrackRecorder.swift`, in `AudioEngine` bedingungslos angelegt;
  durchgereicht nur hinter `FeatureFlags.audioLaneRecording`, und dieser Key wird nie
  an `UserDefaults.register(defaults:)` übergeben — registriert sind nur `multiRoll`,
  `voiceKindRouting`, `instrumentHome` —, löst also zu `false` auf. Offen als #204).
  Ebenso `SamplerVoice` (in `BeatPlayer` und `LaneVoiceRack` angelegt) — es gibt eine
  Sampler-Stimme, nur keine Oberfläche, die dem Nutzer Samples in die Hand gibt.

**Für Content heißt das dasselbe wie vorher: nicht behaupten.** Der Unterschied liegt
nicht im Verbot, sondern in seiner Haltbarkeit — und darin, dass „nie gebaut" eine
Session dazu einlädt, etwas neu zu bauen, das schon da ist.

### 6b. „spielt die Stimmen" (Plural) — gestrichen 2026-08-23 (#774)

Die Zeile im Wahr-Register hieß **„externer Controller spielt die Stimmen"**. Gemessen:
`git grep -n controllerEvents -- Sources` (kommentar-bereinigt) liefert außerhalb von
`EngineBus` **genau einen** Verbraucher — `BioReactiveSynthVoice`, und der ist monophon
(`apply(controller:)` ruft `playNote(` genau einmal, auf ein `synth` — #943b, siehe die Zeile in der Tabelle oben).
`PolySynthVoice` abonniert den Bus zwar, aber nicht diese Topic; die Stimme im
`LaneVoiceRack` ist laut eigenem Kommentar „NEVER subscribed to the bus".

**Es ist genau dasselbe Wort, das #548 aus `CLAUDE.md` gestrichen hat** („notes, plural —
unreachable by construction"), und es stand hier weiter in der Datei, deren einziger Zweck
es ist, falsche Captions zu verhindern. Die Zeile direkt darunter (MIDI-AUSGANG) war die
ganze Zeit peinlich genau — „gespielte NOTEN an dein Rig (MIDI 1.0)", mit Schalter und
Default. Eine Zeile ehrlich zu schreiben härtet die daneben nicht.

*Erlaubt: „steck einen Controller an und spiel die Körperstimme", „Noten und Pitch-Bend
kommen an". Nicht erlaubt: „spielt die Stimmen", „spiel Akkorde", „polyphon".*

⚠️ Nicht überkorrigieren: der Eingang ist NICHT hinter dem „Body voice"-Schalter versteckt —
`apply(controller:)` ist ausdrücklich nicht `isArmed`-gated („the performer always leads").
Ein Controller klingt sofort. Nur eben einstimmig.

### 6. MPE
Aus dem I/O-Satz gestrichen. ⛔ **Die BEGRÜNDUNG, die hier stand, ist seit #713 falsch**
(„die Schalter haben seit dem Tools-Grid-Removal keinen Schreiber") — „MPE note layout"
und „Per-note expression" sind persistiert und haben zwei Schalter in der erreichbaren
Routing-Fläche. Der Schluss hält aus einem ANDEREN Grund: **MPE OUT ist real und
schaltbar, MPE IN nicht** (#548). `MIDIBusPublisher` parst MPE-Verkehr, unterscheidet
aber keine Zonen, und `BioReactiveSynthVoice.apply(controller:)` liest `event.channel`
nirgends — es gibt also keinen Member-Kanal zu unterscheiden.

⛔ **Die BEGRÜNDUNG, die hier stand, ist mit #942 abgelaufen — der SCHLUSS nicht.** Sie
lautete: der Verbraucher laufe „für Slide (CC 74), Air und Channel Pressure in ein einziges
`break` — genau die drei Dimensionen, die MPE erst zu MPE machen". Zwei Fehler in einem Satz.
Erstens ist `.airCC` (CC 21–31) gar keine MPE-Dimension; MPE hat Pitch-Bend, CC 74 und Channel
Pressure — und Pitch-Bend klang schon immer. Zweitens klingen seit #939 (Press) und #942
(Slide) **alle drei**. Trotzdem bleibt „MPE-Eingang" verboten, weil die fehlende Hälfte nie
die Anzahl war: **eine Zone ist das, was MPE hinzufügt**, und RPN 6,6 hat auf dem Eingang
keinen Erzeuger. Ein richtungsloses „MPE"-Wort in einer Caption verspricht also weiter die
Hälfte, die fehlt.

⛔ **UND DIE REGELZEILE, DIE HIER STAND, WAR SEIT #713 ZU BREIT — gestrichen 2026-08-24
(#780).** Sie lautete *»Nicht erlaubt: MPE, per-note expression, spielt Deinen
MPE-Controller«* und verbot damit auch die Hälfte, die AUSGELIEFERT ist. Zwei Kosten,
beide konkret: »per-note expression« ist die wörtliche Beschriftung eines Schalters, den
der Nutzer auf dem Schirm sieht (`PatchbayView`) — eine Caption durfte eine sichtbare
Bedienstelle nicht benennen; und ein Rig-Besitzer las »nein«, wo die App »ja« sagt. **Der
Absatz DARÜBER sagte seit #548 das Richtige** (»MPE OUT ist real und schaltbar, MPE IN
nicht«) — die Begründung wurde nachgeführt, die Regelzeile nicht, und die Regelzeile ist
die, die ein Skript-Autor kopiert. Genau die Lücke, die #775 auf der Website geschlossen
hat und die hier einen Zyklus länger stand, in der Datei, deren einziger Zweck es ist,
falsche Captions zu verhindern (#456: jede Heimat im selben Commit).

⚠️ **Der GRUND für das Verbot bleibt gültig und trägt die neue Fassung: ein RICHTUNGSLOSES
»MPE« verspricht die fehlende Hälfte.** Deshalb ist das Richtungswort Pflicht, nicht
Geschmack — »MPE« allein bleibt verboten, »MPE-Ausgang« ist erlaubt.

*Erlaubt: »MIDI-Noten raus an Dein Rig«; »MPE-AUSGANG an Dein Rig« bzw. »MPE out« — immer
MIT dem Wort Ausgang/out; »per-note expression RAUS an Dein Rig«. Nicht erlaubt: ein
richtungsloses »MPE«; »MPE-Eingang«; »spielt Deinen MPE-Controller«; »per-note expression«
ohne Richtungswort.*

### 7. Abo, „Pro", Paywall, „Monthly/Annual Access", MRR
**v1.0 ist vollständig KOSTENLOS und zeigt KEINE Kauf-Oberfläche.** Das ist eine
protokollierte Founder-Entscheidung (2026-07-10, zweite des Tages, sie hebt das
Einmal-Pro desselben Tages auf) und steht wörtlich im Code über `WorkspaceView.body`:
Umsatz kommt erst in **v1.1** als „Echoel Live"-Jahresabo (~29,99 €, weltweite
SharePlay-Sessions) plus Event-Gebühr in v1.2. `ProUnlockView` / `EchoelStore` /
`ProGate` kompilieren, werden aber **nirgends präsentiert** — sie liegen bereit, um
dafür umgewidmet zu werden.
Ein Preis in einer Caption ist keine Übertreibung, sondern eine **Falschangabe im
App-Store-Sinn** (2.3 „Accurate Metadata") und enttäuscht jeden, der deshalb lädt.
*Erlaubt: „kostenlos". Nicht erlaubt: irgendein Preis, „Pro-Version", „Abo", „Trial".*

### 8. Tech-Stack-Behauptungen: „TCA", „RevenueCat", „SwiftData", „VideoToolbox", „HaishinKit"
`Package.swift` hat ein **leeres `dependencies`-Array** — Echoel hat heute NULL externe
Abhängigkeiten, und das steht oben in der ✅-Tabelle als eigene Behauptung.
Das klingt nach einem Entwickler-Detail, ist aber Marketing-Material, sobald ein
Text über Architektur, Investoren oder Stellen spricht — und es ist die Sorte
Behauptung, die man nicht mehr los wird, weil sie plausibel klingt.

Drei verschiedene Wahrheiten, und die Unterscheidung ist der Punkt:
- **Gar nicht vorhanden:** TCA (The Composable Architecture — wir sind SwiftUI +
  `@Observable`), RevenueCat, VideoToolbox. Null Vorkommen in `Sources/`.
- **Nur als Prosa erwähnt:** SwiftData — eine einzige Kommentarzeile in
  `SessionRecorder.swift`, die erklärt, dass wir es NICHT benutzen.
- **Im Code, aber NICHT VERLINKT:** HaishinKit. ⛔ Die erste Fassung dieses Eintrags
  schrieb „nicht im Code", und das ist mit einem `grep` widerlegbar:
  `BroadcastPublisher.swift` enthält ein `import HaishinKit` hinter
  `#if canImport(HaishinKit)`. Es ist ein Compile-Gerüst ohne Paket — die
  Marketing-Folge (nie RTMP/Livestream behaupten) bleibt dieselbe, aber die
  Begründung muss stimmen: **eine Datei, deren ganze Autorität darauf beruht, nicht
  widerlegbar zu sein, darf keine widerlegbare Begründung tragen.**

*Persistenz = `Codable` + JSON, Video-Encode = `AVAssetWriter`, StoreKit nativ.*

### 9. „Biohacking"
Gehört fachlich zu Punkt 2 und steht trotzdem hier, weil es dort **nicht** in der
Aufzählung stand und deshalb durchrutschte. Es ist die Vokabel, die Echoel in genau
die Ecke stellt, aus der die Marke ausdrücklich heraus ist: Optimierungs-Szene statt
Instrument. **Nie in Skript, Caption, Hashtag oder Titel.**

### 10. „Postet automatisch auf TikTok/YouTube/Instagram", „MCP in der App"
Die App **veröffentlicht nichts**. Sie NIMMT auf und EXPORTIERT (`VisualRecorder`,
Video-Panel mit mp4-Teilen, MIDI-Export) — die Verteilung passiert danach von Hand
oder über diese Pipeline auf einem Rechner.
Drei unabhängige Gründe, damit die Behauptung nicht in anderer Form wiederkommt
(die beiden letzten sind Aussagen über FREMDE Plattformen, Stand 2026-07-31 — sie
altern, ohne dass es hier jemand merkt; vor einer Kampagne kurz nachsehen):
**MCP ist ein Agenten-Host-Protokoll, keine App-Fähigkeit** (es verbindet ein Modell
mit Werkzeugen — eine iOS-App „macht" kein MCP); die **Posting-APIs der Plattformen
sind gated** (eigener Review je Plattform, OAuth, Business-/Creator-Konten, bei TikTok
ein bestandenes Audit — Privatkonten weitgehend gar nicht); und ein Multi-Plattform-
Publisher wäre ein **zweites Produkt** neben dem Instrument.
*Erlaubt: „das fertige Video teilen". Nicht erlaubt: „postet für Dich".*

### 11. Stimme: „nimmt Deine Stimme auf", „Voice Cloning", „AI-Voice", „Text-to-Speech", „Autotune auf der Musik"
Die Stimm-Fähigkeit ist eine **MESSUNG, keine Aufnahme** — das ist die eine
Formulierung, an der hier alles hängt. `VoiceTimbreProfiler` misst eine
Spektral-Hüllkurve (**64 Zahlen**), das Audio selbst wird **nie gespeichert**;
das Mikrofon-Versprechen der App bleibt wörtlich wahr, und ein Reel, das „records
your voice" sagt, macht aus einem Privacy-Vorteil einen Privacy-Verdacht.
Ebenfalls nicht behaupten, weil per Entwurfs-Grenze ausgeschlossen (EchoelVoice
v1, protokolliert): **kein TTS**, **kein Stimm-Klon / keine Synthese Deiner
Sprechstimme**, **kein Import fremder Stimmen** — die Farbe kommt vom lebenden
Spieler am Gerät, und ein gespeicherter Patch trägt immer ein Namens-Label
(Share-Label-Gesetz: nie anonym, keine Misattribution). Und „Tune to key" ist
**Monitor-only**: es stimmt, was Du im Kopfhörer von DIR hörst — die komponierte
Musik läuft nicht durch einen Autotune. *Erlaubt: „das Instrument klingt nach
Dir", „gemessen, nie aufgenommen". Nicht erlaubt: „AI voice", „clones your
voice", „records you", „Autotune auf dem Track".*


### 12. Atemtiefe und LF/HF als Klang-Abbildung — der Kohärenz-TREND ist seit #813 WAHR
**Zwei Bio-Kanäle bewegen heute NICHTS, und sie klingen in einer Caption besonders gut** —
genau deshalb steht das hier. Gemessen: `breathDepth` und `lfHf` sind an BEIDEN
Konstruktionsstellen (`BioReactiveSynthVoice`, `PolySynthVoice`) auf das Literal `0.5`
festgenagelt. Der Atemtiefen-Faktor ist damit auf jedem Frame exakt 1,0, und `lfHfRatio`
wird im Rumpf gar nicht gelesen. `applyBioReactive` sagt es an der Stelle selbst: *„must
not be claimed as live in any user-facing copy."*

⛔ **Hier standen DREI Kanäle, und der dritte war beim Audit 2026-08-28 seit zwei Wochen
falsch:** `coherenceTrend` hat seit **#813** einen echten Produzenten — `Core/CoherenceTrend`
leitet aus der Kohärenz-HISTORIE eine Änderungsrate ab, und beide Konstruktionsstellen
übergeben `coherenceTrend: trend` statt der Literal-0 (nachmessbar:
`git grep -n "coherenceTrend: trend" -- Sources` → zwei Treffer). **„Der Kohärenz-Trend
morpht die Klangform (steigend/fallend)" ist damit ERLAUBT** — mit der ehrlichen Fußnote,
dass die SKALA des Effekts eine Schätzung ist (NEEDS-FOUNDER-VERIFY am Gerät). Diese Datei
war die Fläche, die #813 NICHT mitzog, und sie hat damit vierzehn Tage einen wahren Claim
verboten und eine widerlegte Messung behauptet — genau der Defekt, vor dem §5 warnt: eine
widerlegbare Begründung entwertet auch ein richtiges Verbot.

**Das ist die Behauptung mit den meisten Fundstellen in der Geschichte dieses Repos.** Sie
wurde dreimal getilgt: #496 aus der App-Kopie (drei Wächter, alle lesen nur Swift), #755
aus `docs/overview.html`, #757 aus dem **englischen** App-Store-Text — wo die deutsche
Fassung derselben Anzeige die ganze Zeit ehrlich war. Diese Datei war die vierte Fläche und
hatte keinen Eintrag; ein Skript-Autor, der sie liest, hätte nichts gefunden, was ihn
aufhält.

⚠️ **LF/HF wird sehr wohl BERECHNET** (`HRVCoherence`, Welch + Lomb-Scargle) — die FAQ nennt
das korrekt „LF/HF-Analyse". **Analysiert ist nicht abgebildet.** Verboten ist der Pfeil,
nicht das Wort.

**Was stattdessen stimmt — die geprüfte Vier-Kanal-Tabelle** (`AlwaysOnBioChannel.shapedParameters`):
Kohärenz → Filter-Cutoff · Brillanz · Harmonizität · Rauschanteil ·
HRV → Brillanz · Herzfrequenz → Vibrato (Tiefe UND Rate) · Brillanz ·
Atem**phase** → die Amplituden-Schwelle · **Kohärenz-Trend → Klangform-Morph (#813)**.
Daraus zitieren.
*Erlaubt: „Dein Atem lässt den Klang anschwellen und wieder absinken", „wird dein Körper
ruhiger, verschiebt sich die Klangfarbe". Nicht erlaubt: „Deine Atemtiefe formt das
Rauschen", „LF/HF kippt das Spektrum".*

---

## Woher die Punkte 7–10 kommen — und was das über diese Datei sagt

Am **2026-07-31** legte der Founder ein durchdachtes Strategiepapier vor. Es enthielt
in einem Dokument: ein **AUv3-Plugin** als Content- und Umsatzsäule (Punkt 1, seit
2026-07-24 gelöscht), **TCA** und **RevenueCat** als bestehende Architektur (Punkt 8,
null Codezeilen), **watchOS-Einbindung** als ausgelieferte Eigenschaft (Punkt 3, Embed
in `project.yml` blockiert), **„Biohacking"** als Content-Fokus (Punkt 9) und ein
**Abo-Modell** als nächsten Schritt (Punkt 7, gegen die eigene Entscheidung des
Founders).

Fünf Falschbehauptungen, gut geschrieben, plausibel — und **nur eine davon** (AUv3)
stand vorher in dieser Datei. Die Lehre ist nicht „mehr Zeilen", sondern eine
**zweite Achse**: bis hierhin listete die Datei nur FEATURES. Erfunden werden aber
genauso zuverlässig **Tech-Stack**, **Preis/Geschäftsmodell** und **Vertriebswege**,
weil ein Modell (oder ein Berater) sie aus dem Umfeld ähnlicher Apps ergänzt, wo sie
üblich sind. Wer hier einen Punkt ergänzt, prüfe deshalb nicht nur „kann die App
das?", sondern auch **„kostet sie das?", „ist das im Stack?", „geht das da raus?"**

---

## Sprache

- Marke: **Echoel**. Nie „BLAB", „Vibrational Force", nie Heilfrequenzen, Chakren, Solfeggio.
- **Wissenschaft zuerst:** lesbare Zahl vor Deko-Visual. HRV-Resonanz ist zitierbar
  (Lehrer/Vaschillo, Goessl 2017) — als *Forschungslage*, nie als Versprechen.
- Blitzrate in jedem Videomaterial **≤ 3 Hz** (W3C WCAG, Epilepsie). Das gilt auch für
  den Schnitt, nicht nur für die App.
- Diese Pipeline ist **PIPELINE-ONLY**: sie fasst `Sources/` niemals an.
