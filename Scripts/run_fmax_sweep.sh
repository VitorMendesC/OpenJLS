#!/usr/bin/env bash
# Launch the fmax sweep inside the vivado_box distrobox (batch mode).
# Usage: ./Scripts/run_fmax_sweep.sh
# Output: ~/EDA/Logs/fmax_sweep.csv  (+ per-point rpt_*.log, vivado.log)
#
# Expect a long run: 7 sizes x 3 strategies = 21 impl + 7 synth (~3-4 h on this box).
# Watch progress with:  tail -f ~/EDA/Logs/vivado.log
set -euo pipefail

BOX="vivado_box"
WORKDIR="/home/Vitor/EDA/Logs"
TCL="/home/Vitor/Repos/OpenJLS/Scripts/fmax_sweep.tcl"

distrobox enter "$BOX" -- /home/Vitor/EDA/vivado-launch "$WORKDIR" \
    -mode batch -source "$TCL"

echo "Sweep finished. CSV: $WORKDIR/fmax_sweep.csv"
