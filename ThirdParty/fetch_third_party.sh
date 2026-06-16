#!/usr/bin/env bash
# Rebuild this project's third-party environment from scratch, pinned to the
# versions below. Run it on a fresh clone to get everything the build and
# verification flows need. This script is also the provenance record: the pins
# and file lists are the source of truth for what each dependency is and where
# it came from.
#
# Three kinds of dependency live here:
#   - Vendored HDL (open-logic, osvvm, osvvm-scripts, tcllib): a curated set of
#     files is copied in and committed; the build then reads them offline and
#     never needs the network. Re-run only to (re)materialize or bump them.
#   - Built-from-source tools (charls): cloned at a pinned commit and compiled
#     locally; the source tree and binary are gitignored (reproducible from the
#     pin). Also built on demand by the golden-model flows, which call this.
#   - System packages (nvc): the VHDL simulator, installed via the OS package
#     manager. Runs last so the vendored deps land first; needs sudo (Ubuntu)
#     or an AUR helper (Arch), so a no-arg run may prompt for elevation.
#
# Usage:  ./fetch_third_party.sh                 everything (full environment)
#         ./fetch_third_party.sh nvc             one or more named components
#         (names: open-logic osvvm osvvm-scripts tcllib charls nvc)
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

NVC_URL="https://github.com/nickg/nvc"   # GPL-3.0 VHDL simulator (system install, not vendored)
NVC_DOCS="https://www.nickg.me.uk/nvc/"
NVC_VERSION="1.21.0"                     # the version this project develops and tests against

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

# --- NVC: the VHDL simulator every flow runs on ------------------------------
# Not vendored (its GPL covers the simulator, not the IP it runs); installed as
# a system package. Auto-installs the pinned version on the platforms we can
# detect, and otherwise points you at the upstream instructions. Idempotent:
# skips when nvc is already on PATH.
fetch_nvc() {
  if command -v nvc > /dev/null 2>&1; then
    echo "==> nvc already installed: $(nvc --version | head -n1)"
    return 0
  fi

  local id ver arch
  id="$( [ -r /etc/os-release ] && . /etc/os-release && printf '%s' "${ID:-}" )"
  ver="$( [ -r /etc/os-release ] && . /etc/os-release && printf '%s' "${VERSION_ID:-}" )"
  arch="$(uname -m)"

  manual_nvc() {
    echo "Due to your system OS or version we can't automatically install NVC." >&2
    echo "Install it manually — releases: $NVC_URL/releases  docs: $NVC_DOCS" >&2
    return 1
  }

  case "$id" in
    ubuntu)
      # Prebuilt .deb is amd64-only and published per Ubuntu LTS.
      [ "$arch" = "x86_64" ] || { manual_nvc; return 1; }
      case "$ver" in
        22.04 | 24.04)
          local deb="nvc_${NVC_VERSION}-1_amd64_ubuntu-${ver}.deb"
          echo "==> nvc $NVC_VERSION (Ubuntu $ver)"
          curl -fLo "$TMP/$deb" "$NVC_URL/releases/download/r${NVC_VERSION}/$deb"
          sudo apt install -y "$TMP/$deb"
          ;;
        *) manual_nvc; return 1 ;;
      esac
      ;;
    arch | manjaro | endeavouros)
      echo "==> nvc (Arch, via yay)"
      command -v yay > /dev/null 2>&1 \
        || { echo "yay not found — install an AUR helper, or build from source: $NVC_URL" >&2; return 1; }
      yay -S --needed nvc
      ;;
    *) manual_nvc; return 1 ;;
  esac
}

# --- dispatch ---------------------------------------------------------------
components=("$@")
[ ${#components[@]} -eq 0 ] && components=(open-logic osvvm osvvm-scripts tcllib charls nvc)
for c in "${components[@]}"; do
  case "$c" in
    open-logic)    fetch_open_logic ;;
    osvvm)         fetch_osvvm ;;
    osvvm-scripts) fetch_osvvm_scripts ;;
    tcllib)        fetch_tcllib ;;
    charls)        fetch_charls ;;
    nvc)           fetch_nvc ;;
    *) echo "unknown component: $c (open-logic osvvm osvvm-scripts tcllib charls nvc)" >&2; exit 1 ;;
  esac
done

echo "Done. Review with: git status ThirdParty"
