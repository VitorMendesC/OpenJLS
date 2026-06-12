#!/usr/bin/env bash
# Code-coverage regression — the full OSVVM suite with statement+branch
# instrumentation of every design unit.
#
# Functional coverage says whether the scenarios we thought of occurred; this
# answers the opposite question — which RTL statements/branches in Sources/
# does NO test execute. Per-test .covdb files land in Coverage/, are merged,
# and rendered to Coverage/html/index.html (all gitignored).
#
# Usage:  ./build_coverage.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

rm -rf Coverage
CODE_COVERAGE=1 ./build_reports.sh

echo "== merge + report =="
# --work: nvc creates a default ./work library stub even for these
# library-less commands — point it into the (gitignored) Coverage dir.
nvc --work=work:Coverage/work --cover-merge -o Coverage/merged.covdb Coverage/tb_*.covdb
nvc --work=work:Coverage/work --cover-report -o Coverage/html Coverage/merged.covdb
echo "== Sources/ statement coverage (union over all tests) =="
python3 cover_summary.py Coverage ../../Sources
echo "Coverage report: $HERE/Coverage/html/index.html"
