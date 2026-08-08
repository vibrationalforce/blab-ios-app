#!/usr/bin/env bash
# review.sh — Surface decisions that are due for review
# Usage: ./review.sh [--flag|--check]
#   --flag:  Also update decisions.csv with REVIEW_DUE status
#   --check: Only validate that the log is machine-readable (exit 1 if not)
#
# Cron install (daily at 9 AM):
#   crontab -e
#   0 9 * * * /home/user/Echoelmusic/check-decisions.sh
#
# ⛔ THE PARSER LIVES IN EXACTLY ONE PLACE (#509, 2026-08-08) — and the reason is
# measured, not stylistic. This script used to read the log with
#     while IFS=, read -r date decision reasoning outcome review_date status
# which splits on EVERY comma and is blind to quoting; `tr -d '"'` then ran AFTER
# the split, so quoting a field never helped. Measured on the log of 2026-08-08:
# **241 of 363 rows** handed a non-date to `review_date` (e.g. ` checkout --`,
# ` App Store differentiation`) — the field-5 token happened to fall inside a
# quoted reasoning. Two thirds of the decision log was invisible to the report
# that exists to surface it, and nothing said so.
#
# ⚠️ The `--flag` path was the dangerous half: it rewrote the file by echoing the
# same mangled split back out. `is_due` compares strings, and a garbage token
# starting with a space sorts BEFORE any date, so it read as due; the status token
# was garbage too, so the "already flagged" skip never fired. One `--flag` run
# would have shifted every field of every comma-carrying row, permanently. It has
# never run (`grep -c REVIEW_DUE decisions.csv` = 0) — that is luck, not design.
# `check-decisions.sh`, the documented daily cron, calls exactly `review.sh --flag`.
#
# ⚠️ FIRST `--flag` RUN MAY RE-QUOTE: the rewrite goes through `csv.writer`
# (QUOTE_MINIMAL), so a field that carried unnecessary quotes loses them and one
# that needed them gains them. Content is unchanged and the result is idempotent.
# That normalisation is deliberately NOT done eagerly here — reflowing 295 KB in a
# commit nobody can review is worse than a one-time diff on the day it is needed.
#
# ⚠️ The due-predicate is PRESERVED exactly as it was (review_date <= today AND
# status not in {REVIEW_DUE, REVIEWED}) — widening it to also skip `superseded` /
# `shipped` / `RESOLVED` is a judgment call about the review workflow, not a parse
# fix, and does not belong in the same change.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV="$SCRIPT_DIR/decisions.csv"
MODE="${1:-}"

if [[ ! -f "$CSV" ]]; then
    echo "No decisions.csv found at $CSV"
    exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "review.sh needs python3 to parse the log"; exit 1; }

CSV="$CSV" MODE="$MODE" python3 - <<'PY'
import csv, os, sys, datetime, signal

# `./review.sh | head` is the normal way to skim 132 due decisions, and python
# turns the resulting SIGPIPE into a traceback on stderr. Restore the default
# handler so a truncated read stays quiet — the cron pipes this into a log file.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):
    pass  # no SIGPIPE on this platform

path = os.environ["CSV"]
mode = os.environ.get("MODE", "")
today = datetime.date.today().isoformat()

with open(path, newline="", encoding="utf-8") as f:
    rows = list(csv.reader(f))

if not rows:
    print(f"{path} is empty")
    sys.exit(1)

header, body = rows[0], rows[1:]
EXPECTED = len(header)  # date,decision,reasoning,expected_outcome,review_date,status

# A row that does not have the header's shape cannot be reported on honestly:
# every field after the break belongs to the wrong column. Say so loudly instead
# of silently reporting a reasoning string as a review date.
malformed = [(i + 2, len(r)) for i, r in enumerate(body) if len(r) != EXPECTED]
if malformed:
    print(f"MALFORMED — {len(malformed)} row(s) do not have {EXPECTED} columns:")
    for line_no, n in malformed:
        print(f"  line {line_no}: {n} columns")
    print("Fix decisions.csv before trusting this report.")
    sys.exit(1)

if mode == "--check":
    print(f"decisions.csv OK — {len(body)} decisions, {EXPECTED} columns each.")
    sys.exit(0)

SKIP_STATUS = {"REVIEW_DUE", "REVIEWED"}

def is_due(row):
    return row[4] <= today and row[5] not in SKIP_STATUS

print(f"=== Decision Review — {today} ===")
print()

due = [r for r in body if is_due(r)]
for r in due:
    print(f"REVIEW DUE [{r[4]}]")
    print(f"  Decision:  {r[1]}")
    print(f"  Reasoning: {r[2]}")
    print(f"  Expected:  {r[3]}")
    print(f"  Made on:   {r[0]}")
    print()

if not due:
    print("No decisions due for review.")

if mode == "--flag":
    for r in body:
        if is_due(r):
            r[5] = "REVIEW_DUE"
    tmp = path + ".tmp"
    with open(tmp, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(body)
    os.replace(tmp, path)
    print(f"Updated decisions.csv — flagged {len(due)} decision(s) REVIEW_DUE.")
PY
