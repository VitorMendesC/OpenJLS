#!/usr/bin/env python3
"""Deterministic max-entropy 16-bit PGM — a byte_stuffer stall probe.

The byte_stuffer drains at OUT_BYTES_PER_CYCLE = 4 B/cycle, while a single
bit_packer beat can be up to LIMIT = 2*(BPP + max(8,BPP)) bits wide: 4 B at
8-bit (== the cap, harmless) but 8 B at 16-bit. The intent here was to overrun
that cap with incompressible 16-bit noise and force byte_stuffer to back-pressure
upstream.

It does NOT: measured Image-1 internal stalls are 0 for random, adversarial
(checkerboard/stripes/spikes) and natural 16-bit images alike. Input is 1
pixel/cycle and k-adaptation pins the sustained code length well under 32
bits/pixel (random expands only ~1.03x), so the 4 B/cycle cap is never
sustained-overrun; transient LIMIT beats are absorbed by buffering. So these
stand as a robustness probe (the attempt that proved the cap safe) plus genuine
incompressible/random inputs in the golden set.

Seeded => byte-reproducible across runs/hosts, so the committed generator is the
source of truth for an Images/ file that is otherwise gitignored.
"""
import argparse
import random


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("out", help="output PGM path")
    ap.add_argument("--size", type=int, default=256, help="square edge length (px)")
    ap.add_argument("--seed", type=lambda s: int(s, 0), default=0x0FF5,
                    help="PRNG seed (determinism); accepts 0x.. hex")
    a = ap.parse_args()

    w = h = a.size
    payload = random.Random(a.seed).randbytes(w * h * 2)  # uniform 16-bit, big-endian-agnostic
    header = f"P5\n{w} {h}\n65535\n".encode()
    with open(a.out, "wb") as f:
        f.write(header + payload)
    print(f"{a.out}: {w}x{h} 16-bit max-entropy (seed {a.seed:#06x}), "
          f"{len(header) + len(payload)} B")


if __name__ == "__main__":
    main()
