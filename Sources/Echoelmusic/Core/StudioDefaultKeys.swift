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

    /// Founder 8-bar produce-able phrase (see EchoelStudioView loop picker).
    public static let loopBars = StudioDefault(key: "studio.loopBars", value: LoopBarLength.eight)
    public static let genre = StudioDefault(key: "studio.genre", value: MusicStyle.selfObservation)
    public static let scale = StudioDefault(key: "studio.scale", value: Scale.minor)
    public static let rootIndex = StudioDefault(key: "studio.rootIndex", value: 0)
    public static let lockBPM = StudioDefault(key: "studio.lockBPM", value: false)
    public static let lockedBPM = StudioDefault(key: "studio.lockedBPM", value: 70.0)
    public static let loudnessTarget = StudioDefault(key: "studio.loudnessTarget",
                                                     value: LoudnessTarget.streaming.rawValue)

    // MARK: visual.* — immersive visual look + window

    public static let visualStyle = StudioDefault(key: "visual.style", value: 5)
    public static let visualStyleB = StudioDefault(key: "visual.styleB", value: 0)
    public static let visualBlend = StudioDefault(key: "visual.blend", value: 0.0)
    public static let visualIntensity = StudioDefault(key: "visual.intensity", value: 1.0)
    public static let visualDetail = StudioDefault(key: "visual.detail", value: 40.0)
    public static let visualMotion = StudioDefault(key: "visual.motion", value: 1.0)
    public static let visualSpread = StudioDefault(key: "visual.spread", value: 1.0)
    public static let visualHue = StudioDefault(key: "visual.hue", value: 0.0)
    public static let visualSaturation = StudioDefault(key: "visual.saturation", value: 0.82)
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
    /// `push` is deliberately ABSENT TOO, for a different reason: `arpTouches` carries it but does
    /// NOT yet honour it (#253 A2b owns displacing a generated onset). A row for it today would be
    /// a lying control (#164/#227) — the key arrives with the behaviour, not before it.
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

    // MARK: weather.*

    public static let weatherEnabled = StudioDefault(key: "weather.enabled", value: false)
}
