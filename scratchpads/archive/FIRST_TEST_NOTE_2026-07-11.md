# Erster Test — v10.79.151 (Build für die Signal-Tester-Gruppe)

## Status (verifiziert 2026-07-11)
- **Build 10.79.151 ist auf TestFlight hochgeladen + verarbeitet** (TestFlight-Run
  `ab72451` = success, 07:06). Alle Gates grün.
- **Keine Export-Compliance-Sperre:** `ITSAppUsesNonExemptEncryption = false` in Info.plist
  → Tester bekommen den Build sofort, kein Verschlüsselungs-Dialog.
- **Alle Berechtigungs-Texte da:** Mikrofon · Health · Kamera · Bluetooth.
- Stabilität device-bewiesen: v148 (25 Min ohne Crash), v149/v150 (Bio-Schleife end-to-end),
  v151 = rPPG-Interruption ehrlich behandelt statt Kalt-Restart-Schleife.

## „What to Test" (in TestFlight einfügen + in die Signal-Gruppe posten)

---
**Echoel — erster Test 🎛️**

Danke fürs Testen! Echoel ist ein Instrument, das dein Körper spielt — dein Puls,
Atem und deine Ruhe formen die Musik in Echtzeit.

**Bitte ausprobieren:**
1. **Puls lesen:** Unten „Read pulse" antippen, Fingerspitze ruhig auf die
   Rückkamera+Blitz legen. Findet die App deinen Puls (BPM erscheint)? Wie lange dauert's?
2. **Falls der Puls nicht kommt:** einmal kurz Kontrollzentrum öffnen/schließen oder App
   wechseln und zurück — erholt sich die Kamera dann von selbst?
3. **Generieren + spielen:** Play drücken. Klingt die Musik organisch/angenehm? Verändert
   sie sich mit deinem Zustand?
4. **Klang:** Sample-Browser öffnen (Pad antippen → durchblättern) — durch die Kategorien
   (Bass/Stab/Keys/Pad/…) blättern, Sounds vorhören, auf Pads legen. Fühlt sich der Beat
   lebendig an?
5. **Spuren-Mixer:** In der Timeline pro Spur M (Mute) · S (Solo) · Level. Schneidet Mute
   sofort? Lässt sich der Level-Regler gut bedienen?

**Was noch NICHT drin ist** (kommt später): Video, Streaming, weltweite Live-Sessions.

**Bitte melden:** Was hat sich gut angefühlt? Wo hat es geruckelt/verwirrt? Screenshots +
kurze Beschreibung reichen. Ganz ehrlich — genau dafür ist der Test da. 🙏

*Hinweis: Echoel dient der Selbstbeobachtung, nicht der medizinischen Diagnose.*
---

## Was NUR du in App Store Connect machen kannst (von hier nicht steuerbar)
1. **App Store Connect → deine App → TestFlight →** Build 10.79.151 auswählen.
2. **Tester-Weg wählen:**
   - **Interne Tester** (bis 100, müssen als „Benutzer" in ASC angelegt sein): bekommen den
     Build SOFORT, KEINE Beta-Prüfung. Schnellster Weg für heute.
   - **Externe Tester** (deine Signal-Freunde per E-Mail/öffentlichem Link): brauchen beim
     ERSTEN Build eine **Beta-App-Prüfung** durch Apple (meist < 24 h, oft nur Stunden).
     → Wenn heute rausgehen soll: JETZT zur Beta-Prüfung einreichen; danach sind alle
     Folge-Builds für dieselbe Gruppe sofort ohne neue Prüfung.
3. **„What to Test"** (oben) + kurze Beschreibung eintragen, Gruppe zuweisen, einladen.
4. **Fertig** — Tester bekommen die TestFlight-Einladung.

## Empfehlung
Für „heute rausbringen" ohne Wartezeit: ein, zwei Leute als INTERNE Tester (ihre Apple-IDs
als ASC-Benutzer) → sofort. Parallel die EXTERNE Gruppe für die Signal-Runde zur
Beta-Prüfung einreichen — die ist dann morgen früh durch. Kein neuer Build nötig,
10.79.151 ist der richtige.
