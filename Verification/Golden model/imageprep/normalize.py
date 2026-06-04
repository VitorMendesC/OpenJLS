#!/usr/bin/env python3
"""Normalization layer for the golden-model conformance suite.

Turns *any* image into a single-component grayscale binary PGM (P5), the only
format the golden TB and CharLS consume here. Drop whatever you like into a
directory and run:

    python3 normalize.py <dir>

Per file:
  * already a binary PGM (P5)  -> left untouched (idempotent re-runs are cheap)
  * other format (TIFF/PNG/..) -> re-encoded as PGM
  * color                      -> converted to grayscale (Rec.601 luma)
  * bit depth preserved        -> 8-bit => maxval 255, 16-bit => maxval 65535
The original file is deleted once its .pgm replacement is written, so the
directory converges to grayscale PGMs only.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# USC-SIPI / imagecompression.info images far exceed Pillow's decompression-bomb
# guard; these are trusted inputs, so lift the cap.
Image.MAX_IMAGE_PIXELS = None

SIXTEEN_BIT_MODES = {"I", "I;16", "I;16B", "I;16L", "I;16N"}


def is_binary_pgm(path: Path) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(2) == b"P5"
    except OSError:
        return False


def to_gray_array(im: Image.Image):
    """Return (HxW ndarray, maxval), single component, bit depth preserved."""
    single = len(im.getbands()) == 1
    sixteen = im.mode in SIXTEEN_BIT_MODES

    if single and sixteen:
        return np.asarray(im, dtype=np.uint32).astype(np.uint16), 65535
    if single:
        return np.asarray(im.convert("L"), dtype=np.uint8), 255

    # Multi-band -> grayscale via Rec.601 luma. 16-bit colour is essentially
    # nonexistent for these inputs; Pillow collapses it to 8-bit RGB first,
    # which is an acceptable best-effort fallback.
    rgb = np.asarray(im.convert("RGB"), dtype=np.float64)
    luma = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    return np.clip(luma + 0.5, 0, 255).astype(np.uint8), 255


def write_pgm(arr: np.ndarray, maxval: int, out: Path) -> None:
    h, w = arr.shape
    dtype = ">u2" if maxval > 255 else ">u1"  # PGM stores 16-bit big-endian
    tmp = out.with_name(out.name + ".tmp")
    with open(tmp, "wb") as f:
        f.write(f"P5\n{w} {h}\n{maxval}\n".encode("ascii"))
        f.write(arr.astype(dtype).tobytes())
    os.replace(tmp, out)  # atomic; safe even when out == source


def normalize_dir(root: Path):
    converted = removed = skipped = 0
    for p in sorted(root.rglob("*")):
        if not p.is_file() or p.name.endswith(".tmp"):
            continue
        if p.suffix.lower() == ".pgm" and is_binary_pgm(p):
            skipped += 1
            continue
        try:
            with Image.open(p) as im:
                im.load()
                arr, maxval = to_gray_array(im)
        except Exception:
            continue  # not a decodable image (readme, etc.) -> leave it alone
        out = p.with_suffix(".pgm")
        write_pgm(arr, maxval, out)
        converted += 1
        if p != out:
            p.unlink()  # drop the original color / non-PGM source
            removed += 1
    return converted, removed, skipped


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if not root.is_dir():
        sys.exit(f"normalize: not a directory: {root}")
    converted, removed, skipped = normalize_dir(root)
    print(f"normalized: converted={converted} removed_originals={removed} "
          f"already_pgm={skipped}")


if __name__ == "__main__":
    main()
