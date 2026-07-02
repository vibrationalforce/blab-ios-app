# DEEP AUDIT: EngineBus → DSP Connection Map
**Date:** 2026-05-22  
**Scope:** Bio-modulation wiring points between EngineBus pub/sub and DSP/Audio engines  
**Status:** READ-ONLY ANALYSIS — Zero code changes, purely investigative

---

## 1. PUBLIC MODULATION SURFACE (DSP Classes)

### EchoelDDSP (Harmonic+Noise Synthesizer) — **PRIMARY TARGET**
Modulation candidates (public properties accepting [0..1] floats):
- **`harmonicity`** [0..1]: blend harmonic ↔ noise (coherence maps here best)
- **`brightness`** [0..1]: spectral envelope tilt (HRV variability drives this)
- **`amplitude`** [0..1]: global output level (breathing depth)
- **`vibratoDepth`** [0..1]: modulation amount per note (heart rate)
- **`vibratoRate`** [Hz]: LFO speed for vibrato (heart rate BPM normalization)
- **`filterCutoff`** [20-20000 Hz]: resonant SVF cutoff (coherence opens filter)
- **`reverbMix`** [0..1]: wet/dry blend (HRV → spatial character)
- **`noiseLevel`** [0..1]: noise amplitude (inverse coherence for tension/grit)
- **Method: `applyBioReactive(coherence, hrvVariability, heartRate, breathPhase, breathDepth, lfHfRatio, coherenceTrend)`** — **READY TO WIRE**

### EchoelCellular (Cellular Automata Synthesizer) — **SECONDARY TARGET**
- **`coherence`** [0..1]: rule selection (didSet updates rule based on coherence)
- **`frequency`** [Hz]: fundamental pitch
- **`evolutionRate`** [steps/sec]: CA evolution speed (HRV → glacial to frantic)
- **`gain`** [0..1]: output amplitude
- **`smoothing`** [0..1]: state interpolation (breathing depth for smoothness)

### EchoelModalBank (Physics Modal Resonators) — **DORMANT / NOT INSTANTIATED**
- **`damping`** [0..1]: ring decay time (HRV inversely → long/short tails)
- **`brightness`** [0..1]: high-frequency mode emphasis
- **`strikeVelocity`** [0..1]: excitation strength
- **`continuousExcitationLevel`** [0..1]: breath-driven sustained excitation
- **`frequency`** [Hz]: fundamental pitch

### EchoelSVFilter (State Variable Filter) — **EMBEDDED IN EchoelDDSP.filter**
- **`cutoff`** [20-20000 Hz]: resonant cutoff frequency
- **`resonance`** [0-1]: Q / peaking emphasis
- **Mode switching:** lowpass ↔ highpass ↔ bandpass ↔ notch

### EchoelLFO (Modulation Oscillator) — **EMBEDDED IN EchoelDDSP.filterLFO**
- **`rate`** [Hz]: LFO sweep speed
- **`depth`** [0..1]: modulation amplitude
- **`waveform`:** sine / triangle / square / sawtooth / sample-and-hold

### EchoelEntrainment (Brainwave Entrainment) — **EMBEDDED IN EchoelDDSP.entrainment**
- **`band`** [BrainwaveBand]: delta/theta/alpha/beta/gamma (10 Hz for alpha default)
- **`depth`** [0..1]: amplitude modulation envelope strength

### EchoelVDSPKit (DSP Utility Functions) — **NOT A SYNTH, UTILITY ONLY**
- `EchoelComplexDFT`: forward FFT (no modulation targets)
- `EchoelRealFFT`: real-to-complex FFT (no modulation targets)
- **No public control parameters** — used by MicrophoneManager for analysis only

---

## 2. INSTANTIATION POINTS & DEPENDENCY CHAIN

### Active Instantiations (in current flow EchoelmusicApp → StudioRoot → BeatTab):

#### **SoundscapeEngine** (Deprecated but defined)
- **Location:** `/Core/SoundscapeEngine.swift`
- **Instantiations inside SoundscapeEngine:**
  - `voiceRoot = EchoelDDSP(sampleRate: 48000)` (line 37)
  - `voiceFifth = EchoelDDSP(sampleRate: 48000)` (line 39)
  - `voiceOctave = EchoelDDSP(sampleRate: 48000)` (line 41)
  - `voiceHigh = EchoelDDSP(sampleRate: 48000)` (line 43)
  - `textureSynth = EchoelCellular(...)` (line 60-68)
- **Reachability:** NOT instantiated in EchoelmusicApp, NOT referenced in StudioRoot, NOT used in BeatTab
- **Status:** **ORPHANED** — SoundscapeEngine itself never created; its DDSP voices are unreachable from the main app flow

#### **BeatPlayer** (Active)
- **Location:** `/Sequencer/BeatPlayer.swift`
- **Instantiations:**
  - Contains `SamplerVoice` array (one-shot WAV players, not DDSP/Cellular)
  - No DSP synthesizers, only sample playback
- **Reachability:** Injected into StudioRoot as `@State private var beatPlayer: BeatPlayer` (EchoelmusicApp line 11), used in BeatTab

#### **AudioEngine** (Active)
- **Location:** `/Audio/AudioEngine.swift`
- **Contains:**
  - `AutoMixChain()`: EQ + gain node (no bio-modulation surface)
  - `RetroCapture()`: ring buffer (no modulation)
  - `SingleExport()`: WAV/AAC mastering (no modulation)
  - `MicrophoneManager()`: FFT analysis only (outputs `frequency`, `audioLevel`, no modulation inputs)
- **Reachability:** Instantiated in EchoelmusicApp (line 25), injected into StudioRoot, started at launch

#### **EngineBus** (Active — THE CENTRAL PUB/SUB HUB)
- **Location:** `/Core/EngineBus.swift`
- **Instantiation:** `_bus = State(wrappedValue: EngineBus())` (EchoelmusicApp line 31)
- **Topics published:**
  - `bioFrames`: Lock-free SPSC queue of `BioSampleFrame` (audio-thread consumers read here)
  - `controllerEvents`: Lock-free SPSC queue of `ControllerEvent` (MIDI events)
  - `bioEvents`: Lock-free SPSC queue of `BioEvent` (discrete bio events)
- **Current Publishers:**
  - `HealthKitBioPublisher()`: publishes to `bus` (line 81 of EchoelmusicApp)
  - `PolarH10BioPublisher()`: publishes to `bus` (line 84)
- **Current Subscribers:** **NONE** — queues are filled but not consumed by any DSP voice

#### **Bio Publishers** (Active, isolated)
- `HealthKitBioPublisher`: reads from HealthKit, calls `bus.publish(bio: frame)`
- `PolarH10BioPublisher`: reads from Polar H10 BLE, calls `bus.publish(bio: frame)`
- **Reachability:** Instantiated conditionally in EchoelmusicApp, started in `.task` block
- **Status:** Publishing successfully but **no consumer** reads their frames

---

## 3. AUDIO ENGINE ARCHITECTURE & MODULATION POINTS

### Master Audio Graph
```
masterPlayerNode → masterMixer → AutoMixChain (EQ → gainNode) → mainMixerNode → hardware output
                                      ↑ (metering tap installed)
```

### Problem: No Synth Voice in Beat-Only MVP
- **BeatPlayer** uses only `SamplerVoice` (fixed WAV playback, not bio-modulated)
- **SoundscapeEngine's DDSP voices** exist but are never instantiated
- **AudioEngine** has **no synthesis path** that accepts bio parameters
- **No voice node** is attached to the master AVAudioEngine graph where bio-modulated DDSP could feed

### Cheapest Modulation Integration Path
1. **Create a new `BioReactiveSynthesizer` node** wrapping the 4 DDSP voices from SoundscapeEngine
2. **Attach to masterEngine** as an AVAudioSourceNode (like BeatPlayer does)
3. **Subscribe to `EngineBus.bioFrames`** and call `voice.applyBioReactive()` on each frame
4. **Mix with BeatPlayer output** via masterMixer (both feed masterMixer, master mixer sends to AutoMixChain)
5. **Gating:** Start/stop via button; amplitude control via slider

---

## 4. MICROPHONEMANAGER & MIDIINPUT AS CONTROLLER PUBLISHERS

### MicrophoneManager (Audio Analysis Only)
- **Current capability:** FFT frequency detection, audio level metering
- **Cannot be a ControllerEvent publisher:** Does not generate normalized [0..1] events
- **Workaround:** Wrap `audioLevel` [0..1] and `frequency` [Hz] in a periodic timer that publishes `ControllerEvent` (CC 1 = modulation wheel, CC 11 = expression)
- **Cost:** Minimal — add a timer that polls `audioLevel` every 50ms, enqueues to `bus.controllerEvents`

### MIDIInput (Ready)
- **Location:** `/Audio/MIDIInput.swift`
- **Already parses:** noteOn, noteOff, CC, pitchBend into normalized [0..1] values
- **Callbacks:** `onNoteOn`, `onCC`, `onPitchBend` (set by SoundscapeEngine but **currently unused**)
- **Cost to wire:** Call `bus.publish(controller: ControllerEvent(...))` inside the callback handlers
- **Status:** **READY TO SHIP** — only need 3 lines of code per handler

---

## 5. DORMANT/DEPRECATED MODULES — REACHABILITY AUDIT

| Module | File | Instantiated? | Referenced? | Status |
|--------|------|---------------|-------------|--------|
| **SoundscapeEngine** | Core/SoundscapeEngine.swift | NO | NO | Defined, never created; 4 DDSP voices unreachable |
| **ClipEngine** | Core/ClipEngine.swift | NO | NO | Orphaned, zero references |
| **WeatherProvider** | Core/WeatherProvider.swift | YES (inside SoundscapeEngine only) | NO (SoundscapeEngine never created) | Indirectly orphaned |
| **CircadianClock** | Core/CircadianClock.swift | YES (inside SoundscapeEngine only) | NO | Indirectly orphaned |
| **BioSourceManager** | Bio/BioSourceManager.swift | NO | NO | Replaced by HealthKitBioPublisher + PolarH10BioPublisher + EngineBus |
| **OuraRingClient** | Bio/OuraRingClient.swift (690 LOC) | NO | NO | Orphaned; Oura integration moved to PolarH10-like pattern |
| **MotionActivityProvider** | Bio/MotionActivityProvider.swift (164 LOC) | NO | NO | Orphaned; motion → `EngineBus.latestBio.motionEnergy` |
| **MomentCaptureView** | Views/MomentCaptureView.swift | NO | NO | Not in TabView; orphaned meditation UI |
| **MasterView** | Views/MasterView.swift | NO | NO | Orphaned master volume UI |
| **SoundscapeView** | Views/SoundscapeView.swift | NO | NO | Orphaned soundscape preset UI |
| **MetalBioView** | Views/MetalBioView.swift | NO | NO | Orphaned GPU bio visualization |

**Verdict:** CLAUDE.md correctly lists them as "kept compilable, not initialized." None are reachable from EchoelmusicApp → StudioRoot → BeatTab.

---

## 6. PUBLIC MARKETING COPY vs. CURRENT REALITY

### README.md Claims
```
| Tab | What you do |
|---|---|
| Beat | 16-step × 8-track drum sequencer with sampler pads. ✓ IMPLEMENTED |
| Record | Sing, rap, record an instrument over the beat. ✗ PLACEHOLDER |
| Video | Capture 1080p30 video on the iPhone camera. ✗ PLACEHOLDER |
| Share | Live-stream RTMP to YouTube / Twitch / Facebook. ✗ PLACEHOLDER |
```
**Claim:** "Make Beats. Record Video. Stream Live."  
**Reality:** Beat tab only; Record/Video/Share show "Coming in v1.1" placeholder text.  
**Gap:** No mention of bio-reactivity, no "first bio-reactive performance instrument" positioning.

### CLAUDE.md Brand Statement
```
Echoel — Make Beats. Record Video. Stream Live.

The product replaces FL Studio Mobile + Ableton + iPhone-Camera + InShot + OBS in one iPhone app.
NEVER use "BLAB", "Vibrational Force", or legacy bio-wellness/soundscape branding in user-facing copy.
```
**Implication:** All bio-wellness/soundscape narrative has been excised; purely a DAW now.

### Contradictions Found
1. **SoundscapeEngine** still exists with full bio-modulation mappings but is never instantiated
2. **HealthKit/PolarH10 publishers** are wired and publishing but have **zero subscribers**
3. **No mention** in README of biofeedback or health integration (was there in earlier strategy docs?)
4. **EngineBus** is fully wired for bio-modulation but the UI/synth to consume it does not exist

---

## 7. ACTIONABLE CONNECTION POINTS

### Highest-Priority Wiring (Minimal Invasiveness)

#### **1. Wire DDSP Voices to EngineBus** ← CHEAPEST
- **Action:** Create `BioReactiveDDSPNode` wrapping SoundscapeEngine's 4 voices
- **Wiring:** Subscribe to `EngineBus.bioFrames`, call `voice.applyBioReactive()` on each frame
- **Lines of code:** ~80 (init, audio render loop, bio frame subscriber)
- **Risk:** NONE — SoundscapeEngine already has complete bio-mapping logic
- **Where:** New file `Audio/BioReactiveDDSPNode.swift` OR extend SoundscapeEngine

#### **2. Wire MIDIInput to EngineBus** ← READY-TO-SHIP
- **Action:** In MIDIInput callbacks, call `bus.publish(controller: ControllerEvent(...))`
- **Lines of code:** 6 per handler × 4 handlers = 24 lines
- **Risk:** NONE — MIDIInput already parses and normalizes values
- **Benefit:** Any MIDI device (keyboard, pad controller, MPE synth) immediately feeds EngineBus

#### **3. Wire MicrophoneManager to EngineBus** ← FUTURE
- **Action:** Create a timer that polls `audioLevel` and `frequency`, publishes as CC events
- **Lines of code:** ~30
- **Risk:** Low — non-critical path
- **Benefit:** Microphone amplitude and detected pitch become modulation sources

#### **4. Add UI Buttons to Enable/Disable Bio-Modulated Synth** ← VISIBILITY
- **Action:** BeatTab checkbox to toggle SoundscapeEngine's DDSP voices on/off (mute/solo)
- **Lines of code:** ~15 (toggle state, slider for mix level)
- **Benefit:** User can hear bio-reactivity immediately; no code risk
- **Where:** BeatTab.swift, near transport controls

---

## SUMMARY TABLE: Connection Readiness

| Component | Current State | Bio-Ready? | Effort | Blocker |
|-----------|---------------|-----------|--------|---------|
| EngineBus | ✓ Built, publishing | ✓ YES | 0 | None |
| HealthKit/Polar Publishers | ✓ Active | ✓ YES | 0 | None |
| EchoelDDSP (harmonicity, brightness, amplitude, etc.) | ✓ Full bio mappings | ✓ YES | 0 | **No subscriber** |
| SoundscapeEngine (4 DDSP voices) | ✓ Defined | ✗ Orphaned | 80 LOC | **Never instantiated** |
| MIDIInput | ✓ Parsing MIDI | ✓ Trivial | 24 LOC | **Not publishing to bus** |
| MicrophoneManager | ✓ FFT analysis | ✓ Trivial | 30 LOC | Non-critical |
| AutoMixChain (EQ/mastering) | ✓ Active | ✗ NO | N/A | Not a synth target |

---

## RECOMMENDATION

**Immediate (v10.1):** Wire `EchoelDDSP` voices as an optional synthesis layer:
1. Create `BioReactiveDDSPNode.swift` (inherit from SoundscapeEngine pattern)
2. Attach to masterEngine as a second source (mix with BeatPlayer)
3. Subscribe to `EngineBus.bioFrames` and pump into `voice.applyBioReactive()`
4. Add UI toggle in BeatTab to enable/disable

**Cost:** ~100 LOC  
**Risk:** ZERO — no changes to existing code paths  
**Benefit:** Immediately demonstrates "first bio-reactive performance instrument" without touching beat sequencer  
**Timeline:** 2–4 hours including UI

---

*Report generated 2026-05-22 by automated codebase audit. No code modifications made.*
