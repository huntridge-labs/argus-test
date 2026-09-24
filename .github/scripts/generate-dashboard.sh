#!/usr/bin/env bash
# generate-dashboard.sh — Generates a self-contained HTML dashboard + history.json
# for the Argus test suite. Called from the summary job in test-suite.yml.
#
# Expected env vars:
#   ALL_JSON      — merged JSON array of all test results
#   SCOPE         — test scope (all, unit, remote, etc.)
#   RUN_URL       — link to this workflow run
#   RUN_ID        — github.run_id
#   REPO          — owner/repo
#   PAGES_DIR     — directory to write output files into
#   UNIT_JSON, ACTIONS_JSON, REMOTE_JSON, DISCOVER_JSON, COMBO_JSON, EDGE_JSON, WF_JSON, SCN_JSON, REGRESSION_JSON
#   UNIT_RESULT, ACTIONS_RESULT, REMOTE_RESULT, DISCOVER_RESULT, COMBO_RESULT, EDGE_RESULT, SCN_RESULT, I1_RESULT, I2_RESULT, I3_RESULT
#   ARGUS_REPO — upstream repo (e.g., huntridge-labs/argus)
#   ARGUS_REF  — branch/tag being tested (e.g., main)
#   ARGUS_SHA  — full commit SHA of the ref
#   ARGUS_SHA_SHORT — short (7-char) commit SHA
set -euo pipefail

OUT="${PAGES_DIR:?PAGES_DIR not set}"
mkdir -p "$OUT"

# The dashboard lives at <branch>/tests/, but history.json and favicon.png are
# shared with the root index and the branch redirect, so they sit one level
# up at the branch root. SHARED_DIR defaults to OUT so the script still works
# standalone.
SHARED_DIR="${SHARED_DIR:-$OUT}"
mkdir -p "$SHARED_DIR"
# How the page reaches the shared files and its siblings: '' when the dashboard
# IS the branch root, '../' when nested under tests/.
UP="${SITE_UP:-}"

# ---------- safe JSON helper (empty string → []) ----------
safe_json() {
  if [ -n "$1" ] && echo "$1" | jq empty 2>/dev/null; then
    echo "$1"
  else
    echo "[]"
  fi
}

UNIT_JSON=$(safe_json "${UNIT_JSON:-}")
ACTIONS_JSON=$(safe_json "${ACTIONS_JSON:-}")
REMOTE_JSON=$(safe_json "${REMOTE_JSON:-}")
DISCOVER_JSON=$(safe_json "${DISCOVER_JSON:-}")
COMBO_JSON=$(safe_json "${COMBO_JSON:-}")
EDGE_JSON=$(safe_json "${EDGE_JSON:-}")
WF_JSON=$(safe_json "${WF_JSON:-}")
SCN_JSON=$(safe_json "${SCN_JSON:-}")
REGRESSION_JSON=$(safe_json "${REGRESSION_JSON:-}")
RUNTIME_JSON=$(safe_json "${RUNTIME_JSON:-}")
RUNTIME_JSON=$(safe_json "${RUNTIME_JSON:-}")
ALL_JSON=$(safe_json "${ALL_JSON:-}")

# ---------- compute stats ----------
TOTAL=$(echo "$ALL_JSON" | jq 'length')
PASSED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "pass")] | length')
FAILED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "FAIL")] | length')
SKIPPED=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "skip" or .status == "cancel")] | length')
RUNNABLE=$((TOTAL - SKIPPED))
[ "$RUNNABLE" -eq 0 ] && RUNNABLE=1
PASS_RATE=$((PASSED * 100 / RUNNABLE))   # superseded below by PCT_DEFINED; see there

if [ "$FAILED" -eq 0 ] && [ "$PASSED" -gt 0 ]; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

DATE_STR=$(date -u '+%Y-%m-%d %H:%M UTC')

# ---------- history ----------
HISTORY_FILE="$SHARED_DIR/history.json"
if [ ! -f "$HISTORY_FILE" ]; then
  echo '[]' > "$HISTORY_FILE"
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/site-nav.sh"
# ---------- failure classes (what a red test costs a consumer) ------------
CLASSES_FILE="$SCRIPT_DIR/../data/failure-classes.json"
if [ -f "$CLASSES_FILE" ] && jq empty "$CLASSES_FILE" 2>/dev/null; then
  CLASSES_JSON=$(jq -c '{default, weights, labels, short, glossary, status, index, descriptions, classes, references}' "$CLASSES_FILE")
else
  CLASSES_JSON='null'
  echo "WARNING: no readable $CLASSES_FILE — the risk score will fall back to counting failures"
fi

# Risk has to be computed here as well as in the browser, so it can be recorded
# in history and plotted over time. Same definition: sum of class weights over
# failing tests, with the file's default applied to anything unclassified.
RISK=$(jq -n -c --argjson all "$ALL_JSON" --argjson fc "${CLASSES_JSON:-null}" '
  ($fc // {}) as $f
  | (($f.weights) // {open:10, closed:3, auxiliary:1}) as $w
  | (($f.default) // "closed") as $dflt
  | (($f.classes) // {} | to_entries | map(.value[] as $id | {key:$id, value:.key}) | from_entries) as $cls
  | [ $all[] | select(.status == "FAIL") | (((.class // "") as $c | if ($w | has($c)) then $c else ($cls[.id] // $dflt) end)) | ($w[.] // 0) ] | add // 0')
echo "Risk index: $RISK"


# ---------- build category data for HTML ----------
cat_status() {
  case "${1:-}" in
    success) echo "pass" ;;
    failure) echo "fail" ;;
    skipped) echo "skip" ;;
    cancelled) echo "skip" ;;
    *) echo "unknown" ;;
  esac
}

UNIT_RESULT="${UNIT_RESULT:-skipped}"
ACTIONS_RESULT="${ACTIONS_RESULT:-skipped}"
REMOTE_RESULT="${REMOTE_RESULT:-skipped}"
DISCOVER_RESULT="${DISCOVER_RESULT:-skipped}"
COMBO_RESULT="${COMBO_RESULT:-skipped}"
EDGE_RESULT="${EDGE_RESULT:-skipped}"
WF_RESULT="${WF_RESULT:-skipped}"
SCN_RESULT="${SCN_RESULT:-skipped}"
I1_RESULT="${I1_RESULT:-skipped}"
I2_RESULT="${I2_RESULT:-skipped}"
I3_RESULT="${I3_RESULT:-skipped}"

# Build categories JSON for embedding
CATEGORIES=$(jq -n -c \
  --arg us "$(cat_status "$UNIT_RESULT")" \
  --arg as "$(cat_status "$ACTIONS_RESULT")" \
  --arg rs "$(cat_status "$REMOTE_RESULT")" \
  --arg ds "$(cat_status "$DISCOVER_RESULT")" \
  --arg cs "$(cat_status "$COMBO_RESULT")" \
  --arg es "$(cat_status "$EDGE_RESULT")" \
  --arg ws "$(cat_status "$WF_RESULT")" \
  --arg ss "$(cat_status "$SCN_RESULT")" \
  --arg i1s "$(cat_status "$I1_RESULT")" \
  --arg i2s "$(cat_status "$I2_RESULT")" \
  --arg i3s "$(cat_status "$I3_RESULT")" \
  --arg i4s "$(cat_status "${I4_RESULT:-skipped}")" \
  --arg i5s "$(cat_status "${I5_RESULT:-skipped}")" \
  --arg i6s "$(cat_status "${I6_RESULT:-skipped}")" \
  --arg i4s "$(cat_status "${I4_RESULT:-skipped}")" \
  --argjson u "$UNIT_JSON" \
  --argjson a "$ACTIONS_JSON" \
  --argjson r "$REMOTE_JSON" \
  --argjson d "$DISCOVER_JSON" \
  --argjson co "$COMBO_JSON" \
  --argjson ed "$EDGE_JSON" \
  --argjson wf "$WF_JSON" \
  --argjson sc "$SCN_JSON" \
  --argjson ig "$REGRESSION_JSON" \
  --argjson rt "$RUNTIME_JSON" \
  --arg rts "$(cat_status "${RUNTIME_RESULT:-skipped}")" \
  '[
    {name:"Unit Tests",        status:$us, tests:$u},
    {name:"Direct Action Tests",status:$as, tests:$a},
    {name:"Runtime Environment Tests", status:$rts, tests:$rt},
    {name:"Remote Mode Tests", status:$rs, tests:$r},
    {name:"Discover Mode Tests",status:$ds, tests:$d},
    {name:"Combination Tests", status:$cs, tests:$co},
    {name:"Edge & Adversarial", status:$es, tests:$ed},
    {name:"Top-level Workflow Tests", status:$ws, tests:$wf},
    {name:"SCN Detector Tests",status:$ss, tests:$sc},
    {name:"Happy Path (I1)",            status:$i1s,tests:[$ig[0]]},
    {name:"No Hardcoded URLs (I2)",     status:$i2s,tests:[$ig[1]]},
    {name:"Config-Driven Scan (I3)",    status:$i3s,tests:[$ig[2]]},
    {name:"Dispatch Targets (I4)",      status:$i4s,tests:[$ig[3]]},
    {name:"Infrastructure Scan (I5)",   status:$i5s,tests:[$ig[4]]},
    {name:"No Duplicate Tests (I6)",    status:$i6s,tests:[$ig[5]]}
  ]
  # Indexing a short REGRESSION_JSON yields nulls, which reach the browser as
  # `null` entries and throw on the first property access -- the whole board
  # goes blank. Drop them here: a regression row that did not report should
  # make its category empty, not take the page down.
  | map(.tests |= map(select(. != null)))')

# ---------- test catalog (every test the suite DEFINES, not just what ran) ----
# The run results only contain categories that executed, so on a push (where
# scope=all skips the SCN tests) those 25 tests would vanish from search and the
# page would answer "not tested" about something that is. The catalog is parsed
# straight from the workflow definitions so search is complete regardless of
# scope; run status is layered on top of it in the browser.
WF_DIR="$SCRIPT_DIR/../workflows"

category_for() {
  case "$1" in
    test-unit)            echo "Unit Tests" ;;
    test-actions-direct)  echo "Direct Action Tests" ;;
    test-runtime-env)     echo "Runtime Environment Tests" ;;
    test-remote)          echo "Remote Mode Tests" ;;
    test-discover)        echo "Discover Mode Tests" ;;
    test-combination)     echo "Combination Tests" ;;
    test-edge)            echo "Edge & Adversarial" ;;
    test-workflows)       echo "Top-level Workflow Tests" ;;
    test-scn-detector)    echo "SCN Detector Tests" ;;
    test-suite)           echo "Regression Tests" ;;
    *)                    echo "Other" ;;
  esac
}

# Which scope has to be dispatched for a category to run, so the page can say
# WHY a test shows as not run rather than leaving it looking broken.
scope_for() {
  case "$1" in
    test-scn-detector) echo "scn" ;;
    *)                 echo "all" ;;
  esac
}

CATALOG_JSON='[]'
for wf in test-unit test-actions-direct test-runtime-env test-remote test-discover test-combination test-edge test-workflows test-scn-detector test-suite; do
  f="$WF_DIR/$wf.yml"
  [ -f "$f" ] || continue

  # Two collect-step shapes exist, and only one was ever parsed here.
  #
  # (a) an inline jq array literal  -- test-unit, test-actions-direct,
  #     test-runtime-env, test-suite
  # (b) a /tmp/detail.json heredoc  -- test-remote, test-discover,
  #     test-combination, test-edge, test-workflows
  #
  # Shape (b) yielded an empty `part`, which was then passed to
  # `jq --argjson p ""` -- invalid JSON, non-zero exit, and under `set -e` the
  # whole script died. That is why "Generate dashboard" has been failing on
  # every dev run and the published site has no index.html. Five of the nine
  # categories, and the 42 tests in them, were also missing from the search
  # corpus, so the page would have answered "not tested" about things that are.
  part=$(sed -n "/^ *'\[$/,/^ *\]')$/p" "$f" \
    | sed -e "s/^ *'\[$/[/" -e "s/^ *\]')$/]/" \
    | sed -E 's/:\$[a-z0-9_]+/:null/g' \
    | jq -c --arg cat "$(category_for "$wf")" --arg file ".github/workflows/$wf.yml" \
           --arg scope "$(scope_for "$wf")" \
        '[.[] | {id, name, question: .detail, category: $cat, file: $file, scope: $scope}]' 2>/dev/null) || part=""

  # Shape (b): the heredoc maps id -> [name, question]. Dedent it and read it
  # as the object it already is.
  if [ -z "$part" ] || [ "$part" = "[]" ]; then
    part=$(awk "/cat > \/tmp\/detail.json <<'JSON'/{f=1;next} f&&/^ *JSON$/{exit} f" "$f" \
      | sed -E 's/^ {10}//' \
      | jq -c --arg cat "$(category_for "$wf")" --arg file ".github/workflows/$wf.yml" \
             --arg scope "$(scope_for "$wf")" \
          'to_entries | [.[] | {id: .key, name: .value[0], question: .value[1],
                                category: $cat, file: $file, scope: $scope}]' 2>/dev/null) || part=""
  fi

  # Never hand an empty string to --argjson. A category that cannot be parsed
  # must degrade to "no catalog entries", not take the whole board down.
  [ -n "$part" ] || part='[]'

  # Line number of each test's job definition, so a row links to the source that
  # defines it instead of repeating the same run URL on every row. Job names look
  # like `name: "R6: fail on critical"`; take the last match per id so E1 lands on
  # the scan job rather than its digest-resolving helper.
  locs=$(grep -nE '^ *name: "[A-Z]+[0-9]+[a-z]?:' "$f" 2>/dev/null \
    | sed -E 's/^([0-9]+): *name: "([A-Z]+[0-9]+)[a-z]?:.*/{"id":"\2","line":\1}/' \
    | jq -s -c 'group_by(.id) | map(max_by(.line))' 2>/dev/null) || locs='[]'
  [ -n "$locs" ] || locs='[]'
  part=$(jq -c -n --argjson p "$part" --argjson l "$locs" \
    '($l | map({(.id): .line}) | add // {}) as $m | $p | map(. + {line: ($m[.id] // null)})')
  if [ -n "$part" ]; then
    CATALOG_JSON=$(jq -c -n --argjson a "$CATALOG_JSON" --argjson b "$part" '$a + $b')
  else
    echo "WARNING: could not parse a test catalog out of $wf.yml"
  fi
done
echo "Test catalog entries: $(echo "$CATALOG_JSON" | jq 'length')"


# ---------- history ----------
# Written here, not earlier: DEFINED is the catalog count, so this has to
# run after the catalog exists.
# DEFINED is the catalog count -- every test the suite declares, including the
# ones that did not run. It is the denominator the board divides by, and it is
# NOT the same as TOTAL (results actually reported). Persisting both, plus the
# worst failing class, is what stops the root index, the branch hub and the
# dashboard from each deriving a slightly different headline from the same run
# and disagreeing in public.
DEFINED=$(echo "$CATALOG_JSON" | jq 'length')
[ "$DEFINED" -gt 0 ] 2>/dev/null || DEFINED="$TOTAL"
# THE pass rate: passed / defined, rounded down, everywhere. There were three
# -- passed/defined on the headline, passed/(total - skipped) on the trend
# line, passed/(passed + failed) for "vs last run" -- and they disagreed
# whenever a test did not run. A test that did not run was not verified, so it
# counts against; rounding down means the figure never overstates.
PCT_DEFINED=$(( DEFINED > 0 ? PASSED * 100 / DEFINED : 0 ))
PASS_RATE=$PCT_DEFINED
WORST=$(jq -n -r --argjson all "$ALL_JSON" --argjson fc "${CLASSES_JSON:-null}" '
  ($fc // {}) as $f
  | (($f.weights) // {open:10, closed:3, auxiliary:1}) as $w
  | (($f.default) // "closed") as $dflt
  | (($f.classes) // {} | to_entries | map(.value[] as $id | {key:$id, value:.key}) | from_entries) as $cls
  | [$all[] | select(.status == "FAIL") | (((.class // "") as $c | if ($w | has($c)) then $c else ($cls[.id] // $dflt) end))] as $fc2
  | ($w | to_entries | sort_by(-.value) | map(.key))
  | map(select(. as $c | $fc2 | index($c))) | first // "none"')
echo "Defined: $DEFINED   passing: $PASSED ($PCT_DEFINED%)   worst class: $WORST"

CURRENT_RUN=$(jq -n -c \
  --argjson risk "$RISK" \
  --argjson defined "$DEFINED" \
  --argjson pct_defined "$PCT_DEFINED" \
  --arg worst "$WORST" \
  --arg date "$DATE_STR" \
  --arg scope "$SCOPE" \
  --arg branch "${BRANCH_NAME:-}" \
  --arg self_sha "${SELF_SHA:-}" \
  --arg self_repo "${REPO:-}" \
  --argjson passed "$PASSED" \
  --argjson total "$TOTAL" \
  --argjson rate "$PASS_RATE" \
  --arg verdict "$VERDICT" \
  --arg url "$RUN_URL" \
  --arg run_id "$RUN_ID" \
  '{date:$date, scope:$scope, branch:$branch, self_sha:$self_sha, self_repo:$self_repo,
    passed:$passed, total:$total, defined:$defined,
    rate:$rate, pct_defined:$pct_defined, risk:$risk, worst:$worst,
    verdict:$verdict, url:$url, run_id:$run_id}')

# Append and cap at 20
jq -c --argjson run "$CURRENT_RUN" '. + [$run] | .[-20:]' "$HISTORY_FILE" > "$HISTORY_FILE.tmp"
mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"


# ---------- coverage gaps (searchable "is this tested?" corpus) ----------
GAPS_FILE="$SCRIPT_DIR/../data/coverage-gaps.json"
if [ -f "$GAPS_FILE" ] && jq empty "$GAPS_FILE" 2>/dev/null; then
  # The file was a bare array; it now carries _comment and _retired alongside
  # a .gaps array. Accept both so an older checkout of the data file still
  # renders rather than silently showing no gaps -- "nothing listed" and "no
  # gaps" look identical on the page, which is the confusion this list exists
  # to prevent.
  GAPS_JSON=$(jq -c 'if type == "array" then . else (.gaps // []) end' "$GAPS_FILE")
  RETIRED_JSON=$(jq -c 'if type == "array" then [] else (._retired // []) end' "$GAPS_FILE")
  echo "Coverage gaps loaded: $(echo "$GAPS_JSON" | jq 'length') (retired: $(echo "$RETIRED_JSON" | jq 'length'))"
else
  GAPS_JSON='[]'
  RETIRED_JSON='[]'
  echo "WARNING: no readable $GAPS_FILE — search will not be able to answer 'not covered'"
fi

# ---------- ref liveness (which half of a branch run is actually the branch) --
# Written by audit-ref-liveness.sh earlier in the job. Absent is not the same
# as "everything is live", so a missing file renders as unknown.
LIVENESS_FILE="${LIVENESS_FILE:-$OUT/ref-liveness.json}"
if [ -f "$LIVENESS_FILE" ] && jq empty "$LIVENESS_FILE" 2>/dev/null; then
  LIVENESS_JSON=$(jq -c '.' "$LIVENESS_FILE")
  echo "Ref liveness loaded: sdk_live=$(jq -r '.summary.sdk_live' "$LIVENESS_FILE")"
else
  LIVENESS_JSON='null'
  echo "No ref-liveness.json -- this page will not claim anything about which parts of the ref are live"
fi

HISTORY_DATA=$(cat "$HISTORY_FILE")

# ---------- generate HTML ----------
cat > "$OUT/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Argus Test Suite</title>
<link rel="icon" type="image/png" href="__UP__favicon.png">
<link rel="apple-touch-icon" href="__UP__favicon.png">
<style>
/* Bootswatch Lux-flavoured: Nunito Sans, near-black primary, hairline borders,
   square corners, uppercase letter-spaced labels, generous whitespace.
   Hand-written rather than pulling Bootstrap + Lux (≈250KB) so the page stays a
   single self-contained file; only the typeface is fetched. */
@import url('https://fonts.googleapis.com/css2?family=Nunito+Sans:ital,wght@0,300;0,400;0,600;0,700&display=swap');
__NAV_CSS__
:root {
  --bg: #ffffff; --surface: #ffffff; --surface2: #f8f9fa;
  --fg: #1a1a1a; --fg2: #55595c; --fg3: #919aa1;
  --border: #dee2e6; --rule: #ebedef;
  --primary: #1a1a1a;
  --pass: #4bbf73; --pass-bg: #edf9f1; --pass-ink: #2f8f52;
  --fail: #d9534f; --fail-bg: #fdefee; --fail-ink: #b8413d;
  --warn: #f0ad4e; --warn-bg: #fef7ec; --warn-ink: #a3701f;
  --idle: #919aa1; --idle-bg: #f3f5f6;
  --accent: #1a1a1a;
  --radius: 0px;
  --track: 0.08em;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
  /* Night: Lux's geometry and typography, but ink on charcoal rather than a
     mechanical inversion. Warm ivory text on a cool near-black, hairline rules
     that sit just above the background, and semantic hues pulled down in
     saturation so they read as accents rather than alerts. */
  --bg: #101214; --surface: #16191c; --surface2: #1b1f23;
  --fg: #ece9e4; --fg2: #a7adb3; --fg3: #737b82;
  --border: #282d32; --rule: #1f2429;
  --primary: #ece9e4;
  --pass: #5cbf82; --pass-bg: #14241a; --pass-ink: #7fd49f;
  --fail: #e06c69; --fail-bg: #281618; --fail-ink: #ef918e;
  --warn: #e3ad63; --warn-bg: #261e13; --warn-ink: #e8c48c;
  --idle: #737b82; --idle-bg: #1b1f23;
  --accent: #ece9e4;
  }
}
:root[data-theme="dark"] {
  /* Night: Lux's geometry and typography, but ink on charcoal rather than a
     mechanical inversion. Warm ivory text on a cool near-black, hairline rules
     that sit just above the background, and semantic hues pulled down in
     saturation so they read as accents rather than alerts. */
  --bg: #101214; --surface: #16191c; --surface2: #1b1f23;
  --fg: #ece9e4; --fg2: #a7adb3; --fg3: #737b82;
  --border: #282d32; --rule: #1f2429;
  --primary: #ece9e4;
  --pass: #5cbf82; --pass-bg: #14241a; --pass-ink: #7fd49f;
  --fail: #e06c69; --fail-bg: #281618; --fail-ink: #ef918e;
  --warn: #e3ad63; --warn-bg: #261e13; --warn-ink: #e8c48c;
  --idle: #737b82; --idle-bg: #1b1f23;
  --accent: #ece9e4;
}
}
*, *::before, *::after { box-sizing: border-box; }
body {
  font-family: 'Nunito Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
  background: var(--bg); color: var(--fg2); margin: 0;
  font-size: 15px; font-weight: 400; line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}
.container { max-width: 1160px; margin: 0 auto; padding: 36px 28px 72px; }
a { color: var(--primary); text-decoration: none; border-bottom: 1px solid var(--border); }
a:hover { border-bottom-color: var(--primary); }
.mono { font-family: ui-monospace, 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace; font-size: 0.92em; }

/* Lux signature: small, uppercase, widely tracked labels */
.lbl { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.7rem; color: var(--fg3); }

/* Argus's eye beside the title. Grayscaled deliberately: it is a mark, not a
   status light, and the page already spends colour on severity -- a green eye
   next to a red risk number competes with the one signal that should carry it.
   The source is the same 32x32 PNG used as the favicon, so nothing extra is
   fetched. Slightly darkened in light mode: the green grayscales to about
   #a1a1a1, which sits well on near-black but is weak on white.
   aria-hidden because the title beside it already says the name. */
.eye { height: 1.2em; width: auto; vertical-align: -0.2em; margin-right: 0.55em;
       filter: grayscale(1) brightness(0.72); }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) .eye { filter: grayscale(1) brightness(1.05); }
}
:root[data-theme="dark"] .eye { filter: grayscale(1) brightness(1.05); }
:root[data-theme="light"] .eye { filter: grayscale(1) brightness(0.72); }

.head-meta { margin-left: auto; font-size: 0.78rem; color: var(--fg3); display: flex; gap: 12px; flex-wrap: wrap; align-items: baseline; }
.head-meta .sep { color: var(--border); }
.head-meta a { border-bottom: 0; }
.head-meta a:hover { border-bottom: 1px solid var(--primary); }

.card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); }

/* One card, read top to bottom: what happened, then how it is trending. The
   two plots are equal halves so neither reads as the primary. An earlier
   two-column split left the narrative column almost empty beside a tall
   chart column. */
.hero { margin-bottom: 14px; }
/* Plots first, then what they are about: the charts carry the measurement, the
   strip beneath names the failures behind it. */
.plot-foot {
  padding: 14px 24px 16px; display: flex; align-items: baseline; min-width: 0;
  justify-content: space-between; gap: 10px 16px; flex-wrap: wrap;
  border-top: 1px solid var(--border);
}
.plot-foot .rate { flex: 1 1 220px; }
#rate-break { font-size: 0.82rem; color: var(--fg3); }
#rate-break b { color: var(--fg2); font-weight: 600; }
/* Heads on row 1, charts on row 2, both spanning the same grid. Each row is
   sized once for the whole row, so the two x axes share a baseline even if one
   head wraps to a second line. */
.hero-plots { display: grid; grid-template-columns: 1fr 1fr; grid-auto-rows: min-content; }
.plot-head { padding: 20px 24px 0; min-width: 0; align-self: end; }
.plot-body { padding: 6px 24px 18px; min-width: 0; }
.col2 { border-left: 1px solid var(--border); }
@media (max-width: 760px) {
  .hero-plots { grid-template-columns: 1fr; }
  .col2 { border-left: 0; }
  .plot-head.col2 { border-top: 1px solid var(--border); padding-top: 18px; }
  /* One column: each chart directly under its own title. In source order both
     heads come first (they share a row on desktop), which on a phone put
     "Risk index" and "Pass rate" together above two unlabelled charts. */
  .hero-plots > :nth-child(1) { order: 1; }
  .hero-plots > :nth-child(3) { order: 2; }
  .hero-plots > :nth-child(5) { order: 3; }
  .hero-plots > :nth-child(2) { order: 4; }
  .hero-plots > :nth-child(4) { order: 5; }
  .hero-plots > :nth-child(6) { order: 6; }
}
.badge {
  font-size: 2.1rem; font-weight: 700; line-height: 1; padding: 12px 20px;
  border-radius: var(--radius); font-variant-numeric: tabular-nums; border: 1px solid transparent;
}
.badge { font-size: 1.15rem; letter-spacing: 0.1em; }
.badge.v-good { background: var(--pass-bg); color: var(--pass-ink); border-color: var(--pass); }
.badge.v-bad  { background: var(--fail-bg); color: var(--fail-ink); border-color: var(--fail); }
.badge.v-warn { background: var(--warn-bg); color: var(--warn-ink); border-color: var(--warn); }
.statline { font-size: 0.82rem; color: var(--fg2); font-weight: 600; max-width: 62ch; }
details.working .dir {
  font-weight: 400; text-transform: none; letter-spacing: 0; color: var(--fg3);
}
.gloss { margin: 4px 0 12px; }
.gl { font-size: 0.72rem; color: var(--fg3); line-height: 1.6; margin-bottom: 5px; max-width: 62ch; }
.gl b { color: var(--fg2); text-transform: uppercase; letter-spacing: var(--track); font-size: 0.64rem; margin-right: 5px; }
.rate .risk { font-size: 2.2rem; font-weight: 300; line-height: 1; letter-spacing: -0.02em; }
table.weights th {
  position: static; background: transparent; border-bottom: 1px solid var(--border);
  padding: 4px 12px 4px 0; font-size: 0.6rem; color: var(--fg3);
}
table.weights td { padding: 4px 12px 4px 0; border-bottom: 1px solid var(--rule); font-size: 0.74rem; }
table.weights tr.idle td { color: var(--fg3); }
table.weights td.wc { text-transform: uppercase; letter-spacing: var(--track); font-weight: 700; font-size: 0.64rem; }
table.weights tr.live td.wc { color: var(--fg); }
table.weights td.ww, table.weights td.wn, table.weights td.wt {
  font-family: ui-monospace, 'SFMono-Regular', Consolas, monospace; text-align: right;
}
/* Each contribution takes its own class colour, and the total takes the same
   tone as the risk number heading the plot, so the two 24s are visibly the
   same figure rather than two numbers that happen to match. */
table.weights tr.live td.wt { font-weight: 700; }
table.weights tr.fc-open td.wt, table.weights tr.fc-closed td.wt { color: var(--fail-ink); }
table.weights tr.fc-auxiliary td.wt { color: var(--warn-ink); }
table.weights tr.total td.wt.v-bad { color: var(--fail-ink); }
table.weights tr.total td.wt.v-warn { color: var(--warn-ink); }
table.weights tr.total td.wt.v-good { color: var(--pass-ink); }
table.weights td.wd { color: var(--fg3); font-size: 0.7rem; }
table.weights tr.total td { border-bottom: 0; border-top: 1px solid var(--fg3); font-weight: 700; color: var(--fg); }
table.weights tr.total td.wt { font-size: 0.86rem; }
table.weights tr.total td:first-child {
  text-transform: uppercase; letter-spacing: var(--track); font-size: 0.62rem; color: var(--fg2); font-weight: 600;
}
.weights-note { font-size: 0.7rem; color: var(--fg3); line-height: 1.6; max-width: 58ch; }
sup.cite { font-size: 0.58rem; font-weight: 600; margin-left: 3px; letter-spacing: 0; }
a.tref {
  font-family: ui-monospace, 'SFMono-Regular', Consolas, monospace; font-size: 0.94em;
  color: inherit; border-bottom: 1px dotted currentColor;
}
a.tref:hover { border-bottom-style: solid; }
/* the row you landed on marks itself, so a jump into an 87-row table lands
   somewhere you can see */
tr.t:target td { box-shadow: inset 0 2px 0 var(--fg), inset 0 -2px 0 var(--fg); }
tr.t:target td.c-id { font-weight: 700; }
sup.cite a { color: var(--fg3); border-bottom: 0; }
sup.cite a:hover { color: var(--fg); border-bottom: 1px solid var(--fg); }
html { scroll-behavior: smooth; }
/* the jumped-to footnote marks itself, so a long reference list does not leave
   the reader hunting for which line they landed on */
.fn:target { background: var(--warn-bg); box-shadow: -8px 0 0 var(--warn-bg), 8px 0 0 var(--warn-bg); }
.fn:target .fn-n { color: var(--warn-ink); }
a.fn-n { border-bottom: 0; text-decoration: none; }
a.fn-n:hover { border-bottom: 1px solid var(--fg); }
.footnotes { margin-bottom: 14px; }
.fn-head {
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 700;
  font-size: 0.62rem; color: var(--fg2); margin-bottom: 8px;
}
.fn { display: flex; gap: 8px; font-size: 0.7rem; line-height: 1.6; margin-bottom: 7px; max-width: 92ch; }
.fn-n { flex: none; color: var(--fg2); font-weight: 700; font-variant-numeric: tabular-nums; }
.fn a { word-break: break-all; }
.fn-note { display: block; color: var(--fg3); font-style: italic; }
.foot-meta { font-size: 0.7rem; color: var(--fg3); }
.fctag {
  display: inline-block; margin-left: 7px; padding: 1px 6px; border-radius: var(--radius);
  font-size: 0.58rem; font-weight: 700; text-transform: uppercase; letter-spacing: var(--track);
  border: 1px solid currentColor; vertical-align: middle;
}
/* Every failing row is red: colour answers "did it pass", and the tag answers
   "how bad". Tinting by class made colour do both jobs and understated a
   blocks-the-run failure, which still breaks the consumer's pipeline. */
tr.fc-open .fctag, tr.fc-closed .fctag { color: var(--fail-ink); }
tr.fc-auxiliary .fctag { color: var(--warn-ink); }
.cc { font-weight: 700; }
.cc-open, .cc-closed { color: var(--fail-ink); }
.cc-auxiliary { color: var(--warn-ink); }
.dot-sep { color: var(--border); margin: 0 8px; font-weight: 400; }
.classline {
  margin-top: 8px; font-size: 0.72rem; text-transform: uppercase;
  letter-spacing: var(--track);
}
details.working > summary {
  cursor: pointer; font-size: 0.7rem; color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 600;
  padding: 4px 0; list-style: revert;
}
details.working > summary:hover { color: var(--fg); }
details.working > summary b { font-variant-numeric: tabular-nums; }
/* Colour states the direction without needing the words: any risk is red. */
.riskv.bad { color: var(--fail-ink); }
.riskv.good { color: var(--pass-ink); }
.trend-line.muted { stroke: var(--fg3); stroke-width: 1.2; opacity: 0.75; }
details.working[open] > summary { margin-bottom: 8px; }
.refs { margin-top: 8px; display: flex; flex-direction: column; gap: 3px; }
.refs a { font-size: 0.7rem; }
.rate { line-height: 1.5; color: var(--fg); flex: 1 1 340px; min-width: 0; }
.plot-head { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
.delta { white-space: nowrap; }
.stat-name {
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 700;
  font-size: 0.66rem; color: var(--fg3); flex: none;
}
.stat-num {
  font-size: 1.9rem; font-weight: 300; line-height: 1; letter-spacing: -0.02em;
  color: var(--fg); font-variant-numeric: tabular-nums;
}
.stat-num { color: var(--fg2); }          /* neutral unless a tone says otherwise */
.stat-num.v-bad { color: var(--fail-ink); }
.stat-num.v-warn { color: var(--warn-ink); }
.stat-num.v-good { color: var(--pass-ink); }
.stat-sub { font-size: 0.66rem; color: var(--fg3); text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; }
.plot-head .delta { margin-left: auto; }
.bignum .dirnote {
  display: block; font-size: 0.62rem; font-weight: 600; color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track); margin-top: 8px;
}
.delta { font-size: 0.72rem; text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; color: var(--fg3); }
.delta.up { color: var(--pass-ink); } .delta.down { color: var(--fail-ink); }
.stats { display: flex; gap: 8px; flex-wrap: wrap; flex: none; }
.stat {
  display: inline-flex; align-items: baseline; gap: 6px; padding: 6px 12px;
  border-radius: var(--radius); font-size: 0.68rem; font-weight: 600;
  text-transform: uppercase; letter-spacing: var(--track);
  background: transparent; border: 1px solid var(--border); color: var(--fg3);
  cursor: pointer; font-family: inherit; --chip: var(--fg3);
}
.stat.pass { --chip: var(--pass); } .stat.fail { --chip: var(--fail); }
.stat.warn { --chip: var(--warn); } .stat.idle { --chip: var(--idle); }
.stat.info { --chip: var(--fg3); }
.stat b { font-size: 0.95rem; font-weight: 700; color: var(--fg); letter-spacing: 0; }
.stat.pass b { color: var(--pass-ink); } .stat.fail b { color: var(--fail-ink); }
.stat.warn b { color: var(--warn-ink); } .stat.idle b { color: var(--fg2); }
.stat:hover { border-color: var(--chip); color: var(--fg2); }
.stat[aria-pressed="true"] { border-color: var(--chip); box-shadow: inset 0 -2px 0 var(--chip); color: var(--fg); }
#grade-note { font-size: 0.75rem; color: var(--fg3); line-height: 1.6; }
.trend-head { display: flex; justify-content: space-between; align-items: baseline; gap: 10px; margin-bottom: 8px; }
.trend-head > span:first-child { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.68rem; color: var(--fg3); }
.trend-svg { width: 100%; display: block; overflow: visible; }
#risk-trend, #rate-trend { height: 108px; }
.trend-head.second { margin-top: 14px; padding-top: 12px; border-top: 1px solid var(--rule); }
.method { padding: 0; margin: 26px 0 14px; }
.method > summary { cursor: pointer; padding: 14px 22px; font-size: 0.7rem; font-weight: 600;
  text-transform: uppercase; letter-spacing: var(--track); color: var(--fg3); list-style: none; }
.method > summary::-webkit-details-marker { display: none; }
.method > summary::before { content: '\25b8'; display: inline-block; width: 1.1em; }
.method[open] > summary::before { content: '\25be'; }
.method > summary:hover { color: var(--fg); }
.method > #grade-note { padding: 4px 22px 18px; }
.stat-name .info { color: var(--fg3); text-decoration: none; border: none; font-size: 0.95em;
  margin-left: 3px; text-transform: none; }
.stat-name .info:hover { color: var(--fg); }
.statline .sum { display: block; margin-top: 3px; color: var(--fg3); font-weight: 400; }
.statline .sum b { color: var(--fg2); font-weight: 600; }
.method-grid { display: grid; grid-template-columns: minmax(320px, 1.1fr) minmax(260px, 1fr); gap: 28px; align-items: start; }
@media (max-width: 760px) { .method-grid { grid-template-columns: 1fr; gap: 16px; } }
.method-defs { font-size: 0.72rem; color: var(--fg3); line-height: 1.6; }
.method-defs .gl { margin-bottom: 7px; max-width: none; }
.method-defs .caveat {
  margin-top: 12px; padding-top: 10px; border-top: 1px solid var(--rule); color: var(--fg3);
}
.method-defs .caveat b { color: var(--fg2); text-transform: uppercase; letter-spacing: var(--track); font-size: 0.64rem; }
table.weights { width: 100%; max-width: none; border-collapse: collapse; margin: 0; }
.ax-grid { stroke: var(--rule); stroke-width: 1; }
.ax-lbl { font-size: 9px; fill: var(--fg3); font-family: inherit; letter-spacing: 0.04em; }
.pt-lbl { font-size: 9px; font-weight: 600; fill: var(--fg3); font-family: inherit; }
.pt-lbl.last { font-weight: 700; fill: var(--fg); }
.trend-area { fill: var(--fg3); opacity: 0.12; }
.trend-line { fill: none; stroke: var(--fg2); stroke-width: 1.5; }
.trend-dot { fill: var(--fg2); }
.trend-dot.fail { fill: var(--bg); stroke: var(--fg2); stroke-width: 1.4; }
.trend-dot.last { fill: var(--fg); }
.trend-hit { fill: transparent; cursor: pointer; }
.tip {
  position: absolute; background: var(--fg); color: var(--bg); border-radius: var(--radius);
  padding: 8px 11px; font-size: 0.72rem; pointer-events: none; z-index: 50; white-space: nowrap;
}

.search { padding: 18px 20px; margin-bottom: 14px; }
.search:focus-within { border-color: var(--primary); }
.search-row { display: flex; align-items: center; gap: 12px; }
.search-row svg { flex: none; color: var(--fg3); }
.input-wrap { position: relative; flex: 1; display: flex; min-width: 0; }
.ghost {
  position: absolute; inset: 0; display: flex; align-items: center;
  font: inherit; font-size: 0.98rem; font-weight: 400; white-space: pre;
  overflow: hidden; pointer-events: none; padding: 4px 0;
}
.ghost .typed { color: transparent; }
.ghost .rest { color: var(--fg3); }
#q {
  flex: 1; border: 0; background: transparent; color: var(--fg); position: relative;
  font: inherit; font-size: 0.98rem; font-weight: 400; padding: 4px 0; outline: none; min-width: 0;
}
#q::placeholder { color: var(--fg3); font-weight: 300; }
.clear-btn {
  flex: none; background: transparent; border: 0; color: var(--fg3);
  font-family: inherit; font-size: 1.15rem; line-height: 1; cursor: pointer; padding: 0 4px;
}
.clear-btn:hover { color: var(--fg); }
.ghost .tabhint {
  margin-left: 10px; font-size: 0.62rem; font-weight: 600; color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track);
  border: 1px solid var(--border); border-radius: var(--radius); padding: 1px 5px;
}
.kbd {
  font-size: 0.64rem; color: var(--fg3); border: 1px solid var(--border);
  border-radius: var(--radius); padding: 2px 7px; text-transform: uppercase; letter-spacing: var(--track);
}
.verdict { margin-top: 16px; padding: 13px 15px; border-radius: var(--radius); font-size: 0.85rem; display: none; border-left: 3px solid transparent; }
.verdict.show { display: block; }
.verdict b { font-weight: 700; text-transform: uppercase; letter-spacing: var(--track); font-size: 0.74rem; display: block; margin-bottom: 3px; }
.verdict.yes { background: var(--pass-bg); border-left-color: var(--pass); color: var(--pass-ink); }
.verdict.no { background: var(--fail-bg); border-left-color: var(--fail); color: var(--fail-ink); }
.verdict.maybe { background: var(--warn-bg); border-left-color: var(--warn); color: var(--warn-ink); }
.verdict .sub { color: var(--fg2); font-weight: 400; }
.try { margin-top: 14px; display: flex; gap: 8px; flex-wrap: wrap; justify-content: center; }
.try-btn {
  font-family: inherit; font-size: 0.68rem; padding: 5px 11px; border-radius: var(--radius);
  cursor: pointer; background: transparent; border: 1px solid var(--border); color: var(--fg3);
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 600;
}
.try-btn:hover { border-color: var(--primary); color: var(--fg); }

.table-bar { display: flex; align-items: baseline; gap: 12px; margin: 0 0 10px; }
#caption { text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; font-size: 0.68rem; color: var(--fg3); }
table { width: 100%; border-collapse: collapse; }
thead th {
  position: sticky; top: 0; z-index: 10; text-align: left; background: var(--bg);
  border-bottom: 2px solid var(--fg); font-size: 0.66rem; font-weight: 700;
  letter-spacing: var(--track); text-transform: uppercase; color: var(--fg); padding: 11px 12px;
}
tbody td { padding: 12px; border-bottom: 1px solid var(--rule); vertical-align: top; }
tbody tr.t:hover td { background: var(--surface2); }
tr.grp td {
  background: var(--surface2); font-size: 0.66rem; font-weight: 700; color: var(--fg);
  letter-spacing: var(--track); text-transform: uppercase; padding: 9px 12px;
  border-bottom: 1px solid var(--border); border-top: 1px solid var(--border);
}
tr.grp .gcount { float: right; font-weight: 600; color: var(--fg3); }
td.c-st { width: 1%; white-space: nowrap; padding-left: 14px; }
.dot { display: inline-block; width: 9px; height: 9px; border-radius: 50%; vertical-align: middle; }
.dot.pass { background: var(--pass); } .dot.fail { background: var(--fail); }
.dot.skip { background: var(--warn); } .dot.idle { background: var(--idle); }
.dot.gap { background: var(--warn); }
.dot.untested { background: var(--fail); }
.dot.upstream { background: var(--idle); }
td.c-id { width: 1%; white-space: nowrap; font-size: 0.72rem; font-weight: 700; color: var(--fg); letter-spacing: 0.04em; }
td.c-q { font-size: 0.875rem; color: var(--fg); font-weight: 400; }
td.c-q .why { color: var(--fg3); font-size: 0.78rem; margin-top: 5px; line-height: 1.55; font-weight: 300; }
td.c-q .checks { color: var(--fg3); font-size: 0.73rem; margin-top: 6px; line-height: 1.6; font-weight: 300; }
td.c-q .checks.empty-checks { color: var(--fail-ink); }
td.c-q .checks .n, td.c-q .checks .bad, td.c-q .checks .dim {
  text-transform: uppercase; letter-spacing: var(--track); font-weight: 700;
  font-size: 0.64rem; margin-right: 8px;
}
td.c-q .checks .n { color: var(--fg2); }
td.c-q .checks .bad { color: var(--fail-ink); }
td.c-q .checks .dim { color: var(--fg3); }
td.c-q .checks .failed-names { color: var(--fail-ink); margin-top: 3px; font-weight: 400; }
td.c-q .checks .all-checks { margin-top: 3px; }
td.c-cat { width: 1%; white-space: nowrap; font-size: 0.68rem; color: var(--fg3); text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; }
td.c-lnk { width: 1%; white-space: nowrap; text-align: right; font-size: 0.68rem; text-transform: uppercase; letter-spacing: var(--track); font-weight: 600; }
td.c-lnk a { margin-left: 10px; border-bottom: 0; color: var(--fg3); }
td.c-lnk a:hover { color: var(--fg); border-bottom: 1px solid var(--fg); }
tr.t.fc-open td, tr.t.fc-closed td { background: var(--fail-bg); }
tr.t.fc-open td.c-st, tr.t.fc-closed td.c-st { box-shadow: inset 3px 0 0 var(--fail); }
tr.t.fc-auxiliary td { background: var(--warn-bg); }
tr.t.fc-auxiliary td.c-st { box-shadow: inset 3px 0 0 var(--warn); }
tr.hidden { display: none; }
mark { background: rgba(240,173,78,0.28); color: inherit; padding: 0 2px; }
.empty { padding: 44px 12px; text-align: center; color: var(--fg3); font-size: 0.85rem; }
.none { color: var(--fg3); }
.chip { display:inline-block; padding:1px 7px; border:1px solid var(--border); font-size:0.68rem;
        font-weight:600; letter-spacing:0.04em; text-transform:uppercase; white-space:nowrap; cursor:help; }
.chip-warn { color: var(--warn-ink); background: var(--warn-bg); border-color: var(--warn); }
.chip-ok   { color: var(--pass-ink); background: var(--pass-bg); border-color: var(--pass); }
/* Deep-linking to a row put it under the sticky table header: the browser
   scrolls the anchor to y=0 and the header then sits on top of it. This is
   what scroll-margin-top is for -- no JS, and it fixes keyboard navigation and
   a reload on an existing #hash at the same time. Applied to any element that
   can be a link target. */
tr[id], [id^="ref-"], [id^="cite-"], section[id] { scroll-margin-top: 92px; }
/* A brief tint so the reader can see WHICH row they landed on, since the row
   is no longer at the very top of the viewport. */
:target > td { animation: land 1.4s ease-out 1; }
@keyframes land { from { background: var(--warn-bg); } to { background: transparent; } }
footer { margin-top: 44px; padding-top: 20px; border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--fg3); }

</style>
</head>
<body>
<div class="container">
  <div class="nav" id="nav"></div>
  <div class="pmeta" id="head-meta"></div>

  <section class="card hero">
    <div class="hero-plots">
      <div class="plot-head">
        <span class="stat-name" id="risk-label">Risk index <a class="info" href="#how" title="How the risk index is calculated" aria-label="How the risk index is calculated">&#9432;</a></span>
        <span class="stat-num" id="risk-num"></span>
        <span class="stat-sub" id="risk-sub">lower is better</span>
        <span class="delta" id="risk-delta"></span>
      </div>
      <div class="plot-head col2">
        <span class="stat-name" id="trend-label">Pass rate</span>
        <span class="stat-num" id="rate-num"></span>
        <span class="stat-sub" id="rate-sub"></span>
        <span class="delta" id="delta"></span>
      </div>
      <div class="plot-body"><svg id="risk-trend" class="trend-svg"></svg></div>
      <div class="plot-body col2"><svg id="rate-trend" class="trend-svg"></svg></div>
      <!-- What each number is made of, under its own chart: the verdict and the
           risk arithmetic belong to the risk index, and "not run" moves the
           pass rate, not the risk. -->
      <div class="plot-foot"><span class="rate" id="rate"></span><div class="stats" id="stats"></div></div>
      <div class="plot-foot col2"><span class="rate" id="rate-break"></span><div class="stats" id="stats2"></div></div>
    </div>
  </section>

  <section class="card search">
    <div class="search-row">
      <svg width="15" height="15" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M10.68 11.74a6 6 0 01-7.922-8.982 6 6 0 018.982 7.922l3.04 3.04a.749.749 0 01-.326 1.275.749.749 0 01-.734-.215zM11.5 7a4.5 4.5 0 10-9 0 4.5 4.5 0 009 0"/></svg>
      <span class="input-wrap">
        <span class="ghost" id="ghost" aria-hidden="true"></span>
        <input id="q" type="text" autocomplete="off" autocorrect="off" spellcheck="false"
               placeholder="Is this behaviour tested?">
      </span>
      <button class="clear-btn" id="clear" type="button" title="Clear search and filters" hidden>&times;</button>
      <span class="kbd" id="kbd">/</span>
    </div>
    <div id="verdict" class="verdict"></div>
  </section>

  <div class="table-bar"><span id="caption"></span></div>
  <table>
    <thead><tr>
      <th class="c-st"></th><th>ID</th><th>What it checks</th><th>Category</th><th style="text-align:right">Definition</th><th style="text-align:right">Logs</th>
    </tr></thead>
    <tbody id="rows"></tbody>
  </table>
  <div class="empty" id="empty" style="display:none"></div>

  <!-- Reference material, so it sits after the tests rather than between the
       headline and them. Collapsed, but one click from the number it explains
       (the info mark beside "Risk index" opens it). -->
  <details class="card method" id="how">
    <summary>How the risk index is calculated</summary>
    <div id="grade-note"></div>
  </details>

  <footer id="foot"></footer>
</div>
<div class="tip" id="tip" style="display:none"></div>
<script>
HTMLEOF

# Inject the data as JS variables
{
  echo "const DATA = {"
  echo "  verdict: \"$VERDICT\","
  echo "  date: \"$DATE_STR\","
  echo "  scope: \"$SCOPE\","
  echo "  passed: $PASSED,"
  echo "  failed: $FAILED,"
  echo "  skipped: $SKIPPED,"
  echo "  total: $TOTAL,"
  echo "  passRate: $PASS_RATE,"
  echo "  runUrl: \"$RUN_URL\","
  echo "  repo: \"$REPO\","
  echo "  argusRepo: \"${ARGUS_REPO:-}\","
  echo "  argusRef: \"${ARGUS_REF:-}\","
  echo "  argusSha: \"${ARGUS_SHA:-}\","
  echo "  argusShaShort: \"${ARGUS_SHA_SHORT:-}\","
  echo "  argusVersion: \"${ARGUS_VERSION:-}\","
  echo "  selfSha: \"${SELF_SHA:-main}\","
  printf '  categories: %s,\n' "$CATEGORIES"
  printf '  gaps: %s,\n' "$GAPS_JSON"
  printf '  retiredGaps: %s,\n' "$RETIRED_JSON"
  printf '  liveness: %s,\n' "$LIVENESS_JSON"
  printf '  failureClasses: %s,\n' "$CLASSES_JSON"
  printf '  catalog: %s,\n' "$CATALOG_JSON"
  printf '  jobs: %s,\n' "${JOBS_JSON:-[]}"
  printf '  branches: %s,\n' "${BRANCHES_JSON:-[]}"
  echo "  branchName: \"${BRANCH_NAME:-}\","
  echo "  branchSlug: \"${BRANCH_SLUG:-}\","
  printf '  history: %s\n' "$HISTORY_DATA"
  echo "};"
} >> "$OUT/index.html"

cat >> "$OUT/index.html" << 'HTMLEOF2'

__NAV_JS__
(function () {
  const d = DATA;
  const server = d.runUrl.split('/').slice(0, 3).join('/');
  // The argus version under test: the release when the ref is main, the ref
  // otherwise, and always the exact commit -- the link cannot move.
  const aSha = d.argusSha && d.argusSha !== 'unknown' ? String(d.argusSha).slice(0, 7) : '';
  const onMain = (d.argusRef || 'main') === 'main';
  const aHref = d.argusRepo ? server + '/' + d.argusRepo +
                (aSha ? '/commit/' + d.argusSha : '/tree/' + (d.argusRef || 'main')) : '';
  renderNav({ el: 'nav', branch: d.branchName || d.branchSlug || 'branch',
              slug: d.branchSlug || d.branchName, sha: d.selfSha, page: 'tests',
              branches: d.branches || [], up: '../',
              argus: d.argusRepo ? { version: onMain && d.argusVersion ? 'v' + d.argusVersion
                                                    : (d.argusRef || 'main'),
                                     sha: aSha, href: aHref } : null,
              run: { date: d.date, href: d.runUrl } });
  const repoUrl = server + '/' + d.repo;
  const srcBase = repoUrl + '/blob/' + (d.selfSha || 'main') + '/';

  const EXAMPLES = ['block the build when a critical CVE is found',
    'scan an image pinned by digest', 'SBOM only, no vulnerability gate',
    'private registry credentials', 'detect secrets in a repo',
    'post a comment on a pull request'];

  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"]/g, function (m) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[m];
    });
  }
  const $ = function (id) { return document.getElementById(id); };

  // ---------------------------------------------------------------- header
  var meta = [];
  // The run's metadata line under the nav; renderHeader lives in site-nav.sh.
  renderHeader({
    metaEl: 'head-meta', up: '__UP__',
    selfRepo: d.repo, selfSha: d.selfSha,
    argusRepo: d.argusRepo, argusRef: d.argusRef,
    argusSha: d.argusSha, argusVersion: d.argusVersion,
    liveness: d.liveness, date: d.date, scope: d.scope, runUrl: d.runUrl
  });

  // ---------------------------------------------------------------- corpus
  const ran = {};
  d.categories.forEach(function (cat) {
    cat.tests.forEach(function (t) {
      // reason and class ride along: the row below reads r.reason, which was
      // never copied here, so a skip's explanation never reached the board.
      ran[t.id] = { status: t.status, category: cat.name, detail: t.detail,
                    checks: t.checks, stats: t.stats, reason: t.reason, cls: t.class };
    });
  });
  const docs = [];
  const seen = {};
  (d.catalog || []).forEach(function (c) {
    const r = ran[c.id];
    seen[c.id] = true;
    docs.push({
      kind: 'test', id: c.id, name: c.name,
      question: (r && r.detail) || c.question || '',
      status: r ? r.status : 'notrun',
      reason: r ? (r.reason || '') : '',
      failclass: r ? (r.cls || '') : '',
      category: c.category || (r && r.category),
      file: c.file || '', line: c.line || null, why: '', scope: c.scope || 'all',
      checks: (r && r.checks) || c.checks || null,
      stats: (r && r.stats) || null
    });
  });
  d.categories.forEach(function (cat) {
    cat.tests.forEach(function (t) {
      if (seen[t.id]) return;
      docs.push({
        kind: 'test', id: t.id, name: t.name, question: t.detail || '', failclass: t.class || '',
        status: t.status, category: cat.name, file: '', line: null, why: '',
        checks: t.checks || null, stats: t.stats || null
      });
    });
  });
  // One coverage section only. "Tested by argus itself" was dropped: this suite
  // should take no credit for coverage argus's own CI provides, and that list
  // had no natural boundary. Each remaining gap is tracked as an issue.
  const KIND_CAT = { gap: 'Known gaps, tracked as issues' };
  const KIND_ORDER = { untested: 0, gap: 1, upstream: 2 };
  (d.gaps || []).slice().sort(function (a, b) {
    return (KIND_ORDER[a.kind] == null ? 1 : KIND_ORDER[a.kind]) -
           (KIND_ORDER[b.kind] == null ? 1 : KIND_ORDER[b.kind]);
  }).forEach(function (g) {
    const k = KIND_CAT[g.kind] ? g.kind : 'gap';
    docs.push({
      kind: k, id: g.id, name: g.name, question: g.question || '', status: k,
      category: KIND_CAT[k], file: '', line: null,
      why: g.why || '', ref: g.ref || '', issue: g.issue || null
    });
  });

  // GitHub gives no per-test URL, but each test is a job, and job names carry
  // the test id ("Remote Mode Tests / R6: fail on critical / ..."). Mapping them
  // makes the Logs column land on the job instead of repeating the run URL.
  // Best-effort: if the jobs API was unavailable, rows fall back to the run.
  const jobUrl = {};
  // A single test spawns several jobs -- discover, scan, summary -- and the
  // first one encountered is often a SKIPPED job whose log is empty. Rank the
  // candidates so a failed job wins, then a job that ran, and only then a
  // skipped one, and deep-link to the failing step rather than the job top.
  const JOB_RANK = { failure: 3, success: 2, cancelled: 1 };
  (d.jobs || []).forEach(function (j) {
    const m = String(j.name || '').match(/(?:^|\/)\s*([A-Z]+\d+[a-z]?)\s*:/);
    if (!m) return;
    const id = m[1];
    const rank = JOB_RANK[j.conclusion] || 0;
    const cur = jobUrl[id];
    if (cur && rank <= cur.rank) return;
    jobUrl[id] = {
      rank: rank,
      url: j.url + (j.conclusion === 'failure' && j.failedStep ? '#step:' + j.failedStep + ':1' : '')
    };
  });

  const tests = docs.filter(function (x) { return x.kind === 'test'; });
  const nGapReal = docs.filter(function (x) { return x.kind === 'gap'; }).length;
  const nUntested = docs.filter(function (x) { return x.kind === 'untested'; }).length;
  const nUpstream = docs.filter(function (x) { return x.kind === 'upstream'; }).length;
  const nPass = tests.filter(function (x) { return x.status === 'pass'; }).length;
  const nFail = tests.filter(function (x) { return x.status === 'FAIL'; }).length;
  const nIdle = tests.filter(function (x) { return x.status === 'notrun' || x.status === 'skip' || x.status === 'cancel'; }).length;


  // ------------------------------------------------------------------ hero
  // The one pass rate: passed / defined, rounded down -- the same figure the
  // generator stores as pct_defined and the index shows. histPct reads it from
  // a history entry; entries written before it existed fall back to `rate`.
  function histPct(p) { return p.pct_defined != null ? p.pct_defined : p.rate; }
  const rate = tests.length ? Math.floor((nPass / tests.length) * 100) : 0;

  // ---- verdict + risk ------------------------------------------------------
  // Binary verdict, because a contract suite is a conformance oracle: an
  // assertion holds or it does not, and averaging them implies a partial-credit
  // semantics that does not exist. Alongside it, an ABSOLUTE risk score rather
  // than a percentage -- a pass rate can be raised by writing more easy tests,
  // while a risk total can only be lowered by fixing something.
  //
  //     Verdict = PASS iff failures = 0
  //     Risk    = sum of weights over failing tests
  //
  // Weights come from .github/data/failure-classes.json and rank a control that
  // fails OPEN above one that fails CLOSED, because only the first lies to you.
  const FC = d.failureClasses || null;
  const W = (FC && FC.weights) || { open: 10, closed: 3, auxiliary: 1 };
  const CLASS_OF = {};
  if (FC && FC.classes) {
    Object.keys(FC.classes).forEach(function (k) {
      (FC.classes[k] || []).forEach(function (id) { CLASS_OF[id] = k; });
    });
  }
  const DEFAULT_CLASS = (FC && FC.default) || 'closed';
  // A test that can fail more than one way reports which (N3, N5); that wins
  // over the fixed class in failure-classes.json, which cannot know.
  function failClass(x) {
    return (x.failclass && W[x.failclass] != null) ? x.failclass : (CLASS_OF[x.id] || DEFAULT_CLASS);
  }

  const failing = tests.filter(function (x) { return x.status === 'FAIL'; });
  const byClass = {};
  Object.keys(W).forEach(function (k) { byClass[k] = []; });
  failing.forEach(function (x) {
    const c = failClass(x);
    (byClass[c] = byClass[c] || []).push(x);
  });
  var risk = 0;
  Object.keys(byClass).forEach(function (c) { risk += (W[c] || 0) * byClass[c].length; });

  // Severity order is DERIVED from the weights, descending, so a class added
  // or renamed in failure-classes.json cannot be left unranked here. It was a
  // hardcoded ['open','closed','degraded'] until 'auxiliary' was added, at
  // which point a run whose only failures were auxiliary computed worst='none'
  // and the board reported PASS with tests failing -- the exact silent pass
  // this suite exists to catch, in the thing that reports it.
  const ORDER = Object.keys(W).sort(function (a, b) { return (W[b] || 0) - (W[a] || 0); });
  const LBL = (FC && FC.labels) || { open: 'fail-open',
                                     closed: 'fail-closed',
                                     auxiliary: 'auxiliary breakage' };
  const SHORT = (FC && FC.short) || LBL;
  const GLOSS = (FC && FC.glossary) || {};
  const REFS = (FC && FC.references) || [];
  const IDX = (FC && FC.index) || { name: 'Risk', anchor: '0 = clean' };
  const STATUS = (FC && FC.status) || {
    open: { word: 'FAIL', tone: 'bad', line: 'argus reports success without running the check it was asked for' },
    closed: { word: 'FAIL', tone: 'bad', line: 'argus errors out where it should succeed -- the pipeline stops, nothing gets through' },
    auxiliary: { word: 'FAIL', tone: 'warn', line: 'an auxiliary path is broken; scans and gates still work' },
    none: { word: 'PASS', tone: 'good', line: 'every defined test that ran, passed' }
  };

  // Headline is the WORST CLASS PRESENT, not a total. Lexicographic ordering
  // needs no arithmetic and makes no claim that the classes are commensurable,
  // which a weighted sum silently does. One fail-open is disqualifying for a
  // security gate however many other tests pass.
  const pctPass = rate;
  const worst = ORDER.filter(function (c) { return (byClass[c] || []).length; })[0] || 'none';
  const st = Object.assign({}, STATUS[worst] || STATUS.none);
  // No verdict badge: a non-zero risk already says the run failed, and the
  // sentence below says what failed. A FAIL chip next to a red 24 is the same
  // fact twice.
  // The sentence says what the worst class means, in the glossary's terms;
  // which tests, and what each cost, follows it as the risk arithmetic. (It
  // used to append "N tests report success without scanning. See …" -- which
  // named the tests twice and was not true of N5, which did scan: the wrong
  // architecture.)

  // Risk carries the severity colour because that is what it measures. Pass
  // rate stays neutral: it is a breadth figure, and 95% is neither good nor bad
  // without knowing what the missing 5% is. Green is reserved for 100%, which
  // is the one threshold that is not arbitrary.
  $('risk-num').textContent = risk;
  $('risk-num').className = 'stat-num v-' + (st.tone || 'good');
  // Pass rate never carries colour, including at 100%. It is severity-blind by
  // construction: a silent pass and a broken SARIF upload each cost it one
  // test. Rendering 95% green would say "good" about a state that includes two
  // scans reporting success without scanning, which is the trap the letter
  // grade fell into. Red would just repeat what risk already says. Uncoloured
  // next to a coloured number reads as "I am the scale, that is the signal".
  $('rate-num').textContent = pctPass + '%';
  $('rate-num').className = 'stat-num';
  $('rate-sub').textContent = nPass + '/' + tests.length;
  $('rate-break').innerHTML = '<b>' + nPass + '</b> passed \u00b7 <b>' + nFail + '</b> failed \u00b7 <b>' +
    nIdle + '</b> not run \u2014 all ' + tests.length + ' defined tests count';

  // The index's working, beside the sentence it qualifies: which tests produced
  // the number and what each cost. Named per test while that stays short; past
  // six it is summed per class instead, and the full table is under "How the
  // risk index is calculated".
  var riskCosts = [];
  ORDER.forEach(function (c) {
    (byClass[c] || []).forEach(function (x) { riskCosts.push({ id: x.id, w: W[c] || 0 }); });
  });
  var riskSum = '';
  if (risk > 0) {
    var riskTerms = riskCosts.length <= 6
      ? riskCosts.map(function (f) { return testLink(f.id) + ' (' + f.w + ')'; })
      : ORDER.filter(function (c) { return (byClass[c] || []).length; }).map(function (c) {
          return (byClass[c] || []).length + ' ' + esc(SHORT[c] || LBL[c] || c) + ' \u00d7 ' + (W[c] || 0);
        });
    riskSum = '<span class="sum">risk <b>' + risk + '</b> = ' + riskTerms.join(' + ') + '</span>';
  }
  $('rate').innerHTML = '<div class="statline">' + st.line + riskSum + '</div>';

  // Bracketed markers link to their footnote, and each footnote links back to
  // the marker that cited it. A citation you cannot follow is decoration.
  // Any test id mentioned anywhere on the page links to its row.
  function testLink(id) {
    return '<a class="tref" href="#row-' + esc(id) + '">' + esc(id) + '</a>';
  }
  function testLinks(ids) { return ids.map(testLink).join(', '); }

  function citeMark(ns) {
    return '<sup class="cite">' + ns.map(function (n) {
      return '<a id="cite-' + n + '" href="#ref-' + n + '">[' + n + ']</a>';
    }).join(', ') + '</sup>';
  }

  var rows = '';
  ORDER.forEach(function (c) {
    const n = (byClass[c] || []).length, w = W[c] || 0;
    const ids = testLinks((byClass[c] || []).map(function (x) { return x.id; }));
    rows += '<tr class="' + (n ? 'live fc-' + c : 'idle') + '">' +
      '<td class="wc" title="' + esc(GLOSS[c] || '') + '">' + esc(LBL[c] || c) +
        (c === 'open' ? citeMark([1, 2]) : '') + '</td>' +
      '<td class="ww">&times;' + w + '</td>' +
      '<td class="wn">' + n + '</td>' +
      '<td class="wt">' + (n * w) + '</td>' +
      '<td class="wd">' + (ids || '&mdash;') + '</td></tr>';
  });
  const glossHtml = ORDER.map(function (c) {
    return '<div class="gl"><b>' + esc(LBL[c] || c) + '</b> ' + esc(GLOSS[c] || '') + '</div>';
  }).join('');

  // Table and definitions side by side, inside the collapsed "How the risk
  // index is calculated" section at the bottom. The working a reader needs day
  // to day -- which tests, what each cost -- is on the strip under the charts;
  // this is the full method, one click from the number via the info mark.
  $('grade-note').innerHTML =
    '<div class="method-grid">' +
    '<div><table class="weights"><thead><tr>' +
      '<th>failure class</th><th>per failure</th><th>n</th><th>weight</th><th>tests</th>' +
    '</tr></thead><tbody>' + rows +
    '<tr class="total"><td colspan="3">risk index = &Sigma; weight</td>' +
    '<td class="wt v-' + (st.tone || 'good') + '">' + risk + '</td><td></td></tr></tbody></table></div>' +
    '<div class="method-defs">' + glossHtml +
      '<div class="caveat"><b>On the index.</b> ' + esc(IDX.caveat || '') +
      ' Each test is itself pass/fail rather than scored' + citeMark([3]) + '.</div>' +
    '</div></div>';

  const hist = d.history || [];
  if (hist.length >= 2) {
    const prev = histPct(hist[hist.length - 2]);
    const diff = rate - prev;
    const el = $('delta');
    el.className = 'delta ' + (diff > 0 ? 'up' : diff < 0 ? 'down' : '');
    el.textContent = diff === 0 ? 'no change vs last run'
      : (diff > 0 ? '\u25b2 +' : '\u25bc ') + diff + ' pts vs last run';
  }

  // One chip per class, in severity order, so a class added to
  // failure-classes.json appears without editing this list.
  const FILTER_KEY = { open: 'fail-open', closed: 'fail-closed' };
  const STAT_DEFS = [{ key: 'not-run', cls: 'idle', label: 'not run', n: nIdle }].concat(
    ORDER.map(function (c) {
      return { key: FILTER_KEY[c] || c,
               cls: (c === 'auxiliary' ? 'warn' : 'fail'),
               label: SHORT[c] || LBL[c] || c,
               gloss: (LBL[c] ? LBL[c] + ' \u2014 ' : '') + (GLOSS[c] || ''),
               n: (byClass[c] || []).length };
    }));
  const statsEl = $('stats'), stats2El = $('stats2');
  STAT_DEFS.forEach(function (s) {
    if (s.n === 0 && s.key !== 'all') return;
    const b = document.createElement('button');
    b.className = 'stat ' + s.cls;
    b.type = 'button';
    b.dataset.filter = s.key;
    b.setAttribute('aria-pressed', s.key === 'all' ? 'true' : 'false');
    // The label alone is a two-word abbreviation of a whole failure class.
    // "scanned less than asked" means nothing without the sentence behind it,
    // so the glossary entry rides along as the tooltip.
    b.title = (s.gloss ? s.gloss + ' ' : '') + '(click to show only these tests)';
    b.innerHTML = '<b>' + s.n + '</b> ' + s.label;
    b.addEventListener('click', function () { toggleFilter(s.key); });
    (s.key === 'not-run' ? stats2El : statsEl).appendChild(b);
  });
  function syncStats(active) {
    Array.prototype.forEach.call([].slice.call(statsEl.children).concat([].slice.call(stats2El.children)), function (b) {
      const k = b.dataset.filter;
      const on = active.indexOf(k) > -1;
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
    });
  }
  // Clicking a chip edits the query text, so the two can never disagree.
  function toggleFilter(key) {
    const cur = parseQuery(input.value);
    var toks;
    if (key === 'all') toks = [];
    else if (cur.filters.indexOf(key) > -1) toks = cur.filters.filter(function (f) { return f !== key; });
    else toks = [key];                     // statuses are exclusive: one at a time
    input.value = (toks.map(function (f) { return 'is:' + f; }).join(' ') + ' ' + cur.text).trim();
    paintGhost();
    onInput();
  }

  // ----------------------------------------------------------------- trend
  const nFailedRuns = hist.filter(function (p) { return p.verdict !== 'PASS'; }).length;

  // Two series: risk first, because it is the severity signal and "going down"
  // reads correctly for it, then pass rate for breadth. Older history entries
  // predate the risk field, so that series plots only the points that have one.
  const riskHist = hist.filter(function (p) { return typeof p.risk === 'number'; });
  // The label keeps its info mark, so only the text node is (re)set.
  $('risk-label').firstChild.nodeValue = 'Risk index ';
  if (riskHist.length >= 2) {
    const rPrev = riskHist[riskHist.length - 2].risk, rNow = riskHist[riskHist.length - 1].risk;
    const rd = rNow - rPrev, el = $('risk-delta');
    el.className = 'delta ' + (rd < 0 ? 'up' : rd > 0 ? 'down' : '');   // down is good here
    el.textContent = rd === 0 ? 'no change' : (rd < 0 ? '\u25bc ' : '\u25b2 +') + rd + ' vs last run';
  }

  function drawSeries(svgId, data, valueOf, opts) {
    const svg = $(svgId), tip = $('tip');
    if (!svg) return;
    if (data.length < 2) {
      svg.innerHTML = '<text x="0" y="30" class="ax-lbl">Not enough runs yet</text>';
      return;
    }
    const box = svg.getBoundingClientRect();
    const W = Math.round(box.width || svg.clientWidth || 340);
    const H = Math.round(box.height || svg.clientHeight || opts.height || 112);
    svg.setAttribute('preserveAspectRatio', 'none');
    const padL = 30, padR = 10, padT = 14, padB = 18;
    const plotW = W - padL - padR, plotH = H - padT - padB;
    svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
    const vals = data.map(valueOf);
    const top = opts.max != null ? opts.max : Math.max(Math.max.apply(null, vals), 1) * 1.15;
    const floor = opts.min != null ? opts.min : 0;
    const xs = function (i) { return padL + (data.length === 1 ? plotW / 2 : i * (plotW / (data.length - 1))); };
    const ys = function (v) { return padT + plotH - ((v - floor) / (top - floor)) * plotH; };
    var g = '';
    (opts.ticks || [floor, top]).forEach(function (v) {
      g += '<line class="ax-grid" x1="' + padL + '" y1="' + ys(v) + '" x2="' + (W - padR) + '" y2="' + ys(v) + '"/>' +
           '<text class="ax-lbl" x="' + (padL - 6) + '" y="' + (ys(v) + 3) + '" text-anchor="end">' + Math.round(v) + '</text>';
    });
    var ticks = data.length > 2 ? [0, Math.floor((data.length - 1) / 2), data.length - 1] : [0, data.length - 1];
    ticks.filter(function (v, i, a) { return a.indexOf(v) === i; }).forEach(function (i) {
      const d0 = String(data[i].date || '').split(' ')[0].slice(5);
      const anchor = i === 0 ? 'start' : (i === data.length - 1 ? 'end' : 'middle');
      g += '<text class="ax-lbl" x="' + xs(i) + '" y="' + (H - 4) + '" text-anchor="' + anchor + '">' + esc(d0) + '</text>';
    });
    var area = 'M' + xs(0) + ',' + (padT + plotH), line = '';
    data.forEach(function (p, i) {
      area += ' L' + xs(i) + ',' + ys(valueOf(p));
      line += (i ? ' L' : 'M') + xs(i) + ',' + ys(valueOf(p));
    });
    area += ' L' + xs(data.length - 1) + ',' + (padT + plotH) + ' Z';
    g += '<path class="trend-area" d="' + area + '"/><path class="trend-line' +
         (opts.muted ? ' muted' : '') + '" d="' + line + '"/>';
    data.forEach(function (p, i) {
      if (p.verdict !== 'PASS') g += '<circle class="trend-dot fail" cx="' + xs(i) + '" cy="' + ys(valueOf(p)) + '" r="2.6"/>';
    });
    const lastI = data.length - 1;
    g += '<circle class="trend-dot last" cx="' + xs(lastI) + '" cy="' + ys(valueOf(data[lastI])) + '" r="3"/>';
    const spacing = plotW / (data.length - 1);
    var labelAt;
    if (spacing >= 30) { labelAt = data.map(function (_, i) { return i; }); }
    else {
      var best = 0, worst = 0;
      data.forEach(function (p, i) {
        if (valueOf(p) > valueOf(data[best])) best = i;
        if (valueOf(p) < valueOf(data[worst])) worst = i;
      });
      labelAt = [0, best, worst, lastI];
    }
    labelAt.filter(function (v, i, a) { return a.indexOf(v) === i; }).forEach(function (i) {
      const v = valueOf(data[i]);
      const anchor = i === 0 ? 'start' : (i === lastI ? 'end' : 'middle');
      const above = ys(v) - 5 > padT + 6;
      g += '<text class="pt-lbl' + (i === lastI ? ' last' : '') + '" x="' + xs(i) +
           '" y="' + (above ? ys(v) - 5 : ys(v) + 11) + '" text-anchor="' + anchor + '">' + v + '</text>';
    });
    const bw = plotW / data.length;
    data.forEach(function (p, i) {
      g += '<rect class="trend-hit" x="' + (xs(i) - bw / 2) + '" y="0" width="' + bw + '" height="' + H + '" data-i="' + i + '"/>';
    });
    svg.innerHTML = g;
    svg.querySelectorAll('.trend-hit').forEach(function (r) {
      r.addEventListener('mouseenter', function (e) {
        const p = data[+r.dataset.i];
        tip.innerHTML = '<b>' + esc(p.date) + '</b><br>' + p.verdict + ' &middot; ' +
          p.passed + '/' + (p.defined != null ? p.defined : p.total) + ' (' + histPct(p) + '%)' +
          (typeof p.risk === 'number' ? '<br>risk ' + p.risk : '');
        tip.style.display = 'block';
        tip.style.left = (e.clientX + window.scrollX + 12) + 'px';
        tip.style.top = (e.clientY + window.scrollY - 52) + 'px';
      });
      r.addEventListener('mouseleave', function () { tip.style.display = 'none'; });
      r.addEventListener('click', function () { window.open(data[+r.dataset.i].url, '_blank'); });
    });
  }

  // A y-axis topping out at an arbitrary max(v)*1.15 produced labels like 66.
  // Round up to a readable step instead, so the gridlines land on numbers a
  // reader can hold in their head.
  function niceMax(v) {
    if (v <= 5) return 5;
    const mag = Math.pow(10, Math.floor(Math.log10(v)));
    return [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].map(function (m) { return m * mag; })
      .filter(function (c) { return c >= v; })[0] || 10 * mag;
  }

  function drawTrend() {
    const top = niceMax(Math.max.apply(null, riskHist.map(function (p) { return p.risk; }).concat([1])));
    drawSeries('risk-trend', riskHist, function (p) { return p.risk; },
               { max: top, ticks: [0, top / 2, top] });
    // Pass rate needs a window, not a zero-based axis: with values in the 80s
    // and 90s, starting at 0 leaves most of the panel empty. The floor is
    // rounded down to a step and LABELLED, so the truncation is visible rather
    // than quietly exaggerating the slope.
    const rates = hist.map(histPct);
    const lo = rates.length ? Math.min.apply(null, rates) : 0;
    const rFloor = Math.max(0, Math.min(90, Math.floor((lo - 2) / 10) * 10));
    drawSeries('rate-trend', hist, histPct,
               { min: rFloor, max: 100,
                 ticks: [rFloor, Math.round((rFloor + 100) / 2), 100], muted: true });
  }


  drawTrend();
  // Redraw when the box actually changes size. Measuring once at init read a
  // width before layout had settled, so the viewBox disagreed with the element
  // and the browser scaled the drawing down to fit rather than filling it.
  if (typeof ResizeObserver === 'function') {
    const ro = new ResizeObserver(function () { drawTrend(); });
    ['risk-trend', 'rate-trend'].forEach(function (id) {
      const el = $(id);
      if (el) ro.observe(el);
    });
  } else {
    window.addEventListener('resize', drawTrend);
    window.addEventListener('load', drawTrend);
  }

  // ------------------------------------------------------- search engine
  // Concept-aware lexical search: a domain thesaurus plus IDF-weighted term and
  // concept overlap. Not embeddings — this page is static, has no backend and
  // can hold no API key, and on ~100 short strings of jargon like
  // `allow_failure` a thesaurus beats a general sentence model.
  const STOP = new Set(('a an the is are was were be been being do does did done will would can could ' +
    'should if when whether that this these those it its to for with and or but of on in at by from as ' +
    'my our your i we you what how why there any some argus test tests suite run runs').split(' '));
  const THESAURUS = {
    gate_fail: 'fail fails failing failed failure block blocks blocking blocked reject rejects refuse stop stops break breaks red abort aborts enforce enforces enforced enforcement gate gates gating deny denies prevent prevents catch catches flag flags',
    gate_pass: 'pass passes passing passed succeed succeeds success successful green allow allows allowed tolerate tolerates ignore ignores continue proceed complete completes',
    severity: 'severity severities threshold thresholds critical criticals high medium low cvss level levels fail_on_severity strict',
    vulnerability: 'vulnerability vulnerabilities vuln vulns cve cves finding findings issue issues advisory advisories insecure exploit risky',
    allow_failure: 'allow_failure allowfailure override overrides bypass bypasses bypassed nonblocking informational soft warn warning',
    sbom: 'sbom syft bom inventory components spdx cyclonedx bill materials',
    trivy: 'trivy aquasecurity',
    grype: 'grype anchore',
    dedup: 'dedup deduplicate deduplicated deduplication duplicate duplicates duplicated twice overlap overlapping merged same both',
    discover: 'discover discovery discovers dockerfile dockerfiles build builds building built local repo repository find finds glob search',
    remote: 'remote image images pull pulls pulled registry registries tag tags digest sha256 reference refs nginx alpine distroless',
    auth: 'auth authentication authenticate credential credentials password passwords token tokens login username private registry_username registry_password',
    sarif: 'sarif codescanning scanning upload uploads uploaded alerts enable_code_security tab',
    config: 'config configuration configs yaml yml schema matrix parse parses parsing container_config validate validation',
    scn: 'scn fedramp classification classify classifies classified routine adaptive transformative impact significant notification compliance manual_review',
    iac: 'iac terraform tf kubernetes k8s cloudformation cfn infrastructure checkov kics aws resource resources',
    container: 'container containers docker oci podman',
    empty: 'empty none nothing zero missing blank absent unset null omitted',
    invalid: 'invalid bad wrong malformed typo unknown unrecognised unrecognized bogus nonexistent garbage junk misspelled broken corrupt',
    ghes: 'ghes enterprise onprem selfhosted airgapped hardcoded github.com urls',
    pr_comment: 'comment comments commented pr pullrequest post posts review',
    secrets: 'gitleaks leak leaks leaked secret secrets hardcoded exposed key keys',
    dependency: 'dependency dependencies deps sca osv supplychain supply chain provenance package packages',
    dast: 'zap dast webapp web application endpoint url running',
    lint: 'lint linter linters linting style format hadolint ruff eslint',
    cli: 'cli commandline command terminal locally pip pypi python package sdk',
    ports: 'port ports exposed exposure service services listening network',
    naming: 'name names naming sanitise sanitize sanitisation character characters slash space uppercase special',
    arch: 'arch architecture arm64 amd64 platform multiarch multi'
  };
  function stem(w) {
    if (w.length > 5 && /(isation|ization)$/.test(w)) return w.replace(/(isation|ization)$/, 'ise');
    if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3);
    if (w.length > 5 && w.endsWith('ed')) return w.slice(0, -2);
    if (w.length > 4 && w.endsWith('es')) return w.slice(0, -2);
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.slice(0, -1);
    return w;
  }
  function terms(text) {
    const out = [];
    ((text || '').toLowerCase().match(/[a-z0-9_.]+/g) || []).forEach(function (raw) {
      if (STOP.has(raw)) return;
      out.push(stem(raw));
      if (raw.indexOf('_') > -1) {
        raw.split('_').forEach(function (p) { if (p.length > 2 && !STOP.has(p)) out.push(stem(p)); });
      }
    });
    return out;
  }
  const TERM2C = {};
  Object.keys(THESAURUS).forEach(function (c) {
    THESAURUS[c].split(' ').forEach(function (f) {
      terms(f).forEach(function (t) { (TERM2C[t] = TERM2C[t] || new Set()).add(c); });
    });
  });
  function conceptsOf(ts) {
    const o = new Set();
    ts.forEach(function (t) { const cs = TERM2C[t]; if (cs) cs.forEach(function (c) { o.add(c); }); });
    return o;
  }
  docs.forEach(function (x) {
    const text = x.id + ' ' + x.name + ' ' + x.question + ' ' + x.category + ' ' + x.why +
                 ' ' + (x.checks || []).join(' ');
    x._checkCount = x.checks ? x.checks.length : null;
    x._terms = new Set(terms(text));
    x._concepts = conceptsOf(Array.from(x._terms));
    x._lower = text.toLowerCase();
  });
  const N = docs.length || 1, dfT = {}, dfC = {};
  docs.forEach(function (x) {
    x._terms.forEach(function (t) { dfT[t] = (dfT[t] || 0) + 1; });
    x._concepts.forEach(function (c) { dfC[c] = (dfC[c] || 0) + 1; });
  });
  function idfT(t) { return Math.log(1 + N / (1 + (dfT[t] || 0))); }
  function idfC(c) { return Math.log(1 + N / (1 + (dfC[c] || 0))); }
  const CW = 0.55;

  function search(query) {
    const qT = Array.from(new Set(terms(query)));
    if (!qT.length) return [];
    const qC = Array.from(conceptsOf(qT));
    const raw = query.toLowerCase().trim();
    var norm = 0;
    qT.forEach(function (t) { norm += idfT(t); });
    qC.forEach(function (c) { norm += idfC(c) * CW; });
    if (norm <= 0) return [];
    return docs.map(function (x) {
      var sc = 0; const hits = [];
      qT.forEach(function (t) { if (x._terms.has(t)) { sc += idfT(t); hits.push(t); } });
      qC.forEach(function (c) { if (x._concepts.has(c)) sc += idfC(c) * CW; });
      var rel = sc / norm;
      if (raw.length >= 8 && x._lower.indexOf(raw) > -1) rel = Math.min(1, rel + 0.3);
      return { doc: x, rel: rel, hits: hits };
    }).filter(function (r) { return r.rel >= 0.22; })
      .sort(function (a, b) { return b.rel - a.rel; });
  }

  // ----------------------------------------------------------------- table
  function dotClass(x) {
    if (x.kind !== 'test') return x.kind;
    return x.status === 'pass' ? 'pass' : x.status === 'FAIL' ? 'fail'
      : x.status === 'notrun' ? 'idle' : 'skip';
  }
  function statusTitle(x) {
    if (x.kind === 'gap') return 'Known gap here, and not covered by argus CI either';
    if (x.kind === 'untested') return 'Untested anywhere - neither here nor in argus CI';
    if (x.kind === 'upstream') return 'Covered by argus own CI; out of scope for this suite';
    if (x.status === 'notrun') return 'Defined in the suite but not run in this scope';
    return x.status === 'pass' ? 'Passing' : x.status === 'FAIL' ? 'Failing' : x.status;
  }
  // A not-run test is a scheduling decision, not a defect: say which scope runs it.
  function notRunNote(x) {
    if (x.kind !== 'test') return '';
    // A test that produced no verdict has to say why. "Not run" on its own is
    // the shape this suite rejects everywhere else: it makes "we did not look"
    // and "there is nothing wrong" read the same. The reason travels with the
    // result when the test knows it; scope and cancellation are inferred.
    if (x.reason) return x.reason;
    if (x.status === 'skip')   return 'Skipped: this test declined to run and did not say why. That is a gap in the test, not a result.';
    if (x.status === 'cancel') return 'Cancelled before it could report -- the run was superseded or stopped, so this is not a verdict either way.';
    if (x.status !== 'notrun') return '';
    if (x.scope && x.scope !== 'all') {
      return 'Runs only when the suite is dispatched with scope=' + x.scope + '.';
    }
    // "Not run in this scope" was circular when the scope WAS all: it restated
    // the status and explained nothing. A test the suite defines, in a scope
    // that should have run it, producing no result means the run never got to
    // it -- which is a fact about the run, and worth saying.
    return 'This scope should have run it, but the run reported no result \u2014 ' +
           'its category most likely failed to start or was cancelled.';
  }
  function srcHref(x) {
    if (x.issue) return repoUrl + '/issues/' + x.issue;   // a gap points at its issue
    if (!x.file) return null;
    return srcBase + x.file + (x.line ? '#L' + x.line : '');
  }
  function highlight(text, hits) {
    var html = esc(text);
    (hits || []).filter(function (t) { return t.length > 2; }).forEach(function (t) {
      html = html.replace(new RegExp('\\b(' + t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '[a-z]{0,3})\\b', 'gi'), '<mark>$1</mark>');
    });
    return html;
  }

  // A row like "do the unit tests pass?" hides a whole pytest file. Show the
  // assertions the run actually collected, capped so the table stays scannable,
  // with the full list on hover.
  const CHECKS_SHOWN = 6;
  function checksLine(x) {
    const c = x.checks;
    const st = x.stats;
    // A red dot on an aggregate row says nothing about severity: one broken
    // assertion and forty look identical. Lead with the split when we have it.
    if (st && st.total) {
      var summary = '<span class="n">' + st.passed + '/' + st.total + ' passed</span>';
      if (st.failed) summary += '<span class="bad">' + st.failed + ' failed</span>';
      if (st.skipped) summary += '<span class="dim">' + st.skipped + ' skipped</span>';
      const names = (st.failures || []).length
        ? '<div class="failed-names">failed: ' + st.failures.slice(0, 6).map(esc).join(' &middot; ') +
          (st.failures.length > 6 ? ' &middot; +' + (st.failures.length - 6) + ' more' : '') + '</div>'
        : '';
      const rest = (c && c.length)
        ? '<div class="all-checks" title="' + esc(c.join('\n')) + '">' +
          c.slice(0, CHECKS_SHOWN).map(esc).join(' &middot; ') +
          (c.length > CHECKS_SHOWN ? ' &middot; +' + (c.length - CHECKS_SHOWN) + ' more' : '') + '</div>'
        : '';
      return '<div class="checks">' + summary + names + rest + '</div>';
    }
    if (c == null) return '';                       // this test has no sub-checks
    if (!c.length) {
      // It declares sub-checks but collected none: usually the paths it points
      // at have moved or been deleted upstream. Say so rather than showing
      // nothing, which reads as "no detail available".
      return '<div class="checks empty-checks">no checks collected. ' +
             'The paths this job runs may no longer exist upstream.</div>';
    }
    const head = c.slice(0, CHECKS_SHOWN).map(esc).join(' &middot; ');
    const more = c.length > CHECKS_SHOWN ? ' &middot; +' + (c.length - CHECKS_SHOWN) + ' more' : '';
    return '<div class="checks" title="' + esc(c.join('\n')) + '">' +
           '<span class="n">' + c.length + ' checks</span> ' + head + more + '</div>';
  }

  function buildRow(x) {
    const tr = document.createElement('tr');
    tr.id = 'row-' + x.id;
    tr.className = 't' + (x.status === 'FAIL' ? ' failing fc-' + failClass(x) : '');
    // Definition and logs answer different questions -- "what does this test
    // assert?" vs "what did it do on this run?" -- so they get their own columns.
    const href = srcHref(x);
    const defCell = href
      ? '<a href="' + href + '" title="' + esc(x.file + (x.line ? ':' + x.line : '')) + '">' +
        (x.kind === 'test' ? 'test &#8599;' : '#' + (x.issue || '') + ' &#8599;') + '</a>'
      : '<span class="none">&mdash;</span>';
    const ran = x.kind === 'test' && (x.status === 'pass' || x.status === 'FAIL');
    const logCell = ran
      ? '<a href="' + ((jobUrl[x.id] && jobUrl[x.id].url) || d.runUrl) +
        '" title="' + (jobUrl[x.id] ? 'Log for the job that ran ' + esc(x.id) : 'Run logs') + '">log &#8599;</a>'
      : '<span class="none">&mdash;</span>';
    tr.innerHTML =
      '<td class="c-st"><span class="dot ' + dotClass(x) + '" title="' + esc(statusTitle(x)) + '"></span></td>' +
      '<td class="c-id mono">' + esc(x.id) +
        (x.status === 'FAIL'
          ? '<span class="fctag" title="' + esc((GLOSS[failClass(x)] || '')) + '">' +
            esc(SHORT[failClass(x)] || failClass(x)) + ' &times;' + (W[failClass(x)] || 0) + '</span>'
          : '') + '</td>' +
      '<td class="c-q"><span class="qt">' + esc(x.question || x.name) + '</span>' +
        (x.why ? '<div class="why">' + esc(x.why) + '</div>' : '') +
        (notRunNote(x) ? '<div class="why">' + esc(notRunNote(x)) + '</div>' : '') +
        checksLine(x) + '</td>' +
      '<td class="c-cat">' + esc(x.category) + '</td>' +
      '<td class="c-lnk">' + defCell + '</td>' +
      '<td class="c-lnk">' + logCell + '</td>';
    tr._doc = x;
    tr._qt = tr.querySelector('.qt');
    return tr;
  }

  const rowOf = new Map();
  docs.forEach(function (x) { rowOf.set(x, buildRow(x)); });

  const grouped = [];
  var lastCat = null;
  docs.forEach(function (x) {
    if (x.category !== lastCat) {
      lastCat = x.category;
      const members = docs.filter(function (y) { return y.category === x.category; });
      const mt = members.filter(function (y) { return y.kind === 'test'; });
      const mp = mt.filter(function (y) { return y.status === 'pass'; }).length;
      const tr = document.createElement('tr');
      tr.className = 'grp';
      // "0/25" reads as 25 failures; say what actually happened instead.
      const mIdle = mt.filter(function (y) { return y.status === 'notrun'; }).length;
      var count;
      if (!mt.length) count = members.length + (members.length === 1 ? ' entry' : ' entries');
      else if (mIdle === mt.length) count = mt.length + ' not run';
      else count = mp + '/' + mt.length;
      tr.innerHTML = '<td colspan="6">' + esc(x.category) +
        '<span class="gcount">' + count + '</span></td>';
      grouped.push(tr);
    }
    grouped.push(rowOf.get(x));
  });

  const tbody = $('rows'), captionEl = $('caption'), emptyEl = $('empty'), verdictEl = $('verdict');
  // Status filtering lives INSIDE the query as `is:` tokens rather than as a
  // separate chip state. Two independent filters ANDing together silently was
  // the problem: you could search, get nothing, and never see that a chip set
  // three minutes ago was excluding every match. Now there is one state, it is
  // visible in the box, and clearing the box clears everything.
  const FILTERS = {
    passing: function (x) { return x.kind === 'test' && x.status === 'pass'; },
    failing: function (x) { return x.kind === 'test' && x.status === 'FAIL'; },
    'not-run': function (x) {
      return x.kind === 'test' && (x.status === 'notrun' || x.status === 'skip' || x.status === 'cancel');
    },
    'fail-open': function (x) { return x.kind === 'test' && x.status === 'FAIL' && failClass(x) === 'open'; },
    'fail-closed': function (x) { return x.kind === 'test' && x.status === 'FAIL' && failClass(x) === 'closed'; },
    auxiliary: function (x) { return x.kind === 'test' && x.status === 'FAIL' && failClass(x) === 'auxiliary'; },
    tests: function (x) { return x.kind === 'test'; },
    gap: function (x) { return x.kind === 'gap'; },
    untested: function (x) { return x.kind === 'untested'; },
    upstream: function (x) { return x.kind === 'upstream'; }
  };

  function parseQuery(raw) {
    const toks = [];
    const text = String(raw || '').replace(/\bis:([a-z-]+)/gi, function (m, v) {
      const k = v.toLowerCase();
      if (FILTERS[k]) { toks.push(k); return ''; }
      return m;
    }).replace(/\s+/g, ' ').trim();
    return { text: text, filters: toks };
  }

  function render() {
    const parsed = parseQuery(input.value);
    const query = parsed.text;
    const preds = parsed.filters.map(function (f) { return FILTERS[f]; });
    function keep(x) { return preds.every(function (fn) { return fn(x); }); }
    syncStats(parsed.filters);

    const hits = query ? search(query) : null;
    var list;
    if (hits) {
      list = hits.filter(function (h) { return keep(h.doc); });
    } else {
      list = docs.filter(keep).map(function (x) { return { doc: x, rel: 1, hits: [] }; });
    }

    // restore plain text, then re-highlight only what matched
    docs.forEach(function (x) { const r = rowOf.get(x); if (r) r._qt.innerHTML = esc(x.question || x.name); });

    if (!query && !preds.length) {
      tbody.replaceChildren.apply(tbody, grouped);
    } else {
      tbody.replaceChildren.apply(tbody, list.map(function (h) {
        const r = rowOf.get(h.doc);
        if (query) r._qt.innerHTML = highlight(h.doc.question || h.doc.name, h.hits);
        return r;
      }));
    }

    emptyEl.style.display = list.length ? 'none' : 'block';
    if (!list.length) {
      const hidden = hits ? hits.length : 0;
      if (hidden && preds.length) {
        // The filter, not the corpus, is why this is empty. Saying "untested"
        // here would be a flat lie.
        emptyEl.innerHTML = hidden + ' entr' + (hidden === 1 ? 'y matches' : 'ies match') +
          ' this search, but ' +
          parsed.filters.map(function (f) { return '<b>is:' + esc(f) + '</b>'; }).join(' and ') +
          ' excludes ' + (hidden === 1 ? 'it' : 'them') + '.' +
          '<div class="try"><button type="button" class="try-btn" id="drop-filter">Drop the filter</button></div>';
        const db = emptyEl.querySelector('#drop-filter');
        if (db) db.addEventListener('click', function () {
          input.value = parseQuery(input.value).text; paintGhost(); onInput();
        });
      } else if (query) {
        emptyEl.innerHTML = 'Nothing in the suite or the coverage notes resembles this. Treat it as untested.' +
          '<div class="try">Try: ' + EXAMPLES.slice(0, 3).map(function (ex) {
            return '<button type="button" class="try-btn">' + esc(ex) + '</button>';
          }).join(' ') + '</div>';
        Array.prototype.forEach.call(emptyEl.querySelectorAll('.try-btn'), function (b) {
          b.addEventListener('click', function () { input.value = b.textContent; onInput(); });
        });
      } else {
        emptyEl.textContent = 'Nothing matches this filter.';
      }
    }

    const nT = list.filter(function (h) { return h.doc.kind === 'test'; }).length;
    const nG = list.length - nT;
    captionEl.textContent = (query ? list.length + ' match' + (list.length === 1 ? '' : 'es')
                                   : 'Showing ' + list.length + (list.length === 1 ? ' entry' : ' entries')) +
      ' — ' + nT + ' test' + (nT === 1 ? '' : 's') + ', ' + nG + ' coverage note' + (nG === 1 ? '' : 's') +
      (parsed.filters.length ? ' · ' + parsed.filters.map(function (f) { return 'is:' + f; }).join(' ') : '');

    // verdict
    if (!query) { verdictEl.className = 'verdict'; verdictEl.innerHTML = ''; return; }
    const all = hits || [];
    // A fixed cut punishes long queries: the more words, the more the score is
    // divided, so a real match to "block the build when a critical CVE is found"
    // scores lower than a two-word one. Cut relative to the best hit, with an
    // absolute floor so a field of weak matches still reads as "maybe".
    const cut = all.length ? Math.max(0.32, all[0].rel * 0.85) : 1;
    const st = all.filter(function (h) { return h.doc.kind === 'test' && h.rel >= cut; });
    const sg = all.filter(function (h) { return h.doc.kind !== 'test' && h.rel >= cut; });
    const bestTest = all.find(function (h) { return h.doc.kind === 'test'; });
    const bestGap = all.find(function (h) { return h.doc.kind !== 'test'; });
    var cls, head, sub;
    if (st.length && (!sg.length || (bestTest && bestGap && bestTest.rel >= bestGap.rel))) {
      cls = 'yes';
      head = 'Yes, covered by ' + st.length + ' test' + (st.length > 1 ? 's' : '');
      const f = st.filter(function (h) { return h.doc.status === 'FAIL'; });
      const nr = st.filter(function (h) { return h.doc.status === 'notrun'; });
      sub = f.length ? f.length + ' of them ' + (f.length > 1 ? 'are' : 'is') + ' failing right now.'
        : (nr.length === st.length ? 'Defined in the suite but not run in this scope.'
          : 'Confirm the match actually asserts what you mean.');
    } else if (sg.length) {
      const k = sg[0].doc.kind;
      if (k === 'upstream') {
        cls = 'maybe'; head = 'Not here. argus tests this itself';
        sub = 'Out of scope for this suite, which checks the consumer contract. Reason in the row below.';
      } else if (k === 'untested') {
        cls = 'no'; head = 'No, untested anywhere';
        sub = 'Covered by neither this suite nor argus CI. Reason in the row below.';
      } else {
        cls = 'no'; head = 'No, this is a known gap';
        sub = 'Considered and deliberately untested here. Reason in the row below.';
      }
    } else if (all.length) {
      cls = 'maybe'; head = 'Maybe, nothing matches closely';
      sub = 'Nearest entries below. If none fit, treat it as untested.';
    } else {
      cls = 'no'; head = 'No match, this looks untested';
      sub = 'Consider adding a test, or a gap entry in .github/data/coverage-gaps.json.';
    }
    verdictEl.className = 'verdict show ' + cls;
    verdictEl.innerHTML = '<b>' + head + '</b> <span class="sub">' + sub + '</span>';
  }

  // ---------------------------------------------------------------- search UI
  const input = $('q');
  const ghost = $('ghost');
  const kbd = $('kbd');
  const clearBtn = $('clear');
  clearBtn.addEventListener('click', function () {
    input.value = ''; paintGhost(); onInput(); input.focus();
  });

  // Inline typeahead: the completion is drawn as grey text continuing what you
  // typed, accepted with Tab or Right-arrow. The pool is the example queries
  // first (short, phrased the way someone would ask) then every test question,
  // so typing "does argus fail" can land you on an exact test.
  const POOL = EXAMPLES.concat(docs.map(function (x) { return x.question; })
    .filter(Boolean)).filter(function (v, i, a) { return a.indexOf(v) === i; });

  function suggest(typed) {
    typed = String(typed == null ? '' : typed);
    if (typed.length < 2) return '';
    const low = typed.toLowerCase();
    var best = '';
    for (var i = 0; i < POOL.length; i++) {
      const cand = POOL[i];
      if (cand.length > typed.length && cand.toLowerCase().indexOf(low) === 0) {
        // shortest completion wins: least presumptuous about what you meant
        if (!best || cand.length < best.length) best = cand;
        if (i < EXAMPLES.length) { best = cand; break; }
      }
    }
    return best;
  }

  var suggestion = '';
  function paintGhost() {
    const typed = String(input.value == null ? '' : input.value);
    suggestion = suggest(typed);
    ghost.innerHTML = suggestion
      ? '<span class="typed">' + esc(typed) + '</span>' +
        '<span class="rest">' + esc(suggestion.slice(typed.length)) + '</span>' +
        '<span class="tabhint">&#8677; Tab</span>'
      : '';
    syncSlot();
  }
  // "/" focuses the box, so it is only worth showing when the box is empty;
  // once there is something to clear, the same slot becomes the clear button.
  function syncSlot() {
    const has = !!String(input.value || '').length;
    kbd.hidden = has;
    clearBtn.hidden = !has;
  }
  function acceptSuggestion() {
    if (!suggestion) return false;
    input.value = suggestion;
    paintGhost();
    onInput();
    return true;
  }

  var t = null;
  function onInput() {
    const raw = input.value.trim();
    syncSlot();
    const u = new URL(window.location);
    if (raw) u.searchParams.set('q', raw); else u.searchParams.delete('q');
    history.replaceState(null, '', u);
    render();
  }
  input.addEventListener('input', function () {
    paintGhost();                       // immediate, so the hint never lags
    clearTimeout(t); t = setTimeout(onInput, 110);
  });
  input.addEventListener('keydown', function (e) {
    const atEnd = input.selectionStart === input.value.length &&
                  input.selectionEnd === input.value.length;
    if (e.key === 'Tab' && suggestion) { e.preventDefault(); acceptSuggestion(); }
    else if (e.key === 'ArrowRight' && atEnd && suggestion) { e.preventDefault(); acceptSuggestion(); }
    else if (e.key === 'Enter' && suggestion) { e.preventDefault(); acceptSuggestion(); }
  });
  input.addEventListener('scroll', function () { ghost.scrollLeft = input.scrollLeft; });
  // Following a test link while a filter is active would jump to a row that is
  // not currently rendered, so clear the query first and let the anchor resolve
  // against the full table.
  document.addEventListener('click', function (e) {
    const a = e.target && e.target.closest && e.target.closest('a.tref');
    if (!a) return;
    if (input.value) { input.value = ''; paintGhost(); onInput(); }
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== input) { e.preventDefault(); input.focus(); }
    if (e.key === 'Escape' && document.activeElement === input) {
      input.value = ''; paintGhost(); onInput(); input.blur();
    }
  });

  $('foot').innerHTML =
    '<div class="footnotes"><div class="fn-head">References</div>' +
    REFS.map(function (r) {
      return '<div class="fn" id="ref-' + r.n + '">' +
             '<a class="fn-n" href="#cite-' + r.n + '" title="back to where this is cited">[' + r.n + ']</a>' +
             '<span>' + esc(r.ieee || r.cite || '') +
             ' <a href="' + esc(r.url) + '">' + esc(r.url) + '</a>' +
             (r.note ? '<span class="fn-note">' + esc(r.note) + '</span>' : '') + '</span></div>';
    }).join('') + '</div>' +
    '<div class="foot-meta">Generated by the test suite CI on every push. ' +
    'Weights live in <span class="mono">.github/data/failure-classes.json</span>; ' +
    'coverage gaps in <span class="mono">.github/data/coverage-gaps.json</span>; ' +
    '<a href="__UP__../">All branches</a>.</div>';

  // Links into the collapsed method section -- the info mark, or a reference's
  // back-link to a citation inside it -- open it first, or they land on nothing.
  document.addEventListener('click', function (e) {
    const a = e.target && e.target.closest && e.target.closest('a[href^="#"]');
    if (!a) return;
    const how = $('how');
    const t = document.querySelector(a.getAttribute('href'));
    if (how && t && (t === how || how.contains(t))) how.open = true;
  });

  // The theme control lives in the nav (initTheme in site-nav.sh).

  // The URL carries the whole query, `is:` tokens included, so a filtered view
  // is a shareable link rather than something you have to re-click.
  const preset = new URL(window.location).searchParams.get('q');
  if (preset) input.value = preset;
  paintGhost();
  render();
})();
</script>
</body>
</html>
HTMLEOF2

# argus's eye as the site icon, copied next to the page so it needs no network
FAVICON_SRC="$SCRIPT_DIR/../data/argus-favicon.png"
if [ -f "$FAVICON_SRC" ]; then
  cp "$FAVICON_SRC" "$SHARED_DIR/favicon.png"
else
  echo "WARNING: $FAVICON_SRC missing - the page will fall back to no icon"
fi

# .nojekyll
touch "$SHARED_DIR/.nojekyll"

# Resolve the relative-path placeholder as a post-pass, so the HTML heredocs
# above stay literal and greppable.
sed -i.bak "s|__UP__|${UP}|g" "$OUT/index.html" && rm -f "$OUT/index.html.bak"

splice_nav "$OUT/index.html"

echo "Dashboard generated: $OUT/index.html"
echo "History entries: $(jq 'length' "$HISTORY_FILE")"
