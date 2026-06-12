#!/usr/bin/env bash
# Post-synthesis netlist verification (vendor tool for synthesis ONLY).
# Synthesizes openjls_top in the vivado_box distrobox at the OSVVM top TB's
# default config (BITNESS=8, 4096x4096, OUT_WIDTH=48), then runs the full
# OSVVM control-plane stress TB against the funcsim netlist under NVC.
#
# Usage:  ./build_run.sh          synthesize + simulate
#         ./build_run.sh --sim    skip synthesis, reuse Output/ netlist
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OSVVM_DIR="$ROOT/Verification/OSVVM"
LIBS="$HERE/work-lib"
NETLIST="$HERE/Output/openjls_top_funcsim.vhd"

TB="tb_openjls_top_osvvm"

# 1. Synthesis (Vivado lives only in the distrobox; log: ~/EDA/vivado.log)
if [[ "${1:-}" != "--sim" ]]; then
  mkdir -p "$HERE/Output"
  distrobox enter vivado_box -- /home/Vitor/EDA/vivado-launch \
    "$HERE/Output" -mode batch -source "$HERE/synth_funcsim.tcl"
fi

if [[ ! -f "$NETLIST" ]]; then
  echo "netlist missing: $NETLIST (synthesis failed? see ~/EDA/vivado.log)" >&2
  exit 1
fi

# Without lsb_release in the container, Vivado dumps raw os-release lines
# (VERSION_ID=...) into the netlist header comment block, unprefixed —
# unparseable. Fix: install lsb-release in vivado_box.
if grep -qm1 '^[A-Z_]\+=' "$NETLIST"; then
  echo "netlist header corrupt — install lsb-release in vivado_box" >&2
  exit 1
fi

# 2. Vendor simulation libraries for NVC (one-time; ~/.nvc/lib)
if ! compgen -G "$HOME/.nvc/lib/unisim*" > /dev/null; then
  XILINX_VIVADO="$(ls -d "$HOME"/EDA/Xilinx/*/Vivado | sort | tail -1)" \
    nvc --install vivado
fi

# 3. OSVVM library (source-built by the routine flow)
if [[ ! -d "$OSVVM_DIR/nvc-libs/osvvm.08" ]]; then
  echo "OSVVM library missing — run Verification/OSVVM/build_osvvm.sh first" >&2
  exit 1
fi

mkdir -p "$LIBS"
NVC=(nvc --std=2008 --ieee-warnings=off -L "$LIBS" -L "$OSVVM_DIR/nvc-libs")

# 4. Packages the TB needs (the netlist itself is self-contained + unisim):
#    olo math for log2ceil, Common for CO_OUT_WIDTH_STD.
OL_SRC="$ROOT/ThirdParty/open-logic/src/base/vhdl"
"${NVC[@]}" --work=openlogic_base:"$LIBS/openlogic_base.08" -a --relaxed \
  "$OL_SRC/olo_base_pkg_array.vhd" \
  "$OL_SRC/olo_base_pkg_math.vhd" \
  "$OL_SRC/olo_base_pkg_string.vhd" \
  "$OL_SRC/olo_base_pkg_logic.vhd" \
  "$OL_SRC/olo_base_pkg_attribute.vhd"
"${NVC[@]}" --work=work:"$LIBS/work.08" -a --relaxed "$ROOT/Sources/Common.vhd"

# 5. The netlist takes the RTL's place: work.openjls_top is the funcsim
#    netlist, and the TB's POST_SYNTH component default-binds to it.
"${NVC[@]}" --work=work:"$LIBS/work.08" -a --relaxed "$NETLIST"

# 6. TB support package + TB
"${NVC[@]}" --work=tb_support:"$LIBS/tb_support.08" -a --relaxed \
  "$OSVVM_DIR/Support/tb_support_pkg.vhd"
"${NVC[@]}" --work=work:"$LIBS/work.08" -a --relaxed \
  "$OSVVM_DIR/Top/tb_openjls_top_osvvm.vhd"

# 7. Elaborate + run from a scratch dir (contains the OSVVM YAML droppings)
mkdir -p "$HERE/sim-out"
cd "$HERE/sim-out"
"${NVC[@]}" --work=work:"$LIBS/work.08" \
  -e --jit --no-save -g POST_SYNTH=true "$TB" \
  -r --exit-severity=error "$TB"
