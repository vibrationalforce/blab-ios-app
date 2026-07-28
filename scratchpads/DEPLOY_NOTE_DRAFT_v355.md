# Deploy-Note Entwurf v10.79.355 — sieben Commits, die nie auf dem Gerät waren

> Entwurf. Wandert nach dem Team-Audit in `.deploy/release`.
> Vorgänger: v10.79.354 (Deploy-Commit `db8926e`).

## Die sieben

| Commit | Was |
|---|---|
| `11a2076` | Eingehendes Netzwerk-MIDI bekommt einen Schalter, Standard AUS (#187) |
| `ae386cb` | …und das Abschalten lag hinter zwei unbeteiligten Fehler-Guards, griff also nicht |
| `34e2355` | Der Akku-Governor-Regler für die Abtastrate erreicht endlich eine Schleife (#197c) |
| `ed083a6` | Nachtrag: die Reglertabelle, die ich dazu schrieb, war selbst ungenau |
| `5c612d1` | Der Tonhöhen-Farbkreis ist gelöscht — EINE Farbsprache statt zwei (#197) |
| `7db996c` | Das schwebende Visual-Fenster bemisst sich adaptiv (#197) |
| `6c9ca28` | Die Chip-Leiste sitzt AUF der Frontplatte statt über einem Formular (#157) |

## Was Du hören/sehen sollst

**Die Farbe der Töne ist jetzt physikalisch, überall.** Es gab zwei Farbsprachen
nebeneinander: einen frei erfundenen „Tonhöhe → Farbton"-Kreis und den echten Weg, der
die Frequenz eines Tons um ganze Oktaven ins sichtbare Licht transponiert (CIE 1931,
Purpurlinie schließt den Kreis, Akkorde mischen amplitudengewichtet in OKLab). Der
erfundene ist raus. Licht (Art-Net/sACN) und Bild sprechen jetzt dieselbe Sprache.
Der App-Store-Text bewarb den erfundenen Weg namentlich („perceptual pitch-to-hue") —
korrigiert, sonst hätten wir etwas beworben, das wir gerade gelöscht haben.

**Das Visual-Fenster war auf einem Querformat-iPhone ein Briefschlitz.** Es bemaß sich
als zwei UNABHÄNGIGE Bruchteile des Containers, mit Mindestwerten, die im Querformat
gebunden haben statt der Bruchteile: „klein" kam als 324 × 120 pt heraus, davon 44 pt
Leiste — ein 324 × 76 pt Bild. Dieses Bild IST die Spielfläche. Jetzt folgt es der
Ausrichtung des Containers, in ein brauchbares Seitenverhältnis-Band geklemmt, und die
Größenstufe skaliert diese Form. Auf einem nahezu quadratischen iPad hätte „groß" sonst
92 % der Höhe geschluckt (≈ 67 pt Ziehweg) — gedeckelt, aber bewusst so, dass die Deckelung
auf Deinem Hochkant-Telefon NICHT greift: „groß wurde kleiner" wäre der schlimmere Fehler.

**Das Hauptfenster liest sich als Instrument, nicht als Formular.** Der Start-Knopf saß
zwischen Chip-Leiste und Platte und hat damit das eine Objekt — Reiter plus die Fläche,
die sie umschalten — mittendurch geschnitten. Er sitzt jetzt darunter: er verankert
statt zu teilen und liegt einhändig in Daumenreichweite. Die Trennlinie unter den Chips
ist weg; sie war die Unterkante einer MENÜLEISTE und damit die Grammatik, die wir
loswerden wollten.

**Netzwerk-MIDI stand offen.** Der eingehende Listener war immer an; jetzt hat er einen
Schalter mit Standard AUS. Der erste Anlauf griff nicht, weil das Abschalten hinter zwei
unbeteiligten Fehler-Guards lag — deshalb zwei Commits.

**Der Akku-Governor hatte einen Regler ohne Schleife.** `bioHz` konnte gedreht werden und
niemand hat zugehört, weil `PollingLoop` das Intervall in seinen Task eingebacken hat.
Jetzt liest die Schleife die Obergrenze vor jedem Schlafen neu. Wichtig und im Code
dokumentiert: es ist eine **DECKELUNG**, kein Zielwert — als Ziel gelesen würde sie
Schleifen auf einem ladenden Telefon BESCHLEUNIGEN.

## Offen und ehrlich

- **Alles hier ist compile-verifiziert, NICHT geräteverifiziert.** UI-Layout und Farbe
  sind genau die Klasse, die man sehen muss, um sie zu beurteilen.
- **Noch offen von v354:** knistert der Limiter wirklich nicht mehr, und pumpt dünnes
  Flow-Material jetzt (#199)? Beides braucht Dein Ohr.
- **Auf kurzen Reitern** (Export, FX, Mood, Bio) steht die schwarze Leere jetzt ZWISCHEN
  Karte und Knopf statt am Fensterende — nicht neu entstanden, nur umgezogen. Ob der
  Knopf dadurch losgelöst statt verankernd wirkt, entscheidet Dein Auge.
- **Auf dem Bio-Reiter** liegt weder Linie noch Kartenkante unter der Chip-Leiste: es ist
  das einzige Panel ohne eigene Karte. Die Chips tragen eigene Ränder, es sollte also
  halten — aber es ist die Stelle, an der es auffallen würde.

<!-- TEAM-AUDIT-BEFUNDE HIER EINSETZEN -->
