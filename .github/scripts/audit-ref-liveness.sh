#!/usr/bin/env bash
# =============================================================================
# Which parts of an argus run are actually coming from the ref under test?
#
# THE TRAP
# --------
# Pointing this suite at a branch of argus feels like it tests that branch. It
# does not, and the gap is not small.
#
# A dispatch target says:
#
#     uses: huntridge-labs/argus/.github/workflows/container-scan.yml@<ref>
#
# That fetches container-scan.yml FROM <ref>. But every `uses:` *inside* that
# file carries its own pin, written into the file at release time:
#
#     uses: huntridge-labs/argus/.github/actions/setup-argus@1.12.5
#
# and setup-argus installs the SDK from its own checkout:
#
#     ROOT="$(cd "${{ github.action_path }}/../../.." && pwd)"; pip install "$ROOT"
#
# `github.action_path` is the checkout of the ref THE ACTION was referenced at,
# which is 1.12.5 -- not the ref the workflow was referenced at. So a branch run
# executes the branch's workflow YAML against the RELEASED SDK.
#
# Concretely, for argus PR #427: the bash `validate-inputs` job is branch-live,
# and every Python fix in the same PR -- validate_sub_scanners, the exit-code 2
# contract, manifest-driven platform detection, _sub_scanner_failed -- is not.
# A test that expects an SDK fix will be red on the branch for a reason that has
# nothing to do with whether the fix is correct.
#
# So: report it, per entry point, and put it on the dashboard next to the ref.
# A board that names a ref it only half-tested is worse than one that says
# nothing, because the half it did not test is invisible.
#
# Usage:   audit-ref-liveness.sh <ref> <output.json>
# Needs:   gh (authenticated), jq
# Exit:    0 always -- this is a report, not a gate. Unreachable refs are
#          recorded as such so the dashboard can say "unknown" rather than
#          silently claiming everything is live.
# =============================================================================
set -uo pipefail

REF="${1:?usage: audit-ref-liveness.sh <ref> <out.json>}"
OUT="${2:?usage: audit-ref-liveness.sh <ref> <out.json>}"
REPO="${ARGUS_REPO:-huntridge-labs/argus}"

# The four workflows the dispatch targets reference directly.
ENTRYPOINTS=(
  "container-scan.yml"
  "reusable-security-hardening.yml"
  "infrastructure-scan.yml"
  "container-scan-from-config.yml"
)

fetch() {
  gh api "repos/${REPO}/contents/.github/workflows/$1?ref=${REF}" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null
}

ENTRIES='[]'

for wf in "${ENTRYPOINTS[@]}"; do
  BODY=$(fetch "$wf")
  if [ -z "$BODY" ]; then
    ENTRIES=$(jq -c --arg wf "$wf" '. + [{workflow:$wf, reachable:false, nested:[], sdk_pins:[], sdk_live:null}]' <<<"$ENTRIES")
    continue
  fi

  # Every `uses: huntridge-labs/argus/<path>@<pin>` in the file. `sed` rather
  # than a YAML parse: these are plain scalars, and a parse would need the
  # whole expression grammar to survive `${{ }}` elsewhere in the file.
  NESTED=$(printf '%s\n' "$BODY" \
    | grep -oE "uses:[[:space:]]*${REPO}/[^@[:space:]]+@[^[:space:]\"']+" \
    | sed -E "s|uses:[[:space:]]*${REPO}/||" \
    | sort -u \
    | jq -R -s -c --arg ref "$REF" '
        split("\n") | map(select(length > 0)) | map(
          (split("@")) as $p
          | { path: $p[0],
              pin: $p[1],
              # Live means: this nested reference resolves to the same ref the
              # entry point was fetched from, so a change on that ref is in play.
              live: ($p[1] == $ref),
              kind: (if ($p[0] | test("setup-argus")) then "sdk"
                     elif ($p[0] | test("^\\.github/workflows/")) then "workflow"
                     else "action" end) })')

  SDK_PINS=$(jq -c '[.[] | select(.kind == "sdk") | .pin] | unique' <<<"$NESTED")
  SDK_LIVE=$(jq -c --arg ref "$REF" 'if length == 0 then null else (map(. == $ref) | all) end' <<<"$SDK_PINS")

  ENTRIES=$(jq -c \
    --arg wf "$wf" \
    --argjson nested "$NESTED" \
    --argjson sdk_pins "$SDK_PINS" \
    --argjson sdk_live "$SDK_LIVE" \
    '. + [{workflow:$wf, reachable:true, nested:$nested, sdk_pins:$sdk_pins, sdk_live:$sdk_live}]' \
    <<<"$ENTRIES")
done

# ---- roll up -------------------------------------------------------------
# yaml_live: the entry-point file itself always comes from the ref, so this is
# true whenever we could read it at all.
# sdk_live:  false if ANY reachable entry point installs the SDK from a pin
#            other than the ref. One stale pin is enough to make "tested on
#            <ref>" false for everything that pin covers.
SUMMARY=$(jq -c --arg ref "$REF" '
  (map(select(.reachable)) | length) as $n
  | {
      ref: $ref,
      entrypoints_reachable: $n,
      yaml_live: ($n > 0),
      sdk_live: (
        [ .[] | select(.reachable) | .sdk_live ] as $s
        | if ($s | length) == 0 then null
          elif ($s | map(. == true) | all) then true
          else false end),
      sdk_pins: ([ .[] | select(.reachable) | .sdk_pins[] ] | unique),
      stale_nested: ([ .[] | select(.reachable) | .nested[] | select(.live | not) ] | length),
      live_nested:  ([ .[] | select(.reachable) | .nested[] | select(.live) ] | length)
    }' <<<"$ENTRIES")

jq -n -c --argjson e "$ENTRIES" --argjson s "$SUMMARY" \
  '{generated: (now | todate), summary: $s, entrypoints: $e}' > "$OUT"

# ---- human-readable, for the job log ------------------------------------
echo "=== argus@${REF} liveness ==================================="
jq -r '
  .entrypoints[]
  | if .reachable | not then "  \(.workflow): UNREACHABLE at this ref"
    else
      "  \(.workflow):",
      ( .nested
        | if length == 0 then ["      (no nested argus references)"]
          else map("      \(if .live then "LIVE " else "PINNED" end)  \(.path)@\(.pin)")
          end
        | .[] )
    end' "$OUT"
echo
jq -r '
  .summary
  | "  workflow YAML from ref : \(if .yaml_live then "yes" else "no" end)",
    "  SDK from ref           : \(if .sdk_live == true then "yes" elif .sdk_live == null then "unknown" else "NO -- installed from \(.sdk_pins | join(", "))" end)",
    "  nested refs live/stale : \(.live_nested)/\(.stale_nested)"' "$OUT"
echo "============================================================="

if [ "$(jq -r '.summary.sdk_live' "$OUT")" = "false" ]; then
  echo "::warning title=SDK is not branch-live::argus@${REF} runs the branch's workflow YAML against the SDK from $(jq -r '.summary.sdk_pins | join(", ")' "$OUT"). Python-side changes on this ref are NOT under test via the reusable workflows; use the SDK-direct suites (test-runtime-env.yml, test-actions-direct.yml, test-unit.yml), which check argus out at the ref."
fi
