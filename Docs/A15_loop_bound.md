# A15 Loop Bound Analysis

## Background

Code segment A.15 in T.87 uses an unbounded `while` loop:

```c
while (RUNcnt >= (1 << J[RUNindex])) {
    AppendToBitStream(1, 1);
    RUNcnt = RUNcnt - (1 << J[RUNindex]);
    if (RUNindex < 31)
        RUNindex = RUNindex + 1;
}
```

The RTL implementation (`A15_encode_run_segments.vhd`) replaces this with a
`for 0 to CO_J_TABLE_SIZE-1` loop (32 iterations). This document proves that
the bounded loop is equivalent for all T.87-compliant inputs.

---

## Variables

| Variable | Description | Bounds |
|---|---|---|
| `iRunCnt` | Pixels counted in the current run by A14 | [0, image_width] |
| `iRunIndex` | Current position in the J table | [0, 31] |
| `J[i]` | T.87 J table entry at index i | [0, 15] |
| `vRg = 2^J[i]` | Segment size consumed per iteration | [1, 32768] |
| `CO_J_TABLE_SIZE` | Loop bound (= J table length) | 32 |

The J table is fixed by T.87 (Table C.3) and declared in `Common.vhd`:

```vhdl
constant CO_J_TABLE : j_table_array := (
  0, 0, 0, 0,
  1, 1, 1, 1,
  2, 2, 2, 2,
  3, 3, 3, 3,
  4, 4, 5, 5,
  6, 6, 7, 7,
  8, 9, 10, 11,
  12, 13, 14, 15
);
```

`vRg` is computed from it inside the loop as a left shift:

```vhdl
vJ  := CO_J_TABLE(vRunIndexInt);        -- J[RUNindex]
vRg := shift_left(to_unsigned(1, vRg'length), vJ);  -- 2^J[RUNindex]
```

Expanded across all 32 indices:

```
Index: 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24  25   26   27   28   29    30    31
J[i]:  0  0  0  0  1  1  1  1  2  2  2  2  3  3  3  3  4  4  5  5  6  6  7  7  8   9   10   11   12   13    14    15
vRg:   1  1  1  1  2  2  2  2  4  4  4  4  8  8  8  8 16 16 32 32 64 64 128 128 256 512 1024 2048 4096 8192 16384 32768
```

---

## Proof: 32 Iterations Are Always Sufficient

### Setup

The RTL loop body (from `A15_encode_run_segments.vhd`):

```vhdl
for i in 0 to CO_J_TABLE_SIZE - 1 loop       -- N = 32 iterations max
    vJ  := CO_J_TABLE(vRunIndexInt);
    vRg := shift_left(to_unsigned(1, vRg'length), vJ);  -- 2^J[RUNindex]
    if vRunCnt >= vRg then
        vRunCnt    := vRunCnt - vRg;          -- consume one segment
        vAppendCnt := vAppendCnt + 1;
        if vRunIndexInt < 31 then
            vRunIndexInt := vRunIndexInt + 1; -- advance index, cap at 31
        end if;
    else
        exit;                                 -- vRunCnt < vRg: done
    end if;
end loop;
```

Each iteration either subtracts `vRg` from `vRunCnt` and advances the index,
or exits. Define `Total(s, N)` as the maximum samples the loop can consume in
`N` iterations when starting at index `s` — i.e., the total consumed if every
iteration succeeds without hitting `exit`.

Since `iRunIndex` increments by 1 per iteration and caps at 31, starting at
`s` the loop uses indices `s, s+1, ..., 31, 31, 31, ...`. For `N = 32`:

```
Total(s, 32) = Σ 2^J[i] for i=s..30   +   (s+1) × 2^J[31]
             = Σ 2^J[i] for i=s..30   +   (s+1) × 32768
```

### Minimum is at s = 0

Since `J[i]` is non-decreasing, shifting the sum window right (increasing `s`)
replaces small early terms with larger index-31 repetitions. Therefore
`Total(s, 32)` is minimised at `s = 0`, which uses each index exactly once:

```
Total(0, 32) = Σ 2^J[i] for i=0..31
             = 4×1 + 4×2 + 4×4 + 4×8 + 2×16 + 2×32 + 2×64 + 2×128
               + 256 + 512 + 1024 + 2048 + 4096 + 8192 + 16384 + 32768
             = 65820
```

### Maximum iRunCnt

`iRunCnt` is incremented once per matching pixel in A14, so it is bounded
by the image width. T.87 encodes image dimensions in 16-bit fields (SOF
marker), fixing the maximum image width at **65535 pixels**.

`RUN_CNT_WIDTH = 16` in the generics is therefore not arbitrary — it is the
correct size to hold any T.87-compliant width without counter overflow.

### Conclusion

```
Total(0, 32) = 65820  >  65535 = max iRunCnt
```

It is impossible for all 32 iterations to succeed without first encountering
`vRunCnt < vRg` (which triggers `exit`). The loop always exits via the `exit`
branch; the `assert` after the loop will never fire for T.87-compliant inputs.

---

## Reducing the Loop for Constrained Image Widths

If the maximum image width is known to be smaller than 65535, the loop bound
can be tightened. The minimum `N` for a given maximum width `W` is the
smallest `N` satisfying:

```
Total(0, N) = Σ 2^J[i] for i=0..N-1  >  W
```

Cumulative `Total(0, N)` values:

| N | Total(0,N) | Largest image width supported |
|---|---|---|
| 22 | 284 | 283 |
| 23 | 412 | 411 |
| 24 | 540 | 539 |
| 25 | 796 | 795 |
| 26 | 1308 | 1307 |
| 27 | 2332 | 2331 |
| 28 | 4380 | 4379 |
| 29 | 8476 | 8475 |
| 30 | 16668 | 16667 |
| 31 | 33052 | 33051 |
| **32** | **65820** | **65535 (full T.87)** |

Common targets:

| Application | Max width | Min loop iterations |
|---|---|---|
| Full HD | 1920 | 27 |
| 4K | 4096 | 28 |
| Full T.87 compliance | 65535 | **32** |

If a future implementation targets a width-constrained subset, `CO_J_TABLE_SIZE`
should become a derived constant:

```vhdl
-- Minimum N such that Total(0, N) > IMAGE_WIDTH_MAX
constant CO_J_TABLE_SIZE : natural := <derived>;
```

The proof remains valid as long as `Total(0, CO_J_TABLE_SIZE) > IMAGE_WIDTH_MAX`.
