
# Information
- The code segments bellow are written in C
- In T.87 sometimes a requirement is in written form instead of code segments
- All code segments and written requirements where directly taken from T.87 verbatim
- Each code segment or written requirement is implemented by a RTL located in the folder `Sources`
- Written requirements are labeled, in this project, as a child of the code segment that originated it, as in `A.4.1` if under code segment `A.4`, this is an organizational and styling choice
- Each RTL file has a name that matches a code segment or written requirement, examples:
  -  The RTL `A4_quantization_gradients.vhd` implements "Code segment A.4 – Quantization of the gradients"
  -  The RTL `A4_1_quant_gradient_merging.vhd` implements "Written requirement A.4.1"

# Instructions
- Check if every code segment bellow is correctly implemented by its corresponding RTL located in the folder `Sources`
  - Some requirements are written instead of code segments, check if what is described in text is correctly implemented by the corresponding RTL
- Check if every code segment has an appropriate testbench in the folder `Testbenches`
  - Create the missing testbenches, if any

# Variables
- A[Q] is unsigned
- B[Q] is signed
- C[Q] is signed
- N[Q] is unsigned

# Procedure
## Context determination
### Code segment A.2 – Mode selection procedure (LOSSY ONLY)
```c
if ((abs(D1) <= NEAR) && (abs(D2) <= NEAR) && (abs(D3) <= NEAR))
  goto RunModeProcessing
else
  goto RegularModeProcessing;
```

### Code segment A.3 – Mode selection procedure for lossless coding
```c
if (D1 == 0 && D2 == 0 && D3 == 0)
  goto RunModeProcessing;
else
  goto RegularModeProcessing;
```

### Code segment A.4 – Quantization of the gradients
```c
if (Di <= –T3) Qi = –4;
else if (Di <= –T2) Qi = –3;
else if (Di <= –T1) Qi = –2;
else if (Di < – NEAR) Qi = –1;
else if (Di <= NEAR) Qi = 0;
else if (Di < T1) Qi = 1;
else if (Di < T2) Qi = 2;
else if (Di < T3) Qi = 3;
else Qi = 4;
```

### Written requirement A.4.1 - Flip quantized vector
"If the first non-zero element of the vector (Q1, Q2, Q3) is negative, then all the signs of the vector (Q1, Q2, Q3) shall be reversed to obtain (–Q1, –Q2, –Q3).
In this case, the variable SIGN shall be set to –1, otherwise it shall be set to +1." 
(T.87 1998, pg. 19)

### Written requirement A.4.2 - Merge quantized vector into Q
"After this possible "merging", the vector (Q1, Q2, Q3) is mapped, on a one-to-one basis, into an integer Q representing the context for the sample x. The function mapping the vector (Q1, Q2, Q3) to the integer Q is not specified in this Recommendation | International Standard. This Recommendation | International Standard only requires that the mapping shall be one-to-one, that it shall produce an integer in the range [0..364], and that it be defined for all possible values of the vector (Q1, Q2, Q3), including the vector (0, 0, 0).

NOTE – A total of 9 × 9 × 9 = 729 possible vectors are defined by the procedure in Code segment A.4. The vector (0, 0, 0) and its corresponding mapped value can only occur in regular mode for sample interleaved multi-component scans, as detailed in Annex B."
(T.87 1998, pg. 19)

## Prediction
### Code segment A.5 – Edge-detecting predictor
```c
if (Rc >= max(Ra, Rb))
  Px = min(Ra, Rb);
else {
  if (Rc <= min(Ra, Rb))
    Px = max(Ra, Rb);
  else
    Px = Ra + Rb – Rc;
}
```

### Code segment A.6 – Prediction correction from the bias
```c
if (SIGN == +1)
  Px = Px + C[Q];
else
  Px = Px – C[Q];
if (Px > MAXVAL)
  Px = MAXVAL;
else if (Px < 0)
  Px = 0;
```

### Code segment A.7 – Computation of prediction error
```c
Errval = Ix – Px;
if (SIGN == –1)
  Errval = – Errval;
```

### Code segment A.8 – Error quantization and computation of the reconstructed value in near-lossless coding (LOSSY ONLY)
```c
if (Errval > 0)
  Errval = (Errval + NEAR) / (2 * NEAR + 1);
else
  Errval = – (NEAR – Errval) / (2 * NEAR + 1);
Rx = Px + SIGN * Errval * (2 * NEAR + 1);
if (Rx < 0)
  Rx = 0;
else if (Rx > MAXVAL)
  Rx = MAXVAL;
```

### Written requirement A.8.1 - Reconstructed value in lossless mode (LOSSLESS ONLY)
"In lossless coding (NEAR = 0), the reconstructed value Rx shall be set to Ix."
(T.87 1998, pg. 20)

### Code segment A.9 – Modulo reduction of the error
```c
if (Errval < 0)
  Errval = Errval + RANGE;
if (Errval >= ((RANGE + 1) / 2))
  Errval = Errval – RANGE;
```
## Prediction error encoding
### Code segment A.10 – Computation of the Golomb coding variable k
```c
for(k=0; (N[Q]<<k)<A[Q]; k++);
```

### Code segment A.11 – Error mapping to non-negative values
```c
if ((NEAR == 0) && ( k == 0) && ( 2 * B[Q] <= – N[Q])) {
  if (Errval >= 0)
    MErrval = 2 * Errval + 1
  else
    MErrval = –2 * (Errval + 1);
}
else {
  if (Errval >= 0)
    MErrval = 2 * Errval;
  else
    MErrval = –2 * Errval – 1;
}
```

### Written requirement A.11.1 and A.11.2 - Golomb encoder and bit packer
"If the number formed by the high order bits of MErrval (all but the k least significant bits) is less than LIMIT – qbpp – 1, this number shall be appended to the encoded bit stream in unary representation, that is, by as many zeros as the value of this number, followed by a binary one. The k least significant bits of MErrval shall then be appended to the encoded bit stream without change, with the most significant bit first, followed by the remaining bits in decreasing order of significance."
(T.87 1998, pg. 21)

"Otherwise, LIMIT – qbpp – 1 zeros shall be appended to the encoded bit stream, followed by a binary
one. The binary representation of MErrval – 1 shall then be appended to the encoded bit stream using
qbpp bits, with the most significant bit first, followed by the remaining bits in decreasing order of
significance."
(T.87 1998, pg. 22)

## Update variables
### Code segment A.12 – Variables update
```c
B[Q] = B[Q] + Errval *(2 *NEAR + 1);
A[Q] = A[Q] + abs(Errval);
if (N[Q] == RESET) {
  A[Q] = A[Q] >> 1;
  if (B[Q] >= 0)
    B[Q] = B[Q] >> 1;
  else
    B[Q] = –((1-B[Q]) >> 1);
  N[Q] = N[Q] >> 1;
}
N[Q] = N[Q] + 1;
```

### Code segment A.13 – Update of bias-related variables B[Q] and C[Q]
```c
if (B[Q] <= –N[Q]) {
  B[Q] = B[Q] + N[Q];
  if (C[Q] > MIN_C)
    C[Q] = C[Q] – 1;
  if (B[Q] <= –N[Q])
    B[Q] = –N[Q] + 1;
}
else if (B[Q] > 0) {
  B[Q] = B[Q] – N[Q];
  if (C[Q] < MAX_C)
    C[Q] = C[Q] + 1;
  if (B[Q] > 0)
    B[Q] = 0
}
```

# Procedure: run mode

## Run scanning and run-length coding
### Code segment A.14 – Run-length determination for run mode
```c
RUNval = Ra;
RUNcnt = 0;
while (abs(Ix – RUNval) <= NEAR) {
  RUNcnt = RUNcnt + 1;
  Rx = RUNval;
  if (EOLine == 1)
    break;
  else
    GetNextSample();
}
```

### Code segment A.15 – Encoding of run segments of length rg
```c
while (RUNcnt >= (1 << J[RUNindex]) ) {
  AppendToBitStream(1,1);
  RUNcnt = RUNcnt – (1 << J[RUNindex]);
  if (RUNindex < 31)
    RUNindex = RUNindex +1;
}
```

### Code segment A.16 – Encoding of run segments of length less than rg
```c
if (abs(Ix – RUNval) > NEAR) {
  AppendToBitStream(0,1);
  AppendToBitStream(RUNcnt, J[RUNindex]);
  if (RUNindex > 0)
    RUNindex = RUNindex –1;
}
else if (RUNcnt > 0)
  AppendToBitStream(1,1);
```

## Run interruption sample encoding
### Code segment A.17 – Index computation
```c
if (abs(Ra – Rb) <= NEAR)
  RItype = 1;
else
  RItype = 0;
```

### Code segment A.18 – Prediction error for a run interruption sample
```c
if (RItype ==1)
  Px = Ra;
else
  Px = Rb
Errval = Ix – Px;
```

### Code segment A.19 – Error computation for a run interruption sample
```c
if ((RItype == 0) && (Ra > Rb)) {
  Errval = –Errval;
  SIGN = –1;
}
else
  SIGN = 1;
if (NEAR > 0) {
  Errval = Quantize(Errval);
  Rx = ComputeRx ();
}
else
  Rx = Ix;
Errval = ModRange (Errval,RANGE);
```

### Code segment A.20 – Computation of the auxiliary variable TEMP
```c
if (RItype == 0)
  TEMP = A[365];
else
  TEMP = A[366] + (N[366] >> 1);
```

### Written requirement A.20.1 – Compute Q for run mode
"Set Q = RItype + 365. " (T.87 1998, pg. 25)

### Written requirement A.20.2 – Golomb k variable
"The Golomb variable k shall be computed, following the same procedure as in the
regular mode, Code segment A.10, but using TEMP instead of A[Q]." (T.87 1998, pg. 25)

### Code segment A.21 – Computation of map for Errval mapping
```c
if ((k == 0) && (Errval > 0) && (2 * Nn[Q] < N[Q]))
  map = 1;
else if ((Errval < 0) && (2 * Nn[Q] >= N[Q]))
  map = 1;
else if ((Errval < 0) && (k != 0))
  map = 1;
else
  map = 0;
```

### Code segment A.22 – Errval mapping for run interruption sample
```c
EMErrval = 2 * abs(Errval) – RItype – map;
```

### Written requirement A.22.1 – EMErrval encoding
"Encode EMErrval following the same procedures as in the regular mode (see A.5.3), but using the limited
length Golomb code function LG(k, glimit), where glimit = LIMIT – J[RUNindex] – 1 and RUNindex
corresponds to the value of the variable before the decrement specified in Code segment A.16." (T.87 1998, pg. 25)

### Code segment A.23 – Update of variables for run interruption sample
```c
if (Errval < 0)
  Nn[Q] = Nn[Q] + 1;
A[Q] = A[Q] + ((EMErrval + 1 - RItype) >> 1);
if (N[Q] == RESET) {
  A[Q] = A[Q] >> 1;
  N[Q] = N[Q] >> 1;
  Nn[Q] = Nn[Q] >> 1;
}
N[Q] = N[Q] + 1;
```

---

# Optimizations
Sources: Mert 2018 ("Key Architectural Optimizations for Hardware Efficient JPEG-LS Encoder")

## Pipeline Structure

### Colocate mode detection, gradient quantization, and prediction in Stage 2
These three operations all use causal-template pixels {a, b, c, d} as input and have independent computation paths, hence run in parallel. Former designs dispersed them into multiple stages; colocating them brings no disadvantage in clock frequency and saves pipeline registers.

### Error mapping and k computation belong in Stage 6
Placed in Stage 6 alongside the Golomb encoder to avoid premature calculation of the final encoding parameters, which would consume more resources than their inputs justify.

---

## Context Address Computation

### Gradient quantization on absolute values
Work with |Di| instead of signed Di. For lossless compression, sign of the local gradients is not involved since the quantization outcomes already carry the same sign. Magnitudes are non-negative and range between 0 and 4, expressible in 3 bits.

### Context address without multipliers
`81·Q1 + 9·Q2 + Q3` — since the optimized quantization reduces Qi to 3-bit non-negative values, the sum operations are eliminated: multiplication by 9 reduces to concatenation into six bits, and multiplication by 81 is realized similarly with one logical-OR operation and concatenation. No DSP blocks or adders needed.

### Sign folding as XOR + MUX
Context addresses for regular mode are determined based on sign parameters: a single XOR of sign bits and a 2-input MUX (Fig. 3b).

---

## Variable Table

### Single 366×33 dual-port BRAM for all variables
All variables integrated into a single memory block. Only FPGA memory primitives needed; no DSP units involved. For 8-bit lossless (RESET=64, RANGE=256, MIN_C=−128, MAX_C=127):

| Variable | Width | Addresses | Value Bounds | Notes (from Table I) |
|---|---|---|---|---|
| A | bpp−1 + ⌈log₂(RESET)⌉ = 13b | 367 | [0, (RESET−1)·RANGE/2] | Error accumulator halved at N=RESET before storing |
| B | ⌈log₂(RESET)⌉ = 6b | 365 + 2 (Nn) | [1−RESET, 0] | Updated values are either zero or negative; sign bit need not be stored |
| C | 8b | 365 | [MIN_C, MAX_C] | Range of C is predefined, bit-size is constant |
| N | ⌈log₂(RESET)⌉ = 6b | 367 | [1, RESET] | N counter starts from 1; stored RESET can be substituted by 0 if RESET is power of 2 |
| Nn | ⌈log₂(RESET)⌉ = 6b | 2 | [0, RESET−1] | Nn counter starts from 0; halved at N=RESET before storing; stored in B table at addresses 365–366 |

### B sign never stored
B values are either zero or negative. Sign can be determined by an equality check and need not be stored.

### N stored as 0 when RESET is a power of two
If RESET is a power of 2, stored RESET can be substituted by 0.

### Nn embedded in B table at addresses 365–366
Both Nn and B variables depend on the magnitude of RESET, so the bit width matches. B table's context addresses 365 and 366 are unused during run interruption sample encoding. Nn is stored there, eliminating wasted memory space and removing its data-forwarding circuitry with another path.

---

## Data Forwarding

### N update delegated to Stage 4
N update process is delegated to Stage 4 as it doesn't have dependence on another parameter. Remaining variables (A, B, C) should wait for the most recent N and the prediction error for being updated in Stage 5. Moving N earlier breaks this sequential dependency.

### Forward only when Q matches
When a data hazard is detected (Q_current == Q_previous), recently updated variables are fed to the previous pipeline stage input, bypassing the stale context RAM read. The forwarding path carries A, B/Nn, C, N (Fig. 4).

---

## Run Mode

### RUNindex normalization via RUNTable (NOT ADOPTED)
The standard A.15 while loop is iterative and in a naive implementation requires multiple cycles at run end. Mert's normalization collapses this loop into a single-stage computation by precomputing cumulative coefficients in a RUNTable:

```
RUNadd[0] = 0
RUNadd[i] = sum(2^J[k] for k=0..i-1)    (i > 0)
```

```
Normalized_RUNcnt = RUNcnt + RUNadd[RUNindex_at_run_start]
```

The normalization produces a quasi-state in which the initial RUNindex equals zero. From Normalized_RUNcnt alone, the final RUNindex is recovered in a single J[] lookup. Update of the RUNindex is completed in a single pipeline stage rather than multiple dichotomy steps.

**Not adopted**: our implementation (`A15_A16_encode_run.vhd`) uses a threshold-based approach that eliminates the while loop entirely. A register `sNextBound` tracks the cumulative pixel count at which the next rg boundary fires. Each cycle during the run, a single comparison (`iRunCnt == sNextBound`) detects boundary hits and emits '1' bits incrementally. RUNindex is always current — no recovery or single-shot computation needed at run end. This avoids the RUNTable, the normalization addition, and the burst computation at run end. The only cost is the per-cycle comparator.

### J[] as pure combinational logic
Due to its regularity, J[] is realized as a combinational circuit rather than another ROM.

### Run interrupted by EOL needs no run segment code
Run segments of length less than rg need not be emitted if run mode is interrupted by EOL — only a single bit '1' suffices as an indicator. The EOL flag itself acts as the end of the 1s stream and as a stream length coefficient.

### Run interruption shares the regular mode datapath
Absence of prediction error correction for run interruption is fulfilled without any change to the regular mode structure: error correction table C returns zero for the context addresses 365 and 366 of run interruption sample encoding.

### A* pre-subtraction unifies regular and run interruption datapaths
All values fetched from the A table are subtracted by RItype before any further process, denoted A*. RItype is always kept zero during regular mode to avoid erroneous updates. This allows variable update and prediction error computation in run interruption sample encoding to share the same datapath with regular mode, unlike former designs.

---

## Error Mapping

### map identity reduces comparisons (run interruption)
The standard map computation (A.21) requires 5 comparisons + 2 equality checks. The logical identity in Fig. 8 simplifies this to 2 comparisons and 2 equality checks. Then map and RItype flags are concatenated to directly generate possible values {0, −1, −2}, completing the error mapping with a single subtraction.

### A[Q] update does not depend on EMErrval (Fig. 9)
The standard A.23 update for run interruption expands algebraically — for both map=0 and map=1 the floor-shift resolves identically:

```
Standard:   EMErrval = 2·abs(Errval) − RItype − map
            A[Q] += (EMErrval + 1 − RItype) >> 1
Equivalent: A[Q] += abs(Errval) − RItype
```

A[Q] update depends only on abs(Errval) and RItype — no dependency on map, EMErrval, or the Golomb encoding chain. RItype is held at 0 during regular mode, so the same formula handles both modes:

```
Regular mode:       A[Q] += abs(Errval)
Run interruption:   A[Q] += abs(Errval) − RItype
```

---

## Bitstream Packing

### Merge bitstream packer and byte-stuffer in Stage 7
Both entities are implemented in the same pipeline stage to eliminate a redundant stage. This is more crucial for encoders compressing higher dynamic range images like 16-bit, where LIMIT=64 and without this optimization many registers would be utilized redundantly.

### Zero-padding decision is combinational
Six candidate 8-bit substrings are evaluated in brute force to find zero-padding bit locations. The final decision takes priority of the upper nibbles. The latency of this procedure is hidden behind the latency of the mode-switching multiplexing prior to data packing.

---

# Architectural Decisions (Internal)
Optimizations derived during design, not sourced from literature.

## Regular Mode: Speculative Three-Chain for A.6–A.9
A.13 can only update C[Q] by −1, 0, or +1. All three candidate values are known at Stage 3 start from the context RAM read. Run three parallel instances of A.6→A.7→A.8→A.9, one per candidate. A.12→A.13 run in parallel producing only a 2-bit select signal (two comparisons on B[Q]_new). A final 3:1 MUX selects the correct result after A.9.

Removes A.12→A.13 from the Stage 3 critical path entirely. Critical path becomes A.6+A.7+A.8+A.9 + MUX. Area cost is minimal since A.6–A.9 are narrow adders and comparators.

## Run Mode: k_zero_flag Decouples A.21 from the Priority Encoder
A.21 uses k only as a boolean (k==0 vs k!=0). The full k value is only needed by the Golomb encoder in Stage 6. Extract a single fast comparison directly after A.20:

```
k_zero_flag = (N[Q] >= TEMP)
```

A.21 depends on k_zero_flag rather than the full priority encoder output. The priority encoder runs in parallel and its result is registered at Stage 4 output for Stage 6. This shortens the Stage 4 writeback critical path from:

```
A.20 → full k (priority encoder) → A.21 → A.22 → A[Q] writeback
```
to:
```
A.20 → k_zero_flag (comparison) → A.21 → A.22 → A[Q] writeback
A.20 → full k (priority encoder) → [REG] → Stage 6 Golomb encoder   (parallel, not on writeback path)
```

Note: combined with the A[Q] equivalence above, A.22 is also off the writeback critical path. The run mode Stage 4 writeback reduces to: `abs(Errval) - RItype → RESET check → N[Q]`.
