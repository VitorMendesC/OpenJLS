# OpenJLS

OpenJLS is a **JPEG-LS encoder IP core for FPGAs**, written in VHDL.

It implements the JPEG-LS standard (ISO/IEC 14495-1 / ITU-T T.87) — a low-complexity lossless image codec with compression ratios comparable to JPEG 2000 lossless at a fraction of the computational cost, and no external memory required.

OpenJLS is vendor-agnostic, targeting any FPGA platform.

> **Status:** Active development. The lossless encoder is integrated end-to-end with AXI4-Stream interfaces, verified bit-exact against the ISO/IEC 14495-1 reference (TEST16, 12-bit grayscale), and characterized for timing and resources (~250 MHz on UltraScale+, see below). Current focus is completing verification with [OSVVM](https://osvvm.org/) (constrained-random + functional coverage). Check the [roadmap](Docs/roadmap.md) file for more details.

---

## Why JPEG-LS?

JPEG-LS hits a sweet spot for hardware: Close to state-of-the-art lossless ratios from a single-pass, low-memory algorithm that needs no external RAM. It matches or beats older standards like PNG and lossless JPEG 2000, and while heavier modern codecs (JPEG XL, FLIF) compress somewhat tighter, they cost far more logic and memory than an embedded pipeline can spare. That makes JPEG-LS the standard of choice where lossless fidelity and bounded resources both matter — satellite and medical imaging (DICOM).

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

![OpenJLS Architecture](Docs/Images/OpenJLS_arch.png)

OpenJLS follows the JPEG-LS encoding pipeline:

1. **Gradient computation** — local gradients from causal pixel neighbors (a, b, c, d)
2. **Context modeling** — gradient quantization into 365 contexts with adaptive bias correction
3. **Prediction** — MED (Median Edge Detector) with context-based bias cancellation
4. **Encoding** — adaptive Golomb-Rice coding for regular mode, run-length encoding for uniform regions
5. **Bitstream packing** — ISO/IEC 14495-1 compliant JPEG-LS output stream

---

## Performance & Resources

Characterized on a Xilinx Zynq UltraScale+ `xczu7eg-fbvb900-1-e` (speed grade −1, slowest), Vivado 2025.2, 12-bit grayscale. Frequencies are *true fmax* — read by over-constraining the clock until the design failed timing. Results are RTL-only, no floorplanning and vendor-specific optimizations, and vary with device, tool version, and implementation strategy; treat them as representative, not guaranteed. At one pixel/clock, ~250 MHz is ~250 Mpixel/s (4K30fps with margin).

### Maximum frequency vs image size

![Maximum frequency vs image size](Docs/Images/fmax_vs_size.png)

The encoder holds ~250 MHz largely independent of image size with a congestion-aware strategy. The byte-stuffer back-end is congestion-bound, so `Congestion_SpreadLogic_high` (which spreads logic) wins consistently; the default strategy trails by ~15 MHz and `Performance_Explore` is less predictable on large images.

| Image width | Default | Performance_Explore | Congestion_SpreadLogic_high |
|------------:|--------:|--------------------:|----------------------------:|
| 4096 | 243.9 | 238.7 | **258.0** |
| 8192 | 240.0 | 243.0 | **252.8** |
| 12288 | 243.5 | **248.5** | 247.9 |
| 16384 | 235.9 | 244.1 | **256.7** |
| 32768 | 232.2 | 212.8 | **247.5** |

Maximum frequency (MHz) by image width and implementation strategy; best per row in bold.

### Resource usage vs image size

![Resource usage vs image size](Docs/Images/util_vs_size.png)

Logic is essentially constant across image size — LUTs (~8k) and flip-flops (~2.1k) are set by the encoder, not the image. Only Block RAM scales: the line buffer holds one image row, so it grows ~linearly with image width and pixel bit depth.

| Image width | LUTs | FFs | BRAM tiles |
|------------:|-----:|----:|-----------:|
| 4096 | 8048 | 2059 | 1.5 |
| 8192 | 7930 | 2062 | 3.0 |
| 12288 | 7855 | 2087 | 4.5 |
| 16384 | 7877 | 2089 | 5.5 |
| 32768 | 7990 | 2095 | 11.0 |

Resource usage by image width (default strategy; near-identical across strategies). Reproduce both tables with [`Scripts/run_fmax_sweep.sh`](Scripts/run_fmax_sweep.sh).

---

## Licensing

OpenJLS is dual-licensed:

- **[GPL v3](LICENSE.md)** — free for any use that complies with GPL v3 terms. This means if you distribute a product containing OpenJLS, your design must also be released under GPL v3.
- **[Commercial License](COMMERCIAL_LICENSE.md)** — for use in proprietary/closed-source products without GPL obligations. Contact vitormendescamilo@protonmail.com for pricing and terms.

**Evaluation is unrestricted.** You can clone, simulate, synthesize, and test OpenJLS freely under the GPL. A commercial license is only required when shipping a product.

---

## Dependencies

All third-party components are vendored under `ThirdParty/` with their license texts, pinned to fixed releases by `fetch_third_party.sh`. Only open-logic is part of the synthesizable IP; everything else is verification tooling and is never distributed in a product.

| Component | License | Scope | Notes |
|---|---|---|---|
| [open-logic](https://github.com/open-logic/open-logic) | LGPL-2.1+ with PSI HDL exception | Synthesized RTL | Memory and FIFO primitives. Weak copyleft confined to its own files; the exception explicitly permits distributing FPGA bitstreams under the user's own terms. |
| [OSVVM](https://github.com/OSVVM/OSVVM) | Apache-2.0 | Verification only | VHDL verification library used by the testbench suite. |
| [OSVVM-Scripts](https://github.com/OSVVM/OSVVM-Scripts) | Apache-2.0 | Verification only | Regression and report-generation script flow. |
| [tcllib](https://github.com/tcltk/tcllib) | Tcl/BSD-style | Verification only | `fileutil` and `yaml` modules required by the report scripts. |
| [CharLS](https://github.com/team-charls/charls) | BSD-3-Clause | Verification only | Golden reference encoder for conformance testing; built from source, not vendored or redistributed. |

No dependency imposes copyleft obligations on the OpenJLS sources; the dual-licensing model above is unaffected. Redistribution of the repository or the IP must retain the third-party copyright notices and license texts in `ThirdParty/`.

---

## References

- [ISO/IEC 14495-1](https://www.itu.int/rec/T-REC-T.87) — JPEG-LS standard specification (ITU-T T.87)
- [LOCO-I algorithm paper](https://doi.org/10.1109/83.730379) — Weinberger, Seroussi, Sapiro (2000)
- [open-logic](https://github.com/open-logic/open-logic) — Vendor-agnostic VHDL building blocks used in this project

---

## Contact

For commercial licensing, technical questions, or collaboration inquiries: vitormendescamilo@protonmail.com
