#!/usr/bin/env bash
# ITU-T T.87 conformance test — vendor-agnostic GHDL build + run.
# Compiles OpenLogic base, the project sources and the conformance TB into a
# local work library, then elaborates and runs it. REPO_ROOT is derived from
# this script's location so it works on any machine.
#
# Usage:  ./build_run.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK_LIB="$HERE/work-lib"

TB="tb_openjls_conformance"

mkdir -p "$WORK_LIB" "$HERE/Output"

# -frelaxed: OpenLogic uses shared variables of non-protected types.
# -fpsl activates the "-- psl" contract assertions embedded in Sources/.
STD_FLAGS=(--std=08 -frelaxed -fpsl -P"$WORK_LIB")

# 1. OpenLogic base (compile order matters — dependency chain)
OL_SRC="$ROOT/ThirdParty/open-logic/src/base/vhdl"
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
for f in "${OL_FILES[@]}"; do
  ghdl -a "${STD_FLAGS[@]}" --work=openlogic_base --workdir="$WORK_LIB" "$OL_SRC/$f"
done

# 2. Project sources (Common first, openjls_top last)
SRC="$ROOT/Sources"
SRC_FILES=(
  Common.vhd
  A1_gradient_comp.vhd
  A3_mode_selection.vhd
  A4_quantization_gradients.vhd
  A4_1_quant_gradient_merging.vhd
  A4_2_Q_mapping.vhd
  A5_edge_detecting_predictor.vhd
  A6_prediction_correction.vhd
  A7_prediction_error.vhd
  A9_modulo_reduction.vhd
  A10_compute_k.vhd
  A11_error_mapping.vhd
  A11_1_golomb_encoder.vhd
  A11_2_bit_packer.vhd
  A12_variables_update.vhd
  A13_update_bias.vhd
  A14_run_length_determination.vhd
  A15_A16_encode_run.vhd
  A17_run_interruption_index.vhd
  A18_run_interruption_prediction_error.vhd
  A19_run_interruption_error.vhd
  A20_compute_temp.vhd
  A21_compute_map.vhd
  A22_errval_mapping.vhd
  A23_run_interruption_update.vhd
  line_buffer.vhd
  context_ram.vhd
  byte_stuffer.vhd
  jls_framer.vhd
  openjls_top.vhd
)
for f in "${SRC_FILES[@]}"; do
  ghdl -a "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$SRC/$f"
done

# 3. Conformance TB
ghdl -a "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$HERE/$TB.vhd"

# 4. Elaborate + run (REPO_ROOT points the TB at the in-repo test images)
ghdl -e "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB"
ghdl -r "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB" --assert-level=error -gREPO_ROOT="$ROOT/"
