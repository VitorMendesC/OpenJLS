#!/usr/bin/env bash
# Image ingestion + normalization for the golden-model conformance suite.
#
# Converges "Images/" to single-component grayscale binary PGMs, ready for the
# golden TB and CharLS. Two stages:
#   1. fetch     download + extract the curated public datasets (USC-SIPI +
#                imagecompression.info grayscale sets) into Images/
#   2. normalize convert every image in Images/ to grayscale PGM, in place,
#                deleting the original color / non-PGM sources
#
# Drop-in friendly: put your own images (any format, color or gray) into
# Images/ and run with --no-fetch to fold them into the suite.
#
# Usage:
#   ./prepare_images.sh             # fetch curated datasets, then normalize
#   ./prepare_images.sh --no-fetch  # normalize whatever is already in Images/
#
# Env:
#   IMG_CACHE=<dir>   reuse already-downloaded dataset zips (by basename)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGES="$HERE/Images"
PREP="$HERE/imageprep"

FETCH=1
[ "${1:-}" = "--no-fetch" ] && FETCH=0

mkdir -p "$IMAGES"

if [ "$FETCH" -eq 1 ]; then
  echo "== fetch =="
  python3 "$PREP/fetch.py" "$IMAGES"
fi

echo "== normalize =="
python3 "$PREP/normalize.py" "$IMAGES"

# 16-bit byte_stuffer stall probes: random noise (several seeds) + adversarial
# patterns (checkerboard/stripes/spikes). Built to try to overrun the byte_stuffer
# 4 B/cycle cap; the pipeline does NOT stall on any of them (k-adaptation +
# buffering hold the sustained rate under the cap), so they serve as a robustness
# probe and as incompressible/structured inputs. Generated after normalize
# (already in target form; must not be down-converted). See imageprep/gen_stress.py.
echo "== random 16-bit probes =="
i=1
for seed in 0x0FF5 0x1234 0xBEEF; do
  python3 "$PREP/gen_stress.py" "$IMAGES/synth-rand16_$i.pgm" --pattern random --seed "$seed"
  i=$((i + 1))
done
echo "== adversarial 16-bit probes =="
for pat in checker vstripe hstripe spikes; do
  python3 "$PREP/gen_stress.py" "$IMAGES/synth-$pat-16.pgm" --pattern "$pat"
done

echo "Images ready: $(find "$IMAGES" -name '*.pgm' | wc -l) PGM(s) in $IMAGES"
