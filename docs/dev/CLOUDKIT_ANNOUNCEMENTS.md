# CloudKit Announcements — Push ohne Konto (E4)

So schickst du einen Push („neues Feature" / „Live-Event") an ALLE Geräte, die
den Schalter **Learn → Stay in the loop → „News & live events"** aktiviert
haben. Kein Server, kein Login — die App abonniert den Record-Type
`Announcement` in der öffentlichen CloudKit-Datenbank; jeder neue Record löst
den Push aus.

## Einmalige Einrichtung (CloudKit Dashboard)

1. https://icloud.developer.apple.com/ → Container **`iCloud.com.echoelmusic.app`**.
2. **Schema → Record Types → New Type:** `Announcement` mit Feldern:
   | Feld | Typ |
   |---|---|
   | `title` | String |
   | `body` | String |
   | `kind` | String (frei: `feature` oder `event`) |
   | `date` | Date/Time |
3. **Wichtig — Indexe:** für `recordName` den Index **Queryable** anlegen
   (Dashboard meckert sonst beim Browsen; die Subscription selbst braucht
   nichts weiter).
4. **Security Roles (Public Database):** Default lassen — `_world` darf
   lesen, nur du (Creator/Admin) schreibst. NIEMALS World-Write erlauben.
5. Nach dem ersten Test: **Deploy Schema Changes → to Production** (das
   Dashboard arbeitet erst in Development; TestFlight/App-Store-Builds lesen
   PRODUCTION — ohne Deploy kommt dort nichts an).

## Einen Push senden (pro Ankündigung ~1 Minute)

1. Dashboard → Container → **Data → Public Database → Records**.
2. Umgebung wählen: **Development** zum Testen (Debug-Builds),
   **Production** für TestFlight/App Store.
3. **New Record → Announcement**, Felder füllen:
   - `title`: z. B. `Echoel Live ist da`
   - `body`: z. B. `Weltweite Sessions — heute 20:00 spielen wir gemeinsam.`
   - `kind`: `event` (oder `feature`)
   - `date`: jetzt
4. **Save** → fertig. Jedes abonnierte Gerät bekommt den sichtbaren Push
   (Titel = `title`, Text = `body`).

## Verifikation (einmal durchspielen)

1. TestFlight-Build: Learn öffnen → „News & live events" AN → Permission
   erlauben → Status sagt „You'll hear about…".
2. Dashboard (PRODUCTION): Test-Record anlegen.
3. Push erscheint auf dem Gerät (App darf im Hintergrund/geschlossen sein).
4. Schalter AUS → weiterer Test-Record → es darf KEIN Push mehr kommen.

## Grenzen & Ehrlichkeit

- Zustellung ist Best-Effort (APNs) — für zeitkritische Event-Reminder
  zusätzlich Social Media nutzen.
- Records sind öffentlich LESBAR (World-Read) — nichts Vertrauliches in
  `title`/`body`.
- Wir sammeln nichts: kein Token bei uns, keine Empfangsbestätigung —
  Privacy-Label bleibt „Data Not Collected".
- Code: `Sources/Echoelmusic/Sync/AnnouncementCenter.swift`
  (Subscription-ID `echoel-announcements-v1`; Container/Type oben).
