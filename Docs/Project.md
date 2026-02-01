
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

# Code segments
## Code segment A.2 – Mode selection procedure (LOSSY ONLY)
```
if ((abs(D1) <= NEAR) && (abs(D2) <= NEAR) && (abs(D3) <= NEAR))
  goto RunModeProcessing
else
  goto RegularModeProcessing;
```

## Code segment A.3 – Mode selection procedure for lossless coding
```
if (D1 == 0 && D2 == 0 && D3 == 0)
  goto RunModeProcessing;
else
  goto RegularModeProcessing;
```

## Code segment A.4 – Quantization of the gradients
```
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

## Written requirement A.4.1
"If the first non-zero element of the vector (Q1, Q2, Q3) is negative, then all the signs of the vector (Q1, Q2, Q3) shall be reversed to obtain (–Q1, –Q2, –Q3).

In this case, the variable SIGN shall be set to –1, otherwise it shall be set to +1." 
(T.87 1998, pg. 19)

## Written requirement A.4.2
"After this possible "merging", the vector (Q1, Q2, Q3) is mapped, on a one-to-one basis, into an integer Q representing the context for the sample x. The function mapping the vector (Q1, Q2, Q3) to the integer Q is not specified in this Recommendation | International Standard. This Recommendation | International Standard only requires that the mapping shall be one-to-one, that it shall produce an integer in the range [0..364], and that it be defined for all possible values of the vector (Q1, Q2, Q3), including the vector (0, 0, 0).

NOTE – A total of 9 × 9 × 9 = 729 possible vectors are defined by the procedure in Code segment A.4. The vector (0, 0, 0) and its corresponding mapped value can only occur in regular mode for sample interleaved multi-component scans, as detailed in Annex B."
(T.87 1998, pg. 19)

## Code segment A.5 – Edge-detecting predictor
```
if (Rc >= max(Ra, Rb))
  Px = min(Ra, Rb);
else {
  if (Rc <= min(Ra, Rb))
    Px = max(Ra, Rb);
  else
    Px = Ra + Rb – Rc;
}
```

## Code segment A.6 – Prediction correction from the bias
```
if (SIGN == +1)
  Px = Px + C[Q];
else
  Px = Px – C[Q];
if (Px > MAXVAL)
  Px = MAXVAL;
else if (Px < 0)
  Px = 0;
```

## Code segment A.7 – Computation of prediction error
```
Errval = Ix – Px;
if (SIGN == –1)
  Errval = – Errval;
```

## Code segment A.8 – Error quantization and computation of the reconstructed value in near-lossless coding (LOSSY ONLY)
```
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

## Code segment A.9 – Modulo reduction of the error
```
if (Errval < 0)
  Errval = Errval + RANGE;
if (Errval >= ((RANGE + 1) / 2))
  Errval = Errval – RANGE;
```

## Code segment A.10 – Computation of the Golomb coding variable k
```
for(k=0; (N[Q]<<k)<A[Q]; k++);
```

## Code segment A.11 – Error mapping to non-negative values
```
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

## Written requirement A.11.1 and A.11.2 (Golomb encoder and packer)
"If the number formed by the high order bits of MErrval (all but the k least significant bits) is less than LIMIT – qbpp – 1, this number shall be appended to the encoded bit stream in unary representation, that is, by as many zeros as the value of this number, followed by a binary one. The k least significant bits of MErrval shall then be appended to the encoded bit stream without change, with the most significant bit first, followed by the remaining bits in decreasing order of significance."
(T.87 1998, pg. 21)

"Otherwise, LIMIT – qbpp – 1 zeros shall be appended to the encoded bit stream, followed by a binary
one. The binary representation of MErrval – 1 shall then be appended to the encoded bit stream using
qbpp bits, with the most significant bit first, followed by the remaining bits in decreasing order of
significance."
(T.87 1998, pg. 22)

## Code segment A.12 – Variables update
```
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

## Code segment A.13 – Update of bias-related variables B[Q] and C[Q]
```
if (B[Q] <= –N[Q]) {
  B[Q] = B[Q] + N[Q];
  if (C[Q] > MIN_C)
    C[Q] = C[Q – 1;
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
