# OpenJLS

OpenJLS is a **JPEG-LS encoder IP core for FPGAs**, written in VHDL.

It implements the JPEG-LS standard (ISO/IEC 14495-1 / ITU-T T.87) — the best-performing lossless image compression algorithm available, delivering compression ratios comparable to JPEG 2000 lossless at a fraction of the complexity, with no external memory required.

OpenJLS is vendor-agnostic, targeting any FPGA platform. It is currently tested on Xilinx Zynq 7020.

> **Status:** Active development. Lossless encoder is integrated end-to-end with AXI4-Stream interfaces and verified bit-exact against the ISO/IEC 14495-1 reference (TEST16, 12-bit grayscale). Current focus is timing closure. Check the [roadmap](Docs/ROADMAP.md) file for more details.

---

## Why JPEG-LS?

JPEG-LS consistently outperforms other lossless compression standards in both compression ratio and implementation efficiency. It is the standard of choice for applications where lossless fidelity is non-negotiable: satellite imaging, medical imaging (DICOM), industrial machine vision, and scientific instrumentation.

---

## Features

**Implemented**
- ISO/IEC 14495-1 compliant JPEG-LS lossless encoding
- End-to-end pipelined top-level (openjls_top) with AXI4-Stream input/output
- Bit-exact conformance verified against ISO reference (TEST16, 12-bit grayscale)
- Up to 16-bit per component grayscale
- One pixel per clock cycle throughput
- No external memory required — on-chip only
- Vendor-agnostic VHDL (portable across FPGA families via [open-logic](https://github.com/open-logic/open-logic))
- Module-level and full-encoder conformance testbenches

**Planned**
- Decoder IP core
- Resource utilization and performance benchmarks
- Multi-vendor (Intel, Microchip, Lattice) verified configurations

---

## Architecture

<!-- TODO: Add block diagram -->

OpenJLS follows the JPEG-LS encoding pipeline:

1. **Gradient computation** — local gradients from causal pixel neighbors (a, b, c, d)
2. **Context modeling** — gradient quantization into 365 contexts with adaptive bias correction
3. **Prediction** — MED (Median Edge Detector) with context-based bias cancellation
4. **Encoding** — adaptive Golomb-Rice coding for regular mode, run-length encoding for uniform regions
5. **Bitstream packing** — ISO/IEC 14495-1 compliant JPEG-LS output stream

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
