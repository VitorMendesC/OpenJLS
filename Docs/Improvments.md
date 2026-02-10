# Testbench Improvement Notes (Backlog)

This document captures improvements to strengthen T.87 compliance coverage in the current testbench suite. It reflects the findings from a review of the existing tests and focuses on gaps that can be addressed later.

## 1) Over‑constrained vs T.87 (Project‑Specific Behavior)
- `Testbenches/tb_A4_2.vhd` enforces a *specific* mapping function for A.4.2.
  - T.87 only requires that the mapping is one‑to‑one and produces values in [0..364]. The exact mapping is *unspecified*.
  - Current test will fail for any other valid mapping, even if compliant.
  - Improvement: either relax the test to validate only one‑to‑one and range constraints, or explicitly document that the mapping is a project‑specific choice and not a T.87 requirement.

## 2) Tests Coupled to `Common.vhd` Constants
- Several tests use constants (LIMIT, QBPP, RESET, J‑table, etc.) from `Common.vhd` which the RTL also uses.
  - If `Common.vhd` constants are wrong vs T.87, these tests will still pass because they check against the same values.
  - Affected tests: `tb_A10.vhd`, `tb_A11_1.vhd`, `tb_A12.vhd`, `tb_A13.vhd`, `tb_A20.vhd`, `tb_A21.vhd`, `tb_A23.vhd`.
  - Improvement: for critical constants derived from T.87, recompute them independently inside the testbench or include reference values derived from T.87 formulas and compare.

## 3) Limited Coverage / Only Single‑Step Checks
- Some tests validate only a single step of a `while` loop or a single run segment transition.
  - Examples: `tb_A14.vhd`, `tb_A15.vhd`, `tb_A16.vhd`.
  - This is acceptable for a combinational slice, but does not validate the iterative behavior implied by the code segments.
  - Improvement: add multi‑step or loop‑accumulation tests that repeatedly apply the RTL block and compare against the full T.87 loop behavior.

## 4) Shallow Directed‑Only Coverage
- Several tests rely only on a few directed cases without randomized or boundary sweeps.
  - Examples: `tb_A1.vhd`, `tb_A3.vhd`, `tb_A17.vhd`, `tb_A20.vhd`, `tb_A21.vhd`, `tb_A22.vhd`, `tb_A23.vhd`.
  - Improvement: add randomized coverage or systematic boundary sweeps for each dimension.

## 5) Written Requirements Not Explicitly Tested
- T.87 written requirements that are not covered by the current tests:
  - A.20.1 (Golomb `k` computed using TEMP and A.10 logic).
  - A.22.1 (EMErrval encoding with `glimit = LIMIT − J[RUNindex] − 1`).
  - Improvement: create dedicated tests for these requirements to validate end‑to‑end compliance.

## 6) Bit‑Packer / Stream‑Level Behavior (A.11.2)
- `tb_A11_2.vhd` uses a hard‑coded expected sequence of output words.
  - The values are correct for the chosen inputs, but the test is limited:
    - No flush behavior is verified.
    - No wrap‑around or buffer edge conditions.
    - No backpressure/ready‑low cases.
  - Improvement: add structured tests that explicitly target these behaviors.

## 7) Traceability/Documentation
- Some tests do not clearly reference which lines/conditions in T.87 they are validating.
  - Improvement: add short comments per testbench section mapping it to the exact code segment or written requirement.

---

This backlog is intentionally scoped to be actionable without changing the RTL. It focuses on widening coverage, decoupling tests from shared constants, and explicitly validating written requirements.
