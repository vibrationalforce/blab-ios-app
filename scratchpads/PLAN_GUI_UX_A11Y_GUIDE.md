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

## BOARD (Synthese aus Phase A — wird nach Audit-Rückkehr gefüllt)

_(leer bis Audit-Synthese)_
