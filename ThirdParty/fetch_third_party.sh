#!/usr/bin/env bash
# Vendor the third-party HDL this project depends on, pinned to the versions
# below. Run only to (re)materialize or bump ThirdParty/ -- the build reads the
# committed files offline and never needs the network. This script is the
# provenance record: the pins and file lists below are the source of truth for
# what lives under ThirdParty/ and where it came from.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- pins -------------------------------------------------------------------
OL_URL="https://github.com/open-logic/open-logic.git"
OL_TAG="4.5.0"

OSVVM_URL="https://github.com/OSVVM/OSVVM.git"   # core utility library only
OSVVM_TAG="2026.01"

OSVVM_SCRIPTS_URL="https://github.com/OSVVM/OSVVM-Scripts.git"   # tcl script flow (reports)
OSVVM_SCRIPTS_TAG="2026.01"                                      # keep in lockstep with OSVVM_TAG

TCLLIB_URL="https://github.com/tcltk/tcllib.git"   # fileutil + yaml, required by OSVVM-Scripts
TCLLIB_TAG="tcllib-2-0"

# --- open-logic: base packages + RAM/FIFO primitives the RTL instantiates ---
OL_DST="$HERE/open-logic"
OL_FILES=(
  olo_base_pkg_array.vhd
  olo_base_pkg_math.vhd
  olo_base_pkg_string.vhd
  olo_base_pkg_logic.vhd
  olo_base_pkg_attribute.vhd
  olo_base_ram_sp.vhd
  olo_base_ram_sdp.vhd
  olo_base_ram_tdp.vhd
  olo_base_fifo_sync.vhd
)

echo "==> open-logic $OL_TAG"
git clone --quiet --depth 1 --branch "$OL_TAG" -c advice.detachedHead=false "$OL_URL" "$TMP/ol"
rm -rf "$OL_DST/src"
mkdir -p "$OL_DST/src/base/vhdl"
for f in "${OL_FILES[@]}"; do
  cp "$TMP/ol/src/base/vhdl/$f" "$OL_DST/src/base/vhdl/$f"
done
cp "$TMP/ol/License.txt" "$TMP/ol/LGPL2_1.txt" "$OL_DST/"

# --- OSVVM: core packages compiled by Verification/OSVVM/build_osvvm.sh -----
# Keep this list in sync with that script's FILES (it fixes the compile order).
OSVVM_DST="$HERE/osvvm"
OSVVM_FILES=(
  IfElsePkg.vhd
  OsvvmTypesPkg.vhd
  OsvvmScriptSettingsPkg.vhd
  OsvvmScriptSettingsPkg_default.vhd
  OsvvmSettingsPkg.vhd
  OsvvmSettingsPkg_default.vhd
  TextUtilPkg.vhd
  FileUtilPkg.vhd
  ResolutionPkg.vhd
  NamePkg.vhd
  OsvvmGlobalPkg.vhd
  CoverageVendorApiPkg_default.vhd
  TranscriptPkg.vhd
  deprecated/LanguageSupport2019Pkg_c.vhd
  deprecated/FileLinePathPkg_c.vhd
  deprecated/AssertApiPkg_c.vhd
  AlertLogPkg.vhd
  TbUtilPkg.vhd
  NameStorePkg.vhd
  MessageListPkg.vhd
  SortListPkg_int.vhd
  RandomBasePkg.vhd
  RandomPkg.vhd
  RandomProcedurePkg.vhd
  CoveragePkg.vhd
  DelayCoveragePkg.vhd
  ClockResetPkg.vhd
  ResizePkg.vhd
  ScoreboardGenericPkg.vhd
  ScoreboardPkg_slv.vhd
  ScoreboardPkg_int.vhd
  ScoreboardPkg_signed.vhd
  ScoreboardPkg_unsigned.vhd
  ScoreboardPkg_IntV.vhd
  MemorySupportPkg.vhd
  MemoryGenericPkg.vhd
  MemoryPkg.vhd
  ReportPkg.vhd
  deprecated/RandomPkg2019_c.vhd
  OsvvmContext.vhd
  osvvm.pro
  OsvvmVhdlSettings.pro
)

echo "==> OSVVM $OSVVM_TAG"
git clone --quiet --depth 1 --branch "$OSVVM_TAG" -c advice.detachedHead=false "$OSVVM_URL" "$TMP/osvvm"
rm -rf "$OSVVM_DST"
mkdir -p "$OSVVM_DST/deprecated"
for f in "${OSVVM_FILES[@]}"; do
  cp "$TMP/osvvm/$f" "$OSVVM_DST/$f"
done
cp "$TMP/osvvm/LICENSE.md" "$OSVVM_DST/"

# --- OSVVM-Scripts: tcl script flow (build/.pro, YAML -> HTML reports) -------
# All top-level files; doc/ and images/ are documentation only.
SCRIPTS_DST="$HERE/osvvm-scripts"

echo "==> OSVVM-Scripts $OSVVM_SCRIPTS_TAG"
git clone --quiet --depth 1 --branch "$OSVVM_SCRIPTS_TAG" -c advice.detachedHead=false "$OSVVM_SCRIPTS_URL" "$TMP/osvvm-scripts"
rm -rf "$SCRIPTS_DST"
mkdir -p "$SCRIPTS_DST"
find "$TMP/osvvm-scripts" -maxdepth 1 -type f ! -name '.*' -exec cp {} "$SCRIPTS_DST/" \;

# --- tcllib: pure-tcl modules OSVVM-Scripts requires (not packaged on Arch) --
# fileutil depends on cmdline; yaml bundles its huddle dependency.
# build_reports.sh points TCLLIBPATH here.
TCLLIB_DST="$HERE/tcllib"
TCLLIB_MODULES=(fileutil cmdline yaml)

echo "==> tcllib $TCLLIB_TAG"
git clone --quiet --depth 1 --branch "$TCLLIB_TAG" -c advice.detachedHead=false "$TCLLIB_URL" "$TMP/tcllib"
rm -rf "$TCLLIB_DST"
mkdir -p "$TCLLIB_DST"
for m in "${TCLLIB_MODULES[@]}"; do
  mkdir -p "$TCLLIB_DST/$m"
  find "$TMP/tcllib/modules/$m" -maxdepth 1 -name '*.tcl' -exec cp {} "$TCLLIB_DST/$m/" \;
done
cp "$TMP/tcllib/license.terms" "$TCLLIB_DST/"

echo "Done. Review with: git status ThirdParty"
