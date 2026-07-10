#!/usr/bin/env python3
"""
Echoel Sample Processor — PIPELINE ONLY (never ships in-app, never touches Sources/).

Mastering-grade conditioning for every curated sample on its way into the app
bundle (fetch-samples.yml phase 2 runs this per SAMPLES_MAP.tsv entry). Founder
ask 2026-07-10: "optimieren, Processing machen, angleichen, mastern".

What it does — technical optimisation, per category:
  1. DC-offset removal (per channel).
  2. Silence trim: leading (< −60 dBFS, 3 ms pre-roll kept) and trailing
     (< −66 dBFS, 15 ms tail kept) — pads/FX keep their natural release.
  3. TUNING (tonal categories only — Bass/Stab/Keys/Pad/Tone/Chords):
     median f0 via pYIN → cents offset to the nearest A440 semitone; when
     confident and ≥ 8 cents off, correct by VARISPEED (pure resampling).
     Varispeed is chosen deliberately: a phase-vocoder pitch shift smears
     transients (the parked neural-synthesis lesson); resampling preserves
     the attack exactly, and the ≤ 3 % duration change is irrelevant for
     one-shots. Correction is capped at ±60 cents — bigger offsets are
     usually intentional character, not detune.
  4. LEVEL ANGLEICHUNG (per-category targets, mirrors sample_curator.py):
       drums/percussion (Kick/Snare/Clap/Hat/Cymbal/Perc/Tom/Conga, Drums/)
         → peak −6 dBFS   (consistent trigger response on the pads)
       tonal (Bass/Stab/Keys/Tone/Chords)
         → active-region RMS −14 dBFS, peak-capped at −1.5 dBFS
       pads/FX (Pad/FX)
         → active-region RMS −16 dBFS (they sit UNDER the mix), same cap
  5. Click guard: 0.3 ms raised-cosine fade-in + 8 ms fade-out.
  6. 44.1 kHz resample (soxr-quality via librosa) + 16-bit PCM with TPDF
     dither. Mono stays mono, stereo stays stereo.

What it deliberately does NOT do: creative sound design (saturation, EQ
character, reverb). The samples' character is the founder's; creative motion
belongs to the bio-reactive EchoelFX chain in the app, where it is reversible.

Usage:
  python3 sample_processor.py <src> <dst> --category <Cat>
Prints one JSON report line to stdout; exit 0 on success.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np
import librosa
import soundfile as sf

TONAL = {"Bass", "Stab", "Keys", "Tone", "Chords"}
PADS_FX = {"Pad", "FX"}
PERC = {"Kick", "Snare", "Clap", "Hat", "Cymbal", "Perc", "Tom", "Conga", "Drums"}

SR_OUT = 44100
PEAK_TARGET_PERC_DB = -6.0
RMS_TARGET_TONAL_DB = -14.0
RMS_TARGET_PAD_DB = -16.0
PEAK_CEILING_DB = -1.5
TRIM_LEAD_DB = -60.0
TRIM_TAIL_DB = -66.0
TUNE_MIN_CENTS = 8.0
TUNE_MAX_CENTS = 60.0


def db_to_lin(d: float) -> float:
    return 10.0 ** (d / 20.0)


def lin_to_db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def trim(y: np.ndarray, sr: int) -> tuple[np.ndarray, int, int]:
    """Trim leading/trailing silence on the max-abs envelope. y: (ch, n)."""
    env = np.max(np.abs(y), axis=0)
    peak = float(env.max())
    if peak <= 0:
        return y, 0, 0
    lead_thr = peak * db_to_lin(TRIM_LEAD_DB)
    tail_thr = peak * db_to_lin(TRIM_TAIL_DB)
    idx = np.nonzero(env > lead_thr)[0]
    start = max(0, int(idx[0]) - int(0.003 * sr)) if idx.size else 0
    idx2 = np.nonzero(env > tail_thr)[0]
    end = min(y.shape[1], int(idx2[-1]) + int(0.015 * sr)) if idx2.size else y.shape[1]
    if end <= start:
        return y, 0, 0
    return y[:, start:end], start, y.shape[1] - end


def detect_cents(y: np.ndarray, sr: int) -> tuple[float, float] | None:
    """Median f0 of the mono mix → (cents offset to nearest A440 semitone, f0 Hz)."""
    mono = np.mean(y, axis=0)
    # Sustained portion: skip the attack (first 30 ms), analyse ≤ 2 s.
    a = int(0.03 * sr)
    seg = mono[a:a + 2 * sr] if mono.size > a + int(0.1 * sr) else mono
    try:
        f0, voiced, _ = librosa.pyin(seg, sr=sr,
                                     fmin=float(librosa.note_to_hz("C1")),
                                     fmax=float(librosa.note_to_hz("C7")),
                                     frame_length=4096)  # ≥2 periods of C1 @44.1k
    except Exception:
        return None
    if f0 is None:
        return None
    good = f0[np.isfinite(f0) & (voiced if voiced is not None else True)]
    if good.size < 5:  # not confidently pitched (noise/drums/chords too dense)
        return None
    hz = float(np.median(good))
    # POLYPHONY GUARD: a chord/dense texture yields an erratic f0 track — only
    # "tune" clean monophonic material (track spread ≤ 25 cents around median).
    cents_track = 1200.0 * np.log2(np.maximum(good, 1e-6) / hz)
    if float(np.percentile(np.abs(cents_track), 75)) > 25.0:
        return None
    midi = 69.0 + 12.0 * math.log2(hz / 440.0)
    cents = (midi - round(midi)) * 100.0
    return cents, hz


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--category", required=True)
    args = ap.parse_args()
    cat = args.category

    y, sr = librosa.load(args.src, sr=None, mono=False)
    if y.ndim == 1:
        y = y[np.newaxis, :]
    report = {"src": args.src, "dst": args.dst, "category": cat, "sr_in": sr}

    # 1. DC offset
    y = y - np.mean(y, axis=1, keepdims=True)

    # 2. Trim
    y, cut_lead, cut_tail = trim(y, sr)
    report["trim_ms"] = [round(cut_lead / sr * 1000, 1), round(cut_tail / sr * 1000, 1)]

    # 3. Tuning (tonal only) — varispeed, transient-safe
    report["tuned_cents"] = 0.0
    if cat in TONAL:
        det = detect_cents(y, sr)
        if det is not None:
            cents, hz = det
            report["f0_hz"] = round(hz, 2)
            if TUNE_MIN_CENTS <= abs(cents) <= TUNE_MAX_CENTS:
                factor = 2.0 ** (-cents / 1200.0)  # varispeed: rate change
                y = np.stack([
                    librosa.resample(ch, orig_sr=sr, target_sr=int(round(sr * factor)),
                                     res_type="soxr_hq")
                    for ch in y
                ])
                report["tuned_cents"] = round(-cents, 1)

    # 4. Level — per-category target
    peak = float(np.max(np.abs(y))) or 1e-12
    if cat in PERC:
        gain = db_to_lin(PEAK_TARGET_PERC_DB) / peak
    else:
        target = RMS_TARGET_PAD_DB if cat in PADS_FX else RMS_TARGET_TONAL_DB
        env = np.max(np.abs(y), axis=0)
        active = np.mean(np.square(y[:, env > peak * db_to_lin(-40.0)]))
        rms = math.sqrt(max(active, 1e-24))
        gain = db_to_lin(target) / max(rms, 1e-12)
        if peak * gain > db_to_lin(PEAK_CEILING_DB):  # cap, never limit
            gain = db_to_lin(PEAK_CEILING_DB) / peak
    y = y * gain
    report["gain_db"] = round(lin_to_db(gain), 2)

    # 5. Click guard
    n_in = min(int(0.0003 * sr), y.shape[1] // 4)
    n_out = min(int(0.008 * sr), y.shape[1] // 4)
    if n_in > 0:
        y[:, :n_in] *= 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, n_in))
    if n_out > 0:
        y[:, -n_out:] *= 0.5 + 0.5 * np.cos(np.linspace(0, math.pi, n_out))

    # 6. 44.1 kHz + 16-bit TPDF dither
    if sr != SR_OUT:
        y = np.stack([librosa.resample(ch, orig_sr=sr, target_sr=SR_OUT,
                                       res_type="soxr_hq") for ch in y])
    y = np.clip(y, -1.0, 1.0)
    dither = (np.random.default_rng(0).random(y.shape) +
              np.random.default_rng(1).random(y.shape) - 1.0) / 32768.0
    y16 = np.clip(y + dither, -1.0, 1.0)

    Path(args.dst).parent.mkdir(parents=True, exist_ok=True)
    sf.write(args.dst, y16.T, SR_OUT, subtype="PCM_16")
    report["dur_s"] = round(y.shape[1] / SR_OUT, 3)
    print(json.dumps(report, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
