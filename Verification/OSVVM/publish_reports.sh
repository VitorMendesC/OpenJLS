#!/usr/bin/env bash
# Assemble the published verification report tree under Docs/Reports/ (served by
# GitHub Pages via .github/workflows/pages.yml).
#
# The OSVVM suite owns the report: this copies the OSVVM HTML and the NVC code
# coverage HTML it generates, then stitches in the text-only suites (golden
# model, post-synth) from the small report_status.env files each one drops in
# its Output/ when run. Suites that haven't been run show as "not run".
#
# Typical flow — run the suites you want reflected, then publish:
#   ./build_run.sh                                   # OSVVM regression + coverage
#   ( cd "../Golden model" && ./build_run.sh )       # golden cross-check
#   ( cd "../Post synth"   && ./build_run_osvvm.sh ) # gate-level (needs Vivado)
#   ./publish_reports.sh                             # -> Docs/Reports/
#
# Usage:  ./publish_reports.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$ROOT/Docs/Reports"

OSVVM_YML="$HERE/OSVVM_OpenJls/OSVVM_OpenJls.yml"
COV_HTML="$HERE/NVC_CodeCoverage/html"
COVDB="$HERE/NVC_CodeCoverage/merged.covdb"
GOLDEN_ENV="$ROOT/Verification/Golden model/Output/report_status.env"
GOLDEN_MD="$ROOT/Verification/Golden model/Output/golden_sweep_report.md"
PS_OSVVM_ENV="$ROOT/Verification/Post synth/Output/report_status_osvvm.env"
PS_GOLDEN_ENV="$ROOT/Verification/Post synth/Output/report_status_golden.env"

rm -rf "$DEST"
mkdir -p "$DEST"

ROWS=""
# emit_row <name> <note> <status> <pct> <summary> <report-link-or-empty> <date-or-empty>
emit_row() {
  local name="$1" note="$2" status="$3" pct="$4" summary="$5" link="$6" date="$7"
  local cls report
  case "$status" in
    PASS)    cls="ok" ;;
    FAIL)    cls="bad" ;;
    INFO)    cls="info" ;;
    *)       cls="na"; status="not run" ;;
  esac
  if [ -n "$link" ]; then report="<a href=\"$link\">view</a>"; else report="&mdash;"; fi
  ROWS+="    <tr><td>$name</td><td><span class=\"badge $cls\">$status</span></td>"
  ROWS+="<td class=\"pct\">${pct:-&mdash;}</td><td>${summary:-&mdash;}</td>"
  ROWS+="<td class=\"note\">${note:-&mdash;}</td>"
  ROWS+="<td>$report</td><td>${date:-&mdash;}</td></tr>"$'\n'
}

# --- OSVVM regression (HTML tree) -----------------------------------------
if [ -f "$HERE/index.html" ] && [ -f "$OSVVM_YML" ]; then
  # one report dir holds index.html + OSVVM_OpenJls/ + osvvm/ (relative links)
  mkdir -p "$DEST/osvvm"
  cp -r "$HERE/index.html" "$HERE/OSVVM_OpenJls" "$HERE/osvvm" "$DEST/osvvm/"
  pass=$(grep -c 'Status: PASSED' "$OSVVM_YML" || true)
  fail=$(grep -c 'Status: FAILED' "$OSVVM_YML" || true)
  total=$((pass + fail))
  affirm=$(grep -oE 'AffirmCount: [0-9]+' "$OSVVM_YML" | awk '{s+=$2} END{print s+0}')
  rdate=$(awk -F'"' '/^Date:/{print $2; exit}' "$OSVVM_YML")
  [ -z "$rdate" ] && rdate=$(awk '/^Date:/{print $2; exit}' "$OSVVM_YML")
  st=PASS; [ "$fail" -ne 0 ] && st=FAIL
  opct=$(awk -v p="$pass" -v t="$total" 'BEGIN{ if (t > 0) printf "%.0f%%", 100 * p / t }')
  emit_row "OSVVM regression" "module + top control-plane" "$st" "$opct" \
    "$total tests &middot; $affirm affirmations" \
    "osvvm/index.html" "${rdate%T*}"
else
  emit_row "OSVVM regression" "module + top control-plane" "NA" "" \
    "run ./build_run.sh to populate" "" ""
fi

# --- NVC code coverage (HTML tree) ----------------------------------------
if [ -d "$COV_HTML" ]; then
  rm -rf "$DEST/coverage"; cp -r "$COV_HTML" "$DEST/coverage"
  pct=""
  if [ -f "$COVDB" ]; then
    pct=$(cd "$HERE" && python3 cover_summary.py NVC_CodeCoverage ../../Sources 2>/dev/null \
            | awk '/^TOTAL/{print $3}')
  fi
  emit_row "NVC code coverage" "statement, union over all tests" "INFO" \
    "${pct:-n/a}" "per-file breakdown in report" "coverage/index.html" ""
else
  emit_row "NVC code coverage" "statement, union over all tests" "NA" "" \
    "run ./build_run.sh to populate" "" ""
fi

# --- text-only suites: read their report_status.env ------------------------
# fields: NAME, NOTE, STATUS, PCT, SUMMARY, DATE  (shell key=value, quoted)
env_row() {
  local f="$1" fb_name="$2" fb_note="$3" link="$4"
  if [ ! -f "$f" ]; then
    emit_row "$fb_name" "$fb_note" "NA" "" "run the suite to populate" "" ""
    return
  fi
  local NAME="" NOTE="" STATUS="" PCT="" SUMMARY="" DATE=""
  # shellcheck disable=SC1090
  source "$f"
  emit_row "${NAME:-$fb_name}" "${NOTE:-$fb_note}" "${STATUS:-NA}" "${PCT:-}" \
    "${SUMMARY:-}" "$link" "${DATE%%T*}"
}

# Golden detail markdown — only when the suite actually ran (status present),
# so a stale Output/ report doesn't get linked under a "not run" row.
golden_link=""
if [ -f "$GOLDEN_ENV" ] && [ -f "$GOLDEN_MD" ]; then
  mkdir -p "$DEST/golden"; cp "$GOLDEN_MD" "$DEST/golden/"
  golden_link="golden/$(basename "$GOLDEN_MD")"
fi
env_row "$GOLDEN_ENV"    "Golden model" "CharLS byte-exact, 8-bit corpus"  "$golden_link"
env_row "$PS_OSVVM_ENV"  "Post-synth"   "control-plane stress on netlist"  ""
env_row "$PS_GOLDEN_ENV" "Post-synth"   "golden byte-exact on netlist"     ""

# --- landing page ----------------------------------------------------------
GEN_DATE="$(date -u '+%Y-%m-%d %H:%M UTC')"
cat > "$DEST/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenJLS — verification reports</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 15px/1.5 system-ui, sans-serif; max-width: 60rem; margin: 2.5rem auto;
         padding: 0 1.2rem; }
  h1 { margin-bottom: .2rem; }
  p.sub { color: #888; margin-top: 0; }
  table { border-collapse: collapse; width: 100%; margin-top: 1.5rem; }
  th, td { text-align: left; padding: .55rem .7rem; border-bottom: 1px solid #8884; }
  th { font-size: .8rem; text-transform: uppercase; letter-spacing: .04em; color: #888; }
  .badge { display: inline-block; padding: .1rem .5rem; border-radius: .5rem;
           font-size: .8rem; font-weight: 600; }
  .ok   { background: #1a7f37; color: #fff; }
  .bad  { background: #cf222e; color: #fff; }
  .info { background: #0969da; color: #fff; }
  .na   { background: #8884; color: inherit; }
  td.pct { font-variant-numeric: tabular-nums; font-weight: 600; white-space: nowrap; }
  td.note { color: #888; }
  a { color: #0969da; }
  footer { margin-top: 2rem; color: #888; font-size: .85rem; }
</style>
</head>
<body>
<h1>OpenJLS — verification reports</h1>
<p class="sub">JPEG-LS encoder IP &middot; results published from the project's own
verification suites. Drill into a row's report for per-test detail.</p>
<table>
  <thead><tr><th>Suite</th><th>Status</th><th>Pass / cov</th><th>Summary</th><th>Notes</th><th>Report</th><th>Run date</th></tr></thead>
  <tbody>
$ROWS  </tbody>
</table>
<footer>
  Generated $GEN_DATE by <code>Verification/OSVVM/publish_reports.sh</code>.
  OSVVM reports and NVC coverage are full HTML; golden and post-synth are
  byte-exact cross-checks summarized here (they emit PASS/FAIL, not HTML).
</footer>
</body>
</html>
EOF

echo "Published report tree -> $DEST"
echo "  open $DEST/index.html"
