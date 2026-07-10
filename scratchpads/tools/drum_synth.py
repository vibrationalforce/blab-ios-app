#!/usr/bin/env python3
"""
EchoelDrums Synth — PIPELINE ONLY (never ships in-app, never touches Sources/).

Founder 2026-07-10: "Du kannst auch einfach von Sounds lernen und wir machen
eigenes physical modeling wie EchoelSynth nur für Drums."

LEARN → MODEL → SYNTHESIZE:
  1. LEARN (analyze): measure non-copyrightable acoustic FACTS from reference
     hits — decay time, dominant frequency, pitch-sweep endpoints, noise/tonal
     balance, spectral centroid. A handful of numbers, not the waveform.
  2. MODEL: classic analog drum-voice architectures (the 808/909 circuits'
     topology is public knowledge): swept sine + click for kicks, tonal modes
     + band-passed noise for snares, six inharmonic square partials for hats,
     burst-train for claps, modal decay for toms/congas/claves.
  3. SYNTHESIZE: render NEW recordings from those models — 100 % original,
     zero licensing exposure, mastered afterwards by sample_processor.py.

Legal note (honest): parameter extraction = learning facts; the render shares
no audio with any source recording. We deliberately do NOT do spectral cloning
(copying a full spectrogram would be re-creating the recording) — models stay
parametric (a dozen numbers per voice).

Usage:
  python3 drum_synth.py analyze <wav> [...]      # print learned parameters
  python3 drum_synth.py render <out_dir>         # render the EchoelDrums kit
"""

import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100


# ---------------------------------------------------------------- learn

def analyze(path: str) -> dict:
    """Acoustic facts of a one-shot: decay, dominant Hz, sweep, noisiness."""
    import librosa
    y, sr = librosa.load(path, sr=SR, mono=True)
    y = y / (np.max(np.abs(y)) or 1)
    # decay: time to fall 60 dB below peak on the RMS envelope
    hop = 128
    rms = librosa.feature.rms(y=y, frame_length=512, hop_length=hop)[0]
    peak_i = int(np.argmax(rms))
    below = np.nonzero(rms[peak_i:] < rms[peak_i] * 10 ** (-60 / 20))[0]
    t60 = (below[0] * hop / SR) if below.size else len(y) / SR
    # dominant frequency early vs late (sweep endpoints)
    def domfreq(seg):
        if seg.size < 256: return 0.0
        w = np.abs(np.fft.rfft(seg * np.hanning(seg.size)))
        return float(np.fft.rfftfreq(seg.size, 1 / SR)[np.argmax(w)])
    n = len(y)
    f_early = domfreq(y[: max(256, n // 8)])
    f_late = domfreq(y[n // 4: n // 4 + max(256, n // 4)])
    # noisiness: spectral flatness (0 tonal … 1 noise)
    flat = float(np.mean(librosa.feature.spectral_flatness(y=y)))
    cent = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=SR)))
    return {"file": Path(path).name, "t60_s": round(t60, 3),
            "f_early_hz": round(f_early, 1), "f_late_hz": round(f_late, 1),
            "flatness": round(flat, 3), "centroid_hz": round(cent, 0)}


# ---------------------------------------------------------------- model parts

def _env(n: int, t60: float, curve: float = 1.0) -> np.ndarray:
    """Exponential decay envelope hitting −60 dB at t60."""
    t = np.arange(n) / SR
    return np.exp(-6.907 * (t / max(t60, 1e-3)) ** curve)


def _noise(n: int, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).standard_normal(n)


def _bp(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    """FFT brick-wall band-pass — fine for percussion design."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(x.size, 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, x.size)


def _softclip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / math.tanh(drive)


def _swept_sine(n: int, f0: float, f1: float, sweep_t: float) -> np.ndarray:
    """Sine whose pitch falls exponentially f0→f1 over sweep_t seconds."""
    t = np.arange(n) / SR
    k = np.minimum(t / max(sweep_t, 1e-4), 1.0)
    f = f1 + (f0 - f1) * np.exp(-5.0 * k)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


# ---------------------------------------------------------------- voices

def kick(t60=0.42, f0=210.0, f1=48.0, sweep=0.045, click=0.5, drive=1.6, seed=1):
    n = int(SR * (t60 + 0.1))
    body = _swept_sine(n, f0, f1, sweep) * _env(n, t60)
    cl = _bp(_noise(n, seed), 800, 6500) * _env(n, 0.012) * click
    return _softclip(body + cl, drive)


def snare(t60=0.22, modes=(186.0, 332.0), noise_t60=0.28, bright=5200.0,
          tone_mix=0.45, seed=2):
    n = int(SR * (max(t60, noise_t60) + 0.1))
    tone = sum(np.sin(2 * np.pi * m * np.arange(n) / SR) for m in modes)
    tone = tone / len(modes) * _env(n, t60) * tone_mix
    nz = _bp(_noise(n, seed), 900, bright * 2) * _env(n, noise_t60) * (1 - tone_mix)
    return _softclip(tone + nz, 1.3)


def clap(bursts=4, spacing=0.011, t60=0.30, lo=900.0, hi=4200.0, seed=3):
    n = int(SR * (t60 + bursts * spacing + 0.1))
    out = np.zeros(n)
    for i in range(bursts):
        s = int(i * spacing * SR)
        e = _env(n - s, 0.014 if i < bursts - 1 else t60, curve=0.8)
        out[s:] += _bp(_noise(n - s, seed + i), lo, hi) * e * (0.7 if i < bursts - 1 else 1)
    return _softclip(out, 1.2)


def hat(open_=False, t60=None, seed=4):
    # Six inharmonic square partials (the classic metallic recipe), HP'd.
    t60 = t60 if t60 is not None else (0.65 if open_ else 0.055)
    n = int(SR * (t60 + 0.05))
    ratios = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
    x = sum(np.sign(np.sin(2 * np.pi * f * 8.0 * np.arange(n) / SR)) for f in ratios)
    x = _bp(x / 6 + 0.15 * _noise(n, seed), 6800, 16000)
    return x * _env(n, t60, curve=0.9)


def tom(f0=170.0, f1=95.0, t60=0.35, seed=5):
    n = int(SR * (t60 + 0.1))
    body = _swept_sine(n, f0, f1, 0.06) * _env(n, t60)
    attack = _bp(_noise(n, seed), 400, 2500) * _env(n, 0.01) * 0.25
    return _softclip(body + attack, 1.25)


def conga(f0=372.0, t60=0.18, slap=0.15, seed=6):
    # Modal: fundamental + two membrane overtones (1 : 1.59 : 2.14).
    n = int(SR * (t60 + 0.08))
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * f0 * t) * _env(n, t60)
         + 0.4 * np.sin(2 * np.pi * f0 * 1.59 * t) * _env(n, t60 * 0.6)
         + 0.2 * np.sin(2 * np.pi * f0 * 2.14 * t) * _env(n, t60 * 0.4))
    x += _bp(_noise(n, seed), 1500, 5000) * _env(n, 0.008) * slap
    return _softclip(x, 1.15)


def claves(f0=2530.0, t60=0.055):
    n = int(SR * (t60 + 0.03))
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * f0 * t) * _env(n, t60)


def sub808(f0=52.0, t60=0.9, drive=1.8):
    n = int(SR * (t60 + 0.15))
    body = _swept_sine(n, f0 * 2.6, f0, 0.02) * _env(n, t60, curve=0.8)
    return _softclip(body, drive)


def zap(f0=2400.0, f1=60.0, t60=0.28, seed=8):
    n = int(SR * (t60 + 0.05))
    x = _swept_sine(n, f0, f1, t60 * 0.8) * _env(n, t60)
    return _softclip(x + 0.05 * _bp(_noise(n, seed), 200, 3000) * _env(n, t60), 1.4)


# ---------------------------------------------------------------- kit

KIT = {
    # 8 defaults (BeatPlayer track layout) — parameters tuned to the FACTS
    # learned from the previous kit (analyze: kick sweep 156→49 Hz t60 0.41,
    # closed hat t60 0.024, sub 51 Hz t60 1.7): same musical role, new sound.
    "Kick.wav":      lambda: kick(f0=165.0, f1=48.0, t60=0.41),
    "Snare.wav":     lambda: snare(),
    "ClosedHat.wav": lambda: hat(open_=False, t60=0.03),
    "OpenHat.wav":   lambda: hat(open_=True, t60=0.4),
    "Clap.wav":      lambda: clap(t60=0.2),
    "Perc.wav":      lambda: claves(),
    "Bass.wav":      lambda: sub808(t60=1.5),
    "LeadFX.wav":    lambda: zap(),
    # library variations (Samples/<Cat>/)
    "Kick/Echoel Deep Kick.wav":   lambda: kick(t60=0.6, f0=160, f1=42, click=0.3, drive=2.0),
    "Kick/Echoel Punch Kick.wav":  lambda: kick(t60=0.28, f0=260, f1=55, click=0.8, drive=1.4),
    "Snare/Echoel Tight Snare.wav": lambda: snare(t60=0.14, noise_t60=0.16, bright=6500),
    "Snare/Echoel Fat Snare.wav":  lambda: snare(t60=0.3, modes=(160, 285), noise_t60=0.38, tone_mix=0.55),
    "Hat/Echoel Pedal Hat.wav":    lambda: hat(open_=False, t60=0.03),
    "Hat/Echoel Sizzle Hat.wav":   lambda: hat(open_=True, t60=1.1),
    "Tom/Echoel Tom Hi.wav":       lambda: tom(f0=240, f1=150, t60=0.28),
    "Tom/Echoel Tom Lo.wav":       lambda: tom(f0=130, f1=72, t60=0.45),
    "Conga/Echoel Conga Hi.wav":   lambda: conga(f0=420),
    "Conga/Echoel Conga Lo.wav":   lambda: conga(f0=290, t60=0.22),
    "Perc/Echoel Claves.wav":      lambda: claves(),
    "Bass/Echoel 808 Sub.wav":     lambda: sub808(),
    "FX/Echoel Zap.wav":           lambda: zap(),
}


def render(out_dir: str) -> None:
    out = Path(out_dir)
    for name, fn in KIT.items():
        y = fn().astype(np.float64)
        y /= max(np.max(np.abs(y)), 1e-9)
        p = out / name
        p.parent.mkdir(parents=True, exist_ok=True)
        sf.write(p, y, SR, subtype="FLOAT")   # float master; processor does 16-bit
        print(f"rendered {name}  ({len(y)/SR:.3f}s)")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "analyze":
        for p in sys.argv[2:]:
            print(analyze(p))
    elif len(sys.argv) == 3 and sys.argv[1] == "render":
        render(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
