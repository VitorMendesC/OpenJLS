#!/usr/bin/env bash
# Build the OSVVM TBs and run one by name.
# Usage:  ./build_run.sh tb_a11_osvvm
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OSVVM_LIB="$HERE/osvvm-lib"
SUPPORT_LIB="$HERE/tb_support-lib"
WORK_LIB="$HERE/work-lib"

TB="${1:-tb_a11_osvvm}"

if [[ ! -d "$OSVVM_LIB" ]]; then
  echo "OSVVM library missing — run ./build_osvvm.sh first" >&2
  exit 1
fi

mkdir -p "$SUPPORT_LIB" "$WORK_LIB"

STD_FLAGS=(--std=08 -frelaxed -P"$OSVVM_LIB" -P"$SUPPORT_LIB" -P"$WORK_LIB")
# LLVM/GCC backend optimization for analyze + elaborate (not run); matches the
# golden flow. -r instead heap-allocates large stack objects (LLVM 128 kB cap).
OPT_FLAGS=(-O2)
RUN_FLAGS=(--max-stack-alloc=0 --ieee-asserts=disable)

# 1. OpenLogic base
OL_LIB="$WORK_LIB"
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
  ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=openlogic_base --workdir="$OL_LIB" "$OL_SRC/$f"
done

# 2. Project sources
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
  ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$SRC/$f"
done

# 3. Support package (own library so TBs can `library tb_support`)
ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=tb_support --workdir="$SUPPORT_LIB" \
  "$HERE/Support/tb_support_pkg.vhd"

# 4. Module TBs
for f in "$HERE"/Modules/*.vhd; do
  ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$f"
done

# 5. Elaborate + run
ghdl -e "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB"
ghdl -r "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB" "${RUN_FLAGS[@]}" "${@:2}"
