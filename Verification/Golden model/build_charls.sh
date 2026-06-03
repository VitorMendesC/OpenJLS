#!/usr/bin/env bash
# Build the CharLS JPEG-LS encoder CLI from source — the reference encoder used
# by the golden-model cross-check. We build it rather than ship a binary so the
# golden .jls files are reproducible and verifiably CharLS output, not an opaque
# blob. Pinned to a specific commit for reproducibility (the polished cli/ tool
# lives on main; the 2.4.x release tags don't include it yet).
#
# Usage:  ./build_charls.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/charls-src"
CLI="$SRC/build/cli/charls-cli"
CHARLS_COMMIT=57ac3c337083bedbdfc93d19ec75a02101b1cd71

if [ -x "$CLI" ]; then
  echo "charls-cli already built: $CLI"
  exit 0
fi

# Pinned shallow fetch (works without cloning full history).
if [ ! -e "$SRC/CMakeLists.txt" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/team-charls/charls.git 2>/dev/null || true
  git -C "$SRC" fetch -q --depth 1 origin "$CHARLS_COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
fi

# CLI is off by default; argparse is pulled via FetchContent during configure.
cmake -S "$SRC" -B "$SRC/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCHARLS_BUILD_CLI=ON
cmake --build "$SRC/build"

echo "Built: $CLI"
