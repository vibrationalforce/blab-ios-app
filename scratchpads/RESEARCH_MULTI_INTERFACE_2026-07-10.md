# RESEARCH — Mehrere Audio-Interfaces parallel / „virtuelle Soundkarte" (2026-07-10)

Deep-Research-Harness: 5 Suchwinkel · 20 Quellen · 49 extrahierte Claims ·
25 adversarial verifiziert (3-Voter), 0 getötet. Founder-Frage: kann eine
virtuelle Soundkarte das Aggregat-/Clock-Latenz-Problem umgehen, und können wir
in Echoelmusic mehrere Interfaces „entspannt parallel" anbieten?

## DAS VERDIKT (Founder-Prämisse WIDERLEGT — per Mechanik, nicht Meinung)

**Eine virtuelle Soundkarte umgeht das Clock-Problem NICHT — sie verschiebt nur
den Ort des Resamplings.** Mechanik: JEDES Core-Audio-Gerät — auch ein
virtuelles — präsentiert der HAL eine eigene freilaufende Clock (Zero-Timestamp-
Paare). Zwei freilaufende Interfaces (BiG SiX + Xone:96 — keines kann sich über
USB auf das andere clocken, keines hat Wordclock) erfordern IMMER asynchrone
Sample-Rate-Konvertierung irgendwo: in Apples Aggregat (Drift Correction =
Resampling, opt-in pro Gerät), in Loopback/BlackHole (Rogue Amoebas EIGENE Doku
verlangt Drift Correction, sobald das virtuelle Gerät in einem Aggregat liegt;
BlackHoles Alternative ist ein manueller ±1 %-Rate-Lock auf EIN Gerät), oder
in der App (Varispeed). Quellen: Apple-Doku/DTS, Rogue-Amoeba-KB, BlackHole-Wiki.

## Pro Plattform

### iPhone (unsere Plattform): KEIN Weg — belegt, nicht behauptet
- `multiRoute` (der einzige Multi-Device-Mechanismus) routet nur getrennte
  **Output**-Streams (dokumentiertes Beispiel: 1 USB-Gerät + Kopfhörer);
  **ein einziger Input**, last-in gewinnt (Apple-Staff-Bestätigung). Zwei
  Interfaces am Hub: das zuletzt angesteckte gewinnt die Route — iOS
  entscheidet, nicht die App.
- multiRoute ist zudem fragil (Route-Änderung invalidiert die Konfiguration;
  iOS-10-Regressionen brachen shipping Apps).
- **Kein DriverKit auf dem iPhone** (Apple DTS, zuletzt für iOS-18-Ära
  bestätigt; „iOS 16"-Badges in der Doku sind ein iPadOS-Artefakt).
- → Für Live-Sets gilt der analoge Ketten-Weg: EIN USB-Interface (eine Clock,
  null Sync-Thema), zweites Pult analog dahinter. Produkt-Item bleibt:
  **Multichannel-Stems auf die Kanäle des EINEN Interfaces** (Roadmap).

### iPadOS 16+ (M-Serie): eine Tür, aber schmal
- DriverKit/AudioDriverKit existiert dort — aber nur für PHYSISCHE Geräte.
- Offene Forschungsfrage (ungelöst): ein Dext, der BEIDE USB-Interfaces claimt
  und als ein Gerät präsentiert — Entitlement-Vergabe durch Apple höchst
  fraglich (Policy verweigert virtuelle Geräte; Fremd-Hardware-Spanning erst recht).

### macOS (künftige Mac-Version): die GUTE Nachricht
- **`AudioHardwareCreateAggregateDevice` ist öffentliche API (macOS 10.9+):
  Echoelmusic-am-Mac kann das BiG-SiX+Xone-Aggregat SELBST zur Laufzeit bauen —
  kein Nutzer-Ausflug ins Audio-MIDI-Setup**, Drift Correction programmatisch
  gesetzt. Das ist „entspannt parallel" als Produkt: App an, Geräte da, fertig.
- Eigener virtueller Treiber: MUSS ein AudioServerPlugIn sein (Apple verweigert
  AudioDriverKit-Entitlements für virtuelle Geräte, DTS-bestätigt 2023) →
  Installer + Notarisierung + coreaudiod-Neustart, und latenzmäßig NICHT besser
  (Resampling bleibt) → **eigenen Treiber NICHT bauen.**
- In-App-Alternative (Apples CAPlayThrough-Muster: 2 AUHAL-IOProcs + Ringpuffer
  + Varispeed): gleiche Resampling-Physik unter App-Kontrolle, Ringpuffer =
  inhärente Zusatzlatenz. Nur sinnvoll, falls Messungen das Aggregat als
  Engpass zeigen (keine Quelle liefert gemessene Zahlen — offene Frage).

## Produkt-Konsequenzen (Vision-Gate)

| Option | Verdikt |
|---|---|
| iPhone zwei Interfaces parallel | **REJECT (OS-Grenze)** — ehrlich kommunizieren; analoge Kette + Multichannel-Stems ist der Weg |
| Eigene virtuelle Soundkarte (Mac) | **REJECT** — verschiebt nur das Resampling, kostet Installer-Reibung |
| Mac-Version: Aggregat AUTOMATISCH in-app bauen (`AudioHardwareCreateAggregateDevice` + Drift-Correction) | **ADOPT-ROADMAP** — der „entspannt"-Faktor ohne Physik-Lüge; hängt am Mac-Tier-2-Entscheid |
| iPad-Dext als Privat-Aggregat | **WATCH** — Entitlement unwahrscheinlich; jährlich neu prüfen (Apple-Policy „currently") |

## Offene Fragen (ehrlich)
- Keine Quelle liefert GEMESSENE Latenz-Deltas (Aggregat vs. Loopback-Topologie
  vs. In-App-Varispeed) — bei Mac-Umsetzung selbst messen.
- Verhalten der Xone:96-Dual-USB-Ports am selben Mac: ein oder zwei Clock-Domains?
- SSL/Xone „kein Clock-Slaving über USB" stammt aus Verifier-Reasoning (kein
  Wordclock-I/O laut Produktseiten) — bei Umsetzung in beiden Manuals gegenprüfen.
