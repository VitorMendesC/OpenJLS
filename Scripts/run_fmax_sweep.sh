#!/usr/bin/env bash
# Launch the fmax sweep in Vivado batch mode. `vivado` must be on PATH (if
# Vivado lives in a container on your machine, point a local shim at it).
# Usage: ./Scripts/run_fmax_sweep.sh
# Output: $FMAX_OUTDIR (default ~/EDA/Logs): fmax_sweep.csv + per-point
#         rpt_*.log, vivado.log
#
# Expect a long run: 7 sizes x 3 strategies = 21 impl + 7 synth (~3-4 h on this box).
# Watch progress with:  tail -f "$FMAX_OUTDIR"/vivado.log
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="${FMAX_OUTDIR:-$HOME/EDA/Logs}"

mkdir -p "$WORKDIR"
(cd "$WORKDIR" && vivado -mode batch -source "$HERE/fmax_sweep.tcl")

echo "Sweep finished. CSV: $WORKDIR/fmax_sweep.csv"
