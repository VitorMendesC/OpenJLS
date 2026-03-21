# Top-Level Integration Design Notes

## Pipeline Record Approach

The top-level encoder uses a single VHDL record type to carry all signals through every pipeline stage. Both the regular mode and run-interruption mode fields live in the same record, accompanied by a `mode` tag. Downstream stages gate on the tag to select which fields are meaningful.

**Benefits:**
- All data is inherently time-aligned — no delay lines needed to match path latencies.
- Synthesis prunes unused fields per stage, so resource cost is minimal.
- Stages are easy to add or reorder without recalculating relative delays.
- The Golomb encoder (A11.1/A11.2) is shared between both modes naturally.

The record type should be defined in `Common.vhd`. Each pipeline stage passes the record forward, modifying only the fields it owns.

---

## Run Mode: Pre-Stage and Run Controller

**Problem:** A14 is variable-length — an unknown number of samples must be absorbed before the run ends. This cannot be a pipeline stage.

**Solution:** Two components sit upstream of the pipeline.

### Stage 0: A1/A2/A3 registered pre-stage

A1 (gradients), A2/A3 (mode check) run combinationally from the line buffer output and are **registered before the run controller**. The run controller only ever reads settled values — its combinational logic is purely decision logic with no arithmetic.

### Run controller (one pixel per cycle, always)

This is **not** a traditional FSM. A traditional FSM can sit in a state for multiple cycles without consuming input. The run controller processes exactly one pixel every cycle — every clock edge either absorbs a run pixel or injects a token into the pipeline. There are no wait states.

It is a clocked process with registered state `(in_run, RUNcnt, RUNindex, next_boundary, RUNval)` and purely combinational output logic:

```
each cycle — reads registered state + registered pre-stage outputs:

  if in_run:
    if run_continues (|Ix - RUNval| <= NEAR):
      RUNcnt++
      if RUNcnt == next_boundary:                               ← boundary check every cycle
        emit '1' bit, RUNindex++, next_boundary += 2^J[RUNindex]
      pixel absorbed
    else:
      emit A16 bits to bit packer
      inject run-interruption token (Ix, Ra, Rb) to pipeline    ← pixel consumed as token
      clear run state

  else (not in_run):
    if mode_is_run (D1=D2=D3=0):
      RUNval=Ra, RUNcnt=1, enter in_run
      if 1 == next_boundary:                                    ← boundary check for first pixel too
        emit '1' bit, RUNindex++, next_boundary += 2^J[RUNindex]
      pixel absorbed
    else:
      inject regular token to pipeline                           ← pixel consumed as token
```

Every branch consumes the input pixel. Nothing waits.

The run controller owns:
- **Run accumulation (A14)** — pixels consumed at full rate, RUNcnt increments
- **A15/A16 + RUNindex** — handled internally (see below), never touches the pipeline
- **Run bit output** — streamed directly to the bit packer

At run end it injects one token: a **run-interruption token** carrying Ix, Ra, Rb for A17–A23.

### RUNindex: incremental tracking

RUNindex must be updated sequentially across runs — the decoder maintains the same counter and both sides must agree. Putting RUNindex in the pipeline would require forwarding or stalls between consecutive runs.

Instead, RUNindex lives only in the FSM as a register, updated incrementally **during accumulation**. The FSM maintains a `next_boundary` register alongside it:

```
each pixel cycle during a run:
  RUNcnt++
  if RUNcnt == next_boundary:
    emit '1' bit to bit packer          ← A15 output, streamed live
    RUNindex++
    next_boundary += 2^J[RUNindex]      ← one J-table lookup
```

Each cycle costs one equality check, one table lookup, one add — 3–4 LUT levels. The 32-iteration A15 loop is dissolved: each iteration happens in the natural pixel cycle it corresponds to, amortised to zero overhead.

By the time the run breaks, RUNindex is already at its post-A15 value and all `1` bits have been emitted. A16 at run end is then trivial:

```
if break (|Ix - RUNval| > NEAR):
  emit '0' bit
  emit lower J[RUNindex] bits of RUNcnt   ← wire extraction, no logic
  RUNindex--
else (EOLine, RUNcnt > 0):
  emit '1' bit
```

No unrolled loop, no stall, no global register.

---

## Context RAM Hazard: Read-After-Write

**Problem:** The context RAM stores A[Q], B[Q], C[Q], N[Q] indexed by context Q. If two consecutive samples share the same context Q, the second sample's RAM read returns stale values because the first sample's write-back (A12/A13) has not yet committed.

### What the existing feed-forward does and does not solve

`context_ram` already implements a combinational feed-forward:
```vhdl
oRdData <= iWrData when ((iWrEn and iRdEn) = '1' and iWrAddr = iRdAddr) else sRamRdData;
```
This mux intercepts the registered RAM output and replaces it with the **current-cycle** write data when both read and write target the same address **on the same clock cycle**.

In a pipeline of depth D, at cycle T+D sample N's write-back and sample N+D's read can coincide on the same address. The feed-forward correctly handles this case — samples that are **exactly D cycles apart** sharing Q get the right updated values.

What it does **not** cover: samples N+1, N+2, ..., N+D-1 that share Q_N. Their reads happen at T+1 through T+D-1 — before the write-back at T+D — so the feed-forward never fires for them. **The hazard window is D-1 cycles wide**, and those cases still need stall or forwarding logic.

### D = 1: the correct architecture for lossless mode

For the feed-forward to cover every consecutive same-context pair, sample N's write-back must land in the **same cycle** as sample N+1's read. That requires the entire update path — A5/A6 → A7 → A8/A9 → A12 → A13 — to be purely combinational within one clock period (D = 1).

This is feasible for all practical NEAR values. `C_ERR_SCALE = 2*NEAR+1` is a generic-derived constant; synthesis resolves the multiply at elaboration time and implements it as shifts and adds (constant-coefficient multiplier). No DSP is ever inferred. The full update path (A5 → A6 → A7 → A9 → A12 → A13) is pure adder/comparator logic regardless of NEAR, achievable at 200+ MHz.

### Timing diagram for D = 1 (lossless)

```
Cycle T:   iRdAddr = Q_N
Cycle T+1: sRamRdData = old values for Q_N     (registered, 1-cycle latency)
           A5/A6/A7/A9/A12/A13 run (combinational)  → iWrData = new values
           iWrAddr = Q_N, iWrEn = '1'               (write-back, same cycle T+1)
           iRdAddr = Q_{N+1}                         (next sample reads)
           ↳ if Q_{N+1} = Q_N: feed-forward fires → oRdData = iWrData  ✓
Cycle T+2: sample N+1 pipeline stage runs with correct values
```

The feed-forward in `context_ram` was designed for exactly this. No stalls, no forwarding buffers. **The coding path (A10 → A11 → A11.1/A11.2) is independent** — it carries A[Q], B[Q], N[Q] from the pipeline record and can span as many registered stages as needed without touching the hazard.

---

## Overall Pipeline Structure

```
pixel input (Ix, Ra, Rb, Rc, Rd from line_buffer)
        ↓
  [A1/A2/A3 — combinational, registered output]
  D1, D2, D3, mode_is_run
  [|Ix - RUNval| <= NEAR — separate comparator, registered alongside, uses RUNval from run controller state]
  run_continues
        ↓
  [Run controller — one pixel per cycle, always]
     registered state: in_run, RUNcnt, RUNindex, next_boundary, RUNval
     run accumulation: RUNcnt++, incremental RUNindex tracking
     A15/A16 bits streamed live to bit packer
     on break: inject run-interruption token only
  ─────────────────────────────────────────────────────────────────────┘
        │ regular tokens and run-interruption tokens only
        ↓
  Stage: A4/A4.1/A4.2 — quantization + Q mapping     (regular)
         A17           — RItype computation            (interruption)
        ↓
  Stage: context_ram READ — A[Q], B[Q], C[Q], N[Q]
        ↓
  Stage: A5/A6/A7/A8/A9/A12/A13 — update path (combinational, D=1)
         A8 is identity for NEAR=0 (no logic, wire-through)
         A18/A19/A23            — run-interruption prediction, error, update
         → context_ram WRITE (same cycle as READ of next sample)
         Note: A23 writes indices 365/366; same D=1 constraint applies for
         consecutive interruption tokens sharing RItype.
        ↓
  Stage: A10 / A20/A20.1 — Golomb k computation (shared hardware)
        ↓
  Stage: A11  — error mapping                         (regular)
         A21/A22 — EMErrval mapping                   (interruption)
        ↓
  Stage: A11.1/A11.2 — Golomb encoder + bit packer   (shared)
        ↓
  byte_stuffer → jls_framer → AXI4-Stream output
```

---

## AXI4-Stream Interface Notes

- **Input:** One sample per cycle when ready/valid handshake is asserted. The run controller consumes pixels at full rate during run accumulation. No stall occurs.
- **Output:** Downstream of `jls_framer`, standard AXI4-Stream with `tlast` marking end of image (driven by `jls_framer.oLast`).
- Image dimensions (`iImageWidth`, `iImageHeight`) and encoding parameters (`NEAR`, `BITNESS`) are static per image, latched at the start pulse.
