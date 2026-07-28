# PLAN — Visual auf externem Bildschirm / Beamer (#206)

**Founder-Ask 2026-07-28:** „Mir geht's dabei drum das man das Bild für die visuals für
einen anderen Bildschirm, Beamer etc nutzen kann. Es soll trotzdem vom iPhone aus spielbar
sein sprich es soll gedoppelt werden oder wäre das dann AirPlay oder wie macht man das?"

**Founder-Entscheidung (AskUserQuestion, 2026-07-28):** „Ja, eigene Ausgabe-Szene bauen" —
damit ist die Info.plist-Änderung ausdrücklich freigegeben.

---

## Warum nicht das Naheliegende

**PiP ist das falsche Werkzeug.** iOS-Picture-in-Picture hält ein Video über *anderen Apps
auf demselben Gerät*; es erreicht keinen zweiten Bildschirm. Für Nicht-`AVPlayer`-Inhalt
(unser Metal-Rendering) bräuchte es zusätzlich eine `AVSampleBufferDisplayLayer`-Konstruktion
— viel Arbeit für etwas, das die Aufgabe nicht löst.

**Spiegeln (AirPlay/HDMI) funktioniert heute schon, ohne Code** — zeigt aber die gesamte
Bedienoberfläche mit. Das ist der Grund für diesen Plan, nicht ein technisches Hindernis.

**`UIScreen.didConnectNotification` + zweites `UIWindow`** wäre der Weg ohne Info.plist und
damit die billigere Scheibe. Ausgeschlossen wird er, weil er seit iOS 16 **deprecated** ist
und die Szenen-Rolle der unterstützte Mechanismus ist — also aus API-Gründen.

⛔ **Korrektur (2026-07-28):** hier stand, das wäre „ein roter Build", weil `Package.swift:28`
mit `-warnings-as-errors` baut. Das war **falsch** — und es war ausgerechnet die Begründung
dafür, den Startpfad anzufassen. Jeder `UIScreen`-Code steht in `#if canImport(UIKit)`, beide
SwiftPM-Jobs bauen für Hosts **ohne** UIKit (`ci.yml:41` macos-26, `ci.yml:310` ubuntu-latest),
und die Xcode-Lanes setzen gar kein `SWIFT_TREAT_WARNINGS_AS_ERRORS`. Die Deprecation hätte
nichts rot gemacht. Die Entscheidung bleibt dieselbe, der Grund ist ein anderer.

---

## Council-Verdikt (2026-07-28)

- **Vision-Keeper:** stärkstes Ja im Backlog. „Installation · Event · Cinema · Theater ·
  Performance" ist die Markenzeile — ein Instrument, dessen Bild auf die Leinwand geht,
  IST das Produktversprechen.
- **Skeptic:** das Risiko ist **nicht** der zweite Bildschirm, sondern der **Start**. Diese
  App hat eine dokumentierte Black-Screen-/SIGSEGV-Geschichte, und ein
  `UIApplicationDelegateAdaptor` + Scene-Delegate fasst genau den Startpfad an.
- **Architect:** `UIApplicationSupportsMultipleScenes = true` wirkt app-weit (State
  Restoration, mögliche Zweitfenster auf iPad/Mac). v10 ist iPhone-only, dort bietet iOS
  keine Zweitfenster an → praktisch gering, aber nicht null.
- **User-Advocate:** zwei Dinge, sonst ist es unbrauchbar auf der Bühne: ein sichtbares
  Zeichen, dass die externe Ausgabe läuft, und ein sauberes Verhalten beim **Abziehen
  mitten in der Show**.
- **Shipper:** kleinste versandfähige Form = eine zweite Szene, die `MetalBioView` mit
  denselben Parametern rendert. Nichts Interaktives, kein neuer Sheet.

**Gate: proceed-with-mitigation.** Die Mitigation ist die Leitplanke für jede Scheibe:
> Ohne angeschlossenen zweiten Bildschirm muss der Telefon-Pfad **identisch** bleiben.
> Die externe Szene ist additiv, nie eine Umleitung des bestehenden Pfads.

---

## Scheiben

### S1 — Szene existiert, Telefon unverändert
- `Resources/iOS/Info.plist`: `UIApplicationSupportsMultipleScenes` → `true`, plus
  `UISceneConfigurations` mit einer Rolle `UIWindowSceneSessionRoleExternalDisplayNonInteractive`.
- ~~`UIApplicationDelegateAdaptor` + `application(_:configurationForConnecting:options:)`~~ —
  **abgewichen beim Bauen (2026-07-28):** die Info.plist nennt die Delegate-Klasse direkt
  (`UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate`), es gibt
  **keinen** App-Delegate und keine `configurationForConnecting`-Methode. Grund: das ist
  strikt WENIGER Code im Startpfad — und der Startpfad ist genau das Risiko, das diese
  Scheibe prüfen soll. Der Application-Rollen-Eintrag trägt bewusst **keine**
  `UISceneDelegateClassName`, damit SwiftUIs eigene Szenen-Behandlung unangetastet bleibt.
- Die externe Szene zeigt zunächst nur eine schwarze Fläche mit dem Wortmarken-Text.
- **Zusätzlich (nicht geplant, vom Reviewer erzwungen):** eine `startupDone`-Latch in
  `EchoelmusicApp.swift`. `UIApplicationSupportsMultipleScenes` erlaubt auf iPad ein
  ZWEITES App-Fenster; dessen `.task` würde den kompletten Startlauf ein zweites Mal gegen
  die bereits laufende Engine fahren (`AudioEngine.attachSourceNode` hat keine
  „schon-angehängt"-Prüfung) — genau die Hot-Attach-Form, die diese Datei für den
  Startabsturz von Build 1363 verantwortlich macht. Die Latch macht den Start einmalig.
- **Verify: Start auf dem Gerät ohne angeschlossenen Bildschirm.** Das ist der eigentliche
  Test dieser Scheibe — nicht der Beamer.

### S2 — Das Visual auf die Leinwand
- Externe Szene rendert `MetalBioView` mit denselben `@AppStorage`-Look-Parametern.
- **Freeze-Gesetz beachten:** die externe Szene liest Bio/Musik in ihrem EIGENEN Leaf,
  niemals über den Telefon-Body. Zwei `MTKView`-Instanzen heißt zwei Renderer — die
  `ResourceGovernor`/`AdaptiveQuality`-Frage („was passiert mit 60 fps × 2?") gehört
  ausdrücklich in diese Scheibe, nicht in eine spätere.
- Randlos, ohne jede Bedienung.

### S3 — Sichtbarkeit + Abziehen
- Ein Zeichen im Header, dass die externe Ausgabe live ist (User-Advocate).
- Abziehen mitten im Betrieb: Szene wird abgebaut, Telefon läuft weiter, kein Freeze.
  **Das ist ein Bühnen-Szenario, kein Randfall.**

---

## Offene Fragen, die erst das Gerät beantwortet

- Zwei gleichzeitige Metal-Renderer auf einem iPhone: thermisch und für die Bildrate.
  `MetalBioView.swift` pinnt `preferredFramesPerSecond = 60` statisch — ob das für beide
  Ansichten tragfähig ist, kann hier niemand ausrechnen.
- Auflösung/Seitenverhältnis eines echten Beamers (der Simulator hilft nur begrenzt).
- AirPlay-Latenz gegen Kabel, in der Praxis, mit laufendem Audio.
