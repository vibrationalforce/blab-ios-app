# 🎹 DAW Integration Guide - BLAB iOS App

Complete guide for integrating BLAB's MIDI 2.0 + MPE output with professional DAWs and MPE synths.

---

## 🎯 Quick Start

### **BLAB is now broadcasting:**
- **MIDI 2.0 Virtual Source:** "BLAB MIDI 2.0 Output"
- **Protocol:** MIDI 2.0 UMP (Universal MIDI Packet)
- **Channels:** 1-15 (MPE member channels), 16 (master channel)
- **Resolution:** 32-bit parameter control
- **Pitch Bend Range:** ±48 semitones (4 octaves)

---

## 📱 **iOS MIDI Setup**

### **1. Check MIDI Virtual Source**

After launching BLAB, you should see in console:
```
✅ MIDI 2.0 initialized (UMP protocol)
✅ MIDI 2.0 + MPE enabled via UnifiedControlHub
🎹 MIDI 2.0 + MPE + Spatial Audio Ready
```

### **2. Verify MIDI Connection (iOS Settings)**

**Settings → Music (or Audio MIDI Setup on Mac)**
- BLAB should appear as "BLAB MIDI 2.0 Output"
- Protocol: MIDI 2.0
- Status: Active

---

## 🎛️ **Ableton Live Integration**

### **Setup (Ableton Live 11.3+)**

1. **Preferences → Link, Tempo & MIDI**
   - **Track:** Enable "BLAB MIDI 2.0 Output"
   - **Remote:** Enable "BLAB MIDI 2.0 Output"
   - **MPE:** Enable MPE mode

2. **Load MPE Instrument**
   - Wavetable (MPE mode enabled)
   - Sampler (MPE mode)
   - Third-party: Equator 2, Cypher2, Surge XT

3. **Create MIDI Track**
   - **MIDI From:** BLAB MIDI 2.0 Output
   - **Monitor:** In
   - **Channel:** Any (MPE uses all 15 channels)

4. **Configure MPE**
   - Right-click track → **MPE Control**
   - **Lower Zone:** Channels 1-15
   - **Master Channel:** 16
   - **Pitch Bend Range:** ±48 semitones

### **Gesture → Ableton Mapping**

| BLAB Gesture | MPE Control | Ableton Parameter |
|--------------|-------------|-------------------|
| Fist | Note On | Trigger note on channel 1-15 |
| Pinch | Per-note pitch bend | ±4 octaves per note |
| Spread | Per-note brightness (CC 74) | Filter cutoff per note |
| Jaw Open | Per-note brightness (all) | Filter cutoff (all voices) |
| Smile | Per-note timbre (CC 71) | Filter resonance (all) |
| HRV Coherence | N/A | *Visuals/AFA field only* |

### **Recommended Ableton Devices**
- **Wavetable** - Full MPE support, per-note modulation
- **Sampler** - MPE mode for polyphonic control
- **External Instrument** - Route to hardware MPE synths

---

## 🎹 **Logic Pro Integration**

### **Setup (Logic Pro 11+)**

1. **Preferences → MIDI**
   - **Inputs:** Enable "BLAB MIDI 2.0 Output"
   - **MPE Mode:** Enabled
   - **Pitch Bend Range:** ±4800 cents (48 semitones)

2. **Create Software Instrument Track**
   - **Input:** BLAB MIDI 2.0 Output
   - **Channel:** All (MPE)

3. **Load MPE Instrument**
   - **Alchemy** (MPE mode)
   - **Sculpture** (polyphonic)
   - **Third-party:** Equator 2, Osmose plugin, Seaboard Rise plugin

4. **Enable MPE**
   - Track Inspector → **Details** → **MPE**
   - **Lower Zone:** Channels 1-15
   - **Pitch Bend Range:** 48 semitones

### **Smart Controls Mapping**

Map BLAB gestures to Logic Smart Controls:
- **CC 74 (Brightness)** → Filter Cutoff
- **CC 71 (Timbre)** → Resonance
- **Pitch Bend** → Pitch (per-note)

---

## 🎚️ **Bitwig Studio Integration**

### **Setup (Bitwig 4.4+)**

1. **Settings → Controllers**
   - **Add Controller:** Generic MIDI Keyboard
   - **MIDI Input:** BLAB MIDI 2.0 Output
   - **MPE:** Enabled

2. **Configure MPE**
   - **MPE Zone:** Lower
   - **Channels:** 1-15
   - **Master:** 16
   - **Pitch Bend:** ±48 semitones

3. **Load MPE Instrument**
   - **Polymer** (MPE native)
   - **Phase-4** (MPE support)
   - **Third-party:** Equator 2, Surge XT

4. **Track Setup**
   - Create Instrument Track
   - **Input:** BLAB MIDI 2.0 Output
   - Enable **MPE** in track settings

### **Modulation Mapping**

Bitwig's modulation system works perfectly with BLAB:
- **Per-note Pitch Bend** → Oscillator pitch
- **Per-note CC 74** → Filter cutoff
- **Per-note CC 71** → Wavetable position

---

## 🎸 **MPE Hardware Synth Integration**

### **Roli Seaboard (Receiving BLAB MIDI)**

**BLAB can control Seaboard synth module:**

1. **Connect via USB (Mac) or Bluetooth MIDI (iOS)**
2. **Seaboard Dashboard:**
   - **MIDI Mode:** MPE
   - **Input:** BLAB MIDI 2.0 Output
   - **Channels:** 1-15

**Mapping:**
- BLAB Fist → Seaboard Note On
- BLAB Pinch → Seaboard Glide (pitch bend)
- BLAB Spread → Seaboard Press (brightness)

### **Expressive E Osmose**

1. **Osmose Plugin or Hardware:**
   - **MIDI Input:** BLAB MIDI 2.0 Output
   - **MPE:** Enabled
   - **Channels:** 1-15

**Gesture Mapping:**
- Pinch → Pitch bend per note
- Jaw → Initial aftertouch (all notes)

### **LinnStrument**

1. **LinnStrument Control Panel:**
   - **MIDI Mode:** MPE
   - **Receiving:** BLAB MIDI 2.0 Output
   - **Channels:** 1-15

**Use Case:** BLAB triggers notes, LinnStrument lights follow

---

## 🌊 **Spatial Audio Output (iOS 19+)**

### **Setup for Spatial Rendering**

BLAB generates spatial positions based on MIDI notes:

**Stereo Mode:**
- Note number → L/R pan
- Low notes = left, high notes = right

**3D Mode (AirPods Pro/Max):**
- Note number → Azimuth (horizontal angle)
- Velocity → Distance (soft = far, loud = near)
- CC 74 → Elevation (vertical angle)

**4D Mode (Orbital Motion):**
- Pitch bend → Orbital rotation speed
- HRV Coherence → Orbit radius

**AFA Mode (Algorithmic Field Array):**
- MPE voices → Spatial sources
- HRV < 40 → Grid (3x3)
- HRV 40-60 → Circle
- HRV > 60 → Fibonacci Sphere

### **iOS Spatial Audio Settings**

1. **Settings → Accessibility → Audio/Visual → Headphone Accommodations**
   - Enable **Spatial Audio**
   - Enable **Head Tracking** (AirPods Pro/Max only)

2. **BLAB will automatically use:**
   - `AVAudioEnvironmentNode` for 3D positioning
   - Head tracking data for dynamic spatialization

---

## 🎨 **Visual Feedback (MIDI → Visuals)**

### **Cymatics Mode**
- MIDI note → Chladni pattern frequency
- Velocity → Pattern amplitude
- HRV → Color hue

### **Mandala Mode**
- MIDI note → Petal count (6-12)
- Velocity → Petal size
- Heart rate → Rotation speed

### **Waveform Mode**
- Real-time audio waveform
- HRV-based color gradient

---

## 💡 **LED Control (Ableton Push 3)**

### **Setup**

BLAB sends SysEx to Push 3 for LED feedback:

**LED Mapping:**
- HRV Coherence → LED Brightness (30-100%)
- HRV Coherence → LED Hue (Red → Green)
- Heart Rate → Animation speed
- Gesture detection → Flash LEDs

### **Push 3 Configuration**

1. **Connect Push 3 via USB**
2. **BLAB sends SysEx:** `F0 00 21 1D 01 01 0A ...`
3. **8x8 Grid = 64 LEDs** (RGB control)

---

## 🔧 **Troubleshooting**

### **No MIDI Output**

**Check console for:**
```
⚠️ MIDI 2.0 not available: [error]
```

**Fix:**
- Restart BLAB
- Check iOS MIDI permissions
- Verify CoreMIDI availability

### **No Spatial Audio**

**Requirements:**
- iOS 19+ (for full spatial audio engine)
- AirPods Pro/Max (for head tracking)
- Spatial Audio enabled in iOS Settings

**Fallback:**
- Stereo mode works on all devices
- 3D mode works without head tracking (static positioning)

### **MPE Not Working in DAW**

**Checklist:**
1. ✅ MPE mode enabled in DAW
2. ✅ BLAB MIDI 2.0 Output selected
3. ✅ Channels 1-15 assigned to lower zone
4. ✅ Pitch bend range = ±48 semitones
5. ✅ MPE-compatible instrument loaded

---

## 📊 **MIDI Monitor (Debugging)**

### **View MIDI 2.0 Messages**

**macOS:** Use **MIDI Monitor app**
- Shows UMP packets
- 32-bit parameter resolution visible
- Per-note controllers displayed

**Expected Output:**
```
MIDI 2.0 Note On: Note 60, Channel 1, Velocity (16-bit): 52428
MIDI 2.0 Per-Note Controller: Channel 1, Note 60, CC 74, Value: 2147483648
MIDI 2.0 Per-Note Pitch Bend: Channel 1, Note 60, Bend: +0.5
```

---

## 🎯 **Recommended Workflows**

### **Workflow 1: Live Performance**
- **DAW:** Ableton Live
- **Instrument:** Wavetable (MPE mode)
- **Control:** BLAB gestures → Live looping
- **Visual:** Projected visuals from BLAB

### **Workflow 2: Sound Design**
- **DAW:** Bitwig Studio
- **Instrument:** Polymer (MPE)
- **Control:** Bio-reactive modulation (HRV → AFA field)
- **Output:** Spatial audio recording

### **Workflow 3: Meditation/Healing**
- **DAW:** Logic Pro
- **Instrument:** Alchemy (pad sounds)
- **Control:** HRV coherence → Reverb/Filter
- **Visual:** Mandala mode
- **LED:** Push 3 bio-reactive feedback

---

## 🎹 **MPE Synth Recommendations**

### **Software (VST/AU)**
1. **Equator 2** (Roli) - Best MPE synth, deep modulation
2. **Cypher2** (FXpansion) - MPE-ready, complex modulation
3. **Surge XT** (Free!) - Open-source, MPE support
4. **Bitwig Polymer** - Native MPE, amazing sound

### **Hardware**
1. **Expressive E Osmose** - Full MPE keyboard + synth
2. **Roli Seaboard Rise 2** - MPE controller + Equator plugin
3. **LinnStrument** - Grid-based MPE controller
4. **Haken Continuum** - Ultimate expressive control

---

## 📖 **Further Reading**

- [MIDI 2.0 Specification](https://www.midi.org/specifications)
- [MPE Specification](https://www.midi.org/specifications/midi-polyphonic-expression-mpe)
- [Apple Spatial Audio](https://developer.apple.com/documentation/avfaudio/audio_engine)
- [Ableton MPE Guide](https://www.ableton.com/en/manual/mpe/)

---

**🫧 consciousness expressed through MIDI
🌊 spatial sound from multimodal input
✨ bio-reactive polyphonic synthesis**
