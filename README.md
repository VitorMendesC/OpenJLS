# OpenJLS

OpenJLS is a **JPEG-LS encoder IP core for FPGAs**, written in VHDL.

It implements the JPEG-LS standard (ISO/IEC 14495-1 / ITU-T T.87) — the best-performing lossless image compression algorithm available, delivering compression ratios comparable to JPEG 2000 lossless at a fraction of the complexity, with no external memory required.

OpenJLS is vendor-agnostic, targeting any FPGA platform. It is currently tested on Xilinx Zynq 7020.

> **Status:** Active development. Lossless encoder is integrated end-to-end with AXI4-Stream interfaces and verified bit-exact against the ISO/IEC 14495-1 reference (TEST16, 12-bit grayscale). Current focus is timing closure. Check the [roadmap](Docs/roadmap.md) file for more details.

---

## Why JPEG-LS?

JPEG-LS consistently outperforms other lossless compression standards in both compression ratio and implementation efficiency. It is the standard of choice for applications where lossless fidelity is non-negotiable: satellite imaging, medical imaging (DICOM), industrial machine vision, and scientific instrumentation.

---

## Features

Specifications

- **Compression** — Lossless JPEG-LS
- **Pixel Bit depth** — 8 to 16 bits
- **Components** — Single-component (grayscale)
- **Image size** — Configurable up to 64k × 64k px
- **Memory** — Line buffer, as big as image width, on-chip
- **Throughput** — One pixel per clock cycle
- **Interface** — AXI4-Stream input/output
- **Conformance** — Bit-exact against the ISO/IEC 14495-1 reference and gold-model [CharLS](https://github.com/team-charls/charls) 
- **Portability** — Vendor-agnostic VHDL, portable across FPGA families via [open-logic](https://github.com/open-logic/open-logic)

Planned

- Decoder IP core
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

## Performance & Resources

Characterized on a Xilinx Zynq UltraScale+ `xczu7eg-fbvb900-1-e` (speed grade −1), Vivado 2025.2, 12-bit grayscale. Frequencies are *true fmax* — read by over-constraining the clock (`fmax = 1000 / (period − WNS)`), not a met-constraint floor. Results are RTL-only (no floorplanning) and vary with device, tool version, and implementation strategy; treat them as representative, not guaranteed. At one pixel/clock, ~250 MHz is ~250 Mpixel/s (4K30 with margin).

### Maximum frequency vs image size

![Maximum frequency vs image size](Docs/Images/fmax_vs_size.png)

The encoder holds ~250 MHz largely independent of image size with a congestion-aware strategy. The byte-stuffer back-end is congestion-bound, so `Congestion_SpreadLogic_high` (which spreads logic) wins consistently; the default strategy trails by ~15 MHz and `Performance_Explore` is less predictable on large images. Full analysis in [timing_considerations.md](Docs/timing_considerations.md).

### Resource usage vs image size

![Resource usage vs image size](Docs/Images/util_vs_size.png)

Logic is essentially constant across image size — LUTs (~8k) and flip-flops (~2.1k) are set by the encoder, not the image. Only Block RAM scales: the line buffer holds one image row (`depth = image width`), so it grows ~linearly with width.

### Measured values

| Image width | LUTs | FFs | BRAM tiles | fmax Default | fmax Performance_Explore | fmax Congestion_SpreadLogic_high |
|------------:|-----:|----:|-----------:|-------------:|-------------------------:|---------------------------------:|
| 4096 | 8048 | 2059 | 1.5 | 243.9 | 238.7 | **258.0** |
| 8192 | 7930 | 2062 | 3.0 | 240.0 | 243.0 | **252.8** |
| 12288 | 7855 | 2087 | 4.5 | 243.5 | **248.5** | 247.9 |
| 16384 | 7877 | 2089 | 5.5 | 235.9 | 244.1 | **256.7** |
| 32768 | 7990 | 2095 | 11.0 | 232.2 | 212.8 | **247.5** |

Frequencies in MHz; resource columns are for the default strategy (synthesis-bound, near-identical across strategies). Reproduce with [`Scripts/run_fmax_sweep.sh`](Scripts/run_fmax_sweep.sh).

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
