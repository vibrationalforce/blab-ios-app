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
# ⚠️ THE DEFERRED JUDGMENT CALL IS MADE (#815). This block used to say the predicate
# was "PRESERVED exactly as it was … widening it is a judgment call about the review
# workflow, not a parse fix, and does not belong in the same change." Correct then;
# the call is now taken, and here is the measurement it rests on.
#
# ⛔ THE OLD SKIP LIST NAMED TWO STATUSES THAT DO NOT OCCUR IN THE FILE.
# `{REVIEW_DUE, REVIEWED}` — `grep -c REVIEW_DUE decisions.csv` is 0 and always has
# been, and nothing writes REVIEWED either. So the skip was empty in practice and the
# report listed every past-dated row, including decisions explicitly recorded as
# replaced or refused. A filter whose entries cannot match is the same defect class as
# a needle that cannot match (#808).
#
# WHAT IS SKIPPED NOW, and why exactly these: a decision that is NO LONGER IN FORCE
# asks nothing on review — `superseded*` (replaced by a later decision), `rejected`
# (refused), `resolved` and `fixed` (the question is closed). `shipped` is deliberately
# NOT skipped: the change landed, but "did the expected outcome happen?" is precisely
# what a review asks, and skipping it would hide the only rows where the log can be
# wrong about reality. `active` obviously stays.
#
# CASE-INSENSITIVE, because the file holds `active` (199) AND `ACTIVE` (137) — one
# status in two casings — plus `resolved`/`RESOLVED` and `in-progress`/`in_progress`.
# A case-sensitive list catches half of each pair and looks like it works.
#
# MEASURED EFFECT: 246 due -> 219, with 27 skipped. ⛔ The first version of this line
# said "-> 216" and "30 skipped" — the numbers from the PROTOTYPE, whose terminal set
# also held `confirmed`, `assessed`, `amended` and `parked`. Those four are not in the
# shipped list (each is one or two rows and none clearly means "no longer in force"), so
# the shipped filter is narrower than the one I measured with. Third time this session a
# predicted number differed from the driven one (#808, #813): **the number that goes in
# the comment is the one the SHIPPED code prints.** These two are re-derivable and stay
# only as the size of this change; the live figures are the BACKLOG line the script now
# prints on every run.
#
# The change is small on purpose: the backlog is NOT mostly noise. 219 decisions really
# have never been reviewed, the oldest dated 2026-04-10 — four and a half months.
# Nothing flags them (#810: there is no cron), and a 30-day default on every row makes
# the backlog unbounded by design. Fixing the filter does not fix that, and this line
# must not be read as having done so.

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

# Lower-case, and matched on the token BEFORE any "-" so `superseded-#122/#123` and
# `superseded-2026-07-24-#121` are caught by the one entry. See the block at the top of
# this file for why each is here and why `shipped` is not.
SKIP_STATUS = {"review_due", "reviewed", "superseded", "rejected", "resolved", "fixed"}

def not_in_force(row):
    return row[5].strip().lower().split("-")[0] in SKIP_STATUS

def is_due(row):
    return row[4] <= today and not not_in_force(row)

print(f"=== Decision Review — {today} ===")
print()

due = [r for r in body if is_due(r)]
# The size and the age FIRST, because 216 items is a backlog and not a to-do list, and a
# reader who starts at the first entry cannot tell which they are looking at. `skipped`
# is printed so the filter never quietly grows into hiding real work.
skipped = sum(1 for r in body if r[4] <= today and not_in_force(r))
if due:
    print(f"BACKLOG: {len(due)} due, oldest {min(r[4] for r in due)}; "
          f"{skipped} past-dated row(s) skipped as no longer in force.")
    print()
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
