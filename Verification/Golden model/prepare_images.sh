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

echo "Images ready: $(find "$IMAGES" -name '*.pgm' | wc -l) PGM(s) in $IMAGES"
