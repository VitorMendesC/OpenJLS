# OpenJLS

OpenJLS is a **JPEG-LS encoder IP core for FPGAs**, written in VHDL.

It implements the JPEG-LS standard (ISO/IEC 14495-1 / ITU-T T.87) — the best-performing lossless image compression algorithm available, delivering compression ratios comparable to JPEG 2000 lossless at a fraction of the complexity, with no external memory required.

OpenJLS is vendor-agnostic, targeting any FPGA platform. It is currently tested on Xilinx Zynq 7020.

> **Status:** Active development. Core building blocks (codec segments, context memory) are implemented and individually verified. Top-level integration with AXI4-Stream interfaces is in progress. Check the [roadmap](ROADMAP.md) file for more details.

---

## Why JPEG-LS?

JPEG-LS consistently outperforms other lossless compression standards in both compression ratio and implementation efficiency. It is the standard of choice for applications where lossless fidelity is non-negotiable: satellite imaging, medical imaging (DICOM), industrial machine vision, and scientific instrumentation.

---

## Features

**Implemented**
- ISO/IEC 14495-1 compliant JPEG-LS encoding
- Up to 16-bit per component grayscale
- One pixel per clock cycle throughput
- No external memory required — on-chip only
- Vendor-agnostic VHDL (portable across FPGA families via [open-logic](https://github.com/open-logic/open-logic))
- Module-level testbenches for all core components

**Planned**
- Lossless and near-lossless (lossy) encoding modes
- AXI4-Stream input/output interfaces
- Top-level integration with pipelining
- Decoder IP core
- Resource utilization and performance benchmarks

---

## Architecture

<!-- TODO: Add block diagram -->

OpenJLS follows the JPEG-LS encoding pipeline:

1. **Gradient computation** — local gradients from causal pixel neighbors (a, b, c, d)
2. **Context modeling** — gradient quantization into 365 contexts with adaptive bias correction
3. **Prediction** — MED (Median Edge Detector) with context-based bias cancellation
4. **Encoding** — adaptive Golomb-Rice coding for regular mode, run-length encoding for uniform regions
5. **Bitstream packing** — ISO/IEC 14495-1 compliant JPEG-LS output stream

**Key design decisions:**
- One pixel per clock cycle, fully pipelined datapath
- On-chip context memory — no external DRAM access
- Vendor-agnostic memories and FIFOs via open-logic
- AXI4-Stream interfaces for straightforward SoC integration

---

## Getting Started

### Prerequisites

- Xilinx Vivado (tested; other vendor tools should work with open-logic compatibility)
- VHDL-2008 capable simulator

### Running Simulations

```bash
vivado -mode batch -notrace -source Tcl/run_all_testbenches.tcl -tclargs -runtime all
```

---

## Licensing

OpenJLS is dual-licensed:

- **[GPL v3](LICENSE.md)** — free for any use that complies with GPL v3 terms. This means if you distribute a product containing OpenJLS, your design must also be released under GPL v3.
- **[Commercial License](COMMERCIAL_LICENSE.md)** — for use in proprietary/closed-source products without GPL obligations. Contact vitormendescamilo@protonmail.com for pricing and terms.

**Evaluation is unrestricted.** You can clone, simulate, synthesize, and test OpenJLS freely under the GPL. A commercial license is only required when shipping a product.

---

## References

- [ISO/IEC 14495-1](https://www.itu.int/rec/T-REC-T.87) — JPEG-LS standard specification (ITU-T T.87)
- [LOCO-I algorithm paper](https://doi.org/10.1109/83.730379) — Weinberger, Seroussi, Sapiro (2000)
- [open-logic](https://github.com/open-logic/open-logic) — Vendor-agnostic VHDL building blocks used in this project

---

## Contact

For commercial licensing, technical questions, or collaboration inquiries: vitormendescamilo@protonmail.com
