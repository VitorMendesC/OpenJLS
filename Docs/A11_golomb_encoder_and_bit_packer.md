# JPEG-LS Regular-Mode Golomb Encoder and Bit Packer

This document explains how the regular-mode Golomb encoder (A.5.3) is implemented in `A11_1_golomb_encoder.vhd` and how its outputs are packed into a contiguous bitstream by `A11_2_bit_packer.vhd`. It covers data flow, parameters, bit ordering, timing/throughput, and edge cases.

## Overview

- JPEG-LS regular mode maps the signed prediction error to a non-negative value `MErrval` (see A.11), and encodes it using the limited-length Golomb code function `LG(k, LIMIT)` (see T.87, A.5.3).
- The Golomb code is composed of:
  - A unary prefix: `q` zeros, followed by a single `1` bit.
  - A binary suffix: `k` bits of the remainder, or, in escape, `qbpp` bits of `(MErrval − 1)`.
- We split the problem into two modules:
  1) A pure-combinational encoder that outputs metadata (counts and values).
  2) A sequential bit packer that appends those bits each cycle into a fixed-width output word stream.

This separation minimizes critical paths and supports 1-sample-per-cycle throughput.

## Inputs from Upstream Stages

- `k` is computed in A.10 (see `A10_compute_k.vhd`) from per-context statistics.
- `MErrval` is produced by A.11 error mapping (see `A11_error_mapping.vhd`).
- `qbpp` is the number of bits needed to represent `RANGE` (often equals the sample bit-depth when `RANGE = 2^b`).
- `LIMIT` bounds the total code length. For JPEG-LS baseline, a common configuration uses `LIMIT = 32`.

## A11_1: Golomb Encoder (Metadata)

File: `project_JPEG_LS/project_JPEG_LS.srcs/sources_1/new/A11_1_golomb_encoder.vhd`

### Purpose

Compute the limited-length Golomb encoding parameters in a single cycle without constructing the full codeword.

### Generics

- `BITNESS`: sample precision (bits). Controls width of `iMErrval`.
- `K_WIDTH`: width of the input `k` value.
- `QBPP`: number of bits used in the escape suffix (`ceil(log2(RANGE))`).
- `LIMIT`: maximum code length (total bits); typical JPEG-LS uses 32.
- `UNARY_WIDTH`, `SUFFIX_WIDTH`, `SUFFIXLEN_WIDTH`, `TOTLEN_WIDTH`: sizing for outputs.

### Ports

- Inputs:
  - `iK`: unsigned `k` from A.10.
  - `iMErrval`: unsigned mapped error value (non-negative).
- Outputs (metadata):
  - `oUnaryZeros`: number of leading zeros in the unary prefix.
  - `oSuffixLen`: number of suffix bits (`k` normally, `qbpp` in escape).
  - `oSuffixVal`: suffix value aligned to LSBs (`r` or `(MErrval − 1)`).
  - `oTotalLen`: total bits to append = `oUnaryZeros + 1 + oSuffixLen`.
  - `oIsEscape`: ‘1’ when escape path is taken (for optional monitoring).

### Algorithm (A.5.3)

Given `k` and `MErrval`:

1) Compute quotient and remainder with shifts (no division):
   - `q = floor(MErrval / 2^k) = iMErrval >> k`
   - `r = MErrval mod 2^k = iMErrval − ((iMErrval >> k) << k)`
2) Threshold: `t = LIMIT − qbpp − 1`.
3) If `q < t` (normal case):
   - Unary zeros = `q`
   - Suffix length = `k`
   - Suffix value = `r`
   - Total length = `q + 1 + k`
4) Else (escape case):
   - Unary zeros = `t`
   - Suffix length = `qbpp`
   - Suffix value = `(MErrval − 1)` (in `qbpp` bits)
   - Total length = `LIMIT`

The encoder implements exactly this logic combinationally. It does not build the code bits; it only outputs the counts and suffix value.

### Notes

- `oIsEscape` is not required downstream; it’s exposed for optional statistics or debugging.
- All integer operations are implemented with `unsigned` shifts and slices for synthesis-friendly timing.

## A11_2: Bit Packer

File: `project_JPEG_LS/project_JPEG_LS.srcs/sources_1/new/A11_2_bit_packer.vhd`

### Purpose

Append the per-sample fragments into a contiguous MSB-first output stream of fixed-width words, while sustaining 1 sample per cycle.

### Generics

- `OUT_WIDTH`: width of the output word (commonly 32).
- `BUFFER_WIDTH`: internal buffer size (should be ≥ 2 × `OUT_WIDTH`).
- `UNARY_WIDTH`, `SUFFIX_WIDTH`, `SUFFIXLEN_WIDTH`: sizes matching A11_1 outputs.

### Ports

- Inputs:
  - `iClk`, `iRst`: clock and synchronous reset.
  - `iValid`: high when metadata is valid this cycle.
  - `iUnaryZeros`, `iSuffixLen`, `iSuffixVal`: metadata from A11_1.
  - `iFlush`: request to emit remaining bits (end of frame/scan), zero-padding to a full word if necessary.
  - `iWordReady`: downstream ready for the next output word.
- Outputs:
  - `oWord`: next MSB-first output word.
  - `oWordValid`: asserted when `oWord` is valid.

### Bit Ordering Convention

Per sample, bits are appended in this exact order:

```
zeros (Z times) -> single '1' -> suffix (MSB-first, length = S)
```

Across samples, bits are concatenated. `oWord(OUT_WIDTH-1)` carries the chronologically earliest bit. When the buffer holds at least `OUT_WIDTH` bits and `iWordReady=1`, the packer outputs the top `OUT_WIDTH` bits and shifts the buffer left by `OUT_WIDTH`.

### Internal Operation

- The packer maintains a left-aligned buffer (`BUFFER_WIDTH` bits) and a counter of bits-in-buffer.
- On each cycle with `iValid=1`:
  1) Build a small word containing the sample’s unary ‘1’ and suffix; the leading zeros are implicit because the word is initialized to zero.
  2) Shift the buffer left by the sample total length (`Z + 1 + S`).
  3) OR the sample word into the bottom of the buffer.
- Emission:
  - If `bits_in_buffer ≥ OUT_WIDTH` and `iWordReady=1`, output the top word, set `oWordValid=1`, then shift-left by `OUT_WIDTH` and decrement the bit count.
  - If `iFlush=1`, and `bits_in_buffer > 0` and `iWordReady=1`, output the top word zero-padded and clear the buffer.

### Throughput and Sizing

- Designed for 1 px/cycle steady-state when `iValid=1` continuously.
- To avoid buffer overflow without input backpressure:
  - Use `LIMIT ≤ OUT_WIDTH` (e.g., 32/32), and
  - Use `BUFFER_WIDTH ≥ 2 × OUT_WIDTH` (default 64).
- If downstream may deassert `iWordReady` for multiple cycles while input keeps arriving, consider increasing `BUFFER_WIDTH` proportionally or introducing backpressure.

## Putting It Together

1) Compute `k` (A.10) and `MErrval` (A.11).
2) Feed them to `A11_1_golomb_encoder` (combinational):

   - Outputs: `oUnaryZeros (Z)`, `oSuffixLen (S)`, `oSuffixVal`, `oTotalLen`, `oIsEscape`.

3) Each cycle, with `iValid=1`, feed the metadata to `A11_2_bit_packer`:

   - The packer appends `Z` zeros, a ‘1’, and `S` suffix bits, updates its buffer, and emits an output word whenever it has at least `OUT_WIDTH` bits and `iWordReady=1`.

At the end of a strip/scan/frame, assert `iFlush=1` (for as many cycles as needed with `iWordReady=1`) to drain any remaining partial word.

## Example (Conceptual)

Assume `k=2`, `qbpp=12`, `LIMIT=32`.

- `MErrval = 9 (1001b)`: `q = 2`, `r = 1` → normal
  - Z = 2 zeros, then ‘1’, then `r` in 2 bits (01)
  - Code bits: `00101` (length 5)

- `MErrval = 256`, `q = 64`, `t = 32 − 12 − 1 = 19` → escape
  - Z = 19 zeros, then ‘1’, then `(MErrval−1)` in 12 bits
  - Total length = 32 (LIMIT)

The encoder outputs metadata reflecting these; the packer appends them to the internal buffer and emits 32-bit words when available.

## Integration Notes

- The encoder and packer are parameterized; match widths across modules (`UNARY_WIDTH`, `SUFFIX_WIDTH`, etc.).
- Choose `OUT_WIDTH` to match your downstream interface (e.g., AXI-Stream 32/64 bits).
- If your system requires byte alignment or markers, insert them downstream of the packer using the same buffering scheme.

## References

- ITU-T T.87 | ISO/IEC 14495-1 (JPEG-LS), Annex A.5.3 (Limited-length Golomb code).
- Module files:
  - `project_JPEG_LS/project_JPEG_LS.srcs/sources_1/new/A11_1_golomb_encoder.vhd`
  - `project_JPEG_LS/project_JPEG_LS.srcs/sources_1/new/A11_2_bit_packer.vhd`

