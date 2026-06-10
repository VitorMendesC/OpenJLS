# OpenJLS OSVVM verification

This directory holds the OSVVM testbench suite: one TB per RTL module
(`Modules/`) plus a top-level control-plane stress TB (`Top/`). This document
records how the suite is organised and which OSVVM facilities each testbench
relies on, with pointers into the actual files.

OSVVM is a pure-VHDL verification library (no SystemVerilog; runs on GHDL). The
suite uses four parts of it: **AlertLog** for assertions with pass/fail
accounting, **RandomPkg** for constrained-random stimulus, **CoveragePkg** for
functional coverage, and **ScoreboardPkg** for order-checking streamed output.
Each is described below as it is used here.

---

## Layout

```
Verification/OSVVM/
├── build_osvvm.sh      # one-time: compile vendored OSVVM into ./osvvm-lib (fast flow)
├── build_run.sh        # fast flow: compile deps + all TBs, elaborate+run one by name
├── build_reports.sh    # script flow: full regression + YAML -> HTML reports (needs tcl)
├── OpenJls.pro         # OSVVM build script: library/analyze/TestSuite/RunTest
├── Support/tb_support_pkg.vhd   # shared helpers (clk_tick, apply_reset, end_of_test)
├── Modules/tb_*_osvvm.vhd       # one TB per module
└── Top/tb_openjls_top_osvvm.vhd # top-level stress TB
```

OSVVM itself is vendored under `ThirdParty/osvvm/`, and the OSVVM tcl script
flow under `ThirdParty/osvvm-scripts/`, both pinned to the same release (see
`ThirdParty/fetch_third_party.sh`). A fresh checkout runs `./build_osvvm.sh`
once for the fast flow; the script flow builds its own libraries.

## Running

Two flows over the same TBs:

### Fast flow — one TB, plain GHDL, no tcl

```bash
./build_run.sh tb_a5_osvvm                           # build everything, run one TB
./build_run.sh tb_byte_stuffer_osvvm -gIN_WIDTH=64   # pass a generic
```

`build_run.sh` recompiles the OpenLogic base, the RTL sources, the support
package, and every TB in `Modules/` and `Top/` on each invocation, then
elaborates and runs the named TB from `sim-out/` (scratch, gitignored).

### Script flow — full regression with HTML reports

```bash
./build_reports.sh        # requires tclsh only (Arch: sudo pacman -S tcl);
                          # the tcllib modules it needs are in ThirdParty/tcllib
```

This is "the OSVVM intended way": `OpenJls.pro` drives the vendored tcl
scripts (`build` → `library`/`analyze`/`TestSuite`/`RunTest`), every TB's
`end_of_test` emits YAML via `EndOfTestReports`, and the scripts render it to
HTML. Outputs (all gitignored, in this directory):

- `index.html` — report index, linking each build's summary
- `OSVVM_OpenJls/OSVVM_OpenJls.html` — build summary with one row per test
  (suite, status, alert counts, functional coverage %, links)
- `OSVVM_OpenJls/reports/<suite>/<test>.html` — per-test detail: alert tree,
  every coverage model's bin table, scoreboard stats
- `OSVVM_OpenJls/logs/` — per-test simulate transcripts; `VHDL_LIBS/` —
  compiled libraries (incremental between runs)

Note: GHDL analysis must be warning-clean under this flow (tcl's `exec`
treats any stderr output as a failure), hence the `-Wno-shared` and
`-Wno-elaboration` flags in `OpenJls.pro`.

`RunTest Modules/tb_a5_osvvm.vhd` = analyze the file + simulate the entity
named like it + register the result under the current `TestSuite`. The two
flows share sources but compile into separate library trees; keep the file
lists in `build_run.sh` and `OpenJls.pro` in sync.

### Reading the output

A passing run ends with:

```
%%  205 ns    DONE   PASSED   tb_a5_osvvm  Passed: 209  Affirmations Checked: 209
... tb_support_pkg.vhd:63 (report note): tb_a5_osvvm: PASS
```

`Affirmations Checked` is the number of checks that ran; `Passed` is how many
passed. A failure looks like:

```
%%  211 ns    Alert  ERROR   <the message that was passed to the check>  Received : 20  Expected : 0
%% 2231 ns    DONE   FAILED   tb_..._osvvm  Total Error(s) = 1 ...
./tb_..._osvvm:error: simulation failed
```

Each failing check prints an `Alert ERROR` line carrying its message, which
localises it. The run then reports `FAILED` and exits nonzero (what the
regression sweep keys on).

---

## OSVVM facilities used in the suite

### AlertLog — assertions and pass/fail accounting

Checks are written as `AffirmIf(condition, "msg")` and
`AffirmIfEqual(actual, expected, "msg")` (overloaded for `integer`,
`std_logic_vector`, `unsigned`, …). A failing check raises an ERROR alert
carrying its message; `AffirmIfEqual` additionally logs `Received`/`Expected`.
Each TB names itself with `SetAlertLogName(...)` and calls
`SetLogEnable(PASSED, FALSE)` to suppress per-pass logging so only failures and
the summary print. The watchdog processes use `Alert("msg", FAILURE)` to fail on
timeout.

The PASS/FAIL decision lives in `Support/tb_support_pkg.vhd::end_of_test`:

```vhdl
errors := EndOfTestReports;   -- ReportAlerts + YAML for the script flow
if errors = 0 then
  report test_name & ": PASS";
else
  report test_name & ": FAIL" severity failure;
end if;
std.env.stop;
```

`EndOfTestReports` (ReportPkg) prints the same alert summary `ReportAlerts`
would, returns the total error count, and additionally writes the per-test
YAML (alerts, every registered coverage model, scoreboards) that
`build_reports.sh` turns into HTML. A failing `AffirmIf` raises an ERROR →
the count is nonzero → `end_of_test` reports FAIL. Reference:
`Modules/tb_a5_osvvm.vhd`.

### RandomPkg — constrained-random stimulus

Stimulus is generated from a `RandomPType` object seeded deterministically
(`rv.InitSeed(rv'instance_name)`), so every run — including a failing one — is
reproducible. The suite uses:

```vhdl
rv.RandInt(lo, hi)                  -- uniform integer in [lo, hi]
rv.RandSlv(WIDTH)                   -- random std_logic_vector
rv.RandUnsigned(WIDTH)              -- random unsigned
rv.DistValInt(((1, 20), (0, 80)))  -- weighted: 1 about 20%, 0 about 80%
```

`DistValInt` biases rare events so they occur often enough to test — e.g. the
all-zero run-mode case in `tb_a3_osvvm`, or extra backpressure in
`tb_byte_stuffer_osvvm`.

### CoveragePkg — functional coverage

Functional coverage records whether the stimulus exercised the interesting
*combinations*, not merely whether it passed. Each TB creates a coverage model
in OSVVM's global coverage store (`CoverageIDType` + `NewID` — the singleton
API), records hits during the run, and asserts the model is fully covered at
the end:

```vhdl
variable cov : CoverageIDType;
...
cov := NewID("branch");                            -- register in the singleton
AddBins(cov, GenBin(0, 2, 3));                     -- 3 bins for values 0,1,2
AddCross(cov, GenBin(0, 1, 2), GenBin(0, 2, 3));   -- 2 x 3 = 6 cross bins
...
ICover(cov, branch_value);                         -- record a hit
ICover(cov, (sign_value, region_value));           -- record a cross hit
...
exit when IsCovered(cov) and i > 200;              -- stop once every bin is hit
WriteBin(cov);                                     -- print the bin table
AffirmIf(IsCovered(cov), "coverage closed");       -- FAIL if any bin never hit
```

`IsCovered` is true once every bin has been hit (default at-least-once); the
random loops therefore run "until covered" rather than for a fixed count, and a
TB only passes if the stimulus reached every interesting case. Because the
models live in the global store (unlike the older `CovPType` protected type),
`EndOfTestReports` finds them automatically and they appear in the per-test
HTML coverage tables. Examples: `tb_a5_osvvm` (three branches), `tb_a6_osvvm`
(sign × saturation-region cross), `tb_a15_a16_osvvm` (terminal type, immediate
break, EOI, RUNindex range).

### Intelligent Coverage — coverage-driven randomization

Uniform random closes a sparse cross slowly: the last uncovered bin is hit
with probability 1/N per pass (the coupon-collector tail). Intelligent
Coverage inverts the loop — instead of randomizing stimulus and recording
what it happened to hit, ask the coverage model for a random *uncovered* bin
and drive exactly that scenario:

```vhdl
while not IsCovered(covSweep) loop
  pt := RandCovPoint(covSweep);   -- integer_vector: one value per cross axis
  -- drive the scenario encoded by pt(1), pt(2), pt(3) ...
  ICover(covSweep, pt);           -- mark it covered
end loop;
```

An N-bin cross closes in exactly N passes. The top TB's Phase A sweep uses
this over `(backpressure x input-stall x prelude)` — see
`Top/tb_openjls_top_osvvm.vhd`; its `WriteBin` table shows every bin with
`Count = 1`, the signature of coverage-driven selection.

### ScoreboardPkg_slv — order-checking for streams

Modules that emit a stream are checked with a scoreboard — a FIFO of expected
values the driver pushes and the monitor checks in order. Like coverage, the
scoreboard is registered in a global store so reports find it:

```vhdl
constant SB_ID : ScoreboardIDType := NewID("framer SB");
...
Push(SB_ID, expected_byte);          -- driver enqueues expected
Check(SB_ID, observed_byte);         -- monitor dequeues and compares
AffirmIf(IsEmpty(SB_ID), "scoreboard drained");
AffirmIfEqual(GetErrorCount(SB_ID), 0, "no mismatches");
```

A `Check` mismatch raises an alert and increments the error count; the
per-test HTML shows the scoreboard's check/error totals. Used by
`tb_jls_framer_osvvm` (expected stream = `header ++ payload ++ FF D9`) and
`tb_byte_stuffer_osvvm`.

### tb_support_pkg — shared helpers

`Support/tb_support_pkg.vhd` provides `clk_tick(clk, n)` (wait n edges),
`apply_reset(clk, rst, n, active)` (pulse reset for n edges then release), and
`end_of_test(name)` (summary + PASS/FAIL + stop). Note: `apply_reset`'s trailing
edge re-latches whatever inputs are still driven, so the TBs idle their inputs
before it when checking a cleared output.

---

## Testbench structure

Combinational module TBs (e.g. `tb_a5_osvvm`) follow one shape: instantiate the
DUT; define a reference function transcribed from the **T.87 C model** in
`Docs/Project.md`; run directed corner cases, then a constrained-random sweep
checking each vector with `AffirmIfEqual(dut_output, reference(inputs))`; close
functional coverage; `end_of_test`.

Stateful module TBs (e.g. `tb_a15_a16_osvvm`, `tb_byte_stuffer_osvvm`) are
transaction-level: they drive a whole transaction (a run, an image), collect the
output, and compare it against the reference for that transaction — using a
scoreboard for streamed output and a clock plus `apply_reset`.

### Reference models come from the spec, not the RTL

Every reference is derived from the T.87 C model in `Docs/Project.md` (code
segments A.1–A.23), not from `Sources/*.vhd`, so an RTL bug cannot appear on both
sides and pass. Where T.87 leaves something open (e.g. the A.4.2 context map) the
TB checks the required properties (range, one-to-one, totality). Where the RTL
adds non-spec behaviour (e.g. the A.22 clamp) the TB tests only the domain T.87
reaches and asserts the skipped domain is genuinely unreachable per T.87.

### Reset coverage

Each stateful TB checks that asserting `iRst` drives the outputs/state to their
defined reset values, and that a reset injected mid-operation recovers cleanly
(the next transaction is correct from scratch). The scoreboard-based TBs use an
`sIgnore` signal so the monitor skips the aborted transaction's output (which is
never pushed to the scoreboard); the recovery transaction then runs normally. The
top-level TB injects mid-image reset end-to-end.

---

## References

- OSVVM documentation: <https://github.com/OSVVM/Documentation> (per-package user
  guides for AlertLogPkg, RandomPkg, CoveragePkg, ScoreboardPkg).
- Smallest worked examples in this suite: `Modules/tb_a5_osvvm.vhd`
  (combinational + coverage), `Modules/tb_a11_2_osvvm.vhd` (clocked + reset +
  stall), and `Modules/tb_jls_framer_osvvm.vhd` (driver/monitor/scoreboard).
