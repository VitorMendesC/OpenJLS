#!/usr/bin/env bash
# Golden-model cross-check — vendor-agnostic GHDL build + run.
#
# For each test image: mint a reference .jls with the CharLS encoder, then have
# OpenJLS encode the same image and byte-compare against it. Covers the 8-bit
# TEST8 planes, which exercise the BITNESS=8 datapath the T.87 suite (TEST16,
# 12-bit) never touches. Raw PGM inputs are shared with the T.87 suite under
# "Verification/T87 conformance/Reference Images"; only the results live here.
#
# Before trusting CharLS, a gate re-verifies it reproduces the official ITU
# T16E0.JLS byte-for-byte; if not, the golden generator is suspect and we abort.
#
# Usage:  ./build_run.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK_LIB="$HERE/work-lib"
GOLDEN="$HERE/Output/Golden"
OUTPUT="$HERE/Output/OpenJLS"
REF_DIR="$ROOT/Verification/T87 conformance/Reference Images"
CLI="$HERE/charls-src/build/cli/charls-cli"

TB="tb_openjls_golden"

mkdir -p "$WORK_LIB" "$GOLDEN" "$OUTPUT"

# 0. Reference encoder.
[ -x "$CLI" ] || "$HERE/build_charls.sh"

# 0a. Toolchain gate: CharLS must reproduce the official T16E0.JLS byte-exact,
#     otherwise the goldens it mints are not trustworthy.
"$CLI" encode "$REF_DIR/TEST16.PGM" "$GOLDEN/TEST16_charls.jls" >/dev/null
if ! cmp -s "$GOLDEN/TEST16_charls.jls" "$REF_DIR/T16E0.JLS"; then
  echo "FATAL: CharLS does not reproduce the official T16E0.JLS byte-for-byte." >&2
  echo "       The golden generator is not trustworthy — aborting." >&2
  exit 1
fi
echo "CharLS gate: reproduces official T16E0.JLS byte-exact OK"

# -frelaxed: OpenLogic uses shared variables of non-protected types.
STD_FLAGS=(--std=08 -frelaxed -P"$WORK_LIB")

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

# 3. Golden-model TB
ghdl -a "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$HERE/$TB.vhd"
ghdl -e "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB"

# 4. Per-image: mint golden with CharLS, run OpenJLS, compare (in-TB byte check).
#    All 8-bit, so BITNESS stays at the TB default (8) — no runtime override.
IMAGES=(TEST8R TEST8G TEST8B TEST8GR4 TEST8BS2)
fail=0
for img in "${IMAGES[@]}"; do
  echo "=============================================================="
  echo "Image: $img"
  "$CLI" encode "$REF_DIR/$img.PGM" "$GOLDEN/${img}_charls.jls" >/dev/null
  if ghdl -r "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB" \
      -gREPO_ROOT="$ROOT/" \
      -gPGM_PATH="Verification/T87 conformance/Reference Images/$img.PGM" \
      -gJLS_PATH="Verification/Golden model/Output/Golden/${img}_charls.jls" \
      -gOUT_PATH="Verification/Golden model/Output/OpenJLS/${img}_OPENJLS.jls"; then
    echo "$img: PASS"
  else
    echo "$img: FAIL"
    fail=1
  fi
done

echo "=============================================================="
if [ "$fail" -ne 0 ]; then
  echo "Golden-model suite: FAIL"
  exit 1
fi
echo "Golden-model suite: PASS (all images)"
