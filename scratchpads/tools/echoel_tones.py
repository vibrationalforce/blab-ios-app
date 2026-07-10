#!/usr/bin/env python3
"""
EchoelTones Synth — PIPELINE ONLY (never ships in-app, never touches Sources/).

Founder 2026-07-10: "Bass, chords und effektsounds … zu eigenen Kreationen
machen … eigenes physical modeling wie EchoelSynth." The licence-clean tonal
counterpart to drum_synth.py: 100 % original synthesis (subtractive, FM,
additive, Karplus-Strong physical modeling) — no sample, no pack, no exposure.

Each one-shot is rendered at a known pitch (default C3) so the sampler pitches
it per pad. sample_processor.py masters afterwards (tonal RMS target, fades).

Voices:
  Bass  — subtractive saw/square through a lowpass env; FM growl; pure sub sine
  Stab  — detuned saw stack with a fast filter-decay (rave/house chord stab)
  Pad   — many slightly-detuned oscillators, slow attack (wide, contemplative)
  Keys  — FM electric-piano (Rhodes-like), FM bell
  Tone  — Karplus-Strong pluck / string (genuine physical modeling)

Usage:  python3 echoel_tones.py render <out_dir>
"""

import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100


def hz(note: str) -> float:
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5,
             "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    n = note[:-1]
    octv = int(note[-1])
    midi = (octv + 1) * 12 + names[n]
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def env_adsr(n, a, d, s, r, sr=SR):
    a, d, r = max(int(a * sr), 1), max(int(d * sr), 1), max(int(r * sr), 1)
    sus = max(n - a - d - r, 0)
    e = np.concatenate([
        np.linspace(0, 1, a),
        np.linspace(1, s, d),
        np.full(sus, s),
        np.linspace(s, 0, r),
    ])
    return e[:n] if e.size >= n else np.pad(e, (0, n - e.size))


def saw(f, n, sr=SR):
    t = np.arange(n) / sr
    return 2.0 * (t * f - np.floor(0.5 + t * f))


def square(f, n, duty=0.5, sr=SR):
    t = np.arange(n) / sr
    return np.where((t * f) % 1.0 < duty, 1.0, -1.0)


def sine(f, n, sr=SR):
    return np.sin(2 * np.pi * f * np.arange(n) / sr)


def onepole_lp(x, cutoff_env, sr=SR):
    """Time-varying one-pole low-pass; cutoff_env in Hz per sample."""
    y = np.zeros_like(x)
    prev = 0.0
    two_pi = 2 * np.pi
    for i in range(len(x)):
        fc = max(20.0, min(cutoff_env[i], sr * 0.45))
        a = math.exp(-two_pi * fc / sr)
        prev = (1 - a) * x[i] + a * prev
        y[i] = prev
    return y


def svf_lp(x, cutoff_env, q=2.0, sr=SR):
    """Resonant state-variable low-pass (Chamberlin). cutoff_env in Hz/sample,
    q>1 adds resonance for reese/acid/brass character. Stable for fc < sr/6."""
    y = np.zeros_like(x)
    low = band = 0.0
    damp = 1.0 / q
    for i in range(len(x)):
        fc = max(20.0, min(cutoff_env[i], sr / 6.0))
        f = 2.0 * math.sin(math.pi * fc / sr)
        high = x[i] - low - damp * band
        band += f * high
        low += f * band
        y[i] = low
    return y


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / math.tanh(drive)


def norm(x):
    return x / (np.max(np.abs(x)) or 1.0)


# ---------------------------------------------------------------- voices

def bass_sub(note="C2", t=0.9):
    f = hz(note)
    n = int(SR * t)
    y = sine(f, n) + 0.3 * sine(2 * f, n)
    return norm(softclip(y * env_adsr(n, 0.005, 0.2, 0.7, 0.3), 1.4))


def bass_saw(note="C2", t=0.8):
    f = hz(note)
    n = int(SR * t)
    e = env_adsr(n, 0.004, 0.25, 0.5, 0.25)
    cut = 200 + 2600 * env_adsr(n, 0.004, 0.18, 0.15, 0.2)
    y = onepole_lp(saw(f, n) + 0.5 * saw(f * 1.005, n), cut)
    return norm(softclip(y * e + 0.4 * sine(f, n) * e, 1.3))


def bass_fm(note="C2", t=0.7, index=4.0):
    f = hz(note)
    n = int(SR * t)
    mod = index * sine(f * 1.0, n) * env_adsr(n, 0.002, 0.15, 0.3, 0.2)
    car = np.sin(2 * np.pi * f * np.arange(n) / SR + mod)
    return norm(softclip(car * env_adsr(n, 0.003, 0.2, 0.5, 0.25), 1.2))


def stab(note="C3", t=0.5, voices=(0, 4, 7), detune=0.008):
    f = hz(note)
    n = int(SR * t)
    e = env_adsr(n, 0.003, 0.16, 0.0, 0.06)  # fast, percussive
    cut = 400 + 5000 * env_adsr(n, 0.002, 0.09, 0.0, 0.05)
    y = np.zeros(n)
    for semis in voices:
        vf = f * 2 ** (semis / 12.0)
        y += saw(vf, n) + saw(vf * (1 + detune), n)
    y = onepole_lp(y / (len(voices) * 2), cut)
    return norm(softclip(y * e, 1.3))


def pad(note="C3", t=2.4, voices=(0, 7, 12, 16), detunes=(-0.006, 0.006, -0.01, 0.01)):
    f = hz(note)
    n = int(SR * t)
    e = env_adsr(n, 0.6, 0.4, 0.8, 0.8)
    y = np.zeros(n)
    for semis, dt in zip(voices, detunes):
        vf = f * 2 ** (semis / 12.0)
        y += saw(vf * (1 + dt), n) + 0.6 * sine(vf, n)
    cut = 800 + 1400 * env_adsr(n, 0.7, 0.5, 0.7, 0.8)
    y = onepole_lp(y / len(voices), cut)
    return norm(y * e)


def rhodes(note="C3", t=1.4, index=1.6):
    """FM electric piano: sine carrier, sine modulator at 1:1, bell-ish attack."""
    f = hz(note)
    n = int(SR * t)
    modenv = env_adsr(n, 0.001, 0.35, 0.1, 0.4)
    mod = index * sine(f, n) * modenv
    car = np.sin(2 * np.pi * f * np.arange(n) / SR + mod)
    return norm(car * env_adsr(n, 0.002, 0.5, 0.35, 0.5))


def bell(note="C4", t=1.6):
    """FM inharmonic bell (carrier:modulator ~1:1.41)."""
    f = hz(note)
    n = int(SR * t)
    mod = 3.0 * sine(f * 1.41, n) * env_adsr(n, 0.001, 0.6, 0.0, 0.6)
    car = np.sin(2 * np.pi * f * np.arange(n) / SR + mod)
    return norm(car * env_adsr(n, 0.001, 0.8, 0.0, 0.7))


def pluck(note="C3", t=1.2, seed=1, damp=0.996):
    """Karplus-Strong plucked string — genuine physical modeling."""
    f = hz(note)
    n = int(SR * t)
    N = max(2, int(SR / f))
    buf = list(np.random.default_rng(seed).standard_normal(N))
    out = np.empty(n)
    idx = 0
    for i in range(n):
        v = buf[idx]
        nxt = (idx + 1) % N
        buf[idx] = damp * 0.5 * (v + buf[nxt])
        out[i] = v
        idx = nxt
    return norm(out * env_adsr(n, 0.001, 0.4, 0.6, 0.5))


def reese(note="C2", t=1.0, detune=0.03):
    """Detuned-saw reese bass — moody, wide, DnB/jungle staple."""
    f = hz(note)
    n = int(SR * t)
    y = saw(f, n) + saw(f * (1 + detune), n) + saw(f * (1 - detune), n)
    cut = 180 + 900 * env_adsr(n, 0.02, 0.4, 0.6, 0.4)
    y = svf_lp(y / 3, cut, q=1.6)
    return norm(softclip(y * env_adsr(n, 0.01, 0.3, 0.7, 0.4), 1.3))


def acid(note="C2", t=0.6, res=4.0):
    """303-ish resonant squelch — env sweeps a high-Q filter."""
    f = hz(note)
    n = int(SR * t)
    sweep = env_adsr(n, 0.002, 0.22, 0.05, 0.1)
    cut = 150 + 3200 * sweep
    y = svf_lp(square(f, n, duty=0.5), cut, q=res)
    return norm(softclip(y * env_adsr(n, 0.003, 0.3, 0.2, 0.15), 1.5))


def brass_stab(note="C3", t=0.6, voices=(0, 4, 7)):
    """Bright resonant saw-stack stab — brassy, synth-brass chord hit."""
    f = hz(note)
    n = int(SR * t)
    y = np.zeros(n)
    for s in voices:
        vf = f * 2 ** (s / 12.0)
        y += saw(vf, n) + saw(vf * 1.007, n)
    cut = 500 + 4500 * env_adsr(n, 0.01, 0.14, 0.2, 0.1)
    y = svf_lp(y / (len(voices) * 2), cut, q=1.8)
    return norm(softclip(y * env_adsr(n, 0.008, 0.18, 0.15, 0.12), 1.25))


def glass_pad(note="C4", t=2.6):
    """Bell + slow pad = shimmering glass texture."""
    n = int(SR * t)
    y = bell(note, t) * 0.5 + pad(note, t, voices=(0, 12, 19), detunes=(-0.005, 0.005, 0.008)) * 0.7
    return norm(y)


def clav(note="C3", t=0.35):
    """Short bright square pluck — clavinet-ish funk stab."""
    f = hz(note)
    n = int(SR * t)
    y = svf_lp(square(f, n, duty=0.35), 300 + 4000 * env_adsr(n, 0.001, 0.1, 0.0, 0.05), q=2.5)
    return norm(softclip(y * env_adsr(n, 0.001, 0.12, 0.0, 0.06), 1.3))


def marimba(note="C4", t=0.9):
    """FM mallet (carrier:mod 1:3, fast decay) — warm wooden tone."""
    f = hz(note)
    n = int(SR * t)
    mod = 2.2 * sine(f * 3.0, n) * env_adsr(n, 0.001, 0.25, 0.0, 0.2)
    car = np.sin(2 * np.pi * f * np.arange(n) / SR + mod)
    return norm(car * env_adsr(n, 0.001, 0.35, 0.0, 0.3))


def riser(t=1.6, seed=7):
    """Noise+tone upward sweep — a transition FX (tension builder)."""
    n = int(SR * t)
    k = np.linspace(0, 1, n)
    nz = svf_lp(_noise_1d(n, seed), 300 + 8000 * k ** 2, q=2.0)
    tone = sine(200, n) * 0  # placeholder to keep shape; sweep the noise band
    env = k ** 1.5
    return norm((nz + tone) * env)


def _noise_1d(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


# ---------------------------------------------------------------- library

KIT = {
    # Bass (Bass/)
    "Bass/Echoel Sub C.wav":        lambda: bass_sub("C2"),
    "Bass/Echoel Sub G.wav":        lambda: bass_sub("G1"),
    "Bass/Echoel Saw Bass C.wav":   lambda: bass_saw("C2"),
    "Bass/Echoel Saw Bass F.wav":   lambda: bass_saw("F2"),
    "Bass/Echoel FM Growl C.wav":   lambda: bass_fm("C2", index=5.0),
    "Bass/Echoel FM Bass A.wav":    lambda: bass_fm("A1", index=3.0),
    # Stab (Stab/)
    "Stab/Echoel Rave Stab C.wav":  lambda: stab("C3", voices=(0, 3, 7)),
    "Stab/Echoel Rave Stab A.wav":  lambda: stab("A2", voices=(0, 3, 7)),
    "Stab/Echoel Maj Stab C.wav":   lambda: stab("C3", voices=(0, 4, 7)),
    "Stab/Echoel Wide Stab F.wav":  lambda: stab("F3", voices=(0, 7, 12), detune=0.012),
    # Pad (Pad/)
    "Pad/Echoel Warm Pad C.wav":    lambda: pad("C3"),
    "Pad/Echoel Warm Pad A.wav":    lambda: pad("A2"),
    "Pad/Echoel Wide Pad F.wav":    lambda: pad("F3", voices=(0, 5, 12, 19)),
    # Keys (Keys/)
    "Keys/Echoel Rhodes C.wav":     lambda: rhodes("C3"),
    "Keys/Echoel Rhodes E.wav":     lambda: rhodes("E3"),
    "Keys/Echoel Rhodes G.wav":     lambda: rhodes("G3"),
    "Keys/Echoel Bell C.wav":       lambda: bell("C4"),
    "Keys/Echoel Bell G.wav":       lambda: bell("G4"),
    # Tone (Tone/) — Karplus-Strong physical modeling
    "Tone/Echoel Pluck C.wav":      lambda: pluck("C3", seed=1),
    "Tone/Echoel Pluck E.wav":      lambda: pluck("E3", seed=2),
    "Tone/Echoel Pluck G.wav":      lambda: pluck("G3", seed=3),
    "Tone/Echoel String C.wav":     lambda: pluck("C2", t=1.8, seed=4),

    # --- Expansion (cycle 7): resonant-filter character voices ---
    "Bass/Echoel Reese C.wav":      lambda: reese("C2"),
    "Bass/Echoel Reese G.wav":      lambda: reese("G1"),
    "Bass/Echoel Acid C.wav":       lambda: acid("C2"),
    "Bass/Echoel Acid A.wav":       lambda: acid("A1"),
    "Stab/Echoel Brass Stab C.wav": lambda: brass_stab("C3"),
    "Stab/Echoel Brass Stab G.wav": lambda: brass_stab("G3"),
    "Stab/Echoel Min Stab A.wav":   lambda: stab("A2", voices=(0, 3, 7, 10)),
    "Pad/Echoel Glass Pad C.wav":   lambda: glass_pad("C4"),
    "Pad/Echoel Glass Pad G.wav":   lambda: glass_pad("G3"),
    "Keys/Echoel Clav C.wav":       lambda: clav("C3"),
    "Keys/Echoel Clav E.wav":       lambda: clav("E3"),
    "Keys/Echoel Marimba C.wav":    lambda: marimba("C4"),
    "Keys/Echoel Marimba G.wav":    lambda: marimba("G4"),
    "Tone/Echoel Pluck Soft C.wav": lambda: pluck("C3", seed=5, damp=0.999),
    "Tone/Echoel Pluck A.wav":      lambda: pluck("A2", seed=6),
    "FX/Echoel Riser.wav":          lambda: riser(),
}


def render(out_dir: str) -> None:
    out = Path(out_dir)
    for name, fn in KIT.items():
        y = fn().astype(np.float64)
        y = y / (np.max(np.abs(y)) or 1e-9)
        p = out / name
        p.parent.mkdir(parents=True, exist_ok=True)
        sf.write(p, y, SR, subtype="FLOAT")
        print(f"rendered {name}  ({len(y)/SR:.2f}s)")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "render":
        render(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
