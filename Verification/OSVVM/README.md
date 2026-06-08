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
├── build_osvvm.sh      # one-time: compile vendored OSVVM into ./osvvm-lib
├── build_run.sh        # per-run: compile deps + all TBs, elaborate+run one by name
├── Support/tb_support_pkg.vhd   # shared helpers (clk_tick, apply_reset, end_of_test)
├── Modules/tb_*_osvvm.vhd       # one TB per module
└── Top/tb_openjls_top_osvvm.vhd # top-level stress TB
```

OSVVM itself is vendored under `ThirdParty/osvvm/` (see the `osvvm-build-run`
project note). A fresh checkout runs `./build_osvvm.sh` once.

## Running

```bash
./build_run.sh tb_a5_osvvm                           # build everything, run one TB
./build_run.sh tb_byte_stuffer_osvvm -gIN_WIDTH=64   # pass a generic
```

`build_run.sh` recompiles the OpenLogic base, the RTL sources, the support
package, and every TB in `Modules/` and `Top/` on each invocation, then
elaborates and runs the named TB.

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
ReportAlerts;
if GetAlertCount(FAILURE) + GetAlertCount(ERROR) = 0 then
  report test_name & ": PASS";
else
  report test_name & ": FAIL" severity failure;
end if;
std.env.stop;
```

A failing `AffirmIf` raises an ERROR → the count is nonzero → `end_of_test`
reports FAIL. Reference: `Modules/tb_a5_osvvm.vhd`.

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
*combinations*, not merely whether it passed. Each TB builds a `CovPType` model,
records hits during the run, and asserts the model is fully covered at the end:

```vhdl
cov.AddBins("branch", GenBin(0, 2, 3));         -- 3 bins for values 0,1,2
cov.AddCross("sign x region",                   -- cross-product of two axes
             GenBin(0, 1, 2), GenBin(0, 2, 3)); -- 2 x 3 = 6 bins
...
cov.ICover(branch_value);                       -- record a hit
cov.ICover((sign_value, region_value));         -- record a cross hit
...
exit when cov.IsCovered and i > 200;            -- stop once every bin is hit
cov.WriteBin;                                   -- print the bin table
AffirmIf(cov.IsCovered, "coverage closed");     -- FAIL if any bin was never hit
```

`IsCovered` is true once every bin has been hit (default at-least-once); the
random loops therefore run "until covered" rather than for a fixed count, and a
TB only passes if the stimulus reached every interesting case. Examples:
`tb_a5_osvvm` (three branches), `tb_a6_osvvm` (sign × saturation-region cross),
`tb_a15_a16_osvvm` (terminal type, immediate break, EOI, RUNindex range).

### ScoreboardPkg_slv — order-checking for streams

Modules that emit a stream are checked with a scoreboard — a FIFO of expected
values the driver pushes and the monitor checks in order:

```vhdl
sb.Push(expected_byte);              -- driver enqueues expected
sb.Check(observed_byte);             -- monitor dequeues and compares
AffirmIf(sb.Empty, "scoreboard drained");
AffirmIfEqual(sb.GetErrorCount, 0, "no mismatches");
```

A `Check` mismatch raises an alert and increments `GetErrorCount`. Used by
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
