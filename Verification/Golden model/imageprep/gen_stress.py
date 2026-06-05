#!/usr/bin/env python3
"""Deterministic 16-bit byte_stuffer stall probes (random + adversarial).

The byte_stuffer drains at OUT_BYTES_PER_CYCLE = 4 B/cycle, while a single
bit_packer beat can be up to LIMIT = 2*(BPP + max(8,BPP)) bits wide: 4 B at
8-bit (== the cap, harmless) but 8 B at 16-bit. These images were built to
overrun that cap and force byte_stuffer to back-pressure upstream.

None of them do: measured Image-1 internal stalls are 0 for the random and for
all four adversarial patterns (and for natural 16-bit images too). Input is 1
pixel/cycle and k-adaptation pins the sustained code length well under 32
bits/pixel, so the 4 B/cycle cap is never sustained-overrun; transient LIMIT
beats are absorbed by buffering. They stay as a robustness probe (the attempt
that proved the cap safe) and as incompressible/structured inputs in the set.

Patterns (all maxval 65535):
  random   uniform 16-bit noise (incompressible; --seed controls it)
  checker  1px checkerboard 0/FFFF        -- MED predictor wrong full-scale every px
  vstripe  alternating columns 0/FFFF     -- vertical 1px stripes
  hstripe  alternating rows 0/FFFF        -- horizontal 1px stripes
  spikes   max spikes on a flat field     -- sparse FFFF where x%3==0 and y%3==0

Seeded => byte-reproducible across runs/hosts, so the committed generator is the
source of truth for Images/ files that are otherwise gitignored.
"""
import argparse
import random
import struct


def pattern_value(pat, x, y):
    if pat == "checker":
        return 0xFFFF if (x + y) & 1 else 0
    if pat == "vstripe":
        return 0xFFFF if x & 1 else 0
    if pat == "hstripe":
        return 0xFFFF if y & 1 else 0
    if pat == "spikes":
        return 0xFFFF if (x % 3 == 0 and y % 3 == 0) else 0
    raise ValueError(pat)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="output PGM path")
    ap.add_argument("--size", type=int, default=256, help="square edge length (px)")
    ap.add_argument("--pattern", default="random",
                    choices=["random", "checker", "vstripe", "hstripe", "spikes"])
    ap.add_argument("--seed", type=lambda s: int(s, 0), default=0x0FF5,
                    help="PRNG seed for --pattern random; accepts 0x.. hex")
    a = ap.parse_args()

    w = h = a.size
    if a.pattern == "random":
        payload = random.Random(a.seed).randbytes(w * h * 2)  # big-endian-agnostic
        tag = f"random (seed {a.seed:#06x})"
    else:
        payload = bytearray()
        for y in range(h):
            for x in range(w):
                payload += struct.pack(">H", pattern_value(a.pattern, x, y))
        tag = a.pattern

    header = f"P5\n{w} {h}\n65535\n".encode()
    with open(a.out, "wb") as f:
        f.write(header + payload)
    print(f"{a.out}: {w}x{h} 16-bit {tag}, {len(header) + len(payload)} B")


if __name__ == "__main__":
    main()
