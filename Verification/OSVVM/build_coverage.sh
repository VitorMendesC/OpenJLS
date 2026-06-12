#!/usr/bin/env bash
# Code-coverage regression — the full OSVVM suite under NVC with
# statement+branch instrumentation of every design unit.
#
# Complements build_reports.sh (GHDL, the routine flow): functional coverage
# says whether the scenarios we thought of occurred; this answers the opposite
# question — which RTL statements/branches in Sources/ does NO test execute.
# Per-test .covdb files land in Coverage/, are merged, and rendered to
# Coverage/html/index.html (all gitignored).
#
# Usage:  ./build_coverage.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

command -v nvc >/dev/null || {
  echo "nvc not found — install it (Arch: nvc from the AUR)" >&2
  exit 1
}
command -v tclsh >/dev/null || {
  echo "tclsh not found — install tcl (Arch: sudo pacman -S tcl)" >&2
  exit 1
}

# fileutil + yaml come from the vendored tcllib subset (not packaged on Arch).
export TCLLIBPATH="$HERE/../../ThirdParty/tcllib"
export CODE_COVERAGE=1

rm -rf Coverage
tclsh <<'EOF'
source ../../ThirdParty/osvvm-scripts/StartNVC.tcl
# Match the project (and the GHDL flow): VHDL-2008. The scripts default NVC
# to VHDL-2019, whose OSVVM support files are not in the vendored snapshot;
# 2008 selects the deprecated/*_c.vhd fallbacks, like GHDL. Same reason for
# the "default" coverage vendor API (no CoverageVendorApiPkg_NVC.vhd vendored;
# functional coverage reporting comes from OSVVM itself either way).
SetVHDLVersion 2008
set ::osvvm::FunctionalCoverageIntegratedInSimulator "default"
build ../../ThirdParty/osvvm/osvvm.pro
build OpenJls.pro
EOF

echo "== merge + report =="
nvc --cover-merge -o Coverage/merged.covdb Coverage/tb_*.covdb
nvc --cover-report -o Coverage/html Coverage/merged.covdb
echo "== Sources/ statement coverage (union over all tests) =="
python3 cover_summary.py Coverage ../../Sources
echo "Coverage report: $HERE/Coverage/html/index.html"
