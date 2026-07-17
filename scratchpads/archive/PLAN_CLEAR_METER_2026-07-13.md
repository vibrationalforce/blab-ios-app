# PLAN — klarer Takt / "die Eins" / produzierbare Loops (Founder 2026-07-13)

## Founder-Anforderung (verbatim-Kern)
"Erst gut chords, dann holpert es… Es ist nicht so richtig im Taktschema. Kool
ist wenn eindeutig zu erkennen ist — jetzt sind 8 Takte vollständig und dann
wiederholt es sich. Sinnvolle Loops sind am besten zum Musik produzieren. Wenn
auf einmal nicht mehr erkennbar ist wo die Eins ist, sucht man nur nach dem Takt
und verliert Zeit und Lust." + AskUserQuestion → "Harmonisch — Akkorde springen".

→ Kern: **eindeutiger Downbeat ("die Eins") + saubere, wiederholbare N-Takt-Loops
zum PRODUZIEREN.** Verschiebung von Meditation (formlose Fläche) → Produktion
(klare Meter). "Eindeutig" = man hört sofort, wo Takt 1 ist.

## Ursache (Code-verifiziert 2026-07-13)
- Default-Produkt = "pure meditative Flächen, KEIN Beat" (Founder 2026-07-07
  "Schmeiß den Beat komplett raus" → `generate()` lädt `BioComposer.silentBeat()`).
- `composeHarmonic` (sustained-Profil): EIN weicher Akkord pro Takt, Attack auf
  Step 0, über den ganzen Takt gehalten, padVelocity ~0.34–0.56. Akkordwechsel
  liegt zwar auf dem Downbeat, aber ein WEICHER Pad-Attack ohne Transiente gibt
  dem Ohr keinen rhythmischen Anker → "die Eins" verschwimmt.
- `barDynamic` hebt s==0 velocity-mäßig an ("the one was hard to hear"), reicht
  bei einem Flächen-Pad aber nicht als Metrum-Cue.
- Loop-Struktur selbst ist sauber (N distinct bars, Structure-Seed hält's
  zusammen, wiederholt sich) — das Problem ist die fehlende METRIK innerhalb.

## Entscheidungs-Dial (branch-t die Umsetzung, kehrt tw. "Beat raus" um → FOUNDER)
- A **Subtiler Anker, kein Beat:** festerer Bass + Pad-Reartikulation exakt auf
  Takt 1, Akkordwechsel hart auf die Eins, saubere feste Loop. Bleibt ambient,
  kein Schlagzeug. Respektiert die Flächen-Identität.
- B **Leichter, klarer Puls zurück (Produktions-Modus):** sanfter eindeutiger
  rhythmischer Puls (Kick/Klick auf die Beats) → Takt unmissverständlich. Kehrt
  "Beat raus" bewusst um.
- C **Umschalter Flächen ↔ Produktion:** A als Default, plus ein Toggle, das für
  Produktion einen klaren Puls (B) dazuschaltet. Versöhnt beide Welten, mehr Arbeit.

## Gate
Blind nicht entscheidbar (ich höre den Klang nicht) + kehrt eine Founder-
Entscheidung um → EIN scharfe Frage, dann genau EINE Richtung sauber bauen +
gezielter Build zum Hören. Kein Blind-Umbau des Kerns.
