
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

### Written requirement A.4.1
"If the first non-zero element of the vector (Q1, Q2, Q3) is negative, then all the signs of the vector (Q1, Q2, Q3) shall be reversed to obtain (–Q1, –Q2, –Q3).
In this case, the variable SIGN shall be set to –1, otherwise it shall be set to +1." 
(T.87 1998, pg. 19)

### Written requirement A.4.2
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
  if (Errval >= 0
    MErrval = 2 * Errval;
  else
    MErrval = –2 * Errval – 1;
}
```

### Written requirement A.11.1 and A.11.2 (Golomb encoder and packer)
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
  A[Q] == A[Q] >> 1;
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
  if C[Q] < MAX_C)
    C[Q] = C[Q] + 1;
  ο
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
if (abs(Ra – Rb) <= NEAR
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

### Written requirement A.20.1 – Golomb k variable
- Note: Use A.10 hardware
  
"Set Q = RItype + 365. The Golomb variable k shall be computed, following the same procedure as in the
regular mode, Code segment A.10, but using TEMP instead of A[Q]." (T.87 1998, pg. 25)

### Code segment A.21 – Computation of map for Errval mapping
```c
if ((k == 0) && (Errval > 0) && (2 * Nn[Q] < N[Q]))
  map = 1;
else if ((Errval < 0) && (2 * Nn[Q] >= N[Q]))
  map = 1;
else if ((Errval < 0) && (k ! = 0))
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
if Errval < 0)
  Nn[Q] = Nn[Q] + 1;
A[Q] = A[Q] + ((EMErrval + 1 RItype) >> 1);
if (N[Q] == RESET) {
  A[Q] = A[Q] >> 1;
  N[Q] = N[Q] >> 1;
  Nn[Q] = Nn[Q] >> 1;
}
N[Q] = N[Q] + 1;
```
