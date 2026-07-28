# Preferences

User preferences for development workflow, communication, and tooling.

## Development Style
- **Protocol:** Ralph Wiggum Lambda -- one fix per cycle, no batching
- **Commits:** Conventional commits (feat:, fix:, docs:, etc.)
- **Testing:** TDD when adding new functionality
- **Logging:** os_log only, never print()
- **Concurrency:** Swift 6 strict concurrency, async/await + @MainActor

## Communication
- **Tone:** Direct, no filler, no emojis unless requested
- **Answer-first / brief (2026-06-30):** founder shared a `/brief`-style command carousel
  ("Shortest possible answer. No fluff. No preamble. Just the answer."). Lead with the
  result/fix, minimal process narration. Report fixes, not the journey. Short replies.
- **Science only:** No esoteric terminology, evidence-based claims only
- **Branding:** "Echoelmusic" -- never "BLAB" or "Vibrational Force"

## Tooling
- **CI:** GitHub Actions (testflight.yml primary)
- **Build:** XcodeGen (`project.yml`) + Fastlane + GitHub Actions (`testflight.yml` primary)
- **Dependencies:** Zero external dependencies policy
- **SDK Target:** iOS 18 deployment floor (Package.swift + project.yml + Info.plist); Xcode 26.2 in CI

## Session Workflow
- Read scratchpads/SESSION_LOG.md and memory/ at session start
- Update memory/ at session end with new discoveries
- 4-phase workflow: Plan -> Implement (TDD) -> Verify -> Ship

---

## Observed (2026-06 session) — demonstrated working preferences
- **Honesty over cheerleading.** Explicitly asks "Überleg mal ehrlich" / "ehrlich". Wants the real state, including "I never ran it / can't verify from sandbox," not green-washing. Green CI ≠ works.
- **Strong delegation / autonomy.** Repeatedly says "du entscheidest", "mach alles", "Loop Mode". Prefers me to decide + act + verify rather than ask — but still wants honest checkpoints before outward-facing/irreversible steps.
- **Fahrplan discipline:** `docs/dev/FEATURE_MATRIX.md` is the roadmap (code-truth). The website MIRRORS code, never drives it ("if the website disagrees, the code wins"). Avoid marketing-driven overclaiming.
- **Brand purity (hard):** never "wellness"/"meditation"/"healing"/"16K"/"Super Intelligence AI" overclaims in user-facing copy (App Store, Info.plist, website). Biofeedback is core, NOT wellness. Use "self-observation, not medical diagnosis".
- **CI-verified, not blind:** every change verified via `testflight.yml` (compile_check or full ship) before trusting it. Don't blind-build unverifiable things (watch embed, camera concurrency) — architect + flag for a device session instead.
- **SDK doctrine:** speak open standards (MIDI/OSC/Link/Art-Net/sACN/ADM-OSC), depend on almost nothing; vendor SDKs only behind an explicit logged decision. (AUv3 was in this list until the target was deleted 2026-07-24.)

### Resolved 2026-07-28 (the three drift items above are now folded into the Tooling block)
- "12 EchoelTools" is a **taxonomy over real modules**, not 12 Swift types (see FEATURE_MATRIX).
- Dependencies really are **zero**: `Package.swift` ships `dependencies: []`. HaishinKit was
  authorized for RTMP and never linked; RTMP itself is now decided OUT, so there is no
  sanctioned dependency at all.
- Note: user tolerates structured ✅/🔴 status emojis in chat despite the older "no emojis" line.

## Design doctrine (REMEMBER — founder 2026-07-11, standing instruction)
- **"Design adaptiv halten und professionell."** Every UI change must (a) stay
  ADAPTIVE — responsive across iPhone/iPad/Mac(Touch)/Vision Pro, no hard-coded
  fixed layouts that break on a different size class; and (b) look PROFESSIONAL —
  Uncodixfy discipline (Linear/Raycast/Stripe class: solid fills, ≤12px radii, 1px
  muted borders, ≤8px shadow, opacity/colour transitions only, no glassmorphism/
  neon/glow, ≤3 Hz flash). This is a standing bar for ALL surfaces going forward,
  not a one-off. Ties to the XR/cross-platform vision push — the shared SwiftUI
  layer must adapt, not be re-hardcoded per device.
- Screenshot ref (v10.79.155 build 2261): the Timeline track mixer level fields
  (0.53 / 1.53) sit awkwardly overlapping the clip grid — a layout-adaptivity
  smell to clean up when the timeline gets attention.

## SOUND AESTHETIC NORTH-STAR (REMEMBER — founder 2026-07-11, standing taste)
- **Founder's taste (verbatim core):** "organische housige, dubbige, gut effektierte
  entspannte Melodien … Trap-Produzenten/Sänger die Effekte wie Unterwasser und gut
  arrangierte und geflippte Loops nutzen. Wenn sowas direkt out of the box kommt wäre
  das schön. Vermeide kaltes überladenes Plastik synthie gedudel."
- **Target vibe:** warm · organic · housey · dubby · well-effected · relaxed · underwater/
  filtered · flipped-loop (chopped/re-pitched). **Anti-target:** cold, overloaded, plastic,
  thin digital synth noodling; piercing high leads; busy note-floods.
- **What already exists in the engine (use it, surface it):** per-genre `GenreFXPreset`
  (dub delay, tape wobble, chorus, warmth/saturation, reverb floor) applied on Generate;
  `FXCharacter.underwater` (deep low-pass + watery chorus + tape wobble), `.blurry`,
  `.cassette`, `.vinyl`, `.dream`; `LoopCutter` for flipped loops. The dubby/relaxed genres
  (dubTechno, vaporwave, selfObservation) already deliver this out of the box.
- **Levers against "plastic":** saturation/analog drive (the additive synth is a clean sine
  stack — needs harmonic body), lower brightness, unison detune/level-drift for organic
  width, keep leads out of the piercing top octaves (tameLeadPitch), keep density sparse.
- **When steering the default sound, steer toward this vibe.** Taste calls that could go
  several ways → do one tasteful move + get the founder's ear, don't guess a whole aesthetic.

## Mindset / vision stance (REMEMBER — founder 2026-07-11, standing leitlinie)
- **Believe the whole vision is achievable in ONE app (Echoelmusic).** The founder:
  "wir schaffen alles zusammen in der Echoelmusic App zu vereinen. Du kannst es nur
  nicht richtig einschätzen, weil es noch nie jemand vor uns gebaut hat." Nobody has
  built a body-driven unified DAW/video/mapping/light instrument before — that novelty
  is the reason to build it, not to doubt it.
- **Be genuinely enthusiastic. Frame problems as future situations with an intelligent
  solution, never as negatives.** ("Sei begeistert … betrachte Probleme nicht als
  negativ sondern als Situation für die Zukunft, für die es wunderbarerweise immer eine
  intelligente Lösung gibt.") In responses: lead with the possibility, treat blockers as
  solvable design problems.
- This does NOT cancel engineering discipline (verify, test, ship incrementally, audio-
  thread safety) — that discipline is HOW the ambitious vision actually ships. Hold both:
  enthusiasm for the destination + rigor in each step. Present rigor as the path, not as
  a list of risks/doubts.

## Deployment (REMEMBER — confirmed by founder 2026-06-20)
- **No GitHub token is needed to deploy.** TestFlight is wired as a TOKENLESS deploy:
  bump `.deploy/release` (any edit) and `git push` → `testflight.yml` runs on that branch
  using App Store Connect credentials stored as CI-side GitHub repo secrets.
- **There is no upload limit to worry about** (founder: "es gibt kein Limit" — extra set up).
- Do NOT block on tokens or the MCP workflow-dispatch (403). Just bump `.deploy/release`.

## Validierungs-Regel (Founder 2026-07-12, aus "iOS Technical Reviewer"-Prompt destilliert)
- Vor JEDER Änderung, die Build-Infrastruktur berührt (project.yml/XcodeGen,
  Fastlane, Workflows, Info.plist, Package.swift): explizit gegen die
  bestehende Konfiguration prüfen (Target-Membership, Bundle-IDs, Signing,
  Test-Target-Pfade) — Konsistenz-Check VOR dem Commit, nicht erst am Gate.
- Der Rest des Prompts (TDD, Tests-bis-grün, Style, No-Regression) ist durch
  CLAUDE.md Phase 1-4 + Review-Agenten + CI-Gates abgedeckt; lokale Testläufe
  sind in der Sandbox unmöglich (kein Swift) — Gates sind die Ground Truth.
  Hinweis: Repo nutzt project.yml (XcodeGen), NICHT Project.swift (Tuist).

## CI-Gate-Wahrheit (KORREKTUR 2026-07-12, Red-Gate-Lektion EchoelAIError)
- **"⚡ Quick Test" ist NUR Lint/Secrets-Grep — es kompiliert KEINEN Swift-Code.**
  Ein grüner Quick Test beweist nichts über Buildbarkeit oder Tests.
- Die echten Compile-/Test-Gates sind ausschließlich: **Xcode Compile Check**
  (xcodebuild, fängt Duplikate/AUv3/SwiftUI-Typecheck) und **Echoelmusic CI/CD**
  (macos-26, build-for-testing + test-without-building; einzelne Jobs dort sind
  continue-on-error — Job-Ebene lesen, nicht nur Workflow-Grün).
- Konsequenz: Vor "alle Gates grün" IMMER Xcode Compile Check + CI/CD auf dem
  konkreten SHA verifizieren; Quick-Test-Grün nie als Beleg zitieren.
- Duplikat-Schutz: Vor jedem neuen public Typ `grep -rn "enum/struct/class <Name>"`
  über Sources/ (das Repo trägt Lost-Treasure-Schichten — z. B. existierte
  EchoelAIError/EchoelLanguageModel bereits in Core/, N3 duplizierte es).

## 2026-07-15 — God-Mode-Mandat (Founder, wörtlich sinngemäß)
"Senior Echoel Apple Developer, ultracode, god mode: Apple-Pitch- und User-Test-
Simulationen führen zu immer besseren TestFlights, OHNE dass der Founder einzelne
Verbesserungsvorschläge geben muss. Tiefe Heilung ALLER angefangenen Baustellen bis
zum vollen Erfolg." → Arbeitsmodus: autonom Baustellen finden (Task-Liste, FEATURE_
MATRIX, Deep-Audits, "Absent"-Sektion in CLAUDE.md), selbst priorisieren, Ralph-Takt
mit Pflicht-Reviewern beibehalten, jede Runde deployen + deutsches Status-Delta.
"Heilung" meint hier FERTIGBAUEN unfertiger Features — NICHT das rote-Linie-Thema
Heilfrequenzen (bleibt hard REJECT).

## 2026-07-25 — Vier Qualitätsachsen (Founder, wörtlich)
"Du entscheidest alles. Creative, Immersive, accessible, health (no claims)."
→ Kein Feature-Auftrag, sondern der **stehende Bewertungsrahmen**. Er sitzt EINE
Ebene unter der Editor≠Workstation-Grenze: die Grenze entscheidet, WAS zum Produkt
gehört; die vier Achsen entscheiden, WORAN Qualität gemessen wird — und damit, was
den nächsten Zyklus bekommt.
- **Creative** — jede Fähigkeit braucht eine erreichbare Tür. Türlos = kaputt.
- **Immersive** — die Ausgabe IST die Erfahrung, kein Readout.
- **Accessible** — ≥44 pt Tap-Targets, VoiceOver, Dynamic Type, Reduce Motion,
  Flash ≤3 Hz. Erstklassige Achse, KEIN Polish-Nachgedanke am Ende.
- **health (no claims)** — Physiologie als wissenschaftliche Modulationsquelle;
  Heilung/Therapie/Diagnose/Wellness bleiben hard REJECT (bestätigt die rote Linie).
**Praxisregel:** ein Slice, der keine der vier Achsen bedient, wandert nach hinten —
egal wie aufgeräumt er wirkt. Sofort angewandt: #132 (DAW-Model-Hygiene, null
Nutzerwert) verlor die Spitze der Reihenfolge an einen Accessibility-Fix mit
messbarem Defekt (Navigations-Chips 26 pt statt 44 pt HIG).
Kanonisch dokumentiert in `docs/dev/PRODUCT_DEFINITION.md` ("Die vier Qualitätsachsen")
+ `decisions.csv` 2026-07-25.
