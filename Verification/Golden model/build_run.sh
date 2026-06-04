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
# Native (LLVM/GCC) backends generate code at analyze/elaborate time; -O2 gives
# a large runtime speedup over the mcode JIT. Applied to -a/-e only, not -r.
OPT_FLAGS=(-O2)

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
  ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=openlogic_base --workdir="$WORK_LIB" "$OL_SRC/$f"
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
  ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$SRC/$f"
done

# 3. Golden-model TB
ghdl -a "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$HERE/$TB.vhd"
ghdl -e "${STD_FLAGS[@]}" "${OPT_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB"

# 4. Per-image: discover normalized PGMs in Images/, mint the golden with
#    CharLS, run OpenJLS, byte-compare (in-TB). BITNESS is derived from each
#    image's maxval (255 => 8, 65535 => 16). Images above MAX_MP megapixels are
#    skipped to keep GHDL sim time bounded — override e.g. MAX_MP=4 ./build_run.sh
#    Populate Images/ with ./prepare_images.sh (fetch curated sets and/or drop
#    in your own images, any format/color — normalize.py folds them in).
#
#    GHDL's runtime is single-threaded, so the per-image runs are fanned out
#    across NUMBER_OF_THREADS processes (default 1). Build/elaboration above is
#    shared; ghdl -r only reads the work library, and every run writes a unique
#    per-image golden/output, so concurrent runs are independent. Eligible images
#    are sharded by file size (LPT greedy) so each worker gets a similar byte
#    budget — e.g. 100 MB of images over 4 threads ≈ 25 MB each.
PREP="$HERE/imageprep"
IMAGES_DIR="$HERE/Images"
MAX_MP="${MAX_MP:-0.5}"
NUMBER_OF_THREADS="${NUMBER_OF_THREADS:-1}"
LOGD="$HERE/Output/logs"
mkdir -p "$LOGD"

shopt -s nullglob
PGMS=("$IMAGES_DIR"/*.pgm)
shopt -u nullglob
if [ "${#PGMS[@]}" -eq 0 ]; then
  echo "No images in $IMAGES_DIR — run ./prepare_images.sh first." >&2
  exit 1
fi

# Eligible images (under the MP cap), tagged with file size for balancing.
skip=0
ELIG=()   # entries: "<size_bytes>\t<pgm_path>\t<bits>"
for pgm in "${PGMS[@]}"; do
  stem="$(basename "${pgm%.pgm}")"
  read -r W H MX BITS < <(python3 "$PREP/pgm_info.py" "$pgm")
  mp=$(awk -v w="$W" -v h="$H" 'BEGIN{printf "%.3f", w*h/1e6}')
  if awk -v mp="$mp" -v cap="$MAX_MP" 'BEGIN{exit !(mp>cap)}'; then
    echo "SKIP $stem (${W}x${H}, ${mp} MP > ${MAX_MP} cap)"
    skip=$((skip + 1)); continue
  fi
  ELIG+=("$(stat -c%s "$pgm")"$'\t'"$pgm"$'\t'"$BITS")
done
NELIG="${#ELIG[@]}"

# Clamp worker count to [1, NELIG].
NT="$NUMBER_OF_THREADS"
[ "$NT" -lt 1 ] && NT=1
[ "$NELIG" -gt 0 ] && [ "$NT" -gt "$NELIG" ] && NT="$NELIG"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# One image: mint golden, run the DUT, byte-compare (log to $LOGD/<stem>.log).
run_image() {
  local w="$1" pgm="$2" bits="$3" stem
  stem="$(basename "${pgm%.pgm}")"
  if ! "$CLI" encode "$pgm" "$GOLDEN/${stem}_charls.jls" >"$LOGD/$stem.log" 2>&1; then
    echo "[t$w] FAIL $stem (charls encode)"; echo "$stem" >>"$TMPD/failures"; return 1
  fi
  if ghdl -r "${STD_FLAGS[@]}" --work=work --workdir="$WORK_LIB" "$TB" \
      --ieee-asserts=disable --max-stack-alloc=0 \
      -gREPO_ROOT="$ROOT/" \
      -gPGM_PATH="Verification/Golden model/Images/${stem}.pgm" \
      -gJLS_PATH="Verification/Golden model/Output/Golden/${stem}_charls.jls" \
      -gOUT_PATH="Verification/Golden model/Output/OpenJLS/${stem}_OPENJLS.jls" \
      -gBITNESS="$bits" >>"$LOGD/$stem.log" 2>&1; then
    echo "[t$w] PASS $stem"; return 0
  fi
  echo "[t$w] FAIL $stem"; echo "$stem" >>"$TMPD/failures"; return 1
}

# A worker drains its assigned shard, tallying pass/fail to $TMPD/wN.res.
run_worker() {
  local w="$1" wpass=0 wfail=0 pgm bits
  while IFS=$'\t' read -r pgm bits; do
    [ -z "$pgm" ] && continue
    if run_image "$w" "$pgm" "$bits"; then wpass=$((wpass + 1)); else wfail=$((wfail + 1)); fi
  done < "$TMPD/w$w.list"
  echo "$wpass $wfail" > "$TMPD/w$w.res"
}

pass=0; fail=0
if [ "$NELIG" -gt 0 ]; then
  # LPT greedy balance: assign largest images first to the least-loaded worker.
  declare -a LOAD
  for ((w = 0; w < NT; w++)); do LOAD[w]=0; : > "$TMPD/w$w.list"; done
  while IFS=$'\t' read -r sz pgm bits; do
    min=0
    for ((w = 1; w < NT; w++)); do
      [ "${LOAD[w]}" -lt "${LOAD[min]}" ] && min=$w
    done
    printf '%s\t%s\n' "$pgm" "$bits" >> "$TMPD/w$min.list"
    LOAD[min]=$((LOAD[min] + sz))
  done < <(printf '%s\n' "${ELIG[@]}" | sort -t$'\t' -k1,1nr)

  echo "Running $NELIG image(s) across $NT thread(s), balanced by size:"
  for ((w = 0; w < NT; w++)); do
    printf '  t%d: %d image(s), %s MB\n' "$w" "$(wc -l < "$TMPD/w$w.list")" \
      "$(awk -v b="${LOAD[w]}" 'BEGIN{printf "%.2f", b/1048576}')"
  done
  echo "=============================================================="

  for ((w = 0; w < NT; w++)); do run_worker "$w" & done
  wait

  for ((w = 0; w < NT; w++)); do
    [ -f "$TMPD/w$w.res" ] || continue
    read -r wp wf < "$TMPD/w$w.res"
    pass=$((pass + wp)); fail=$((fail + wf))
  done
fi

echo "=============================================================="
echo "Golden-model suite: PASS=$pass FAIL=$fail SKIP=$skip (cap ${MAX_MP} MP, ${NT} thread(s))"
if [ "$fail" -ne 0 ]; then
  if [ -f "$TMPD/failures" ]; then
    echo "Failing images (logs under $LOGD):"
    while IFS= read -r s; do
      echo "  -- $s"; grep -iE "RESULT|mismatch|error" "$LOGD/$s.log" 2>/dev/null | head -4 | sed 's/^/     /' || true
    done < "$TMPD/failures"
  fi
  echo "Golden-model suite: FAIL"
  exit 1
fi
echo "Golden-model suite: PASS"
