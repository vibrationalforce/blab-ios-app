//
//  StudioDefaultKeys.swift
//  Echoelmusic — Core
//
//  ONE source of truth for every SHARED @AppStorage preference: the storage key
//  and its canonical fresh-install default (H15-KEYSTORE). @AppStorage defaults
//  are PER-DECLARATION — before the key is first written, every view falls back
//  to its OWN literal, so two views declaring the same key with different
//  literals silently disagree on fresh installs. That class shipped real bugs:
//  the transport chrome showed "loop N/4" while the instrument composed 8 bars
//  (H15-LOOPBARS, v271), the EchoelSynth panel said "Show visual window" while
//  the floating visual was already showing (visual.floating.visible true/false
//  split), and the visual's MP4 filename carried a stale genre (.vaporwave vs
//  the founder's .selfObservation).
//
//  RULE: any @AppStorage key read in MORE THAN ONE view MUST be declared as
//      @AppStorage(StudioDefaultKeys.x.key) private var x = StudioDefaultKeys.x.value
//  Never re-type the string or the default literal at a second site. Defaults
//  here are FOUNDER decisions — change them only on a founder ask, and keep
//  StudioDefaultKeysTests in sync (it pins these values so a drive-by edit at
//  any declaration site can never silently diverge again).
//

import Foundation

/// A shared preference: its storage key + the canonical fresh-install default.
/// Pure value carrier — reading/writing stays with @AppStorage at the use site.
public struct StudioDefault<Value: Sendable>: Sendable {
    public let key: String
    /// The canonical default, used only until the key is first written.
    public let value: Value

    public init(key: String, value: Value) {
        self.key = key
        self.value = value
    }
}

/// Namespace for every shared studio/visual/touch preference (WeatherMood.Param
/// spirit: one typed home instead of scattered string literals).
public enum StudioDefaultKeys {

    // MARK: studio.* — composition panel (semantic owner: EchoelStudioView)

    /// #603 B1 — the founder's on/off guide ("an- und ausschaltbarer Guide der hilft die
    /// App zu bedienen und zu verstehen"). Read by TWO views — `WorkspaceView` mounts the
    /// `GuideOverlay`, `EchoelStudioView`'s Save & Export panel hosts the toggle — hence
    /// H15-KEYSTORE. OFF on fresh installs, deliberately: first contact belongs to
    /// `OnboardingView` + the instrument home ("app open → it lives"); the guide is
    /// invited, never imposed. Founder may flip this default — it is one value, here.
    public static let guideVisible = StudioDefault(key: "studio.guideVisible", value: false)

    /// #604 (GUI-Board Scheibe 1, UX-Audit #2): the instrument hint's retire flag. The
    /// OLD contract wrote this after ONE ~4.5 s showing — miss it once and the app's only
    /// statement of the core mechanic never returned. NEW law: the hint retires when the
    /// lesson is LEARNED — `startBioSource()` writes it (the user found Start, step 1 of
    /// the hint's own sentence) — or after the showing cap below. Two writers in two
    /// views, hence H15-KEYSTORE. The key STRING is unchanged on purpose: users who
    /// already saw it once stay retired; only fresh installs get the patient behaviour.
    public static let instrumentHintSeen = StudioDefault(key: "onboard.instrumentHintSeen", value: false)

    /// #604 — how many times the hint has been shown. At `instrumentHintShowCap` the
    /// overlay retires itself even unlearned: the old once-ever contract existed to stop
    /// the hint nagging on every fullscreen toggle, and that concern survives as this cap
    /// instead of dying with the contract.
    public static let instrumentHintShows = StudioDefault(key: "onboard.instrumentHintShows", value: 0)

    /// #604 — the cap, ONE definition (#416): read by the overlay's retire check and by
    /// the guard test. 5 showings ≈ five fullscreen entries — enough chances to read two
    /// lines, bounded enough never to feel like a nag.
    public static let instrumentHintShowCap = 5

    /// #608 (Founder 2026-08-15, „optionaler Automodus … vibe catcht und harmonisiert") —
    /// the Auto-mode master switch. OFF on fresh installs, deliberately: steering the
    /// user's mood dials without being asked is the one thing this feature must never
    /// do first. Read by TWO sites in EchoelStudioView — the `AutoModeRow` toggle in
    /// `bioPanel` (the door) and `makeComposerInput` (the fold that consults
    /// `AutoAttune`) — hence H15-KEYSTORE. Tempo is NOT steered by this switch in any
    /// state: the only bio→clock path stays the Flow-Servo (T1/T2,
    /// `AutoModeStartsOffAndOwnsNoTempoTests`).
    public static let autoMode = StudioDefault(key: "studio.autoMode", value: false)

    /// Founder 8-bar produce-able phrase (see EchoelStudioView loop picker).
    public static let loopBars = StudioDefault(key: "studio.loopBars", value: LoopBarLength.eight)
    public static let genre = StudioDefault(key: "studio.genre", value: MusicStyle.selfObservation)
    public static let scale = StudioDefault(key: "studio.scale", value: Scale.minor)
    public static let rootIndex = StudioDefault(key: "studio.rootIndex", value: 0)
    public static let lockBPM = StudioDefault(key: "studio.lockBPM", value: false)
    public static let lockedBPM = StudioDefault(key: "studio.lockedBPM", value: 70.0)
    public static let loudnessTarget = StudioDefault(key: "studio.loudnessTarget",
                                                     value: LoudnessTarget.streaming.rawValue)
    /// #736 — the master-bus tonal character (`AutoMixChain.Preset`), stored as its raw value.
    ///
    /// ⚠️ `balanced` IS THE SHIPPED CURVE AND MUST STAY THE DEFAULT. It is the one retuned
    /// 2026-06-23 from an FFT of a real take, and until #736 it was the ONLY curve any session
    /// could hear — the property had no writer anywhere. Persisted rather than live-only
    /// because its neighbour in the same panel (`loudnessTarget`) is, and because a tonal
    /// character is a studio setting, not a performance gesture like Blackout.
    public static let masterCharacter = StudioDefault(key: "studio.masterCharacter",
                                                      value: "balanced")
    /// #253 A3 — the rhythm character the BASS walks in, or `""` meaning "the genre's own".
    ///
    /// ⚠️ **`""` IS THE DEFAULT AND IT MUST STAY THE DEFAULT** until a founder says otherwise. The
    /// genres were curated by ear, twice (#81, #125). A character stored here overrides the bass
    /// rhythm for EVERY genre, so shipping any non-empty default would flatten Disco, Doom and Dub
    /// Techno onto one bassline — precisely the "plötzlich klingt alles gleich" defect those two
    /// tasks fixed. Same shape and same reasoning as `fieldAutoPlayMotion`: off is a real stored
    /// state, and an unrecognised value reads as off rather than as some substituted character.
    ///
    /// Stored as `RoleRhythm.Character`'s raw string rather than an index, so inserting a seventh
    /// character cannot silently re-point every saved take.
    public static let bassRhythm = StudioDefault(key: "studio.bassRhythm", value: "")

    /// #253 A4 — the rhythm character the PAD re-articulates in, or `""` meaning "the genre's own".
    ///
    /// ⚠️ The `""`-must-stay-the-default half of the `bassRhythm` note above applies here, and MORE
    /// sharply: the pad is the genre's biggest audible surface (drums are gone since #166/#167), so a
    /// non-empty default would not merely flatten the basslines — it would make every genre
    /// re-articulate its chords on ONE grid.
    ///
    /// Its OTHER half does NOT carry over, and saying "word for word" (which this note did for one
    /// commit) invites the next reader to copy the wrong caveat: the bass row is inert unless
    /// `appendBass`'s three-part walking gate holds, and the whole point of the pad row is that no
    /// such gate exists — every non-arpeggiated pad path routes through the override.
    public static let padRhythm = StudioDefault(key: "studio.padRhythm", value: "")

    // MARK: - Pad chord shape (#581 / the "A7" rows RoleRhythm's docs have been specifying)

    /// ⭐ FOUNDER, 2026-08-13: *"Ich find es fehlt eine Sektion mit slidern der aus den Pad
    /// Sounds rhythmische chords macht … Fehlt noch."* These three are that section, and none of
    /// them is new machinery: `RoleRhythm.Params` has carried `gate`/`accent`/`evolve` with
    /// measured semantics all along, and `BioComposer.roleRhythmOnsets` hard-coded exactly these
    /// three literals under a comment reading *"The three dials no role UI exposes"*. The engine
    /// named the gap; this is the surface.
    ///
    /// ⚠️ THE DEFAULTS ARE THE OLD LITERALS, EXACTLY. 0.8 / 0.4 / 0.2 are what
    /// `roleRhythmOnsets` wrote before the rows existed, so a player who never opens the section
    /// — and every stored project — sounds bit-identical. Changing one of these numbers re-voices
    /// the chord of every user who has not touched that row, which is the `RoleRhythm` header's
    /// own standing warning about `Params` defaults, one level out.
    ///
    /// ⚠️ AND THEY ONLY DO ANYTHING WHILE A PAD CHARACTER IS CHOSEN. With `padRhythm == ""` the
    /// composer never calls `roleRhythmOnsets` at all (`if let character = padRhythm`), so the
    /// rows are disabled rather than merely inert — a dial that sweeps its range in silence is
    /// the lying-control defect this repo has paid for three times (#135/#164/#227).
    public static let padGate = StudioDefault(key: "studio.padGate", value: 0.8)
    /// See `RoleRhythm.Params.accent`. How deep the accents cut, 0…1 — but HOW MUCH that can be
    /// is the character's choice (measured spread at 1.0: `dynamic` ≈ 5.8 dB … `flowing` ≈ 0.5 dB),
    /// which is why the row reads `Character.accentIsSubtle` instead of hard-coding a list.
    public static let padAccent = StudioDefault(key: "studio.padAccent", value: 0.4)
    /// See `RoleRhythm.Params.evolve`. Bar-to-bar change, 0…1 — and it applies to only TWO of the
    /// six characters (`Character.usesEvolve`). On the other four the row is disabled, because a
    /// value that is stored, persisted and inaudible is worse than one that is absent.
    public static let padEvolve = StudioDefault(key: "studio.padEvolve", value: 0.2)

    /// #275 slice 1 — the eight mood dials as `MoodStorage`'s JSON, or `""` meaning "nothing
    /// stored, use the factory profile".
    ///
    /// ⚠️ `""` IS THE DEFAULT AND IT MUST STAY THE DEFAULT, for a reason unlike its two
    /// neighbours above: there is no "the genre's own mood" to fall back to, so any literal
    /// written here would be a SECOND declaration of `MoodProfile()`'s defaults — and the two
    /// would drift the first time a dial's factory value is retuned. The empty string means
    /// "ask the type", which is why `MoodStorage.decode("")` returns `MoodProfile()` rather
    /// than anything spelled out here.
    ///
    /// ⚠️ ONE KEY, EIGHT VALUES — see `MoodStorage`'s header for why this is a JSON string
    /// rather than eight scalar keys, and specifically why making `MoodProfile`
    /// `RawRepresentable` (the shape `@AppStorage` would prefer) would silently change how
    /// `TimelineLane.mood` already encodes on disk.
    public static let mood = StudioDefault(key: "studio.mood", value: "")

    // MARK: visual.* — immersive visual look + window

    /// Whether the immersive visual is the spectrum→visible DONUT renderer instead of the Metal
    /// field. **Default `false`, and it used to be `true` (#227).**
    ///
    /// ⛔ WHY THE DEFAULT FLIPPED. `SpectralDonutView` is constructed at exactly ONE place —
    /// inside `EchoelStudioView`'s `.fullScreenCover(isPresented: $showVisual)` — and from the
    /// tools-grid removal until #747 `showVisual` had no setter, so that cover could not be
    /// presented. The visual a player could actually reach was `FloatingVisualWindow`, which
    /// never reads this key at all.
    ///
    /// ⭐ THE COVER IS REACHABLE AGAIN (#747) — the "Full screen" button in `visualPanel` — and
    /// the default STAYS `false` anyway. The reason changed, and that is worth stating because
    /// the number did not: `false` used to be the only truthful value; it is now the right
    /// OPENING state. A fresh install lands on the Metal field, which is the identity look, and
    /// the cover's top-bar toggle is how a player asks for donuts. The launch normaliser that
    /// enforced the old reason is DELETED (`normaliseUnreachableDonutMode()`, #227 → #747) —
    /// with a door in place it would have erased that choice on every launch.
    /// With the old default, a FRESH INSTALL showed a filled "Donuts" pill and a readout saying
    /// "Donuts" while the one visible visual drew a Metal look — the #164/#227 lying control, on
    /// first launch, before the player has touched anything. It also skipped the launch look-snap
    /// and the customizer's live re-snap (both guarded by `if !spectralDonuts` in
    /// `EchoelStudioView`), so a persisted look that had fallen out of the slider sequence was
    /// never repaired.
    ///
    /// ⛔ THIS NOTE ALSO CLAIMED, FOR ONE COMMIT, THAT `true` HID `visualBlendControls`. It did
    /// not — that view had ZERO mount sites; the two places that once composed it were comments
    /// recording its removal on 2026-07-07. Caught in review. An unreachable claim inside the
    /// rationale of the commit that removes unreachable claims is the failure itself — but the
    /// damage stayed hypothetical: introduced and retracted the same day (`99c9d13` → `4ef5e68`,
    /// 2026-07-30), caught in review. `visualBlendControls` is deleted as of #324, and the A/B
    /// blend state (`visualStyleB`/`visualBlend` below) is untouched and still slider-driven.
    ///
    /// ⛔ #324's commit message said this note "kept it alive for three weeks". It did not, and
    /// the sentence four lines up ("FOR ONE COMMIT … Caught in review") already said so — the two
    /// stood in the same file. What kept the view alive from 2026-07-07 to 2026-08-01 was the
    /// ordinary failure: present-tense comments about a removal, and no guard.
    ///
    /// The KEY STRING is deliberately unchanged. Its original reason expired with #747 (the
    /// launch normalisation that had to FIND a stored `true` in order to clear it no longer
    /// exists), and a weaker one takes its place: an install that stored `true` before #227 gets
    /// that choice back the moment it opens the cover, and a rename would silently reset it
    /// instead. `VisualLookTruthTests` still pins the string.
    public static let visualSpectralDonuts = StudioDefault(key: "visual.spectralDonuts", value: false)
    public static let visualStyle = StudioDefault(key: "visual.style", value: 5)
    public static let visualStyleB = StudioDefault(key: "visual.styleB", value: 0)
    public static let visualBlend = StudioDefault(key: "visual.blend", value: 0.0)
    public static let visualIntensity = StudioDefault(key: "visual.intensity", value: 1.0)
    public static let visualDetail = StudioDefault(key: "visual.detail", value: 40.0)
    public static let visualMotion = StudioDefault(key: "visual.motion", value: 1.0)
    public static let visualSpread = StudioDefault(key: "visual.spread", value: 1.0)
    public static let visualHue = StudioDefault(key: "visual.hue", value: 0.0)
    /// ⭐ **THIS IS THE SATURATION THAT REACHES THE GPU — the `MetalBioView`/`BioUniforms`
    /// struct defaults are NOT.** All three mounted surfaces (`EchoelStudioView`,
    /// `FloatingVisualWindow`, `ExternalDisplayScene`) pass `saturation:` explicitly from
    /// this `@AppStorage` value, so the struct default is overwritten at every call site and
    /// is only a fallback for a caller that does not exist.
    ///
    /// ⛔ #578 CHANGED THE STRUCT DEFAULTS FIRST AND WOULD HAVE SHIPPED NOTHING. The founder
    /// asked for *"Bunter"* (2026-08-13); the edit moved two `var saturation: Float = 0.82`
    /// to 1.05, transcribed a guard over them, and only a wider `git grep` for the literal —
    /// the §4 step that is supposed to come FIRST — found the fourth copy that actually
    /// renders. A guard over the struct defaults alone would have been green while the
    /// picture stayed exactly as grey as before: pinning a value the GPU never sees.
    ///
    /// ⚠️ AND EVEN HERE IT ONLY REACHES AN UNWRITTEN KEY. `@AppStorage` prefers a stored
    /// value, so anyone who has ever dragged the Saturation field keeps what they dragged.
    /// That is correct — a user's own setting outranks a default — but it means this change
    /// is NOT a guarantee that the founder's next build looks different. Say so; do not
    /// report it as "the grey is fixed". The shader-side warm-tint change in the same slice
    /// is unconditional and does reach every install.
    public static let visualSaturation = StudioDefault(key: "visual.saturation", value: 1.05)
    /// Texture (film grain) and Glitter (per-speck twinkle) amounts — the two finishing
    /// stages #578 added with FIXED gains, now user-dialable (founder 2026-08-28: "mehr
    /// Struktur/Textur Regler"). 1.0 = exactly the #578 look; 0 removes the stage; up to
    /// 2 doubles it. Multipliers on the existing shader terms, so the flash-safety
    /// construction (per-speck phase+frequency, static grain) is untouched at any value —
    /// amplitude scaling cannot re-correlate the specks. Same three-surface pass-through
    /// pattern as `visualSaturation` above: these values reach the GPU, the struct
    /// defaults in `MetalBioView.swift` are fallbacks for a caller that does not exist.
    public static let visualTexture = StudioDefault(key: "visual.texture", value: 1.0)
    public static let visualGlitter = StudioDefault(key: "visual.glitter", value: 1.0)
    /// #853B "Structure" — static domain-warp depth. Neutral is 0 (the stage is NEW;
    /// 0 = the exact pre-dial picture), unlike the two multipliers above whose neutral is 1.
    public static let visualStructure = StudioDefault(key: "visual.structure", value: 0.0)
    /// TRUE — the living visual greets a fresh install ("wow von Sekunde 1",
    /// WorkspaceView header monitor). The studio panel's old `false` copy made
    /// its toggle button lie until the key was first written.
    public static let floatingVisualVisible = StudioDefault(key: "visual.floating.visible", value: true)

    // MARK: touch.* — touch instrument feel (shared studio panel ↔ visual window)

    public static let touchMorphDepth = StudioDefault(key: "touch.morphDepth", value: 0.6)
    public static let touchSlideVibrato = StudioDefault(key: "touch.slideVibrato", value: 0.35)
    public static let touchSlideChorus = StudioDefault(key: "touch.slideChorus", value: 0.30)
    public static let touchGlide = StudioDefault(key: "touch.glide", value: 0.0)
    /// The play surface's own LEVEL, as a real gain on its voice's output — not a
    /// velocity trim (founder 2026-07-27: "Play surface sound noch optimieren vom
    /// mixing"). Until now the surface had no level at all: its position in the mix was
    /// baked into `TouchPitchMap.velocity`'s hardcoded 0.45…0.95 range, widened once by
    /// hand in July so played notes would "sich im mix ein bisschen mehr durchsetzen".
    /// That is the level-as-velocity mistake this repo has now corrected three times;
    /// here it becomes a control instead of a constant.
    public static let touchLevel = StudioDefault(key: "touch.level", value: 1.0)
    /// MICRO-VARIATION ("Leben") — founder 2026-07-27: "Alles soll nie statisch gleich
    /// klingend sein sondern leben wie ein echtes Instrument mit micro changes." How much
    /// each note deviates from its neighbours in brightness and attack — and, since #201,
    /// in TIME: it also sets how much a Sync-corrected touch breathes around the grid
    /// (founder's "auch microtime"). That third meaning only bites while `touchSyncStrength
    /// > 0`; with Sync off this is brightness and attack exactly as before. 0 = the old,
    /// bit-identical behaviour; the default is deliberately audible-but-subtle.
    public static let touchLife = StudioDefault(key: "touch.life", value: 0.35)

    /// ULTRASYNC — founder 2026-07-28: "einen Ultrasync … damit das Touch Instrument
    /// immer perfekt im timing ist auch microtime (somit wird ungeschicktes Spielen auch
    /// zum ästhetischen Ereignis)". How far a touch is pulled onto the beat.
    ///
    /// **Default 0 = OFF, and that is deliberate.** This changes when a played note
    /// SOUNDS, which is the most intimate thing about an instrument; nobody should
    /// discover it by surprise after an update. It also only does anything while the
    /// transport runs — with the clock stopped there is no beat to be in time with.
    public static let touchSyncStrength = StudioDefault(key: "touch.sync.strength", value: 0.0)

    /// The musical grid ULTRASYNC quantizes to. Stored as the enum's raw string, so an
    /// unknown value from an older or newer build falls back to this default instead of
    /// refusing to load.
    public static let touchSyncGrid = StudioDefault(key: "touch.sync.grid",
                                                    value: TouchQuantizer.Grid.sixteenth)

    /// The Field's VOICE — the id of the chosen `SynthPatch`, or `""` meaning "follow the
    /// take". Arguably the most user-visible thing this surface persists: losing it silently
    /// reverts the surface to the generated take's sound, which reads as "my patch is gone".
    ///
    /// ⚠️ Promoted here from a raw `@AppStorage("touch.patchID")` literal on 2026-07-29,
    /// during the Field rename. It was one of exactly two `touch.*` keys living outside this
    /// file — and the rename's own regression test claimed to pin "every shared preference
    /// behind the play surface" while covering neither. A literal at the use site is the
    /// shape of the defect that file exists to prevent (#163/#170): change it there and the
    /// test stays green while the setting vanishes.
    ///
    /// Stored as the UUID string, never the patch NAME, which is why the default patch has
    /// been renamed twice without anyone losing their selection.
    public static let touchPatchID = StudioDefault(key: "touch.patchID", value: "")

    /// Whether the note grid is drawn on the play surface. Read by the visual window and
    /// (once the Field panel offers the toggle) by the studio panel — the shared-key rule
    /// applies the moment a second reader appears, and promoting it now is cheaper than
    /// discovering the split later. Same promotion as `touchPatchID` above.
    public static let touchShowGrid = StudioDefault(key: "touch.showGrid", value: false)

    /// SELF-PLAY — founder 2026-07-29: *"Es soll auch eine Möglichkeit geben wie der Synth
    /// selbst spielt ohne das man Touch bedienen muss. Natürlich mit mehreren Parametern."*
    ///
    /// **`""` = off, and that IS the default.** Everything else in this file describes how
    /// the instrument responds when it is played; this one plays it. A generator that runs
    /// unattended must never be inherited from an update, a restored backup, or a key that
    /// happened to be written once — so "off" is a real stored state, not the absence of one.
    ///
    /// Stored as `FieldAutoPlay.Motion`'s raw string rather than an index: the motions are a
    /// deliberately short, audibly distinct set that will gain the ARP as a sixth (#220), and
    /// an index would silently re-point every saved setting the moment one is inserted. An
    /// unknown value falls back to off.
    public static let fieldAutoPlayMotion = StudioDefault(key: "field.autoPlay.motion", value: "")
    /// How many grid cells fire, 0…1. **0 is silence, not "sparse"** — see `FieldAutoPlay`.
    public static let fieldAutoPlayDensity = StudioDefault(key: "field.autoPlay.density", value: 0.5)
    /// How much of the surface the travel covers (0 collapses onto `centre`).
    public static let fieldAutoPlaySpan = StudioDefault(key: "field.autoPlay.span", value: 0.6)
    /// Where the travel is centred, 0 = left edge … 1 = right edge.
    public static let fieldAutoPlayCentre = StudioDefault(key: "field.autoPlay.centre", value: 0.5)
    /// Which octave band it sits in, 0 = bottom … 1 = top.
    public static let fieldAutoPlayBand = StudioDefault(key: "field.autoPlay.band", value: 0.5)
    /// How far it wanders vertically. ⚠️ Below ~0.34 this moves the LIGHT and not the octave —
    /// `y` selects one of three bands, so the wander must span more than a third to cross a
    /// boundary. The default is deliberately sub-threshold; the panel copy must not promise
    /// pitch movement it does not deliver.
    public static let fieldAutoPlayBandDrift = StudioDefault(key: "field.autoPlay.bandDrift", value: 0.2)
    /// Simultaneous points — a chord under a hand that is not there. Capped by
    /// `FieldAutoPlay.maxVoices` wherever it is used.
    public static let fieldAutoPlayVoices = StudioDefault(key: "field.autoPlay.voices", value: 1.0)
    /// Grid cells in one full traverse. Bigger = a slower sweep at the same tempo. Stored as a
    /// Double because that is what `EchoelValueField` binds to; clamped on the way in.
    public static let fieldAutoPlayPeriod = StudioDefault(key: "field.autoPlay.period", value: 16.0)

    /// ARP RHYTHM (#253 A7, founder 2026-07-30: *"Alle Soundrubriken von Pads, Bass bis arp etc.
    /// brauchen noch verschiedene Rhythmus Regler. Verschiedene variablen die interessante,
    /// treibende, hypnotische, dynamische etc. Rhythmus pattern machen"*).
    ///
    /// ⚠️ **EVERY DEFAULT HERE MUST EQUAL `FieldAutoPlay.Params.init`'s `arpRhythm` DEFAULT**, and
    /// that is not tidiness — #253 A2 shipped that default as the arp's actual sound with no UI
    /// involved. A default here that disagrees would silently re-voice the arp for everyone who
    /// updates, in a slice whose entire purpose is to make the setting reachable. Pinned by
    /// `TouchSurfaceStorageKeysTests` against the `Params` default itself, not against a literal.
    ///
    /// `density` is deliberately ABSENT: the Field's own Density row is the ONE rate control, and
    /// `FieldAutoPlay.arpTouches` overwrites the stored copy with it. A second key for the same
    /// musical dimension is the collision `RoleRhythm`'s header already decides.
    ///
    /// `push` now HAS a key — see `fieldArpRhythmPush` below (#258 / A2c, landed with its row in
    /// one commit, as this note demanded).
    ///
    /// Stored as the enum's raw string, so an unknown value from an older or newer build falls back
    /// to this default instead of refusing to load — same contract as `touchSyncGrid` above, and
    /// stated here too because this is the property that decides whether a REMOVED case degrades to
    /// `.driving` or loses the setting.
    public static let fieldArpRhythmCharacter = StudioDefault(key: "field.autoPlay.arpRhythm.character",
                                                             value: RoleRhythm.Character.driving)
    /// Note length as a fraction of one grid cell, before the character's own scaling.
    public static let fieldArpRhythmGate = StudioDefault(key: "field.autoPlay.arpRhythm.gate",
                                                        value: 0.8)
    /// How far the accent pattern swings between soft and hard, 0 = flat.
    public static let fieldArpRhythmAccent = StudioDefault(key: "field.autoPlay.arpRhythm.accent",
                                                          value: 0.4)
    /// Per-note variation — **only `dynamic` and `flowing` read it** (`Character.usesEvolve`), which
    /// is why its row is hidden for the other four rather than shown and ignored.
    public static let fieldArpRhythmEvolve = StudioDefault(key: "field.autoPlay.arpRhythm.evolve",
                                                          value: 0.0)
    /// How far BEHIND its own grid cell a note lands, as a fraction of one cell (#258 / A2c).
    ///
    /// ⚠️ **THE ROW IS 0…`RoleRhythm.maxPush`, WHILE THE MODEL IS BIPOLAR (−0.45…0.45), AND THAT
    /// ASYMMETRY IS DELIBERATE.** `FieldAutoPlay.pushDelaySeconds` folds every value ≤ 0 to "on the
    /// grid" — the consumer schedules the onset LATE with a `Task.sleep`, and there is nothing to
    /// sleep for a note that should have sounded EARLIER. Playing ahead of the grid needs look-ahead
    /// (generate the cell one tick early and hold it), which does not exist. Offering the negative
    /// half would therefore be a dial whose whole left side does nothing — the #164/#227 lying
    /// control, in the one place where the engine's own range invites it. The bipolar range STAYS in
    /// `RoleRhythm.Params.push` because the composer path and a future look-ahead will want it; only
    /// the player-facing row is clamped.
    ///
    /// Default 0: the character's own bias (`syncopated` +0.12 off-beat, `flowing` +0.05) is what
    /// plays until the player asks for more, so a fresh install sounds exactly as it did before this
    /// key existed. Pinned in `TouchSurfaceStorageKeysTests` (the BLOCKING bundle) against
    /// `FieldAutoPlay.Params().arpRhythm.push` rather than against the literal 0, so the day the
    /// arp's shipped timing changes both sides have to move together.
    public static let fieldArpRhythmPush = StudioDefault(key: "field.autoPlay.arpRhythm.push",
                                                        value: 0.0)

    // MARK: midi.*

    /// Inbound Apple Network MIDI (RTP-MIDI, RFC 6295) — **OFF by default (#187,
    /// founder 2026-07-27)**. When on, `MIDINetworkSession.default()` is enabled with
    /// `connectionPolicy = .anyone`, so the device advertises `_apple-midi._udp` and
    /// accepts a session from ANY host on the LAN. That is a genuinely useful stage
    /// feature — a Mac or rtpMIDI sending wireless notes — but it is an INBOUND network
    /// listener, and until this key existed it was armed unconditionally at launch with
    /// no control anywhere in the app. Outbound MIDI/OSC is a thing you point somewhere;
    /// this is a thing that accepts. Those are not the same consent.
    public static let networkMIDI = StudioDefault(key: "midi.networkSession", value: false)

    /// **MPE note layout on the MIDI OUT stream (#713).** Off = every note on channel 1,
    /// which is what shipped. On = notes spread across the 15 member channels of the MPE
    /// lower zone, and the zone RPN is sent when the port opens.
    ///
    /// It exists because the capability was BUILT and had no control anywhere. `MIDIOutput`
    /// has carried `mpeEnabled` and `expressionEnabled` since the MIDI-out slice; both lost
    /// their only surface when the Tools grid was removed, so a player routing to a hardware
    /// rig got plain notes and could not ask for anything else. CLAUDE.md has listed them as
    /// an open capability gap since — "gehören in die Routing-Fläche". (⛔ #713 dated that
    /// removal here as a fact; this clone is shallow and cannot show it — #714 finding F.)
    public static let midiOutMPE = StudioDefault(key: "midi.out.mpe", value: false)

    /// **Per-note expression on the MIDI OUT stream (#713).** Glide/Slide/Press alongside
    /// each note-on, sourced from the body.
    ///
    /// ⚠️ ONLY MEANINGFUL WITH `midiOutMPE`, and that is not a style note — `MIDIOutput`'s
    /// send path is literally `if mpeEnabled, expressionEnabled`, because per-note bend and
    /// pressure need a member channel per note. A switch that can be turned on while MPE is
    /// off would move, persist, and change nothing: this repo's own lying-control class. The
    /// Routing surface therefore DISABLES it while MPE is off rather than hiding it, so the
    /// dependency is visible instead of mysterious.
    public static let midiOutExpression = StudioDefault(key: "midi.out.expression", value: false)

    // MARK: music.*

    /// How pitch classes are SPELLED — `NoteNaming`'s raw value (#232 E, founder 2026-07-29
    /// *"international für alle Kulturen und Hintergründe accessible"*).
    ///
    /// Stored as the raw STRING and not an index, for the reason the arp's motion key gives:
    /// an index silently re-points if the cases are ever reordered, and here that would show a
    /// German user English names (or worse, solfège) after an update, on the control that
    /// decides the key. Read it back through `NoteNaming(stored:)`, never
    /// `NoteNaming(rawValue:)!` — an unrecognised value must land on English, not crash.
    ///
    /// Default `.english`: it is the app's interop spelling and the one every existing
    /// install already sees, so this key changes nothing until someone chooses.
    public static let noteNaming = StudioDefault(key: "music.noteNaming",
                                                 value: NoteNaming.english.rawValue)

    // MARK: weather.*

    public static let weatherEnabled = StudioDefault(key: "weather.enabled", value: false)
}
