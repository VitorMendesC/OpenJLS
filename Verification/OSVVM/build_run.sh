#!/usr/bin/env bash
# Build the OSVVM TBs and run one by name.
# Usage:  ./build_run.sh tb_a11_osvvm
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIBS="$HERE/nvc-libs"

TB="${1:-tb_a11_osvvm}"

if [[ ! -d "$LIBS/osvvm.08" ]]; then
  echo "OSVVM library missing — run ./build_osvvm.sh first" >&2
  exit 1
fi

# --relaxed: shared variables of non-protected types in open-logic and the TBs.
# --psl activates the "-- psl" contract assertions embedded in Sources/.
NVC=(nvc --std=2008 --ieee-warnings=off -L "$LIBS")
A_FLAGS=(--relaxed --psl)
# --exit-severity=error makes assertion/PSL contract violations fatal (default:
# the sim keeps running and exits 0 — the assertions would be advisory only).
RUN_FLAGS=(--exit-severity=error)

# 1. OpenLogic base
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
"${NVC[@]}" --work=work:"$LIBS/work.08" -a "${A_FLAGS[@]}" \
  "${OL_FILES[@]/#/$OL_SRC/}"

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
"${NVC[@]}" --work=work:"$LIBS/work.08" -a "${A_FLAGS[@]}" \
  "${SRC_FILES[@]/#/$SRC/}"

# 3. Support package (own library so TBs can `library tb_support`)
"${NVC[@]}" --work=tb_support:"$LIBS/tb_support.08" -a "${A_FLAGS[@]}" \
  "$HERE/Support/tb_support_pkg.vhd"

# 4. Module + top-level TBs
"${NVC[@]}" --work=work:"$LIBS/work.08" -a "${A_FLAGS[@]}" \
  "$HERE"/Modules/*.vhd "$HERE"/Top/*.vhd

# 5. Elaborate + run from a scratch dir: the OSVVM YAML droppings (OsvvmRun.yml
#    from EndOfTestReports) stay contained. --no-save keeps the library
#    read-only; --jit skips ahead-of-time codegen.
mkdir -p "$HERE/sim-out"
cd "$HERE/sim-out"
"${NVC[@]}" --work=work:"$LIBS/work.08" \
  -e --jit --no-save "${@:2}" "$TB" \
  -r "${RUN_FLAGS[@]}" "$TB"
