#!/usr/bin/env python3
"""
Echoel Sample Curator — PIPELINE ONLY (never ships in-app, never touches Sources/).

Curates a raw sample folder into the three Echoel sample destinations:

  EchoelDrums/   one-shots (Kicks · Snares · Hats · Percussion · Other)
  EchoelBreak/   rhythmic loops / breakbeats
  EchoelSampler/ tonal one-shots & phrases (pitched material)
  Review/        Legal (flagged names / full-song length) · Unclassified

Per file it measures and writes into manifest.csv:
  - format, duration, sample rate, channels
  - class (oneshot-drum / break / tonal / unclassified) + drum subtype
  - pitch: median f0 → nearest note @ A440, cents offset, suggested
    semitone-align shift ("intelligente Tonhöhen-Angleichung")
  - level: peak dBFS + RMS dBFS + suggested gain to the category target
    (one-shots → −6 dBFS peak · breaks/phrases → −14 dBFS RMS)
  - legal flags: known-break / artist / rip keywords in the NAME, plus
    duration > 30 s ("full song?"). HONEST LIMIT: this is filename +
    duration heuristics — NOT audio fingerprinting. A clean name does
    not prove clean rights; flagged = review, unflagged = still verify
    before ever BUNDLING anything in the app.

Usage:
  python3 sample_curator.py <input_dir> <output_dir> [--render]
    --render  also write gain-adjusted + pitch-aligned copies (via librosa),
              otherwise only classify/copy + write the manifest.
"""

import csv
import math
import re
import shutil
import sys
from pathlib import Path

import numpy as np
import librosa
import soundfile as sf

AUDIO_EXT = {".wav", ".aif", ".aiff", ".flac", ".mp3", ".m4a", ".ogg", ".caf"}

# Filename heuristics for legally sensitive material (famous copyrighted
# breaks/recordings + rip indicators). Lowercase substrings.
LEGAL_PATTERNS = [
    "amen", "think break", "thinkbreak", "funky drummer", "apache",
    "hot pants", "soul pride", "impeach the president", "when the levee",
    "james brown", "lyn collins", "winstons", "incredible bongo",
    "rip", "ripped", "vinyl rip", "(c)", "copyright", "splice", "loopmasters",
]

ONESHOT_MAX_S = 1.6          # ≤ this + one dominant onset → drum one-shot
BREAK_MIN_S, BREAK_MAX_S = 1.6, 30.0
FULLSONG_S = 30.0            # longer → probably a full track: legal review
ONESHOT_PEAK_TARGET_DB = -6.0
LOOP_RMS_TARGET_DB = -14.0


def db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-9))


def analyze(path: Path):
    y, sr = librosa.load(path, sr=None, mono=True)
    info = sf.info(str(path)) if path.suffix.lower() in {".wav", ".aif", ".aiff", ".flac"} else None
    dur = len(y) / sr if sr else 0.0
    peak = float(np.max(np.abs(y))) if len(y) else 0.0
    rms = float(np.sqrt(np.mean(y**2))) if len(y) else 0.0

    onsets = librosa.onset.onset_detect(y=y, sr=sr, units="time")
    centroid = float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr))) if len(y) else 0.0
    flatness = float(np.mean(librosa.feature.spectral_flatness(y=y))) if len(y) else 0.0

    # Pitch: pyin over the file; tonal if enough voiced frames agree.
    f0 = None
    try:
        f0_track, voiced, _ = librosa.pyin(
            y, fmin=librosa.note_to_hz("C1"), fmax=librosa.note_to_hz("C7"), sr=sr)
        voiced_f0 = f0_track[np.asarray(voiced, dtype=bool)]
        if voiced_f0.size >= 10 and (voiced_f0.size / max(len(f0_track), 1)) > 0.25:
            f0 = float(np.nanmedian(voiced_f0))
    except Exception:
        pass

    return {
        "sr": sr, "channels": (info.channels if info else 1), "duration": dur,
        "peak_db": db(peak), "rms_db": db(rms),
        "onsets": len(onsets), "centroid": centroid, "flatness": flatness,
        "f0": f0,
    }


def classify(m):
    dur, f0 = m["duration"], m["f0"]
    if dur > FULLSONG_S:
        return "review-fullsong", ""
    # One-shot: short, few onsets (noisy transients can double-trigger the
    # detector, so allow up to 4). Order matters — a pitched 808 kick IS
    # tonal, but a KICK by expectation: short + dark wins over f0; a longer
    # low pitched hit (bass note) falls through to the Sampler, WITH its
    # note recorded either way (key-matching kicks are valuable).
    if dur <= ONESHOT_MAX_S and m["onsets"] <= 4:
        if dur < 0.8 and m["centroid"] < 900:
            return "oneshot-drum", "Kicks"
        if m["centroid"] > 4500 and dur < 0.7:
            return "oneshot-drum", "Hats"
        if f0 is not None:
            return "tonal", ""              # pitched one-shot → Sampler
        if m["flatness"] > 0.2:
            return "oneshot-drum", "Snares"  # noisy body
        return "oneshot-drum", "Percussion"
    if BREAK_MIN_S < dur <= BREAK_MAX_S and m["onsets"] >= 4 and f0 is None:
        return "break", ""
    if f0 is not None:
        return "tonal", ""
    return "unclassified", ""


def pitch_info(f0):
    if not f0:
        return "", "", ""
    midi = librosa.hz_to_midi(f0)
    nearest = round(midi)
    cents = (midi - nearest) * 100.0
    return librosa.midi_to_note(nearest), f"{cents:+.0f}", f"{-cents:+.0f}"


def legal_flags(name: str, m) -> str:
    low = name.lower()
    hits = [p for p in LEGAL_PATTERNS if p in low]
    if m["duration"] > FULLSONG_S:
        hits.append(f">{int(FULLSONG_S)}s-fullsong?")
    return ";".join(hits)


def dest_for(cls, subtype, flags):
    if flags:
        return Path("Review/Legal")
    return {
        "oneshot-drum": Path("EchoelDrums") / (subtype or "Other"),
        "break": Path("EchoelBreak"),
        "tonal": Path("EchoelSampler"),
    }.get(cls, Path("Review/Unclassified"))


def render_processed(src: Path, dst: Path, m, cls, cents_fix: str):
    """--render: write a normalized (and, for tonal, semitone-aligned) copy."""
    y, sr = librosa.load(src, sr=None, mono=False)
    if y.ndim == 1:
        y = y[np.newaxis, :]
    target = ONESHOT_PEAK_TARGET_DB if cls == "oneshot-drum" else LOOP_RMS_TARGET_DB
    current = m["peak_db"] if cls == "oneshot-drum" else m["rms_db"]
    gain = 10 ** ((target - current) / 20.0)
    y = np.clip(y * gain, -1.0, 1.0)
    if cls == "tonal" and cents_fix:
        shift = float(cents_fix) / 100.0
        if abs(shift) > 0.03:  # only fix audible detune
            y = np.stack([librosa.effects.pitch_shift(ch, sr=sr, n_steps=shift) for ch in y])
    sf.write(dst.with_suffix(".wav"), y.T, sr)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    src_dir, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    render = "--render" in sys.argv
    files = sorted(p for p in src_dir.rglob("*") if p.suffix.lower() in AUDIO_EXT)
    if not files:
        print(f"No audio files under {src_dir}")
        sys.exit(1)

    rows = []
    for p in files:
        try:
            m = analyze(p)
        except Exception as e:
            rows.append({"file": p.name, "class": "ERROR", "notes": str(e)})
            continue
        cls, subtype = classify(m)
        note, cents, cents_fix = pitch_info(m["f0"])
        flags = legal_flags(p.name, m)
        rel_dest = dest_for(cls if cls != "review-fullsong" else "unclassified",
                            subtype, flags or (cls == "review-fullsong" and "fullsong"))
        dest = out_dir / rel_dest
        dest.mkdir(parents=True, exist_ok=True)
        target = ONESHOT_PEAK_TARGET_DB if cls == "oneshot-drum" else LOOP_RMS_TARGET_DB
        current = m["peak_db"] if cls == "oneshot-drum" else m["rms_db"]
        if render and cls in {"oneshot-drum", "break", "tonal"} and not flags:
            render_processed(p, dest / p.stem, m, cls, cents_fix)
        else:
            shutil.copy2(p, dest / p.name)
        rows.append({
            "file": p.name, "dest": str(rel_dest), "class": cls, "subtype": subtype,
            "duration_s": f"{m['duration']:.2f}", "sr": m["sr"], "channels": m["channels"],
            "peak_dBFS": f"{m['peak_db']:.1f}", "rms_dBFS": f"{m['rms_db']:.1f}",
            "gain_to_target_dB": f"{target - current:+.1f}",
            "note": note, "cents_off": cents, "align_shift_cents": cents_fix,
            "legal_flags": flags, "notes": "",
        })

    out_dir.mkdir(parents=True, exist_ok=True)
    cols = ["file", "dest", "class", "subtype", "duration_s", "sr", "channels",
            "peak_dBFS", "rms_dBFS", "gain_to_target_dB", "note", "cents_off",
            "align_shift_cents", "legal_flags", "notes"]
    with open(out_dir / "manifest.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    counts = {}
    for r in rows:
        counts[r.get("dest", "ERROR")] = counts.get(r.get("dest", "ERROR"), 0) + 1
    print(f"{len(rows)} files → {out_dir}")
    for k in sorted(counts):
        print(f"  {k}: {counts[k]}")
    flagged = [r for r in rows if r.get("legal_flags")]
    if flagged:
        print(f"  ⚠ legal review: {len(flagged)} file(s) — see manifest.csv")


if __name__ == "__main__":
    main()
