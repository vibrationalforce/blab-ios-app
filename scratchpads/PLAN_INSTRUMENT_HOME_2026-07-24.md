# PLAN — Home = das ALTE „create from within"-Interface, KEINE Timeline (Founder 2026-07-24)

**Founder, wörtlich:** „Nur das Beste von Instrument komplett sichere Marketing Strategie
wir schon öfters rausgefundenen keine Timeline etc nur das alte Interface mit create from
within. Nur die save gut klingenden Genres ohne den klingt plötzlich alles gleich bug."

Verfeinert das Reines-Instrument-Verdikt (#121): das SICHTBARE Produkt = der alte
`EchoelStudioView`-Generativ-Flow („create from within") als Home, KEINE Timeline/DAW-
Oberfläche. Plus: nur kuratierte gut-klingende Genres, Konvergenz-Bug bleibt weg.

## Ground-Truth (read-only Explore-Agent 2026-07-24, verifiziert file:line)
- **Home HEUTE = Timeline.** `EchoelmusicApp` → `WorkspaceView` → `SurfaceHost`
  (`SurfaceSwitcher.swift:114-175`) rendert `ArrangeTimelineView()` (Timeline, default
  `timelineExpanded=true`, `:127`) als füllenden Canvas; `EchoelStudioView()` sitzt DARUNTER,
  auf die Chip-Leiste geschrumpft. Darüber öffnet `FloatingVisualWindow` per
  `FeatureFlags.instrumentHome` (default ON) beim Kaltstart Vollbild.
- **„create from within"** = der `toggleBiofeedback()`-Generate-&-Play-Flow. Der Button mit
  genau diesem Label lebt in `EchoelStudioView.swift:1098-1112` (`startButton`), ist aber
  UNMOUNTED (getriggert heute vom Header-Puls-Pill via `.echoelToggleBio` → `:512`).
- **`EchoelStudioView.body`** (`:487-597`) = `menuBar`-Chip-Row (immer) + eine BEDINGTE Zone,
  die NUR bei offenem Dropdown/Session rendert (`:563`) — idle also nur die Chip-Leiste. Die
  alten Builder (`startButton :1098`, `moodPadsSection :1069`, Tuning-Banner, Composition) sind
  ALLE unmounted-aber-kompilierend (`:572-580`) — reversibel, nicht gelöscht.
- **Render-Sicherheit:** `EchoelStudioView` ist DIE metadata-limit-/freeze-sensible View
  (~18-Modal-Kette, Black-Screen-Gesetz). Der Body ist zuletzt GESCHRUMPFT (Headroom da), aber
  jedes wieder-gemountete Branch kann ihn regrowen → inkrementell, AnyView-erased, je Slice
  Compile-Gate + Gerät.
- **Genre-„alles klingt gleich"-Bug = BEREITS GEFIXT + aktiv, nicht flag-gated:**
  `BioComposer.swift:1446-1487` (harmonischer Anker: Genre-eigene Progression ab Kohärenz 0.7,
  FLOOR 0.34 — selbst voll erregt bleibt Genre-Identität) + `MusicStyle.swift:246-382`
  (rhythmische Signatur/hatRate/ChordArticulation pro Genre, überlebt den Calm-Strip).
  CI-getestet (#78/#81/#82). → Wenn der Founder es AUF DEM GERÄT noch hört, ist es ein
  Build-/Device-Thema, kein offener Code-Bug.
- **Genres = 23** (`MusicStyle.swift:123-145`), kuratiert per `Category.genres` (`:97-104`);
  KEIN user-„saved"-Store — die App ging bewusst von „curated-6" (2026-07-08) zu „alle rein,
  logisch sortiert" (`:74-77`). „Nur die gut-klingenden" = eine KURATIONS-Entscheidung
  (Edit an `Category.genres`/`allCases`) — welche 23→Teilmenge ist **Founder-Urteil**.

## Council-Verdikt (schnell)
- **Architect:** kohärenter Revert — die alten Builder wiederverwenden, kein neuer Code. Sorge:
  Metadata-Limit — Branches EINZELN wieder-mounten, je Slice Gate + Gerät.
- **Vision-Keeper:** „create from within" IST die Marke (Körper generiert von innen). On-vision.
- **Skeptic:** der Founder TESTETE „instrument-first, leer" (07-11) und mochte es NICHT — weil
  Spur-Features unsichtbar wurden. Jetzt gibt es KEINE Spur-Features mehr (reines Instrument),
  also entfällt der Einwand — ABER: erst die Generativ-UI RICH machen, DANN die Timeline raus,
  nie eine leere Chip-Leiste als Home hinterlassen. Und Metadata-Regression ist der #1-Blocker.
- **Shipper:** reversible Slices, eine/Zyklus, Gate-grün. TestFlight-Freeze → jede Slice
  NEEDS-FOUNDER-VERIFY (Launch-UX nicht sandbox-verifizierbar).
- **User-Advocate:** Founder hat das „öfters" verlangt — entschlossen, aber sicher liefern.
→ **Gate: proceed, PLAN-first, RICH-vor-leer, je Slice Gerät.**

## Slices (reversibel, eine/Zyklus, Gate-grün + Reviewer, NEEDS-FOUNDER-VERIFY je Slice)
1. **H1 — Generativ-UI zurück in `EchoelStudioView` (RICH home).** Den `startButton`
   („Create from Within") + den Kern-Generativ-Block (Mood/Composition-Einstieg) wieder in die
   idle-Zone mounten, sodass das Instrument idle NICHT nur eine Chip-Leiste ist. **Render-Regeln:**
   KEIN neues `.sheet`/`.fullScreenCover` (Slot wiederverwenden), AnyView-erased, KEIN 10-Hz-Bio-
   Read im Body — inkrementell, Compile-Gate je Schritt. swiftui-render-safety-Skill laden.
2. **H2 — Timeline nicht mehr Default-Home.** `workspace.timelineExpanded` default `true→false`
   (Founder-autorisiert — die `SurfaceSwitcher.swift:125`-Sperre „nicht ohne frischen Founder-Ask"
   ist jetzt erfüllt). Instrument füllt den Home; Timeline nur noch per Leiste erreichbar.
   NUR NACH H1 (sonst leerer Home = der abgelehnte Zustand).
3. **H3 — Timeline ganz raus aus `SurfaceHost`.** `ArrangeTimelineView()`-Mount entfernen →
   Home = `EchoelStudioView` allein. (= Epic #121 Slice 4 „DAW-UI-Removal"; konvergiert hier.)
4. **H4 — Chrome reconcilen.** Klären, ob das alte Interface Genre/Tempo wieder selbst zeigt
   oder `CompositionHeaderStrip`/`TransportBar` sie behalten (Founder-Gerät entscheidet).

## Genre (parallel, Founder-gated)
- **Bug:** KEIN offener Code-Bug — Konvergenz-Fix ist drin (s.o.). Nur device-verify nötig.
- **Kuration:** „nur die gut-klingenden Genres" braucht die Founder-Liste (welche der 23 bleiben)
  — ODER Autorisierung, auf die dokumentierte „six-calm"-Kuration zurückzugehen. Ohne Liste NICHT
  raten (reversibel als `Category.genres`-Edit, keine Enum-Löschung).

## Status
- ✅ **H1+H2 GESHIPPT** — Commit `040b84b`, beide echten Gates grün (Xcode Compile + CI/CD),
  ui-state-reviewer PASS auf alle 5 Render-Checks (Sheet-Kette byte-identisch 12+2, kein 10-Hz-
  Read, valide Struktur, kein Doppel-Modal, @AppStorage-Flip in bereits-unterstütztem Zustand).
  H1: `startButton` („Create from Within") zurück in `EchoelStudioView.body` (AnyView, kein
  Sheet, nur `running`-@State). H2: `timelineExpanded` default `true→false` (Founder-Ask erfüllt).
  **NEEDS-FOUNDER-VERIFY**: Launch-UX + Metadata-Runtime nur am Gerät verifizierbar (Compile-Gate
  beweist Build, nicht das Metadata-Budget). Nächster TestFlight nach Freeze-Lift → Founder-Pass.
- ✅ **H3 GESHIPPT** — Commit `2f8dba1`, beide echten Gates grün (Xcode Compile + CI/CD).
  „refactor: remove Arrange timeline from home". Der
  `ArrangeTimelineView()`-Mount + die Fold-Leiste + `workspace.timelineExpanded`-@AppStorage +
  der `timelineBar`-Builder sind alle raus; `SurfaceHost` ist jetzt ein statischer Wrapper, der
  NUR `EchoelStudioView` mountet. Konvergiert mit #121 Slice 4 („DAW-UI-Removal"). Rein
  SUBTRAKTIV → schrumpft den composed tree (kann das Metadata-Budget nur entlasten, nie
  vergrößern — Black-Screen-Gesetz); `SurfaceHost` liest kein @Observable/@AppStorage mehr →
  rebuildet nie (Freeze-Gesetz trivial safe); H7-Invariante trivial gehalten (`EchoelStudioView`
  = einziges Kind). `ArrangeTimelineView`/`SurfaceSwitcherBar` bleiben im Code, unmounted,
  reversibel — KEINE Datei-Löschung. ui-state-reviewer PASS auf alle 5 Render-Checks; stale
  WorkspaceView-Kommentar mitgezogen. **NEEDS-FOUNDER-VERIFY** (Launch-UX nur am Gerät,
  TestFlight-Freeze).
- ▶ **H4 — Chrome reconcilen** (nächster Zyklus): klären, ob das alte Interface Genre/Tempo
  wieder selbst zeigt oder `CompositionHeaderStrip`/`TransportBar` sie behalten — Founder-Gerät
  entscheidet. **Genre-Kuration** (#125) bleibt Founder-gated (Keep-Liste).
