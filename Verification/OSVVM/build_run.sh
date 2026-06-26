#!/usr/bin/env bash
# Main OSVVM entry point — run the full regression with HTML reports AND
# statement+branch code coverage of every design unit.
#
# Thin wrapper around build_reports.sh: it runs the SAME full regression
# (CODE_COVERAGE=1 turns on NVC's --cover instrumentation in OpenJls.pro),
# then merges the per-test databases into one NVC report. Run build_reports.sh
# directly if you want the reports without the coverage instrumentation.
#
# Functional coverage says whether the scenarios we thought of occurred; this
# answers the opposite question — which RTL statements/branches in Sources/
# does NO test execute. Per-test .covdb files land in NVC_CodeCoverage/, are
# merged, and rendered to NVC_CodeCoverage/html/index.html (all gitignored).
# The code-coverage report is NVC's own: OSVVM has no NVC coverage vendor API,
# so its OSVVM_OpenJls/CodeCoverage/ tree stays empty under this toolchain.
#
# Usage:  ./build_run.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

COV="NVC_CodeCoverage"
rm -rf "$COV"
CODE_COVERAGE=1 ./build_reports.sh

echo "== merge + report =="
# --work: nvc creates a default ./work library stub even for these
# library-less commands — point it into the (gitignored) coverage dir.
nvc --work=work:"$COV/work" --cover-merge -o "$COV/merged.covdb" "$COV"/tb_*.covdb
# --per-file: report per source file (DUT files show their real coverage)
# instead of per testbench instance (which buries the DUT under TB scaffolding).
nvc --work=work:"$COV/work" --cover-report --per-file -o "$COV/html" "$COV/merged.covdb"
# dut_only.spec leaves the testbenches/primitives uninstrumented (all-N.A. rows);
# drop those rows so the report lists only the DUT source files.
python3 cover_prune.py "$COV/html"
echo "== Sources/ statement coverage (union over all tests) =="
python3 cover_summary.py "$COV" ../../Sources

echo "== reports =="
echo "NVC code coverage     : $HERE/$COV/html/index.html"
echo "OSVVM report index    : $HERE/index.html"
echo "OSVVM build summary   : $HERE/OSVVM_OpenJls/OSVVM_OpenJls.html"
echo "OSVVM requirements    : $HERE/OSVVM_OpenJls/reports/OSVVM_OpenJls_req.html"
