#!/usr/bin/env bash
# Materialize the third-party dependencies this project relies on, pinned to the
# versions below. This script is the provenance record: the pins and file lists
# are the source of truth for what lives under ThirdParty/ and where it came
# from.
#
# Two kinds of dependency live here:
#   - Vendored HDL (open-logic, osvvm, osvvm-scripts, tcllib): a curated set of
#     files is copied in and committed; the build then reads them offline and
#     never needs the network. Re-run only to (re)materialize or bump them.
#   - Built-from-source tools (charls): cloned at a pinned commit and compiled
#     locally; the source tree and binary are gitignored (reproducible from the
#     pin). Built on demand by the golden-model flows, which call this script.
#
# Usage:  ./fetch_third_party.sh                 all components
#         ./fetch_third_party.sh charls          one or more named components
#         (names: open-logic osvvm osvvm-scripts tcllib charls)
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

CHARLS_URL="https://github.com/team-charls/charls.git"   # JPEG-LS reference encoder
CHARLS_COMMIT=57ac3c337083bedbdfc93d19ec75a02101b1cd71    # polished cli/ lives on main, not in 2.4.x tags

# --- open-logic: base packages + RAM/FIFO primitives the RTL instantiates ---
fetch_open_logic() {
  local OL_DST="$HERE/open-logic"
  local OL_FILES=(
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
}

# --- OSVVM: core packages compiled by Verification/OSVVM/build_osvvm.sh -----
# Keep this list in sync with that script's FILES (it fixes the compile order).
fetch_osvvm() {
  local OSVVM_DST="$HERE/osvvm"
  local OSVVM_FILES=(
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
}

# --- OSVVM-Scripts: tcl script flow (build/.pro, YAML -> HTML reports) -------
# All top-level files; doc/ and images/ are documentation only.
fetch_osvvm_scripts() {
  local SCRIPTS_DST="$HERE/osvvm-scripts"

  echo "==> OSVVM-Scripts $OSVVM_SCRIPTS_TAG"
  git clone --quiet --depth 1 --branch "$OSVVM_SCRIPTS_TAG" -c advice.detachedHead=false "$OSVVM_SCRIPTS_URL" "$TMP/osvvm-scripts"
  rm -rf "$SCRIPTS_DST"
  mkdir -p "$SCRIPTS_DST"
  find "$TMP/osvvm-scripts" -maxdepth 1 -type f ! -name '.*' -exec cp {} "$SCRIPTS_DST/" \;
}

# --- tcllib: pure-tcl modules OSVVM-Scripts requires (not packaged on Arch) --
# fileutil depends on cmdline; yaml bundles its huddle dependency.
# build_reports.sh points TCLLIBPATH here.
fetch_tcllib() {
  local TCLLIB_DST="$HERE/tcllib"
  local TCLLIB_MODULES=(fileutil cmdline yaml)

  echo "==> tcllib $TCLLIB_TAG"
  git clone --quiet --depth 1 --branch "$TCLLIB_TAG" -c advice.detachedHead=false "$TCLLIB_URL" "$TMP/tcllib"
  rm -rf "$TCLLIB_DST"
  mkdir -p "$TCLLIB_DST"
  for m in "${TCLLIB_MODULES[@]}"; do
    mkdir -p "$TCLLIB_DST/$m"
    find "$TMP/tcllib/modules/$m" -maxdepth 1 -name '*.tcl' -exec cp {} "$TCLLIB_DST/$m/" \;
  done
  cp "$TMP/tcllib/license.terms" "$TCLLIB_DST/"
}

# --- CharLS: JPEG-LS reference encoder for the golden-model cross-check -------
# Built from source (not a shipped binary) so the golden .jls files are
# verifiably CharLS output and reproducible from the pinned commit. The source
# tree and the compiled CLI are gitignored; this is idempotent, skipping the
# build when the CLI is already present.
fetch_charls() {
  local SRC="$HERE/charls"
  local CLI="$SRC/build/cli/charls-cli"

  if [ -x "$CLI" ]; then
    echo "==> charls already built: $CLI"
    return 0
  fi

  echo "==> charls ${CHARLS_COMMIT:0:12}"
  if [ ! -e "$SRC/CMakeLists.txt" ]; then
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$CHARLS_URL" 2>/dev/null || true
    git -C "$SRC" fetch -q --depth 1 origin "$CHARLS_COMMIT"
    git -C "$SRC" checkout -q FETCH_HEAD
  fi
  # CLI is off by default; argparse is pulled via FetchContent during configure.
  cmake -S "$SRC" -B "$SRC/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCHARLS_BUILD_CLI=ON
  cmake --build "$SRC/build"
  echo "Built: $CLI"
}

# --- dispatch ---------------------------------------------------------------
components=("$@")
[ ${#components[@]} -eq 0 ] && components=(open-logic osvvm osvvm-scripts tcllib charls)
for c in "${components[@]}"; do
  case "$c" in
    open-logic)    fetch_open_logic ;;
    osvvm)         fetch_osvvm ;;
    osvvm-scripts) fetch_osvvm_scripts ;;
    tcllib)        fetch_tcllib ;;
    charls)        fetch_charls ;;
    *) echo "unknown component: $c (open-logic osvvm osvvm-scripts tcllib charls)" >&2; exit 1 ;;
  esac
done

echo "Done. Review with: git status ThirdParty"
