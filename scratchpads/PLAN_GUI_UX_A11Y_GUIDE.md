# PLAN — Gesamte GUI: User Experience + Accessibility + abschaltbarer Guide

**Founder-Auftrag (2026-08-15, wörtlich):** „Gesamte GUI überarbeiten für User expierence
und accessibility mit an und auschaltbatem Guide der hilft die App zu bedienen und zu
verstehen"

**Status: PHASE A LÄUFT (drei parallele Audits), Plan lebt.** Dieses Dokument ist die
eine Quelle für die Reihenfolge; jede Scheibe bleibt Ralph-klein und einzeln shipbar.

---

## Lesart des Auftrags (PM-Entscheidung unter stehender Delegation)

Drei Aufträge in einem Satz, in absteigender Neuheit:
1. **Der GUIDE ist das neue Feature** — an-/abschaltbar, erklärt Bedienung UND Konzept
   („verstehen": der Körper spielt das Instrument — das ist nicht selbsterklärend).
2. **Accessibility** ist messbare, gesetzesnahe Arbeit (Dynamic Type, VoiceOver,
   Tap-Targets, Kontrast, Reduce Motion) — hier liegt der ehrlichste Rückstand; CLAUDE.md
   nennt den AX1-Chrome-Clamp selbst „the single largest accessibility defect in the app".
3. **„Gesamte GUI überarbeiten"** heißt NICHT Redesign-Big-Bang (das wäre der
   DMMW-Fehler in UI-Form), sondern: gemessene Defekt-Liste, dann Scheibe für Scheibe.

## Nicht verhandelbare Gesetze (gelten für JEDE Scheibe dieses Plans)

- **Sheet-Ketten-Decke:** EchoelStudioView-Kette ≤ 14 Präsentations-Modifier (dateiweit
  16, beide gepinnt). Der Guide bekommt KEINEN neuen Sheet — er ist ein Overlay-Layer im
  WorkspaceView-ZStack (der existiert schon) oder nutzt einen toten Slot.
- **Freeze-Gesetz:** kein 10-Hz-Read in Root/Ancestor-Bodies; Guide-Zustand ist
  niederfrequent (Toggle + Schritt-Index), Leaf-Views für alles Live-Bio.
- **Uncodixfy:** keine Glassmorphism-Coach-Marks, Radien ≤ 16, solide Füllungen; der
  Guide sieht aus wie die App, nicht wie ein Tutorial-Theme.
- **EchoelValueField-Gesetz** unberührt; **Rausch-Triade READ-ONLY**; **Flash ≤ 3 Hz**.
- **Kein Heilungs-/Wellness-Vokabular** im Guide-Text (Brand-Gesetz).
- Founder-gated bleibt founder-gated (project.yml, Info.plist, Workflows).

## Phasen

### Phase A — MESSEN (läuft, 3 parallele Read-only-Audits)
- **A11y-Audit:** Dynamic-Type-Clamps (welche tragen, welche nicht) · fehlende
  VoiceOver-Labels/Hints/Values · Tap-Targets unter 44 pt · Reduce-Motion-Lücken ·
  Kontrast-Kandidaten. → Top-15, je S/M/L.
- **UX-Audit:** Onboarding-Ende → erster Ton · Chip-Jargon · starre Panels (6 von 10
  reflowen nicht, #292) · Auffindbarkeit versteckter Features (Play-Surface, Voice,
  Monitoring, Export) · Zustands-Lesbarkeit („was treibt gerade den Klang?") ·
  stille Sackgassen. → Top-15, je S/M/L.
- **Guide-Substrat:** vorhandene Erklär-Texte (LearnView/LearnLibrary, Onboarding,
  Fußnoten) · bester Overlay-Mount ohne neuen Sheet · bestes Toggle-Zuhause ·
  Anchoring-Präzedenz · die eine Chip-Definitionsquelle (#416).

**Synthese:** EIN ranked Board hier im Dokument (ersetzt die drei Rohlisten), jede Zeile
→ eine Ralph-Scheibe.

### Phase B — GUIDE v1 (das neue Feature, 3–4 Scheiben)
Architektur-Entscheid (Council unten):
- **B1 — Schalter + Skelett:** `@AppStorage("guideEnabled")`, Tür im bestehenden
  Learn-/Utility-Bereich (KEIN neuer Sheet), Overlay-Layer im WorkspaceView-ZStack,
  leerer Karten-Host, VoiceOver-sauber, Dynamic Type ungeclampt. Wächter: Tür existiert,
  Kette wächst nicht, Overlay liest kein Hochfrequenz-Observable.
- **B2 — Inhalt „Bedienen":** kartenbasierte Tour über die realen Flächen (aus der
  Chip-Quelle enumeriert, #416): Start · Puls-Pille · Chips · Transport · Visual ·
  Speichern/Export. Kurze Sätze, App-Sprache (EN-UI), keine Screenshots (Wartungsfalle).
- **B3 — Inhalt „Verstehen":** die Bio-Geschichte (Kamera-rPPG → Kohärenz → Klang/Farbe;
  ehrliche Wissenschafts-Sprache aus BioScienceInfo wiederverwenden, kein Health-Claim).
- **B4 — Kontext-Hilfe (optional, nach Founder-Probe von B1–B3):** „?"-Modus, der beim
  Antippen eines Chips die Karte der Fläche öffnet statt der Fläche selbst.

### Phase C — A11y-Scheiben (aus dem Board, je 1 Zyklus)
Erwartete Spitzenkandidaten (werden vom Audit bestätigt/verworfen):
- C1: AX-Clamp-Abbau im Chrome (der benannte größte Defekt) — vorsichtig, minHeight-Muster
  ist da, `topBar` wächst schon; prüfen, was die restliche Kette blockiert.
- C2: VoiceOver-Lücken (Labels/Values/Hints) in Batch-Scheiben pro Fläche.
- C3: #292-Fortsetzung — die 6 starren Panels reflowfähig machen (bewährtes
  AdaptiveCardGrid-Muster, `visualPanel`-Vorbild mit spacing-Argument).
- C4: TapTargetFloorTests-Nachträge aus dem Audit.
- C5: Kontrast-/Reduce-Motion-Nachzügler.

### Phase D — UX-Scheiben (aus dem Board)
Nach dem Guide, weil der Guide die billigste Antwort auf Auffindbarkeit ist und erst
danach klar ist, welche UX-Debts WIRKLICH Umbau brauchen statt Erklärung.

## Council (Kurzform, protokolliert)

- **Architect:** Overlay im bestehenden ZStack, Inhalte aus der einen Chip-Quelle — kein
  neues Subsystem, kein neuer Kopplungspunkt. Sorge: Guide-Inhalt darf nicht zur zweiten
  Wahrheitsquelle über Features verrotten → Inhalte aus Code-Enums ableiten, wo möglich.
- **Shipper:** Big-Bang verboten; B1 ist in einem Zyklus shipbar, jede C-Scheibe einzeln.
  Sorge: Audit-Listen können ausufern → hartes Top-15 pro Audit, Board deckelt.
- **Skeptic:** Der teuerste Fehler wäre ein Guide, der veraltet und dann LÜGT (die
  CLAIMS-Lektion in UI-Form). → Guide-Texte bekommen Wächter gegen die Feature-Wahrheit
  (kein Text über eine Fläche, die es nicht gibt); lieber weniger Karten, alle wahr.
- **User-Advocate:** Der Founder sagt „bedienen UND verstehen" — reine Coach-Marks
  erklären nur WO, nicht WARUM. → B2 und B3 sind getrennte Inhalte, beide Pflicht.
- **DSP Purist:** unberührt, solange der Guide keinen Audio-Pfad anfasst — tut er nicht.
- **Vision-Keeper:** Guide-Sprache = Instrument, Körper, Wissenschaft; nie Wellness/Esoterik.

**Verdikt: PROCEED.** Reihenfolge A → B1..B3 → C (Board-Reihenfolge) → D. B4 und alles
Große in D erst nach Founder-Geräteprobe des Guides.

## Offene Punkte (ehrlich)

- Audit-Ergebnisse ausstehend → Board unten leer, bis die drei Agenten zurück sind.
- AX-Clamp-Abbau (C1) kann sich als L erweisen (Layout-Umbau) — dann eigene Planung.
- Geräteprobe entscheidet Guide-Tonalität; Texte sind bewusst founder-tunbar gehalten.

## ⭐ ULTRAACCESSIBLE DESIGN — die Messlatte (Founder 2026-08-19, wörtlich: „Ultraaccessible Design")

Barrierefreiheit ist ab jetzt die OBERSTE Messlatte dieses Programms, nicht eine Rubrik.
Jede GUI-Scheibe wird gegen diese acht Punkte geprüft (decisions.csv 2026-08-19):

1. **Kein Gesten-only.** Jede Drag/Pinch/Long-Press-Funktion hat eine benannte
   VoiceOver-Action (das #619-Muster: Move-Actions neben dem Drag). Gilt auch für
   Switch Control / Voice Control: benannte Actions sind die eine Tür für alle drei.
2. **Kein Farb-only.** Bedeutung nie allein durch Farbe (WCAG 1.4.1); Kontrast-Grenzen
   1.4.3 (Text) und 1.4.11 (UI-Komponenten, borderStrong-Rollout Zeile 13).
3. **Kein Sicht-only.** Der Kern-Loop — Start → Körper spielt → Hören → Export — ist
   komplett mit VoiceOver bedienbar; Zustandswechsel (Bio lockt, Take fertig, Export
   geschrieben) werden angesagt (Announcement) oder haptisch gespiegelt.
4. **Kein Zeit-only.** Keine Interaktion verlangt schnelle Reaktion; nichts verschwindet,
   bevor es gelesen wurde (das #604-Retire-Gesetz ist ein Spezialfall hiervon).
5. **Dynamic Type ungeclampt** bis AX5, wo Text trägt — minHeight statt height (#353),
   Reflow statt Clipping (#292-Fortsetzung, Zeile 15).
6. **Tap-Ziele ≥ 44 pt effektiv** (TapTargetFloorTests-Programm; gemessene Decken wie
   A11y#8 sind benannte, dokumentierte Ausnahmen).
7. **Reduce Motion respektiert · Flash ≤ 3 Hz** (bestehendes hartes Gesetz).
8. **Eine Vokabel pro Funktion** (#616): Zeiger, Control und VO-Label teilen die
   Schreibweise — für kognitive Zugänglichkeit und funktionierende Suche.

Konsequenz für die Reihenfolge: A11y-Zeilen (11–13, 15 + Audit-Nachträge) rücken vor
reine UX-Komfort-Zeilen. Ein Tiefen-Audit (2026-08-19, Workflow) füllt das Board über
die Top-15 hinaus; seine bestätigten Funde landen als neue Zeilen hier.

## BOARD (Synthese aus Phase A — 3 Audits zurück 2026-08-15, je Top-N, dedupliziert)

**Phase B — Guide: B1+B2 GEBAUT in dieser Session** (GuideOverlay + Keystore-Key +
utilityRow-Toggle + Wächter `TheGuideHasADoorTests`; Inhalte = LearnLibrary „Start Here",
6 wächter-gepinnte Karten, null neue Copy). B3 („Verstehen"-Karten aus BioScienceInfo)
+ B4 (Kontext-Modus) warten auf Founder-Probe von B1/B2.

**Reihenfolge C/D (PM-Rang: Nutzer-Impact × S zuerst; Quellen: A11y-/UX-Audit-Reports
in den Task-Transkripten dieser Session, jede Zeile mit file:line dort):**

| # | Scheibe | Quelle | Aufwand |
|---|---------|--------|---------|
| 1 | Instrument-Hint-Overlay re-armen (einmal-für-immer → bis zur ersten erfolgreichen Bio-Session) | UX#2 | S |
| 2 | Monitor-Banner deckt „Engine gestoppt"-Fall (Toggle an, nichts läuft) | UX#9/A11y-Wissen #485 | S |
| 3 | BioStrip `minimumScaleFactor` 0.6 → 1.0 bei AX-Größen (Anti-Fix raus) | A11y#5 | S |
| 4 | Chip-Strip Overflow-Hinweis (Trailing-Fade; Field/Save unsichtbar auf 393 pt) | UX#5 | S |
| 5 | First-Run-Erklärzeile unter quickActionRow („warum sind die Kacheln grau") | UX#7 | S |
| 6 | Bio-Quellen-Tür sichtbar („Source…"-Button im bioPanel statt nur Long-Press) | UX#4 | S |
| 7 | ✅ #617/#617b: Tap-Target-Batch — Video-Trio (Play-Outset; Share/Delete 44-Frame+contentShape) · Narration-Disclosure (min34+Outset; ⚠ Fläche türlos, #326 — Fix vererbt sich) · drei 30-pt-Chips → min34 (Explore in den Label verlegt, #485-Gesetz) · **A11y#8 NICHT gebaut: gemessene Decke** (Never-shed-Floor 152 > ≈147-Kleinstkarte; Arithmetik am `ChromeCost.iconButton`-Doc, Wiedereröffnung nur mit Kleinkarten-Redesign). Drei Wächter-Fälle. **Review-Nachträge fürs nächste Audit:** `LiveColaboView` Invite (fixed height 30, #353-Klasse) · FVW-Vollbild-„Studio"-Chip (fixed height 30) | A11y#3/6/7/8 | ✅ |
| 8 | ✅ #618: Ready-Satz nennt Play · camera light · Bluetooth strap (Chooser-Vokabular #616); Wächter `TheReadyPageNamesTheFirstActTests` (Tokens, nicht Satz) | UX#3 | ✅ |
| 9 | ✅ #619: vier benannte Rotor-Actions am Logo-Handle („Move to …"-Ecken), Snap-Mathe pur in `FloatingVisualLayout.snapCenter` (Margin-Gesetz von `clamp`, Band-Lift von `defaultCenter` — „bottom right" = Dock-Platz); Namen als `SnapCorner`-rawValues, EINE Definition; nur floating (Fullscreen pinnt, Builder emittiert nichts, Label ehrlich); Drag bleibt. Wächter `TheFloatingWindowMovesWithoutADragTests` (4 END-TO-END + Scans + Gegengewichte). VO-Ansage = Geräteprobe. Review-Nachlese: siehe SESSION_LOG Takt 33 | A11y#4 | ✅ |
| 10 | ✅ #620: beide Panel-Untertitel nennen die Features mit dem EXAKTEN Control-Wortlaut („Production character · Follow the key" · „Shape the timbre — exact to 0.0001 · Voice timbre", #616-Vokabular); Wächter `ThePanelSubtitlesNameTheirDeepFeaturesTests` koppelt Zeiger↔Control beidseitig. Review-Nachlese: siehe SESSION_LOG | UX#12/13 | ✅ |
| 11 | Puls-Pille liest sich als Taste (borderStrong-Grammatik) | UX#15 | S |
| 12 | StudioZoom „Follow system text size"-Reset (Pinch koppelt sonst für immer ab) | A11y#9 | S/M |
| 13 | border→borderStrong-Rollout, beurteilte Batches (≈60 Controls, WCAG 1.4.11) | A11y#2/#10 | M |
| 14 | „Was treibt den Klang"-Status-Leaf (tempoSource · Bio-Kanäle · Body-Voice · Monitoring · Guard) | UX#8/14 | M |
| 15 | #292-Fortsetzung: die 6 starren Panels (bioPanel · videoPanel · tempoTools · master · effects · utilityRow) | UX#11/A11y | M (S je Panel) |
| 16 | AX-Clamp-Abbau Chrome (A4-Feld stapeln → Decke schrittweise heben) — NEEDS-FOUNDER-VERIFY | A11y#1 | M |
| 17 | Founder-Look-Runde (EIN Screenshot-Paket): Start-Chip im Vollbild · Record-Glyph · „Field"-Benennung | UX#1/6/10 | Founder |
| 18 | ✅ #621/#621b: **Ultraaccessible-Audit A (VO-Werte-Batch, 4 Funde):** Sound-Preset-Menü + Mood-Preset-Menü ohne `accessibilityValue` (aktiver Name unhörbar; Haus-Muster = Bio-Source-Menü :3033) · Tuning-Banner `.combine` verschluckt den „Standard"-Rettungsknopf samt Hint (:2409) · „Describe it"-TextField ohne Label (Platzhalter „warm lush pad" wird als Name gelesen, :11302) | UA-Audit 2026-08-19, verifiziert | S |
| 19 | **Ultraaccessible-Audit B (minHeight-Batch, 5 Funde):** sechs textführende Pillen mit hartem `.frame(height:)` in EchoelStudioView (Start :3024; zuerst die zwei Preset-Menüs :6533/:7128) · FVW-Vollbild-„Studio"-Chip (:1001, 30 pt hart + 30-pt-Ziel) · LiveColabo „Invite" (:188) · BodyTempoField-Kompakt-Readout 76×32 beidachsig hart (:228) · AudioDegradedRow „Retry" 28 pt hart (:79) — je Cluster eine Ralph-Scheibe, minHeight-Rezept :2850 | UA-Audit 2026-08-19, verifiziert (deckt die zwei #617-Nachträge ab) | S/M |
| 20 | **Ultraaccessible-Audit C:** Body-driving-Tempo-Zustand ist tint-only (accent vs. text 1.37:1) UND VoiceOver behauptet „driven by your body" auch ohne Signal — `followingSpoken` zustandsbewusst + ein sichtbares Wort (BodyTempoField :226) | UA-Audit 2026-08-19, verifiziert, Bar-Punkte 2+3 | S |

Explizit GEKLÄRT von den Audits (nicht erneut auditieren): EchoelValueField ist
VoiceOver-vollständig (adjustable) · Reduce-Motion-Abdeckung breit · Text-Kontrast via
dim=0.65 + ThemeContrastTests erledigt · türlose Flächen aus dem Ranking ausgeschlossen.

**Ultraaccessible-Audit LOWS (registriert, nicht dringend — 9):** FX-Deko-Symbole nicht hidden (EchoelFXView :802) · Narration-Disclosure ohne expanded-State (:3272) · ImmersiveStageView-Pucks drag-only OHNE Accessibility (türlos heute — CRITICAL-Falle für den Tag der Tür, :159) · feste Wert-Spalten truncaten bei AX (:5621) · FVW-Mini-Transport Playing-State nur Füllfarbe (:75) · Patchbay-Inkompatibel-Glyph 1.16:1 unsichtbar (:386) · InstrumentHintOverlay verletzt „Hidden means INERT" (:1438) · Onboarding-Slide ohne Reduce-Motion-Gate (:317) · Record-Start unbestätigt eyes-free (:2102). Dazu 2 widerlegte Funde (Verifikation hat sie gekippt — nicht erneut einreichen ohne neue Messung).
