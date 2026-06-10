#  OpenJLS OSVVM regression — script-flow entry point.
#
#  Run via ./build_reports.sh (or interactively:
#    tclsh> source ../../ThirdParty/osvvm-scripts/StartGHDL.tcl
#    tclsh> build ../../ThirdParty/osvvm/osvvm.pro
#    tclsh> build OpenJls.pro
#  ). Outputs land in this directory: VHDL_LIBS/ (compiled libraries),
#  logs/, reports/ (per-test YAML + HTML), and the build summary
#  OpenJls.html + index.html.
#
#  build_run.sh remains the fast inner loop for a single TB; this flow is
#  the full regression with HTML reports and merged functional coverage.
#  Keep the file lists below in sync with build_run.sh.

# GHDL options matching build_run.sh: -frelaxed (shared variables of
# non-protected types in open-logic and the TBs), -O2 (LLVM/GCC codegen
# speedup), --max-stack-alloc=0 (large TB stack objects), and
# --ieee-asserts=disable (matches the fast flow's run settings).
# tcl's exec treats any stderr output as failure, so analysis must be
# warning-clean: -Wno-shared (shared variables are intentional -frelaxed use),
# -Wno-elaboration (GHDL false positive on olo math functions in Common.vhd
# package constants).
# -fpsl activates the "-- psl" contract assertions in Sources/;
# --assert-level=error makes a violated contract fail the test (default: the
# violation prints but the sim keeps running and exits 0).
SetExtendedAnalyzeOptions   {-frelaxed -O2 -fpsl -Wno-shared -Wno-elaboration}
SetExtendedElaborateOptions {-frelaxed -O2}
SetExtendedRunOptions       {--max-stack-alloc=0 --ieee-asserts=disable --assert-level=error}

# open-logic base: packages + RAM/FIFO primitives the RTL instantiates.
library openlogic_base
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_pkg_array.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_pkg_math.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_pkg_string.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_pkg_logic.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_pkg_attribute.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_ram_sp.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_ram_sdp.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_ram_tdp.vhd
analyze ../../ThirdParty/open-logic/src/base/vhdl/olo_base_fifo_sync.vhd

# Shared TB skeleton (clk_tick, apply_reset, end_of_test).
library tb_support
analyze Support/tb_support_pkg.vhd

# Project RTL. TBs are analyzed into this same library by RunTest, so their
# `entity work.<dut>` references resolve here.
library openjls
analyze ../../Sources/Common.vhd
analyze ../../Sources/A1_gradient_comp.vhd
analyze ../../Sources/A3_mode_selection.vhd
analyze ../../Sources/A4_quantization_gradients.vhd
analyze ../../Sources/A4_1_quant_gradient_merging.vhd
analyze ../../Sources/A4_2_Q_mapping.vhd
analyze ../../Sources/A5_edge_detecting_predictor.vhd
analyze ../../Sources/A6_prediction_correction.vhd
analyze ../../Sources/A7_prediction_error.vhd
analyze ../../Sources/A9_modulo_reduction.vhd
analyze ../../Sources/A10_compute_k.vhd
analyze ../../Sources/A11_error_mapping.vhd
analyze ../../Sources/A11_1_golomb_encoder.vhd
analyze ../../Sources/A11_2_bit_packer.vhd
analyze ../../Sources/A12_variables_update.vhd
analyze ../../Sources/A13_update_bias.vhd
analyze ../../Sources/A14_run_length_determination.vhd
analyze ../../Sources/A15_A16_encode_run.vhd
analyze ../../Sources/A17_run_interruption_index.vhd
analyze ../../Sources/A18_run_interruption_prediction_error.vhd
analyze ../../Sources/A19_run_interruption_error.vhd
analyze ../../Sources/A20_compute_temp.vhd
analyze ../../Sources/A21_compute_map.vhd
analyze ../../Sources/A22_errval_mapping.vhd
analyze ../../Sources/A23_run_interruption_update.vhd
analyze ../../Sources/line_buffer.vhd
analyze ../../Sources/context_ram.vhd
analyze ../../Sources/byte_stuffer.vhd
analyze ../../Sources/jls_framer.vhd
analyze ../../Sources/openjls_top.vhd

# Per-module testbenches. RunTest = analyze + simulate + register the test;
# the test name is the file root name.
TestSuite Modules
RunTest Modules/tb_a1_osvvm.vhd
RunTest Modules/tb_a3_osvvm.vhd
RunTest Modules/tb_a4_osvvm.vhd
RunTest Modules/tb_a4_1_osvvm.vhd
RunTest Modules/tb_a4_2_osvvm.vhd
RunTest Modules/tb_a5_osvvm.vhd
RunTest Modules/tb_a6_osvvm.vhd
RunTest Modules/tb_a7_osvvm.vhd
RunTest Modules/tb_a9_osvvm.vhd
RunTest Modules/tb_a10_osvvm.vhd
RunTest Modules/tb_a11_osvvm.vhd
RunTest Modules/tb_a11_1_osvvm.vhd
RunTest Modules/tb_a11_2_osvvm.vhd
RunTest Modules/tb_a12_osvvm.vhd
RunTest Modules/tb_a13_osvvm.vhd
RunTest Modules/tb_a14_osvvm.vhd
RunTest Modules/tb_a15_a16_osvvm.vhd
RunTest Modules/tb_a17_osvvm.vhd
RunTest Modules/tb_a18_osvvm.vhd
RunTest Modules/tb_a19_osvvm.vhd
RunTest Modules/tb_a20_osvvm.vhd
RunTest Modules/tb_a21_osvvm.vhd
RunTest Modules/tb_a22_osvvm.vhd
RunTest Modules/tb_a23_osvvm.vhd
RunTest Modules/tb_line_buffer_osvvm.vhd
RunTest Modules/tb_context_ram_osvvm.vhd
RunTest Modules/tb_byte_stuffer_osvvm.vhd
RunTest Modules/tb_jls_framer_osvvm.vhd

# Top-level control-plane stress.
TestSuite Top
RunTest Top/tb_openjls_top_osvvm.vhd
