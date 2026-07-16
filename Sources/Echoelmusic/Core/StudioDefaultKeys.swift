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

    // MARK: weather.*

    public static let weatherEnabled = StudioDefault(key: "weather.enabled", value: false)
}
