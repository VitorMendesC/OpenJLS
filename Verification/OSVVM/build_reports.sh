#!/usr/bin/env bash
# OSVVM script flow: full regression with YAML -> HTML reports.
#
# Builds the vendored OSVVM core via its own osvvm.pro (the scripts generate
# OsvvmScriptSettingsPkg_local.vhd with the report directories), then builds
# and runs every TB via OpenJls.pro. Outputs (all gitignored):
#   VHDL_LIBS/            compiled libraries (incremental between runs)
#   logs/, reports/       per-test transcripts, YAML and HTML
#   OpenJls.html, index.html   build summary / report index
#   reports/OSVVM_OpenJls_req.csv   requirements traceability matrix (also
#                                   the Requirements tab of the build HTML)
#
# With CODE_COVERAGE=1 every test is additionally instrumented for
# statement+branch coverage (see build_run.sh, which wraps this to add NVC
# code coverage).
#
# Requires tclsh (Arch: pacman -S tcl).
#
# Usage:  ./build_reports.sh
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

tclsh <<'EOF'
source ../../ThirdParty/osvvm-scripts/StartNVC.tcl
# The scripts default NVC to VHDL-2019, whose OSVVM support files are not in
# the vendored snapshot; 2008 selects the deprecated/*_c.vhd fallbacks. Same
# reason for the "default" coverage vendor API (no CoverageVendorApiPkg_NVC.vhd
# vendored; functional coverage reporting comes from OSVVM itself either way).
SetVHDLVersion 2008
set ::osvvm::FunctionalCoverageIntegratedInSimulator "default"
build ../../ThirdParty/osvvm/osvvm.pro
# AXI4 verification components (osvvm_common -> osvvm_axi4) for the Xilinx
# wrapper TBs. Built via each subtree's own build.pro in the maintained order
# (common shared packages, then the Axi4Lite and AxiStream models).
build ../../ThirdParty/osvvm-common/build.pro
build ../../ThirdParty/osvvm-axi4/common/build.pro
build ../../ThirdParty/osvvm-axi4/Axi4Lite/build.pro
build ../../ThirdParty/osvvm-axi4/AxiStream/build.pro
build OpenJls.pro
EOF
