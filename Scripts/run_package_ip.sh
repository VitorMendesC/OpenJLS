#!/usr/bin/env bash
# Package the three OpenJLS IP cores (openjls_top, openjls_axis,
# openjls_axis_regs) into <repo>/Sources/Xilinx/ip_repo. `vivado` must be on
# PATH (if Vivado
# lives in a container on your machine, point a local shim at it).
# Usage: ./Scripts/run_package_ip.sh [--verify]
#   --verify: after packaging, create_ip each core with non-default generics
#             and run OOC synthesis as a smoke test.
# Output: <repo>/Sources/Xilinx/ip_repo/<core>/ (component.xml + src/ +
#         xgui/), regenerated
#         from scratch on every run. Vivado logs/scratch land in $WORKDIR
#         (default ~/EDA/Logs), outside the repo.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="${OPENJLS_IP_OUTDIR:-$HOME/EDA/Logs}"

mkdir -p "$WORKDIR"
(cd "$WORKDIR" && vivado -mode batch -source "$HERE/package_ip.tcl")

if [[ "${1:-}" == "--verify" ]]; then
  (cd "$WORKDIR" && vivado -mode batch -source "$HERE/verify_ip.tcl")
fi

echo "IP repo: $(cd "$HERE/.." && pwd)/Sources/Xilinx/ip_repo"
