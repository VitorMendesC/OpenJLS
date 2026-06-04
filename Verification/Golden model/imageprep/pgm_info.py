#!/usr/bin/env python3
"""Print "WIDTH HEIGHT MAXVAL BITS" for a binary PGM (P5).

Tolerant of header comments and arbitrary whitespace, so it also works on
drop-in PGMs not produced by normalize.py. BITS is the JPEG-LS sample
precision implied by maxval (e.g. 255 -> 8, 4095 -> 12, 65535 -> 16).
"""
import sys


def read_token(f) -> bytes:
    tok = b""
    while True:
        c = f.read(1)
        if not c:
            break
        if c == b"#":            # comment runs to end of line
            f.readline()
            continue
        if c.isspace():
            if tok:
                break
            continue
        tok += c
    return tok


def main():
    with open(sys.argv[1], "rb") as f:
        magic = read_token(f)
        if magic != b"P5":
            sys.exit(f"not a binary PGM (magic={magic!r})")
        w = int(read_token(f))
        h = int(read_token(f))
        mx = int(read_token(f))
    print(w, h, mx, mx.bit_length())


if __name__ == "__main__":
    main()
