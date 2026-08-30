#!/usr/bin/env python3
"""Measure how close each `…[anchor...].prefix(N)` window in Tests/CISmoke is to going RED
ON CORRECT CODE.

WHY THIS EXISTS (#897 found it, #898 measured it). `SourceText.codeOnly` blanks a comment's
TEXT but keeps its leading whitespace — it must, because several guards assert on the
relative ORDER of two matches, so lines are preserved rather than deleted. A stripped doc
line therefore still costs 8–28 characters. Every character-counted window in the blocking
bundle is consequently spent on whitespace as much as on code, and writing prose above the
thing being asserted walks the needle out of the window. The failure shape is the worst
available: a guard fails on CORRECT code, during unrelated work, naming the wrong culprit.

WHAT IT PRINTS: per site, the offset of the furthest needle inside the window and the
characters left over. Small margin = the next ⛔ block in that region breaks an unrelated
guard.

⚠️ HONEST LIMITS, because a measuring tool that hides its blind spots is the defect it looks
for. (1) It resolves the target file and the anchor by scanning BACKWARDS from the window
line for the nearest `"Sources/….swift"` and the nearest `range(of: "…")`. Where a test
builds either indirectly, the site prints `unresolved` — that is the tool failing, never a
verdict about the guard. (2) It collects needles from `contains("…")` on the following few
lines only; a needle built by interpolation or held in a variable is invisible, so a printed
margin is an UPPER BOUND on safety, never a proof. (3) It never runs a test. (4) #899: it sees ONE syntactic shape, `[ident...].prefix(N)`.
BACKWARD windows of the same class — `index(x, offsetBy: -N)` — are outside the census; three
exist today (the thinnest measured 314 characters, none thinner than the two that were
converted), so the conclusion held, but the census does not cover them. (5) #899: the MECHANISM
needs the site's file to use `SourceText.codeOnly`; a file whose local stripper DELETES comment
lines is immune, so a site appearing here is not by itself evidence of exposure.

    python3 scripts/window-margins.py            # all sites, worst margin first
    python3 scripts/window-margins.py --thin 250 # only sites at or under that margin
    python3 scripts/window-margins.py --selftest
"""
import argparse
import glob
import os
import re
import sys

WINDOW = re.compile(r'\[[\w.]+\.\.\.\]\s*\.prefix\((\d[\d_]*)\)')
ANCHOR = re.compile(r'range\(of:\s*"((?:[^"\\]|\\.)*)"')
PATH = re.compile(r'"(Sources/[^"]+\.swift)"')
# ⛔ #898: widened once to `(?:contains|range\(of:)` and that made it WORSE — 5 measured
# down to 4 — because `range(of:)` is how a LATER window states its own anchor, so the
# extra literals landed outside and turned resolvable sites into "needle outside window".
# A measuring tool that reaches further and reports less is not more thorough.
NEEDLE = re.compile(r'contains\(\s*"((?:[^"\\]|\\.)*)"')
MIN_WINDOW = 100          # below this it is a message truncation, not a source window
LOOKBACK, LOOKAHEAD = 120, 14


def strip_line(line, in_block):
    """Port of SourceText.stripLine — a `//` or `/*` inside a string literal is not a comment."""
    out, block, in_str, i, n = [], in_block, False, 0, len(line)
    while i < n:
        c, nxt = line[i], i + 1
        has = nxt < n
        if block:
            if has and c == "*" and line[nxt] == "/":
                block, i = False, nxt + 1
            else:
                i = nxt
            continue
        if in_str:
            if c == "\\" and has:
                out.append(c), out.append(line[nxt]); i = nxt + 1; continue
            if c == '"':
                in_str = False
            out.append(c); i = nxt; continue
        if has and c == "/" and line[nxt] == "/":
            break
        if has and c == "/" and line[nxt] == "*":
            block, i = True, nxt + 1
            continue
        if c == '"':
            in_str = True
        out.append(c); i = nxt
    return "".join(out), block


def code_only(text):
    out, blk = [], False
    for raw in text.split("\n"):
        code, blk = strip_line(raw, blk)
        out.append(code)
    return "\n".join(out)


def sites(root):
    for path in sorted(glob.glob(os.path.join(root, "Tests/CISmoke/*.swift"))):
        lines = open(path, encoding="utf-8").read().split("\n")
        for i, line in enumerate(lines):
            m = WINDOW.search(line)
            if not m:
                continue
            size = int(m.group(1).replace("_", ""))
            if size < MIN_WINDOW:
                continue
            # Search back to the top of the enclosing test (or a fixed distance, whichever
            # is nearer): a guard commonly loads its source once at the start of the method
            # and windows much further down, so a fixed lookback resolved barely a sixth of
            # the sites on the first run.
            # #899: "whichever is NEARER" now actually holds. The first version assigned the
            # `func test` bound unconditionally, discarding the fixed one even when the method
            # header was farther away — which for a site outside any `func test` left the scan
            # unbounded and able to bind an anchor from an unrelated earlier test. Latent only
            # (max measured distance to an enclosing test: 69), but a comment that describes a
            # bound the code does not take is the defect this repo pays for most often.
            stop = max(-1, i - LOOKBACK)
            for j in range(i, -1, -1):
                if lines[j].lstrip().startswith("func test"):
                    stop = max(stop, j - 1)
                    break
            target = anchor = None
            for j in range(i, stop, -1):
                if anchor is None:
                    a = ANCHOR.search(lines[j])
                    if a:
                        anchor = a.group(1).replace('\\"', '"')
                if target is None:
                    p = PATH.search(lines[j])
                    if p:
                        target = p.group(1)
                if target and anchor:
                    break
            # Joined, not per-line: a needle is routinely the argument of a call whose
            # literal sits on the NEXT line, and `range(of:)` is as common as `contains(` for
            # asking whether the window holds something.
            ahead = "\n".join(lines[i:min(len(lines), i + LOOKAHEAD)])
            needles = [n.replace('\\"', '"') for n in NEEDLE.findall(ahead)]
            yield os.path.basename(path), i + 1, size, target, anchor, needles


def measure(root, thin):
    cache, rows, unresolved = {}, [], []
    for name, line, size, target, anchor, needles in sites(root):
        label = f"{name}:{line}"
        if not (target and anchor and needles):
            unresolved.append((label, size, "no path/anchor/needle on the surrounding lines"))
            continue
        full = os.path.join(root, target)
        if full not in cache:
            try:
                cache[full] = code_only(open(full, encoding="utf-8").read())
            except OSError:
                cache[full] = None
        text = cache[full]
        if text is None or anchor not in text:
            unresolved.append((label, size, f"anchor not found in {target}"))
            continue
        window = text[text.index(anchor):][:size]
        offsets = [window.find(x) for x in needles]
        if any(o < 0 for o in offsets):
            unresolved.append((label, size, "a collected needle is outside the window (see LIMITS)"))
            continue
        rows.append((size - max(offsets), label, size, max(offsets)))
    rows.sort()
    print(f"{len(rows)} measured, {len(unresolved)} unresolved "
          f"(unresolved = the TOOL could not read the site, not a verdict)\n")
    print(f"{'margin':>7}  {'window':>6}  {'furthest needle':>15}  site")
    shown = 0
    for margin, label, size, off in rows:
        if thin is not None and margin > thin:
            continue
        shown += 1
        flag = "  <-- THIN" if margin <= 250 else ""
        print(f"{margin:>7}  {size:>6}  {off:>15}  {label}{flag}")
    if thin is not None:
        # #899: an empty table under --thin read as "all clear". It is not: the filter only
        # ever sees the MEASURED rows, and most sites are not among them.
        if shown == 0:
            print(f"  (no MEASURED site at or under a margin of {thin})")
        print(f"\n  {len(unresolved)} site(s) were never measured — run without --thin to list "
              f"them. A quiet --thin is not an all-clear.")
    if unresolved and thin is None:
        print("\nunresolved:")
        for label, size, why in unresolved:
            print(f"  {label}  (window {size}) — {why}")
    return 0


def selftest():
    # (line, incoming block state) -> (expected code, expected outgoing block state)
    cases = [
        ('let x = "a // b"', False, 'let x = "a // b"', False, "a // inside a string is not a comment"),
        ("code() // why", False, "code() ", False, "a trailing comment is cut"),
        ("        // all prose", False, "        ", False,
         "a comment line KEEPS its indentation — the whole point of this tool"),
        ('let s = "\\"" // t', False, 'let s = "\\"" ', False, "an escaped quote does not close the literal"),
        # #899: the /* branch was untested, and SourceText's own header calls it "the DANGEROUS
        # one". Its state CROSSES lines, which is the only part of this port that is not a pure
        # function of one line — so the outgoing flag is asserted too, not just the text.
        ("a /* b */ c", False, "a  c", False, "an inline block comment is removed, both sides kept"),
        ("a /* b", False, "a ", True, "an unclosed block opens and reports it"),
        ("still inside", True, "", True, "a line inside a block yields nothing and stays open"),
        ("b */ tail", True, " tail", False, "the block closes mid-line and the tail survives"),
        ('let u = "/* not a block"', False, 'let u = "/* not a block"', False,
         "a /* inside a string does not open a block"),
    ]
    bad = 0
    for src, blk_in, want, blk_out, why in cases:
        got, got_blk = strip_line(src, blk_in)
        if got != want or got_blk != blk_out:
            print(f"FAIL {why}\n  in={src!r} block={blk_in}\n  want={want!r} block={blk_out}"
                  f"\n  got ={got!r} block={got_blk}")
            bad += 1
    # #899: `len(cases)`, not a literal — the first version printed "4 cases" beside a list
    # whose length it did not read, which is this repo's most-repeated defect in miniature.
    print("selftest: " + (f"OK, {len(cases)} cases" if not bad else f"{bad} of {len(cases)} FAILED"))
    return 1 if bad else 0


if __name__ == "__main__":
    # A tool that traces back when piped into `head` looks broken and stops being trusted.
    try:
        import signal
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    except (ImportError, AttributeError, ValueError):
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--thin", type=int, default=None, help="only sites at or under this margin")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    args = ap.parse_args()
    sys.exit(selftest() if args.selftest else measure(args.root, args.thin))
