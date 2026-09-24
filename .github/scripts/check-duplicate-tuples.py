#!/usr/bin/env python3
"""I6: no two matrix rows describe the same test.

The suites are matrices of `- { id: X, name: "...", <params> }`. Strip the id
and display name, and two rows that remain identical are one test billed
twice: it adds nothing, and it inflates the denominator of the board's pass
rate. PR #13 removed six of these found by hand.

Two tiers:
  exact       every parameter matches.
  invocation  the same, ignoring `cname` too -- the same argus call under a
              different container name.

An invocation-tier pair can be deliberate, when a follow-on job asserts
something extra about one of them. Record that with `# dry:allow <reason>` in
the comment block directly above either row; one annotated row covers its
group, because the annotation explains the pairing, not the row.

Exit codes:
  0  no unexplained duplicates
  1  at least one unexplained duplicate group
  2  no matrix rows were found at all -- a check that read nothing must not
     report a pass

This used to live in the code-cleanliness panel as a report-only figure that
fell back to null on any error. As a gate it fails closed instead.
"""
import collections
import pathlib
import re
import sys

ROW = re.compile(r"^\s*-\s*\{\s*(id:.*)\}\s*$")
# `key: value` where value is bare, 'single' or "double" quoted.
PAIR = re.compile(r"""(\w+)\s*:\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[^,}]*)""")
ALLOW = re.compile(r"#\s*dry:allow\b[ \t]*(.*)")

IDENTITY = {"id", "name"}          # never behaviour
COSMETIC = {"cname"}               # usually a label, but not always -- see E7


def scan(wf_dir):
    exact = collections.defaultdict(list)
    invoc = collections.defaultdict(list)
    allowed = {}
    rows = 0
    for wf in sorted(pathlib.Path(wf_dir).glob("test-*.yml")):
        lines = wf.read_text().splitlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("#"):
                continue
            m = ROW.match(line)
            if not m:
                continue
            rows += 1
            pairs = {k: v.strip().strip("\"'") for k, v in PAIR.findall(m.group(1))}
            tid = pairs.get("id", "?")
            where = (tid, f"{wf.as_posix()}", i + 1)

            # the comment block immediately above the row
            for j in range(i - 1, max(-1, i - 8), -1):
                t = lines[j].strip()
                if not t.startswith("#"):
                    break
                a = ALLOW.search(t)
                if a:
                    allowed[tid] = a.group(1).strip() or "no reason given"
                    break

            ex = tuple(sorted((k, v) for k, v in pairs.items() if k not in IDENTITY))
            iv = tuple(sorted((k, v) for k, v in pairs.items()
                              if k not in IDENTITY and k not in COSMETIC))
            if ex:
                exact[ex].append(where)
            if iv:
                invoc[iv].append(where)
    return rows, exact, invoc, allowed


def unexplained(groups, allowed):
    bad, ok = [], []
    for members in groups.values():
        if len(members) < 2:
            continue
        why = next((allowed[t[0]] for t in members if t[0] in allowed), None)
        (ok if why else bad).append((members, why))
    return bad, ok


def main():
    wf_dir = sys.argv[1] if len(sys.argv) > 1 else ".github/workflows"
    rows, exact, invoc, allowed = scan(wf_dir)
    if rows == 0:
        print(f"::error title=I6::No matrix rows found under {wf_dir}. The check read "
              "nothing, so it cannot say there are no duplicates.")
        return 2

    ex_bad, _ = unexplained(exact, allowed)
    iv_bad, iv_ok = unexplained(invoc, allowed)
    # A group already reported as exact would be reported again as invocation.
    ex_ids = {frozenset(t[0] for t in m) for m, _ in ex_bad}
    iv_bad = [(m, w) for m, w in iv_bad if frozenset(t[0] for t in m) not in ex_ids]

    print(f"{rows} matrix rows checked.")
    for members, why in iv_ok:
        print(f"  allowed: {' = '.join(t[0] for t in members)} -- {why}")

    for tier, bad, advice in (
        ("identical in every parameter", ex_bad,
         "Remove one of them."),
        ("the same argus invocation under a different container name", iv_bad,
         "Remove one, or if a follow-on job asserts something extra about one of "
         "them, say so with '# dry:allow <reason>' above it."),
    ):
        for members, _ in bad:
            ids = " = ".join(t[0] for t in members)
            first = members[1]
            print(f"::error file={first[1]},line={first[2]},title=I6 duplicate test::"
                  f"{ids} are {tier}, so they are one test counted "
                  f"{len(members)} times. {advice}")
            for tid, f, ln in members:
                print(f"    {tid}  {f}:{ln}")

    n = len(ex_bad) + len(iv_bad)
    if n:
        print(f"FAIL: {n} unexplained duplicate group(s).")
        return 1
    print("PASS: no unexplained duplicate tests.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
