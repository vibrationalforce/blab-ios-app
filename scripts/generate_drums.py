#!/usr/bin/env python3
"""
generate_drums.py — Echoel EchoelBeat default drum kit (procedural).

Synthesizes the 8 default drum one-shots into Sources/Echoelmusic/Resources/Drums/
as mono 16-bit 44.1 kHz WAV (the format SamplerVoice.loadSample expects).

Pure standard library (no numpy) so it runs anywhere, incl. the CI sandbox.
Each voice uses well-known drum-synthesis techniques (pitch+amp envelopes,
filtered noise, transient clicks, soft saturation), normalized with per-voice
headroom so the kit sits together. Re-run to regenerate; deterministic seed.
"""
import math, os, random, struct, wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Echoelmusic", "Resources", "Drums")

random.seed(1234)  # deterministic kit


def _env(n, attack, decay, sustain=0.0, release=0.0, total=None):
    """Simple AD/ADSR-ish exponential-ish envelope, length n samples."""
    out = [0.0] * n
    a = max(1, int(attack * SR))
    d = max(1, int(decay * SR))
    for i in range(n):
        if i < a:
            out[i] = i / a
        elif i < a + d:
            t = (i - a) / d
            out[i] = (1.0 - t) * (1.0 - sustain) + sustain
        else:
            out[i] = sustain
    # exponential tail to zero over the back third for natural decay
    return out


def _expdecay(n, tau):
    """Exponential decay envelope, tau in seconds."""
    return [math.exp(-i / (tau * SR)) for i in range(n)]


def _sat(x, drive=1.0):
    """Soft saturation (tanh) for warmth/punch."""
    return math.tanh(x * drive)


def _normalize(buf, peak=0.97):
    m = max((abs(v) for v in buf), default=0.0)
    if m < 1e-9:
        return buf
    g = peak / m
    return [v * g for v in buf]


def _fade_out(buf, ms=6):
    n = int(ms / 1000 * SR)
    L = len(buf)
    for i in range(min(n, L)):
        buf[L - 1 - i] *= i / n
    return buf


def kick(dur=0.42):
    n = int(dur * SR)
    amp = _expdecay(n, 0.16)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        # pitch glide 120 -> 45 Hz (fast)
        f = 45 + (120 - 45) * math.exp(-t / 0.03)
        phase += 2 * math.pi * f / SR
        body = math.sin(phase)
        # short click transient for attack definition
        click = (random.uniform(-1, 1) * math.exp(-t / 0.002)) * 0.5
        out[i] = _sat((body * amp[i]) * 1.4 + click * amp[i], 1.1)
    return _fade_out(_normalize(out, 0.99))


def snare(dur=0.20):
    n = int(dur * SR)
    tone_env = _expdecay(n, 0.06)
    noise_env = _expdecay(n, 0.085)
    out = [0.0] * n
    p1 = p2 = 0.0
    hp_prev_in = hp_prev_out = 0.0
    for i in range(n):
        p1 += 2 * math.pi * 180 / SR
        p2 += 2 * math.pi * 330 / SR
        tone = (math.sin(p1) * 0.6 + math.sin(p2) * 0.4) * tone_env[i]
        nz = random.uniform(-1, 1)
        # 1-pole high-pass on the noise for snap
        hp = 0.85 * (hp_prev_out + nz - hp_prev_in)
        hp_prev_in, hp_prev_out = nz, hp
        out[i] = _sat(tone * 0.5 + hp * noise_env[i] * 0.9, 1.05)
    return _fade_out(_normalize(out, 0.95))


def _hat(dur, tau):
    n = int(dur * SR)
    env = _expdecay(n, tau)
    out = [0.0] * n
    hp_prev_in = hp_prev_out = 0.0
    for i in range(n):
        nz = random.uniform(-1, 1)
        # strong high-pass (metallic)
        hp = 0.92 * (hp_prev_out + nz - hp_prev_in)
        hp_prev_in, hp_prev_out = nz, hp
        out[i] = hp * env[i]
    return _fade_out(_normalize(out, 0.82))


def closed_hat():
    return _hat(0.06, 0.012)


def open_hat():
    return _hat(0.34, 0.10)


def clap(dur=0.22):
    n = int(dur * SR)
    out = [0.0] * n
    # 3 quick bursts + a softer tail (classic clap)
    bursts = [0.0, 0.010, 0.020]
    hp_prev_in = hp_prev_out = 0.0
    for i in range(n):
        t = i / SR
        amp = 0.0
        for b in bursts:
            if t >= b:
                amp += math.exp(-(t - b) / 0.012)
        # diffuse tail
        amp += 0.4 * math.exp(-(t) / 0.10) if t > 0.025 else 0.0
        nz = random.uniform(-1, 1)
        hp = 0.8 * (hp_prev_out + nz - hp_prev_in)
        hp_prev_in, hp_prev_out = nz, hp
        out[i] = hp * amp * 0.5
    return _fade_out(_normalize(out, 0.9))


def perc(dur=0.16):
    n = int(dur * SR)
    env = _expdecay(n, 0.05)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 420 * math.exp(-t / 0.05) + 220  # tuned tom-ish drop
        phase += 2 * math.pi * f / SR
        out[i] = _sat(math.sin(phase) * env[i], 1.2)
    return _fade_out(_normalize(out, 0.9))


def bass(dur=0.55):
    """808-ish sub with slight pitch glide + saturation."""
    n = int(dur * SR)
    env = _expdecay(n, 0.22)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 55 + 25 * math.exp(-t / 0.04)  # 80 -> 55 Hz
        phase += 2 * math.pi * f / SR
        out[i] = _sat(math.sin(phase) * env[i] * 1.3, 1.15)
    return _fade_out(_normalize(out, 0.99))


def leadfx(dur=0.30):
    """Zappy FM blip sweep."""
    n = int(dur * SR)
    env = _expdecay(n, 0.10)
    out = [0.0] * n
    cphase = mphase = 0.0
    for i in range(n):
        t = i / SR
        carrier_f = 600 + 1800 * math.exp(-t / 0.06)
        mod_f = carrier_f * 1.5
        mphase += 2 * math.pi * mod_f / SR
        idx = 3.0 * math.exp(-t / 0.08)
        cphase += 2 * math.pi * carrier_f / SR
        out[i] = math.sin(cphase + idx * math.sin(mphase)) * env[i]
    return _fade_out(_normalize(out, 0.85))


def write_wav(path, buf):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for v in buf:
            s = int(max(-1.0, min(1.0, v)) * 32767)
            frames += struct.pack("<h", s)
        w.writeframes(bytes(frames))


KIT = {
    "Kick": kick,
    "Snare": snare,
    "ClosedHat": closed_hat,
    "OpenHat": open_hat,
    "Clap": clap,
    "Perc": perc,
    "Bass": bass,
    "LeadFX": leadfx,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in KIT.items():
        buf = fn()
        path = os.path.join(OUT, f"{name}.wav")
        write_wav(path, buf)
        print(f"wrote {name}.wav  {len(buf)} frames  {len(buf)/SR:.3f}s")


if __name__ == "__main__":
    main()
