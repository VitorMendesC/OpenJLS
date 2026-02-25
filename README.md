# OpenJLS

OpenJLS is a source-available **JPEG-LS encoder** for FPGAs, written in **VHDL**.

More information about the project and the JPEG-LS standard on [Project.md](Docs/Project.md).

## Status

Work in progress.
- Core RTL (combinational-only) and module-level testbenches are implemented.
- Next step is **top-level integration** and adding the required registers/pipelining.

## Tool support

This project has been **built and tested only on Xilinx Vivado** so far, targeting a Zynq 7020 SoC.

## TCL scripts

The `Tcl/` folder contains Vivado TCL scripts to:
- build/create simulation libraries
- batch-run simulations

## Repository layout

- `Sources/` – encoder RTL (VHDL)
- `Testbenches/` – simulation testbenches
- `Tcl/` – Vivado TCL automation scripts
- `Docs/` – project documentation
- `ThirdParty/` – external dependencies

## Licensing

OpenJLS is dual-licensed:
- **PolyForm Noncommercial**, free for non-commercial use
- **Commercial license**, required for commercial use
