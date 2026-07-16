# KONZEPT — „The Ledger of Connection" (Founder 2026-07-16)

**Status: DESIGN / PIPELINE (nicht in v1.0, kein `Sources/`-Code bis Founder-Gate).**
Konzept + Swift-Skelett auf Founder-Wunsch. Anchor: Echoel-Vision (on-device, zero-server,
Instrument-first, open standards, KEINE Fake-Social/Manipulation).

---

## 0 · Vision-Gate + Council (ehrlich, vor dem Design)

**Kern-Spannungen, die das Design lösen MUSS (sonst REJECT):**

1. **Zero-Server-Wette (Founder-Entscheid, memory):** „kein eigener Server — der bleibt
   gestrichen." Ein Dual-Audience-System, das „im Backend semantisch verknüpft" und „API-
   Endpoints" an Industrie/Booker ausliefert, IMPLIZIERT einen Server → Direktkonflikt.
   → **Lösung: on-device-first.** Deposits lokal gemintet, beide Renderings lokal erzeugt,
   geteilt über BESTEHENDE Kanäle (die eigenen Socials des Artists, eine Datei, eine Booker-
   Mail). Kein Echoel-betriebenes Social-Backend. Die Live-Industrie-API = separate, GEHALTENE
   Entscheidung (bricht Zero-Server).

2. **„Erst launchen, bevor es zu kompliziert wird" (Founder-Entscheid):** v1.0 = freies
   Instrument JETZT. Eine Community-CRM ist ein **v1.2-Broadcast-Layer**, NICHT v1.0.
   → Placement: auf die Broadcast/EchoelPublish-Roadmap (v1.2), nicht in den Launch.

3. **„Instrument, nicht Social Media" (CLAUDE.md):** ABER die Founder-Rahmung ist explizit
   ANTI-Fake-Social (echte Deposits, Transparenz, Anti-Dopamin-Loop — direkt gegen den
   „Claude-Code-Gambling-Loop" aus dem geteilten Video). Das ist vision-KOMPATIBEL, WENN es
   „der ehrliche Workflow des Artists, geteilt" ist (Broadcast-Werkzeug) statt „ein Feed mit
   Likes" (Zwei-Wege-Social-Graph).

**Vision-Gate-Verdikt: ADOPT-PIPELINE / v1.2.** Starkes Konzept, jetzt designen (Founder-
Ask), on-device-first bauen, NICHT in v1.0, Live-Industrie-Backend GEHALTEN.
**Council-Gate: hold-for-founder** auf (a) v-Version-Placement, (b) Zero-Server-Grenze.

**Der elegante Kern-Insight (macht es Echoel-nativ, nicht generisch-social):** Echoel hat
schon einen Event-Bus (`EngineBus`) und der Workflow produziert schon echte Artefakte
(gespeicherte Patches, Bio-Sessions, Live-Set-Routings, BioVariationMaze-Picks). Der Ledger
ist eine dünne **Capture-+-Dual-Projektion**-Schicht über Events, die OHNEHIN passieren —
keine neue Aktivität. Genau das „automatisiert / minimaler Aufwand", das der Founder will.

---

## 1 · Deposit-Architektur (echte Nähe statt Fake-Social)

Ein `LedgerDeposit` wird **auto-gemintet aus einem echten Workflow-Event**, das der Artist
sowieso erzeugt. Quellen (alle existieren schon oder sind trivial anzuzapfen):

| Micro-Moment | Quelle im Repo | Roh-Payload |
|---|---|---|
| Neuer Synth-Patch geboren | `PatchStore.save` | Patch-JSON + 5-s-Bounce |
| Body hat das geformt | `BioVariationMaze`-Pick / Bio-Session-Ende | Bio-Snapshot + Audio-Schnipsel |
| Rig fürs nächste Set | Patchbay-/ADM-OSC-Scene gespeichert | Routing-Schema (Nodes/Kanten) |
| Fader-Curve / Automation | `AutomationLane` committed | Kurven-Sparkline |
| Warp/Charakter gewählt | `StretchMode` an einem Clip | Vorher/Nachher-Schnipsel |
| (opt-in, off-app) Xcode-Build grün / Commit | lokaler Git-Hook → Deposit-Stub | Commit-Message + Diffstat |

**Capture = ein `EngineBus`-Subscriber**, der auf diese „Milestone"-Events hört und einen
**Ein-Tap „→ Ledger"** anbietet (oder Auto-Capture mit Review-Queue). Reibung ~0: der Moment
IST schon passiert; der Ledger packt nur das rohe Artefakt als unveränderlichen Snapshot.

**„Studio-Logbuch"** = der lokale, chronologische Strom dieser rohen, unpolierten Deposits,
exklusiv für den Core-Circle. ROH heißt roh: das echte Patch-JSON, ein kurzer Bounce, das
Routing-Graph — kein polierter Post. Transparenz = die Einzahlung ist ECHT (ein gespeicherter
Patch ist ein echt gespeicherter Patch, kein inszenierter Content).

---

## 2 · Dual-Interface-Datenmodell (Fans vs. Industrie)

EIN unveränderliches `LedgerEvent` (die Quell-Wahrheit) + ZWEI abgeleitete `LedgerRendering`
(Projektionen desselben Events auf verschiedene Flughöhen — NIE divergente Fakten):

- **`.fan`** — spielerisch, nahbar: „So klingt der neue analoge Basslauf" + 10-s-Audio + Vibe-Tag.
- **`.pro`** — Datenblatt: „SSL Big SiX Bus · MioXL-Routing · Latenz <2 ms · 90-min-live-ready" +
  MIDI-Map + Sample-Rate.

**Semantische Verknüpfung:** beide Renderings tragen dieselbe `sourceEventID`. Sie sind zwei
Projektionen EINER Wahrheit — nie widersprüchliche Fakten (Transparenz-Gesetz: Pro-Sheet und
Fan-Story beschreiben dasselbe echte Event, nur in anderer Auflösung). SwiftData:
`LedgerEvent` (source, immutable) 1—* `LedgerRendering` (audience-tagged projection). Kein
Backend nötig — die Projektion ist eine reine Funktion `render(event, tier)` on-device; Export
wählt die Zielgruppe.

---

## 3 · Core-Only Gamification (Anti-Skalierbarkeit — Ice Cube's Core Law)

Zugang zum Core-Circle (rohes Logbuch + exklusive Tools/Audio) ist gated durch **on-device,
nicht-übertragbaren „Proof of Engagement"** — akkumulierte ECHTE Hörzeit / echte Mitwirkung,
lokal berechnet, **nie kaufbar, bewusst langsam** zu verdienen.

- **Anti-skalierbar BY DESIGN:** kein Geld-Pfad, keine Abkürzung, gedeckeltes Wachstum (der
  Circle öffnet erst nach N Stunden ECHTEM ununterbrochenem Hören oder M echten Beiträgen).
  Ice Cube's Gesetz = den Kern tief bedienen, nicht für Reichweite verdünnen. Der Gate ist
  nicht farmbar — er ist Beweis echter Präsenz.
- **Guardrail (explizit gegen das Video):** „Proof of GENUINE Engagement", KEIN Sucht-/
  Dopamin-Loop. Keine bestrafenden Streaks, kein FOMO, keine Dark Patterns. Transparenz: der
  User sieht exakt, was Zugang verdient. (Kein Heilungs-/Wellness-Claim, keine parasoziale
  Ausbeutung — bleibt hartes Red-Line.)

---

## 4 · Swift-Architektur-Skelett (illustrativ — NICHT in `Sources/` bis Gate)

```swift
// —— Quell-Wahrheit: ein Event, unveränderlich ——————————————————————————————
enum DepositKind: String, Codable, Sendable {
    case patch, bioSession, routing, automation, warpChoice, build
}

/// Ein echtes Workflow-Ereignis, on-device gemintet. IMMUTABLE — die eine Wahrheit,
/// aus der jede Zielgruppen-Projektion abgeleitet wird (nie divergente Fakten).
struct LedgerEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: DepositKind
    let capturedAt: Date
    /// Roh-Artefakt (Patch-JSON, Bounce-Ref, Routing-Graph) — die ehrliche Einzahlung.
    let rawArtifactRef: String
    /// Objektive Fakten, die BEIDE Renderings teilen (kein Spin, nur Messwerte).
    let facts: [String: String]     // z.B. ["latencyMs":"1.8","routing":"MioXL","bpm":"128"]
}

// —— Zielgruppen-Routing ———————————————————————————————————————————————————
enum RecipientTier: String, Codable, Sendable {
    case fan        // nahbar, spielerisch
    case core       // der anti-skalierbare innere Kreis (rohes Logbuch)
    case pro        // Industrie/Booker/Tech-Partner (Datenblatt)
}

/// Eine Projektion EINES Events auf EINE Zielgruppe. Trägt die sourceEventID —
/// semantisch an die Quelle gebunden, nie ein eigenständiger „Fakt".
struct LedgerRendering: Identifiable, Codable, Sendable {
    let id: UUID
    let sourceEventID: UUID
    let tier: RecipientTier
    let headline: String            // "So klingt der neue analoge Basslauf" | "Latency <2ms…"
    let body: String
    let mediaRef: String?           // 10-s-Bounce | Schema-PNG | nil
}

/// Ein Renderer projiziert ein Event auf eine Zielgruppe. Reine Funktion, on-device.
protocol AudienceRenderer {
    func render(_ event: LedgerEvent, for tier: RecipientTier) -> LedgerRendering?
}

// —— Anti-Skalierbarkeits-Gate ————————————————————————————————————————————
/// On-device, nicht-übertragbar, nicht kaufbar. Reine lokale Akkumulation.
struct EngagementProof: Codable, Sendable {
    private(set) var genuineListeningSeconds: Double
    private(set) var genuineContributions: Int
    /// Bewusst hohe, nicht farmbare Schwelle. Kein Geld-Pfad.
    func unlocksCore(minHours: Double = 20, minContributions: Int = 5) -> Bool {
        genuineListeningSeconds >= minHours * 3600 || genuineContributions >= minContributions
    }
}

// —— Facade / Store (on-device; Export statt Live-Backend) ————————————————————
@MainActor
protocol LedgerDepositSource: AnyObject {          // etwas, das Events minten kann
    var onDeposit: ((LedgerEvent) -> Void)? { get set }
}

@MainActor
final class LedgerStore {                          // on-device Wahrheit (SwiftData)
    private(set) var events: [LedgerEvent] = []
    private let renderer: AudienceRenderer
    private var proof = EngagementProof(genuineListeningSeconds: 0, genuineContributions: 0)

    init(renderer: AudienceRenderer) { self.renderer = renderer }

    func record(_ event: LedgerEvent) { events.append(event) }   // aus EngineBus-Milestone

    /// Was ein Empfänger-Typ sieht. Core-Tier zusätzlich hinter dem Anti-Scale-Gate.
    func payload(for tier: RecipientTier) -> [LedgerRendering] {
        guard tier != .core || proof.unlocksCore() else { return [] }   // nicht kaufbar
        return events.compactMap { renderer.render($0, for: tier) }
    }

    /// Export = zwei statische Renderings über BESTEHENDE Kanäle (kein Echoel-Server).
    func exportPayload(for tier: RecipientTier) -> Data? {
        try? JSONEncoder().encode(payload(for: tier))
    }
}
```

**Warum dieses Skelett vision-treu ist:** `LedgerStore` ist on-device (SwiftData), die
Dual-Projektion ist eine reine Funktion, „Auslieferung" = Export über bestehende Kanäle (kein
Server). Der Anti-Scale-Gate ist lokal + nicht kaufbar. Das Live-Industrie-API (falls je
gewollt) wäre der ERSTE Server — separater Founder-Entscheid, hier bewusst NICHT eingebaut.

---

## Gate an den Founder (2 echte Forks)
1. **Placement:** v1.2-Broadcast-Roadmap (mein Read) — oder willst du es früher?
2. **Zero-Server-Grenze:** bleibt on-device-first (Export über eigene Kanäle) — oder öffnest
   du bewusst den ersten Echoel-Server fürs Industrie-Interface (bricht die Zero-Server-Wette)?

Bis dahin: KEIN `Sources/`-Code. Erste baubare Scheibe (nach Ja) = der `EngineBus`-Deposit-
Capture aus EINER echten Quelle (`PatchStore.save` → `LedgerEvent`), rein + test-first.
