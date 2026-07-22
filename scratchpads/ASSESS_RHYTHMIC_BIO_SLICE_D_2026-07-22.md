# ASSESSMENT — #79 Slice D (Rhythmus LIVE bio-gekoppelt)? — 2026-07-22

Folge-Bewertung zu `PLAN_RHYTHMIC_DIVERSITY_2026-07-21.md`. Der Founder-Ask hatte
ZWEI Teile: (1) "rhythmische Vielfalt bei allen Genres" und (2) "die sich **am
Biofeedback orientieren** soll". Slice A–C (alle 18 Genres, geshippt) deckten
Teil (1) — statische Genre-Distinctness. Diese Bewertung prüft ehrlich, ob Teil
(2) noch offene Arbeit ist ODER bereits erfüllt.

## Befund: Die Bio-Orientierung des Rhythmus EXISTIERT bereits

Direkter Code-Read (`BioComposer.swift`):
- `energy = clamp01((heartRateBPM − 50) / 70)` (Zeile 330) — Herzrate 50…120 bpm → 0…1.
- `calm = clamp01(coherence)` (Zeile 328).
- Beide fließen in JEDEN Beat-Builder (`fourOnFloorBeat` / `backbeatBeat` /
  `offbeatBeat` / `halfTimeBeat` / `dubBeat` / `trapBeat`) und steuern dort die
  Dichte: `energy > Schwelle` fügt Hits/Fills hinzu (Puls treibt), `calm > 0.7`
  ("spacious") strippt die seeded Extras (ein ruhiger, kohärenter Körper bekommt
  einen ruhigen, offenen Groove). Zusätzlich skaliert `tempoDensityScale(bpm:)`
  die Notendichte gegen das Tempo (schneller → dünner, konstante Notes/Sekunde).

**Der Rhythmus orientiert sich also SCHON live am Biofeedback** — Herzrate und
Kohärenz bewegen die Beat-Dichte in Echtzeit. Das ist keine neue Baustelle; es ist
seit den Archetyp-Beats (Audit B5) so und war die Grundlage, auf die #79 A–C die
statische Genre-Charakteristik (GenreFlavor: hatDensityBias/percGhostStep/
kickPushEnabled) OBEN DRAUF legte.

## Was Slice D zusätzlich täte — und warum es spekulativ ist

Slice D hieße: den **GenreFlavor-Overlay selbst** bio-reagieren lassen (z. B. der
percGhost feuert nur über einer Kohärenz-Schwelle, oder hatDensityBias driftet mit
der Herzrate). Bewertung:

- **Redundanz-Risiko:** Die Beat-DICHTE reagiert bereits auf energy/calm. Den
  Flavor zusätzlich bio-modulieren = zweite Modulationsebene auf derselben Achse →
  Gefahr von Doppel-Modulation, die die Bio-Reaktion nicht klarer, sondern
  matschiger macht.
- **Identitäts-Risiko:** Der GenreFlavor ist bewusst STATISCH, weil er die
  GENRE-IDENTITÄT trägt (Disco ≠ Psytrance). Ihn beweglich zu machen würde genau
  die Distinctness verwässern, die Slice A–C gerade hergestellt haben — der
  percGhost feuert dann nicht mehr zuverlässig, die Genres könnten bei bestimmten
  Bio-Zuständen wieder gleicher klingen (Regression gegen den `beatArchetype`-Guard).
- **Determinismus:** Slice A–C sind RNG-frei/deterministisch. Bio-gekoppelter
  Flavor bliebe zwar deterministisch pro Bio-Snapshot, aber die Distinctness-Garantie
  (jetzt bedingungslos) würde zustandsabhängig — der Guard-Test müsste lockern.

## Council (kompakt)

- **Vision-Keeper:** Teil (2) des Ask ist durch die bestehende energy/calm-Kopplung
  bereits erfüllt — der Körper bewegt den Rhythmus live. #79 ist damit vollständig
  wie gefragt.
- **Skeptic:** Slice D löst kein bekanntes Problem; es ist eine Vermutung, dass MEHR
  Bio-Bewegung im Rhythmus gewünscht ist. Ohne Founder-Ohr-Beleg = spekulatives
  Gold-Plating mit realem Regressions-Risiko gegen die frische Distinctness.
- **Shipper:** Nichts blind bauen. Wenn überhaupt, erst nach Founder-Ohr-Check des
  aktuellen Builds (c856f4b) mit einer KONKRETEN Aussage ("der Beat müsste sich mehr
  mit dem Puls verändern").

**Verdikt: HOLD.** #79 gilt als vollständig wie gefragt (Vielfalt = Slice A–C;
Bio-Orientierung = bestehende energy/calm-Kopplung). Slice D NICHT bauen, bis der
Founder nach dem Ohr-Check explizit MEHR Rhythmus-Bio-Bewegung verlangt. Falls doch:
der sichere Slice wäre, EINEN zusätzlichen Flavor-Kanal bio-zu-koppeln, der die
Distinctness NICHT trägt (z. B. ein optionaler Fill-Dichte-Kanal getrennt vom
percGhost), damit die Genre-Identität statisch/garantiert bleibt.

## Dead-End-Prävention (für künftige Zyklen)

Ein künftiger Zyklus darf NICHT "dem Rhythmus Bio-Reaktivität hinzufügen" als
vermeintlich fehlend behandeln — sie existiert (energy/calm → Beat-Dichte, alle
Builder). Neue Bio-Rhythmus-Arbeit nur auf konkrete Founder-Ohr-Aussage, und dann
so, dass die #79-Distinctness-Garantie erhalten bleibt.
