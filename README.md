# OpenJLS

OpenJLS is a **JPEG-LS encoder IP core for FPGAs** for real-time image compression.

It implements the JPEG-LS standard (described by ISO/IEC 14495-1 or ITU-T T.87) — a low-complexity lossless image codec with compression ratios comparable to JPEG 2000 lossless at a fraction of the computational cost, and no external memory required.

OpenJLS can reach a maximum frequency up to ~250 MHz on a Xilinx UltraScale+ ZU7EG, an MPSoC often used in space applications, and it processes 1 pixel per clock, resulting in ~250 MPixels/s. It operates on single-component data, often called grayscale, so in a satellite camera with multiple bands each band would need its own compressor; this is not an issue since the resource usage is minimal, and it greatly increases throughput since each compressor can operate in parallel.

OpenJLS is vendor-agnostic, targeting any FPGA platform.

---

## Why JPEG-LS?

JPEG-LS hits a sweet spot for hardware: Close to state-of-the-art lossless ratios from a single-pass, low-memory algorithm that needs no external RAM. It matches or beats older standards like PNG and lossless JPEG 2000, and while heavier modern codecs (JPEG XL, FLIF) compress somewhat tighter, they cost far more logic and memory than an embedded pipeline can spare.

---

## Features

Specifications

- **Compression** — Lossless JPEG-LS
- **Pixel Bit depth** — 8 to 16 bits
- **Components** — Single-component (grayscale)
- **Image size** — Configurable up to 64k × 64k px (minimum 4 × 1)
- **Memory** — Line buffer, as big as image width, on-chip
- **Throughput** — One pixel per clock cycle
- **Interface** — AXI4-Stream input/output
- **Conformance** — Bit-exact against the ISO/IEC 14495-1 reference and golden-model [CharLS](https://github.com/team-charls/charls)
- **Portability** — Vendor-agnostic VHDL, due to memory-agnostic IPs from [open-logic](https://github.com/open-logic/open-logic)

---

## Verification

OpenJLS is verified by simulation with [NVC](https://www.nickg.me.uk/nvc/) using a layered suite that combines constrained-random self-checking tests, functional coverage, and byte-exact comparison against an independent reference encoder — run at both the RTL and post-synthesis (gate-level) stages:

> ** Browse the latest [Verification report](https://vitormendesc.github.io/OpenJLS/)** a live dashboard of every suite that congregates OSVMM, NVC html reports and logs from post-synth verification.

- **OSVVM** — Per-module correctness and system-level control-plane stress. Each of 28 module-level testbenches verifies its module against an independent behavioral reference model derived from the ITU-T T.87 specification; a top-level testbench stresses the control plane (reset injection, output backpressure, randomized image sizes), all with requirements tracking. Confirms the encoder sustains one pixel per clock and stalls *only* under downstream backpressure, and streams images back-to-back with no gap or data loss.
- **Coverage** — Two complementary metrics, both gathered within the OSVVM verification suite: OSVVM provides functional (behavioral) coverage, while NVC provides structural code coverage, reaching 99%+ statement coverage.
- **Golden model** — Byte-exact comparison of the output bitstream against [CharLS](https://github.com/team-charls/charls), an independent open-source C++ reference encoder, over a large dataset of real images — natural photographs and synthetic stress patterns that push the algorithm past anything natural images reach (see below). Also validated against the official ISO/IEC 14495-1 reference vectors.
- **Design contracts** — Embedded PSL assertions (AXI-Stream protocol, internal handshakes) checked on every simulation run.
- **Post-synthesis** — The top-level OSVVM stress test and a subset of the golden-model dataset are re-run on the synthesized gate-level netlist, guaranteeing synthesis did not change the encoder's behavior.

**Golden-model dataset.** The corpus is **287 images** pulled from public datasets and exercised across the full datapath:

| Source | Set | Images |
|---|---|--:|
| [USC-SIPI](https://sipi.usc.edu/database/) | Aerials, textures, miscellaneous, sequences | 210 |
| [imagecompression.info](http://imagecompression.info/test_images/) | 8-bit and 16-bit natural photographs | 30 |
| Generated stress probes | Boundary, predictor-adversarial, high-entropy and fuzz patterns | 47 |

The real datasets give natural image statistics from 256×256 up to **39 megapixels** (7216×5412); the generated probes deliberately target what real images never reach. [`gen_stress.py`](Verification/Golden%20model/imageprep/gen_stress.py) emits them deterministically — seeded and byte-reproducible, so the committed generator is the source of truth — covering:

- **Intermediate bit depths (9–15)** — no natural dataset exists here, so these probes are the only coverage of the 9–15-bit range.
- **Boundary geometries** — the smallest legal image (4×1), tall single-column images, and maximum-width single rows up to 65535×1.
- **Predictor-adversarial content** — checkerboard, vertical/horizontal stripes and sparse spikes that defeat the MED predictor on every pixel, plus incompressible uniform noise.
- **Tiny-image fuzz batch** — many small randomized images that stress start and end-of-image edge conditions far more densely than full-size images can.

---

## Architecture

![OpenJLS Architecture](Docs/Images/OpenJLS_arch.png)

OpenJLS follows the JPEG-LS encoding pipeline:

1. **Gradient computation** — local gradients from causal pixel neighbors (a, b, c, d)
2. **Context modeling** — gradient quantization into 365 contexts with adaptive bias correction
3. **Prediction** — MED (Median Edge Detector) with context-based bias cancellation
4. **Encoding** — adaptive Golomb-Rice coding for regular mode, run-length encoding for uniform regions
5. **Bitstream packing** — ISO/IEC 14495-1 compliant JPEG-LS output stream

The hardware architecture is based on the optimizations in Mert's [*Key Architectural Optimizations for Hardware Efficient JPEG-LS Encoder*](https://www.researchgate.net/publication/331795298_Key_Architectural_Optimizations_for_Hardware_Efficient_JPEG-LS_Encoder), reworked into a vendor-agnostic, fully pipelined VHDL core.

---

## Performance & Resources

Characterized on a Xilinx Zynq UltraScale+ `xczu7eg-fbvb900-1-e` (speed grade −1, slowest), Vivado 2025.2, 12-bit grayscale. Frequencies are *true fmax* — read by over-constraining the clock until the design failed timing. Results are RTL-only, no floorplanning or vendor-specific optimizations, and vary with device, tool version, and implementation strategy; treat them as representative, not guaranteed. At one pixel/clock, ~250 MHz is ~250 Mpixel/s.

### Maximum frequency vs image size

![Maximum frequency vs image size](Docs/Images/fmax_vs_size.png)

The encoder holds ~250 MHz largely independent of image size with a strategy focusing on *handling congestion* and ~240 MHz on Default strategy.

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
- **Commercial License** — for use in proprietary/closed-source products without GPL obligations. Contact vitormendescamilo@protonmail.com for pricing and terms.

**Evaluation is unrestricted.** You can clone, simulate, synthesize, and test OpenJLS freely under the GPL. A commercial license is only required when shipping a product.

---

## Dependencies

Dependencies fall into two independent sets. **Using the IP** needs only the base set below — the core is plain VHDL-1993 and synthesizes in any EDA tool on any OS. **Running the verification suite** needs the Linux toolchain in the second table; none of it is part of, or distributed with, the IP.

### Base IP

| Component | License | Notes |
|---|---|---|
| [open-logic](https://github.com/open-logic/open-logic) | LGPL-2.1+ with PSI HDL exception | Vendor-agnostic memory and FIFO primitives. Weak copyleft confined to its own files; the exception explicitly permits distributing FPGA bitstreams under your own terms. |

The IP carries no OS or vendor lock-in — it builds with Vivado, Quartus, Libero, Lattice, or open-source tools. (The performance figures above were characterized with AMD Vivado, but any synthesis tool works.)

### Verification (Linux)

The verification flows are bash-driven and built around the NVC simulator; they run on Linux and are not supported on Windows.
None of the components below are committed to the repository — running [`ThirdParty/fetch_third_party.sh`](ThirdParty/fetch_third_party.sh) materializes them all: vendoring the HDL with its license texts, building CharLS from source, and installing NVC.

| Component | License | Notes |
|---|---|---|
| [NVC](https://www.nickg.me.uk/nvc/) | GPL-3.0 | VHDL simulator for all simulation, coverage, and post-synthesis flows; developed and tested with NVC 1.21. Not vendored — its GPL covers the simulator, not the IP it runs. |
| [CharLS](https://github.com/team-charls/charls) | BSD-3-Clause | JPEG-LS reference encoder for the golden-model cross-check; built from source at a pinned commit by `ThirdParty/fetch_third_party.sh`. |
| [OSVVM](https://github.com/OSVVM/OSVVM) | Apache-2.0 | VHDL verification library used by the testbench suite. |
| [OSVVM-Scripts](https://github.com/OSVVM/OSVVM-Scripts) | Apache-2.0 | Regression and report-generation script flow. |
| [tcllib](https://github.com/tcltk/tcllib) | Tcl/BSD-style | `fileutil` and `yaml` modules required by the report scripts. |

The verification libraries (OSVVM, OSVVM-Scripts, tcllib) are not committed; [`ThirdParty/fetch_third_party.sh`](ThirdParty/fetch_third_party.sh) materializes each one under `ThirdParty/` from its pinned upstream, license text included. open-logic is committed in-tree (the core RTL instantiates its primitives, so the IP builds without the fetch step). NVC is installed through your OS package manager — the script handles Ubuntu and Arch automatically; on other systems install it manually from the [NVC docs](https://www.nickg.me.uk/nvc/). No dependency imposes copyleft obligations on the OpenJLS sources; the dual-licensing model above is unaffected. Redistribution must retain the third-party copyright notices and license texts in `ThirdParty/`.

---

## References

- [Key Architectural Optimizations for Hardware Efficient JPEG-LS Encoder](https://www.researchgate.net/publication/331795298_Key_Architectural_Optimizations_for_Hardware_Efficient_JPEG-LS_Encoder) — Y. M. Mert, IEEE (2018). The hardware architecture OpenJLS is based on.
- [ISO/IEC 14495-1](https://www.itu.int/rec/T-REC-T.87) — JPEG-LS standard specification (ITU-T T.87)
- [open-logic](https://github.com/open-logic/open-logic) — Vendor-agnostic VHDL building blocks used in this project
- [OSVVM](https://osvvm.org/) — VHDL verification methodology (constrained-random + functional coverage) used by the testbench suite
- [NVC](https://www.nickg.me.uk/nvc/) — VHDL simulator used for all simulation, coverage, and post-synthesis flows
- [CharLS](https://github.com/team-charls/charls) — JPEG-LS reference codec used as the golden model for conformance

---

## Contact

For commercial licensing, technical questions, or collaboration inquiries: vitormendescamilo@protonmail.com
