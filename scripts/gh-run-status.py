#!/usr/bin/env python3
"""gh-run-status.py — compact CI status from a GitHub MCP tool-result dump.

The `mcp__github__actions_list` / `actions_get` tools return ~400 KB of JSON that
overflows the tool-result budget and gets spilled to a file. Reading that file
back blows context. This helper parses the SAVED file (path printed in the
overflow message) and prints just what a deploy decision needs:

    <sha7>  <status>  <conclusion>  <run_id>  <workflow name>  <display_title>

The WORKFLOW NAME column is not decoration. For a push run GitHub sets `display_title`
to the commit-message headline, so a title-only listing can never answer "is Xcode
Compile Check green?" — and that is the question every one of our commands tells the
agent to ask. `name` is the workflow's own `name:` field, which is what to match on.

Usage:
    python3 scripts/gh-run-status.py <saved-tool-result.json> [--limit N]
    python3 scripts/gh-run-status.py --selftest      # after touching this file

EXIT CODES — read them, they are the point of #978:
    0  rows printed, OR the shape was understood and held ZERO runs (said out loud)
    1  the file could not be read or is not JSON
    2  no argument given, OR the JSON is NOT a run listing

⛔ #978: exit 2 for an unreadable SHAPE is new, and it replaces the tool's worst
output. Before it, anything unrecognised fell through to `runs = [data]` and printed
ONE all-`?` row at exit 0. Measured, not supposed: a GitHub error payload
(`{"error": …}`) did that, and so did a listing under a different key
(`{"runs": […]}`) — the second SILENTLY DISCARDING a real run list. In a cycle whose
second step is "read the gates", a `?` row reads as "one run, state unknown", never as
"this file is not a run listing". A blank stdout at exit 0 had the same problem from
the other side, so an empty-but-understood listing now says so in words.

Works on the shapes the tools emit:
  • a single run object (actions_get get_workflow_run)
  • {"workflow_runs": [...]} or a bare [...] (actions_list list_workflow_runs)
  • the MCP text envelope [{"type": "text", "text": "<json>"}] some persisted
    tool results wrap the payload in. ⛔ The first version did not know this
    shape: json.load SUCCEEDED (the envelope is valid JSON), _rows walked a
    list whose one dict has no head_sha, and the output was a single
    "?  -  ?  ?" row — wrong, but not silent. Same defect class as #738 in
    gh-test-verdict.py: a JSON parse that succeeds is not a decode that
    worked. The unwrap below re-parses the inner text.

Zero deps (stdlib only). Never touches the network — it only reads a local file
the MCP tool already wrote, so it composes with the tokenless / MCP-only setup.
"""
import json
import signal
import sys

# #978: a tool that TRACEBACKS when piped into `head` looks broken and stops being
# trusted — `window-margins.py` learned this first and `count-pins.py` carried it over;
# this file, the one every cycle pipes into `head`, never did. Reproduced before fixing:
# `gh-run-status.py <dump> | head -5` printed a BrokenPipeError from the print loop.
try:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
except (AttributeError, ValueError):          # not POSIX, or not the main thread
    pass


def _unwrap_text_envelope(data):
    """Resolve the MCP persisted-output shape [{"type":"text","text":"<json>"}].

    Only unwraps when EVERY list item is such an envelope, so a bare list of
    run objects (which _rows handles) is never touched. The inner texts are
    each parsed; a single payload is returned as-is, several are merged by
    concatenating their run lists.
    """
    if not (isinstance(data, list) and data
            and all(isinstance(i, dict) and i.get("type") == "text"
                    and isinstance(i.get("text"), str) for i in data)):
        return data
    payloads = []
    for item in data:
        try:
            payloads.append(json.loads(item["text"]))
        except ValueError:
            return data  # inner text is not JSON — leave the caller's data alone
    if len(payloads) == 1:
        return payloads[0]
    merged = []
    for p in payloads:
        if isinstance(p, dict) and "workflow_runs" in p:
            merged.extend(p["workflow_runs"])
        elif isinstance(p, list):
            merged.extend(p)
        else:
            merged.append(p)
    return merged


class NotARunListing(Exception):
    """#978: the file parsed as JSON but is not a workflow-run listing.

    It exists because the old `_rows` had no way to say so. Anything it did not
    recognise fell through to `runs = [data]` and printed ONE all-`?` row at exit 0 —
    measured, not supposed: a GitHub error payload (`{"error": …}`) and a listing under
    a different key (`{"runs": […]}`) both did exactly that. In a cycle whose second
    step is "read the gates", a `?` row reads as "one run, state unknown" instead of
    "this is not a run listing", and the second case SILENTLY DISCARDS a real list.
    """


def _looks_like_run(d):
    """#978: a run object as the GitHub API emits it. `head_sha` alone is enough;
    `id`+`status` covers a trimmed/minimal-output row that drops the sha."""
    if not isinstance(d, dict):
        return False
    return "head_sha" in d or ("id" in d and "status" in d)


def _runs(data):
    """The run list, or NotARunListing with a message naming what was found instead."""
    data = _unwrap_text_envelope(data)
    if isinstance(data, dict):
        if "workflow_runs" in data:
            runs = data["workflow_runs"]
            if not isinstance(runs, list):
                raise NotARunListing(
                    f"`workflow_runs` is a {type(runs).__name__}, not a list")
            return runs
        if _looks_like_run(data):
            return [data]                       # a single run object (actions_get)
        keys = ", ".join(sorted(data)[:6]) or "(none)"
        raise NotARunListing(
            f"a JSON object with no `workflow_runs` and no run fields; keys: {keys}")
    if isinstance(data, list):
        dicts = [i for i in data if isinstance(i, dict)]
        if dicts and not any(_looks_like_run(i) for i in dicts):
            keys = ", ".join(sorted(dicts[0])[:6]) or "(none)"
            raise NotARunListing(
                f"a list of {len(dicts)} object(s), none shaped like a run; "
                f"first keys: {keys}")
        return data
    raise NotARunListing(
        f"top-level JSON is a {type(data).__name__}, not an object or a list")


def _row(r):
    return (
        str(r.get("head_sha", ""))[:7],
        r.get("status", "?"),
        r.get("conclusion") or "-",
        r.get("id", "?"),
        (r.get("name") or "?")[:30],
        (r.get("display_title") or "")[:44],
    )


def _rows(data):
    """Kept as the one public entry the callers name. Raises NotARunListing."""
    for r in _runs(data):
        if isinstance(r, dict):
            yield _row(r)


def _parse_limit(argv):
    """#978: `--limit N`, `--limit=N`, in ANY position, and 0 means 0.

    The old parser did two wrong things, both driven before this was written:
    it filtered only tokens starting with `--`, so the VALUE of a separated
    `--limit 5` stayed in the positional list and `gh-run-status.py --limit 5 f.json`
    tried to open the file `5`; and it tested `if limit:`, so `--limit=0` printed
    everything — an argument that silently does the opposite of what it says.
    Returns (limit_or_None, positional_args).
    """
    limit, positional, skip = None, [], False
    for i, a in enumerate(argv):
        if skip:
            skip = False
            continue
        if a.startswith("--limit="):
            try:
                limit = int(a.split("=", 1)[1])
            except ValueError:
                limit = None
            continue
        if a == "--limit":
            if i + 1 < len(argv):
                try:
                    limit = int(argv[i + 1])
                except ValueError:
                    limit = None
                skip = True
            continue
        if a.startswith("--"):
            continue
        positional.append(a)
    return limit, positional


def main(argv):
    if "--selftest" in argv[1:]:
        return selftest()
    limit, args = _parse_limit(argv[1:])
    if not args:
        print(__doc__)
        return 2
    try:
        with open(args[0], "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"error: cannot read/parse {args[0]}: {exc}", file=sys.stderr)
        return 1

    try:
        rows = list(_rows(data))
    except NotARunListing as exc:
        print(f"⛔ NOT A RUN LISTING: {exc}.\n"
              f"   That is NOT 'no runs' — this tool could not read {args[0]} as workflow\n"
              "   runs at all. Check you passed the right overflow file (the one the\n"
              "   `mcp__github__actions_*` result named), and do not report a gate state\n"
              "   from this run.", file=sys.stderr)
        return 2
    if limit is not None:
        rows = rows[:limit]
    for sha, status, concl, rid, wf, title in rows:
        print(f"{sha}  {status:<12} {concl:<10} {rid}  {wf:<30} {title}")
    if not rows:
        # #978: the shape WAS understood and held nothing. Said out loud, because a
        # blank stdout and exit 0 is the one output that reads as "all fine".
        print("gh-run-status: 0 runs in this file — the shape was understood and it is "
              "empty.\n  A real answer only if you expected none; check the branch "
              "filter before\n  reading it as 'nothing has run yet'."
              + (" (--limit 0 was given.)" if limit == 0 else ""))
    return 0


def selftest():
    """#978: this was the ONE script in `scripts/` with no selftest — and it is the one
    every cycle uses to answer "are the gates green". Each case below is DRIVEN through
    `main` or `_rows`, never asserted about by reading the source."""
    failures, total = [], []

    def check(name, ok):
        total.append(name)
        if not ok:
            failures.append(name)

    run = {"head_sha": "abcdef1234567", "status": "completed", "conclusion": "failure",
           "id": 42, "name": "Xcode Compile Check", "display_title": "fix: x"}
    rows = list(_rows({"workflow_runs": [run]}))
    check("a listing yields one row", len(rows) == 1)
    check("the sha is shortened to 7", rows and rows[0][0] == "abcdef1")
    check("the WORKFLOW NAME is carried, not only the title",
          rows and rows[0][4] == "Xcode Compile Check")
    check("a null conclusion prints as a dash",
          list(_rows({"workflow_runs": [dict(run, conclusion=None)]}))[0][2] == "-")
    check("a bare list of runs is read", len(list(_rows([run]))) == 1)
    check("a single run object is read", len(list(_rows(run))) == 1)
    check("the MCP text envelope is unwrapped",
          len(list(_rows([{"type": "text",
                           "text": json.dumps({"workflow_runs": [run]})}]))) == 1)

    def raises(payload):
        try:
            list(_rows(payload))
        except NotARunListing:
            return True
        return False

    # The measured defects: each of these printed ONE all-`?` row at exit 0 before #978.
    check("a GitHub error payload is REFUSED, not shown as a run",
          raises({"error": "rate limited", "documentation_url": "x"}))
    check("a listing under another key is REFUSED rather than silently discarded",
          raises({"total_count": 0, "runs": [run]}))
    check("a non-list `workflow_runs` is refused",
          raises({"workflow_runs": {"a": 1}}))
    check("a scalar payload is refused", raises("hello"))
    check("an EMPTY listing is NOT refused — empty is an answer",
          not raises({"workflow_runs": []}) and not raises([]))

    check("--limit before the file leaves the file positional",
          _parse_limit(["--limit", "5", "f.json"]) == (5, ["f.json"]))
    check("--limit after the file works too",
          _parse_limit(["f.json", "--limit", "5"]) == (5, ["f.json"]))
    check("--limit=N works", _parse_limit(["f.json", "--limit=3"]) == (3, ["f.json"]))
    check("--limit=0 means ZERO, not 'unset'",
          _parse_limit(["f.json", "--limit=0"]) == (0, ["f.json"]))
    check("a non-numeric limit is dropped, not crashed",
          _parse_limit(["f.json", "--limit=x"]) == (None, ["f.json"]))

    # #978: the SIGPIPE guard, checked as INSTALLED STATE rather than as source text.
    # Reproduced before fixing: `gh-run-status.py <dump> | head -5` printed a
    # BrokenPipeError from the print loop, 3 runs out of 3, on the tree at HEAD.
    # This asserts the handler this module set at import; it cannot assert the pipe
    # behaviour itself without a subprocess, and does not pretend to.
    check("the SIGPIPE handler is installed as SIG_DFL",
          not hasattr(signal, "SIGPIPE")
          or signal.getsignal(signal.SIGPIPE) == signal.SIG_DFL)

    # End to end through `main`, including the exit codes a caller would branch on.
    import contextlib
    import io
    import os
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        good = os.path.join(tmp, "good.json")
        bad = os.path.join(tmp, "bad.json")
        empty = os.path.join(tmp, "empty.json")
        torn = os.path.join(tmp, "torn.json")
        open(good, "w").write(json.dumps({"workflow_runs": [run]}))
        open(bad, "w").write(json.dumps({"error": "boom"}))
        open(empty, "w").write(json.dumps({"workflow_runs": []}))
        open(torn, "w").write('{"workflow_runs": [')

        def drive(args):
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                rc = main(["gh-run-status.py"] + args)
            return rc, out.getvalue(), err.getvalue()

        rc, out, _ = drive([good])
        check("a good file exits 0 and prints the row", rc == 0 and "abcdef1" in out)
        rc, out, err = drive([bad])
        check("an unreadable SHAPE exits 2", rc == 2)
        check("...and says so on stderr, not as a row",
              "NOT A RUN LISTING" in err and "?" not in out)
        rc, out, _ = drive([empty])
        check("an empty listing exits 0 and SAYS it is empty",
              rc == 0 and "0 runs in this file" in out)
        rc, _, err = drive([torn])
        check("torn JSON still exits 1", rc == 1 and "cannot read/parse" in err)
        rc, out, _ = drive([good, "--limit=0"])
        check("--limit=0 prints no rows and says why",
              rc == 0 and "abcdef1" not in out and "--limit 0 was given" in out)
        rc, out, _ = drive(["--limit", "1", good])
        check("--limit N before the file no longer eats the path",
              rc == 0 and "abcdef1" in out)
        rc, _, _ = drive([])
        check("no argument prints usage and exits 2", rc == 2)

    print(f"selftest: {'OK' if not failures else 'FAILED'}, {len(failures)} failure(s) "
          f"of {len(total)} checks")
    for name in failures:
        print(f"  FAILED: {name}")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
