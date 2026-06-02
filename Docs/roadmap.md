# OpenJLS Roadmap

This document tracks the development plan for OpenJLS. It reflects current priorities and may change as the project evolves.

---

## Phase 1 — Core Encoder

- [x] JPEG-LS building blocks: gradient computation, context modeling, MED predictor
- [x] Golomb-Rice encoder
- [x] Run-length encoding mode
- [x] Context memory (vendor-agnostic via open-logic)
- [x] Top-level integration with pipelining and registers
- [x] Lossless mode — fully functional end-to-end encoder
- [x] AXI4-Stream input/output interfaces

## Phase 2 — Verification

- [x] Module-level testbenches for all blocks
- [x] Bitstream compliance verification against reference software (ISO 14495-1)
- [x] Resource utilization and timing benchmarks (published in README)
- [ ] OSVVM constrained-random + functional-coverage verification (per-module and top-level control-plane stress)
- [ ] Full compliance test suite with standard test images
- [ ] Bit-accurate software reference model

## Phase 3 — Platform Expansion

- [ ] Verified configurations for Intel/Altera devices
- [ ] Verified configurations for Microchip (Microsemi) devices
- [ ] Verified configurations for Lattice devices

---

*Last updated: June 2026*
