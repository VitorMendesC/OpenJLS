# Timing Considerations

Notes on the fmax-limiting paths in OpenJLS and what has (and hasn't) moved them.
Target device for these measurements: `xczu7eg-fbvb900-1-e` (UltraScale+, speed grade
−1), Vivado 2025.2. The IP is vendor-agnostic, RTL-only: no pblocks, LOC, or
floorplanning, and clock/timing constraints are the integrator's concern.

Headline result (see the sweep below): with a congestion-aware implementation strategy
the core holds **~247–258 MHz across 4k–32k image widths**; with the default strategy it
runs **~232–244 MHz** and sags as the image (BRAM) grows.

## Methodology note: constrain hard to find the real fmax

P&R is timing-driven and **stops optimizing once WNS >= 0**. A loose clock therefore
hides the true speed — the tool closes with lazy placement and reports slack that
reflects the constraint, not the silicon. To find the real ceiling, over-constrain the
clock and read `fmax = 1000 / (period_ns − WNS_ns)`. Only WNS is trustworthy;
hand-computing `1 / data_path_delay` is optimistic because it ignores clock uncertainty,
skew, and setup.

**This is now demonstrated, not just asserted.** The earlier "~217 MHz wall" was probed
at 4 ns. Re-probed at 3 ns, the same design closes 232–258 MHz depending on
size/strategy — the loose 4 ns clock under-reported the ceiling by ~15–25 MHz because
P&R stopped early. Use a probe tighter than the expected fmax (we use **3 ns**); if a
point comes back WNS ≥ 0 the probe was too loose and the number is only a floor.

Use `report_timing -nworst 10 -unique_pins` — without `-unique_pins` the report can be
ten copies of the same path, hiding whether the worst path is a lone spike or a whole
cluster.

## fmax / resource characterization sweep

Reproducible sweep driving the existing `project_OpenJLS_tests` project in batch mode.

- **Scripts:** `Scripts/fmax_sweep.tcl` (harness), `Scripts/run_fmax_sweep.sh` (launches
  it via `vivado` on PATH), `Scripts/plot_fmax.py` (plots the CSV).
- **What is measured, per (size × strategy):**
  - **fmax** via single over-constrain at 3 ns → `1000 / (3.0 − WNS)` (WNS from the worst
    setup path after route). Every point is checked for WNS < 0 so the number is a real
    measurement, not a floor.
  - **Utilization:** LUTs, FFs, Block-RAM tiles (parsed from `report_utilization`). Full
    per-point `report_timing_summary` and `report_utilization` logs are saved alongside
    the CSV for provenance.
- **Matrix:** sizes `{4096, 8192, 12288, 16384, 32768}` (square, `MAX_IMAGE_WIDTH =
  MAX_IMAGE_HEIGHT`; this is the line-buffer-depth driver) × strategies `{Vivado
  Implementation Defaults, Performance_Explore, Congestion_SpreadLogic_high}` = 15 impl
  + 5 synth runs. BITNESS = 12.
- **Runtime:** **~57 minutes wall** for the full matrix (20 P&R runs, ~2.8 min/run) on a
  Ryzen 9 9900X with `-jobs 12`. Budget roughly `~3 min × (#impl + #synth)`.
- **Output:** `~/EDA/Logs/fmax_sweep.csv` + `fmax_vs_size.png`.

Results (fmax in MHz, all real — every point had WNS < 0 at the 3 ns probe):

| Size  | Defaults | Performance_Explore | **Congestion_SpreadLogic_high** | BRAM tiles | LUT  | FF   |
|-------|---------:|--------------------:|--------------------------------:|-----------:|-----:|-----:|
| 4096  | 243.9    | 238.7               | **258.0**                       | 1.5        | ~8.0k| ~2.1k|
| 8192  | 240.0    | 243.0               | **252.8**                       | 3          | ~8.0k| ~2.1k|
| 12288 | 243.5    | **248.5**           | 247.9                           | 4.5        | ~7.9k| ~2.1k|
| 16384 | 235.9    | 244.1               | **256.7**                       | 5.5        | ~8.0k| ~2.3k|
| 32768 | 232.2    | 212.8               | **247.5**                       | 11         | ~8.0k| ~2.3k|

Findings:
- **`Congestion_SpreadLogic_high` wins consistently** — best (or within 0.6 MHz) at all
  five sizes. The design is congestion-bound, so the strategy that deliberately spreads
  logic wins *everywhere*. This is a robust, repeatable gain, not placement luck.
- **`Performance_Explore` is erratic** — best at 12288 (248.5) but it *collapsed* at
  32768 (212.8, below even Defaults). Aggressive exploration can land badly on the
  largest/most-congested design. Do not headline a single-strategy peak.
- **With the congestion strategy fmax is ~flat over image size** (247–258); Defaults sags
  244 → 232 as BRAM grows.
- **Resources:** LUT/FF are essentially size-independent (the encoder logic is fixed; only
  counter widths grow by a bit). Only BRAM scales — 1.5 → 11 tiles, ~linear in width —
  because the line buffer is `DEPTH_G = MAX_IMAGE_WIDTH`.
- **Conservative numbers for a datasheet:** with `Congestion_SpreadLogic_high`,
  **fmax ≥ ~247 MHz across 4k–32k**; with default implementation plan for **~232 MHz**
  worst-case. Quote a guaranteed value, not the best cell.

## Current ceiling

- **byte_stuffer stage 3 is the structural limiter** (see deep-dive below). It is
  congestion/routing-bound, which is why a congestion-aware strategy lifts it ~15 MHz over
  default and why its absolute fmax is placement-sensitive.
- **Context RAM**: BRAM (`RAM_STYLE="block"`) and `"auto"` (LUTRAM) close within a few MHz
  of each other; the design sits on `"auto"`. ctx_ram surfaces as the worst path only when
  byte_stuffer happens to place well (see Placement sensitivity).
- The older single-run figures (BRAM ~219 MHz, byte_stuffer wall ~217 MHz) were 4 ns-probe
  numbers and are **superseded** by the 3 ns sweep above.

## The byte_stuffer stage-3 wall (the hard one)

Stage 3 (FF stuffer + emit) is a single combinational cycle with a **feedback loop on
the holding buffer** (`sStuffBuffer` + `sStuffBufferBits` bit-count). Each cycle it
refills from the skid buffer, runs the FF-equality precompute + the flattened 4-slot
stuff chain, picks an emit count, then **variable-shifts the whole buffer** by the
consumed bit count and feeds it back. All worst paths start at `sStuffBufferBits_reg`.

The key measured fact: **this path is routing-bound, not logic-bound.** At the wall it is
~64–66% routing, and the dominant cost is the wide, high-fanout variable (barrel) shift on
the buffer inside the recurrence — not the logic depth of the FF chain. The fix is to
shrink the buffer width (see "What DID help" below).

> Calibration note: the experiments in this section were probed at 4 ns, so their
> *absolute* MHz run ~15–25 MHz below the 3 ns sweep. The *relative* comparisons
> (what helped / hurt, by how much) remain valid.

### What was tried and did NOT help

1. **Byte-align the buffer** (split into byte-indexed buffer + 3-bit sub-byte offset, so
   the only sub-byte motion is a 0..7 shift on a 40-bit window). Logically sound and
   functionally correct (all TBs passed), but **regressed ~15 MHz**. It replaced one
   well-mapped 176-bit `shift_left` (which Vivado maps to an efficient F7/F8 mux cascade)
   with several poorly-mapped byte-positioned muxes, and chained the refill append
   (itself a 0..22 barrel) ahead of the cone. Net: more shifting, worse routing.

2. **Drop OUT_BYTES_PER_CYCLE 4 -> 3** (shortens the serial FF chain; 24 bits/cycle still
   exceeds the worst-case sustained ~18 bits/cycle for 16-bit pixels, so throughput stays
   positive). Did exactly what it promised to logic — **levels 15-16 -> 12-13, logic
   delay 1.68 -> ~1.4 ns** — but **regressed** because routing rose to 70-74%. Cutting
   logic off a routing-bound path gives the router less slack to hide wires in; the buffer
   barrel-shift net was untouched.

### Why logic reduction can't fix it

The buffer recurrence is routing-bound on a wide feedback net. Reducing logic depth
(byte-align, fewer lanes) cannot move a path whose cost is ~70% wires. Confirmed twice.

### What DID help: narrow the buffer

The lever that worked was cutting the *width* of the routing-bound nets, not their logic
depth. The hold buffer was `2*FIFO_BYTES`; the deadlock floor is `FIFO_BYTES + 1` (one
FIFO pop plus 1 byte of headroom so a refill can land when only a sub-byte remainder is
left). Shrinking it narrows the consume-shift and refill nets directly (~7 MHz at the
4 ns probe), and the refill and consume sides become co-critical.

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
  half-cone gets a full clock. This is the only *deterministic* fix (it removes the
  placement-sensitivity, unlike picking a lucky strategy), but it halves throughput to 2
  bytes/cycle (still well above the ~0.46 bytes/cycle average load) and the speculative
  1-cycle variant (carry-select) blows up because both `prevFF` (2) **and** the read
  position `bitOffset` (8) are loop-carried — ~16-way precompute. Rejected for now:
  complexity / throughput cost vs. uncertain gain, given the congestion strategy already
  holds ~250 MHz.
- **pblock / floorplanning**: would compact placement and cut routing, but violates the
  vendor-agnostic, RTL-only constraint. Out of scope.

## Placement sensitivity: the wall is congestion-bound (resolved by strategy)

The stage-3 wall is **routing/congestion-bound (~66% wires)**, so its WNS is set by *where
the tool places things*, not by its (fixed) logic. This first showed up as a confusing
single-run A/B: same flow (4 ns probe, default strategy), flipping only
`MAX_IMAGE_WIDTH/HEIGHT`:

| Geometry | WNS       | Worst path                                    | Block RAM tiles | Distributed-RAM LUTs |
|----------|-----------|-----------------------------------------------|-----------------|----------------------|
| 4096     | −0.554 ns | `byte_stuffer/byte_valid_fifo → sLastPending` | 1.5 (1×RAMB36)  | 324                  |
| 12288    | −0.026 ns | `ctx_ram/sUseInitReg`                         | 4.5 (4×RAMB36)  | 324                  |

Mechanism (why "bigger looked faster" — it is not a real speedup):
- byte_stuffer has **zero dependence** on `MAX_IMAGE_WIDTH` (generics are `LIMIT`/`OUT_BYTES`/
  `BURST_DEPTH=16`) — its netlist is byte-identical in both runs. ctx_ram is `depth=367`
  (fixed). Distributed-RAM LUTs are 324 in both, so there is **no BRAM↔LUTRAM flip**.
- The *only* physical difference is the line buffer (`olo_base_fifo_sync`, `DEPTH_G =>
  MAX_IMAGE_WIDTH`, 12 b wide): 4096→12288 triples its depth, adding **+3 RAMB36**.
- BRAMs sit in fixed columns and pull memory-attached logic toward them. At 1.5 tiles the
  memory-adjacent logic crowds 1–2 BRAM columns → local congestion, and the routing-bound
  byte_stuffer sideband-FIFO path is a *victim* of it. Spreading the line buffer over 4–5
  columns relieves that knot and the path incidentally routes clean. Bigger footprint did
  not give the tool "more freedom"; it forced a spread that de-congested an unrelated net.

**Resolution (from the sweep):** the swing was strategy/placement-dependent, and
`Congestion_SpreadLogic_high` — which deliberately spreads logic — captures the de-congestion
*on purpose and repeatably* across all sizes (247–258 MHz). So:
- The gain **is** bankable, but only with a congestion-aware strategy, not by accident and
  not by inflating the image size.
- **Do not inflate `MAX_IMAGE_WIDTH` to buy timing** — you pay 3× the line-buffer BRAM
  (4 RAMB36 vs 1) for a one-off placement fluke. Size it to the real max image.
- For a *placement-independent* ceiling (vs. relying on the synthesiser/strategy), the
  stage-3 pipeline split above is still the real fix.
