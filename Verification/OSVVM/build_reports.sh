#!/usr/bin/env bash
# OSVVM script flow: full regression with YAML -> HTML reports.
#
# Builds the vendored OSVVM core via its own osvvm.pro (the scripts generate
# OsvvmScriptSettingsPkg_local.vhd with the report directories), then builds
# and runs every TB via OpenJls.pro. Outputs (all gitignored):
#   VHDL_LIBS/            compiled libraries (incremental between runs)
#   logs/, reports/       per-test transcripts, YAML and HTML
#   OpenJls.html, index.html   build summary / report index
#
# Requires tclsh (Arch: pacman -S tcl). build_run.sh stays the fast,
# tcl-free inner loop for a single TB.
#
# Usage:  ./build_reports.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

command -v ghdl >/dev/null || {
  echo "ghdl not found — install it (Arch: ghdl-llvm-git from the AUR)" >&2
  exit 1
}
command -v tclsh >/dev/null || {
  echo "tclsh not found — install tcl (Arch: sudo pacman -S tcl)" >&2
  exit 1
}

# fileutil + yaml come from the vendored tcllib subset (not packaged on Arch).
export TCLLIBPATH="$HERE/../../ThirdParty/tcllib"

tclsh <<'EOF'
source ../../ThirdParty/osvvm-scripts/StartGHDL.tcl
build ../../ThirdParty/osvvm/osvvm.pro
build OpenJls.pro
EOF
