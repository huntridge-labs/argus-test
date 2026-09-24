#!/usr/bin/env python3
"""Where each test is defined in a workflow file, as a line RANGE.

Usage: test-locations.py <workflow.yml>
Prints a JSON array of {"id", "line", "end"}.

The board's "test" link opens the definition on GitHub, and GitHub highlights
#L<line>-L<end>. It used to get one line -- the job's `name:` line -- and
matrix tests got none, so the link opened the top of the file. A reader wants
the block that IS the test:

  a test that is its own job  -> the whole job, from its key to the line before
                                 the next job (trailing blank lines and the next
                                 job's header comment excluded);
  a matrix test               -> its row, with any annotation comments directly
                                 above it (`# dry:allow ...` sits there). The
                                 comment above the FIRST row describes the whole
                                 list, so it is not claimed by that row.

IDs match exactly: "E1a: resolve digest" is E1a's job, never E1's.
"""
import json
import re
import sys

JOB = re.compile(r"^  ([A-Za-z0-9_-]+):\s*$")
# `name: "R6: ..."`, or a shared job `name: "N1/N2: ..."` that is both tests.
NAME = re.compile(r'^\s*name:\s*"((?:[A-Z]+[0-9]+[a-z]?)(?:/[A-Z]+[0-9]+[a-z]?)*):')
ROW = re.compile(r"^(\s*)-\s*\{\s*id:\s*([A-Z]+[0-9]+[a-z]?)\s*,")


def main(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    n = len(lines)

    try:
        jobs_at = next(i for i, l in enumerate(lines) if l.rstrip() == "jobs:")
    except StopIteration:
        jobs_at = -1
    starts = [i for i in range(jobs_at + 1, n) if JOB.match(lines[i])] if jobs_at >= 0 else []

    def job_block(i):
        """0-based [start, end] of the job containing line i, or None."""
        s = max((j for j in starts if j <= i), default=None)
        if s is None:
            return None
        nxt = min((j for j in starts if j > s), default=n)
        e = nxt - 1
        while e > s and (not lines[e].strip() or lines[e].lstrip().startswith("#")):
            e -= 1
        return s, e

    out = {}
    # Tests that are their own job. If an id names more than one job, keep the
    # last -- the historical rule, and the right one for helper-then-test pairs.
    for i, l in enumerate(lines):
        m = NAME.match(l)
        if m:
            b = job_block(i)
            if b:
                for tid in m.group(1).split("/"):
                    out[tid] = b
    # Matrix rows, for ids that have no job of their own.
    for i, l in enumerate(lines):
        m = ROW.match(l)
        if not m or m.group(2) in out:
            continue
        indent, s = m.group(1), i
        prev_is_row = False
        j = i - 1
        while j >= 0 and lines[j].startswith(indent + "#"):
            j -= 1
        if j >= 0 and ROW.match(lines[j]):
            prev_is_row = True
        if prev_is_row:
            s = j + 1
        out[m.group(2)] = (s, i)

    print(json.dumps([{"id": k, "line": s + 1, "end": e + 1} for k, (s, e) in out.items()],
                     separators=(",", ":")))


if __name__ == "__main__":
    main(sys.argv[1])
