# Timing Considerations

Notes on the fmax-limiting paths in OpenJLS and what has (and hasn't) moved them.
Target device for these measurements: `xczu7eg-fbvb900` (UltraScale+), 4 ns / 250 MHz
constraint used as a probe. The IP is vendor-agnostic, RTL-only: no pblocks, LOC,
or floorplanning, and clock/timing constraints are the integrator's concern.

## Methodology note: constrain hard to find the real fmax

P&R is timing-driven and **stops optimizing once WNS >= 0**. A loose clock therefore
hides the true speed — the tool closes with lazy placement and reports slack that
reflects the constraint, not the silicon. To find the real ceiling, over-constrain the
clock (e.g. ask for 250 MHz) and read `fmax = T_constraint - WNS`. Only WNS is
trustworthy; hand-computing `1 / data_path_delay` is optimistic because it ignores
clock uncertainty, skew, and setup.

Use `report_timing -nworst 10 -unique_pins` — without `-unique_pins` the report can be
ten copies of the same path, hiding whether the worst path is a lone spike or a whole
cluster.

## Current ceiling

- **Context RAM**: BRAM (`RAM_STYLE="block"`) closed ~219 MHz; `"auto"` maps to LUTRAM
  and closes ~213 MHz. The difference is minor; the design sits on `"auto"`.
- **byte_stuffer stage 3 is the wall**, ~**217 MHz** (WNS -0.614 ns @ 4 ns) after
  narrowing the hold buffer (see below). Was ~210 MHz (WNS -0.746) at the old buffer size.

## The byte_stuffer stage-3 wall (the hard one)

Stage 3 (FF stuffer + emit) is a single combinational cycle with a **feedback loop on
the holding buffer** (`sStuffBuffer` + `sStuffBufferBits` bit-count). Each cycle it
refills from the skid buffer, runs the FF-equality precompute + the flattened 4-slot
stuff chain, picks an emit count, then **variable-shifts the whole buffer** by the
consumed bit count and feeds it back. All worst paths start at `sStuffBufferBits_reg`.

The key measured fact: **this path is routing-bound, not logic-bound.** At the wall it is
~64% routing, and the dominant cost is the wide, high-fanout variable (barrel) shift on
the buffer inside the recurrence — not the logic depth of the FF chain. The fix is to
shrink the buffer width (see "What DID help" below).

### What was tried and did NOT help

1. **Byte-align the buffer** (split into byte-indexed buffer + 3-bit sub-byte offset, so
   the only sub-byte motion is a 0..7 shift on a 40-bit window). Logically sound and
   functionally correct (all TBs passed), but **regressed to ~202 MHz (WNS -0.938)**. It
   replaced one well-mapped 176-bit `shift_left` (which Vivado maps to an efficient
   F7/F8 mux cascade) with several poorly-mapped byte-positioned muxes, and chained the
   refill append (itself a 0..22 barrel) ahead of the cone. Net: more shifting, worse
   routing.

2. **Drop OUT_BYTES_PER_CYCLE 4 -> 3** (shortens the serial FF chain; 24 bits/cycle still
   exceeds the worst-case sustained ~18 bits/cycle for 16-bit pixels, so throughput stays
   positive). Did exactly what it promised to logic — **levels 15-16 -> 12-13, logic
   delay 1.68 -> ~1.4 ns** — but **regressed to ~202 MHz (WNS -1.22)** because routing
   rose to 70-74%. Cutting logic off a routing-bound path gives the router less slack to
   hide wires in; the buffer barrel-shift net was untouched.

### Why logic reduction can't fix it

The buffer recurrence is routing-bound on a wide feedback net. Reducing logic depth
(byte-align, fewer lanes) cannot move a path whose cost is ~70% wires. Confirmed twice.

### What DID help: narrow the buffer

The lever that worked was cutting the *width* of the routing-bound nets, not their logic
depth. The hold buffer was `2*FIFO_BYTES`; the deadlock floor is `FIFO_BYTES + 1` (one
FIFO pop plus 1 byte of headroom so a refill can land when only a sub-byte remainder is
left). Shrinking it narrows the consume-shift and refill nets directly: ~210 -> ~217 MHz,
worst-path routing 2.97 -> ~2.7 ns. After this the refill and consume sides are
co-critical (the cluster spans WNS -0.596 to -0.614).

Sizing rationale (`HOLD_BYTES = FIFO_BYTES + 1`):
- `FIFO_BYTES` derives from LIMIT, so it scales with bitness (8b->4, 12b->6, 16b->8);
  HOLD is 5/7/9 bytes respectively. No hardcoding.
- Headroom is always 8 bits >= the worst 7-bit sub-byte remainder, for any bitness, so
  the deadlock floor holds everywhere. Stuffing needs no room (buffer holds pre-stuff
  bits; a stuffed byte consumes only 7).
- Throughput at the floor: peak drops below OUT_BYTES_PER_CYCLE for buffer sizes that
  aren't a clean multiple of the emit width (12b: ~3 B/cyc; 16b: full 4 B/cyc), but all
  cases stay far above the ~0.46 B/cyc average load and the stage-2 FIFO absorbs bursts.
  `FIFO_BYTES + OUT_BYTES_PER_CYCLE` would guarantee peak for any bitness, at the cost of
  wider nets (gives back some of the timing win).

### What WOULD move it (and why we didn't)

- **Pipeline the loop (2-cycle cadence)**: split the recurrence across a register so each
  half-cone gets a full clock. This is the real fix, but it halves throughput to 2
  bytes/cycle (still well above the ~0.46 bytes/cycle average load) and the speculative
  1-cycle variant (carry-select) blows up because both `prevFF` (2) **and** the read
  position `bitOffset` (8) are loop-carried — ~16-way precompute. Rejected: complexity /
  throughput cost vs. uncertain gain.
- **pblock / floorplanning**: would compact placement and cut routing, but violates the
  vendor-agnostic, RTL-only constraint. Out of scope.

## Other notes

- The `framer -> byte_stuffer` boundary (`sFifoByteCount -> sHold`) was the wall in an
  earlier BRAM configuration (~219 MHz). It has since been subsumed by the stage-3 buffer
  recurrence above.
- Spaced-out placement seen in the floorplan is just the sparse design (~3.5% LUT) with a
  non-critical net stretched between two BRAM blobs — cosmetic, since timing is met; a
  pblock would compact it but is out of scope.
