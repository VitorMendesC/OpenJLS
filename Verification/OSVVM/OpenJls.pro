#  OpenJLS OSVVM regression — script-flow entry point.
#
#  Run via ./build_reports.sh (or interactively:
#    tclsh> source ../../ThirdParty/osvvm-scripts/StartNVC.tcl
#    tclsh> build ../../ThirdParty/osvvm/osvvm.pro
#    tclsh> build OpenJls.pro
#  ). Outputs land in this directory: VHDL_LIBS/ (compiled libraries),
#  logs/, reports/ (per-test YAML + HTML), and the build summary
#  OpenJls.html + index.html.
#
#  build_run.sh remains the fast inner loop for a single TB; this flow is
#  the full regression with HTML reports and merged functional coverage.
#  Keep the file lists below in sync with build_run.sh.

# NVC options matching build_run.sh: --relaxed permits the shared variables of
# non-protected types in open-logic and the TBs; --stderr=error keeps warnings
# on stdout (tcl's exec treats any stderr output as failure, so analysis must
# be warning-clean); --psl activates the "-- psl" contract assertions in
# Sources/ (negative-tested: with --exit-severity=error a violated contract
# fails the test; without it the violation prints but the sim exits 0).
set ::osvvm::ExtendedGlobalOptions {--stderr=error}
SetExtendedAnalyzeOptions {--relaxed --psl}
SetExtendedRunOptions     {--ieee-warnings=off --exit-severity=error}

# Statement+branch code coverage: ./build_coverage.sh sets CODE_COVERAGE=1.
# NVC's --cover-file must be unique per test, so the Test wrapper below
# refreshes the option before every RunTest; the .covdb files are merged and
# rendered to HTML by build_coverage.sh.
set ::OpenJlsCodeCoverage [info exists ::env(CODE_COVERAGE)]
if {$::OpenJlsCodeCoverage} {
  SetCoverageSimulateEnable true
  file mkdir Coverage
}
proc Test {TestFile args} {
  if {$::OpenJlsCodeCoverage} {
    # GenericNames suffix keeps [generic ...] variants of one TB from
    # overwriting each other's .covdb.
    set tn [file rootname [file tail $TestFile]]$::osvvm::GenericNames
    SetCoverageSimulateOptions [list --cover=statement,branch --cover-file=Coverage/$tn.covdb]
  }
  RunTest $TestFile {*}$args
}

# open-logic base: packages + RAM/FIFO primitives the RTL instantiates. Shares
# the openjls design library (the RTL references them as work.*).
library openjls
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
Test Modules/tb_a1_osvvm.vhd
Test Modules/tb_a3_osvvm.vhd
Test Modules/tb_a4_osvvm.vhd
Test Modules/tb_a4_1_osvvm.vhd
Test Modules/tb_a4_2_osvvm.vhd
Test Modules/tb_a5_osvvm.vhd
Test Modules/tb_a6_osvvm.vhd
Test Modules/tb_a7_osvvm.vhd
Test Modules/tb_a9_osvvm.vhd
Test Modules/tb_a10_osvvm.vhd
Test Modules/tb_a11_osvvm.vhd
Test Modules/tb_a11_1_osvvm.vhd
Test Modules/tb_a11_2_osvvm.vhd
Test Modules/tb_a12_osvvm.vhd
Test Modules/tb_a13_osvvm.vhd
Test Modules/tb_a14_osvvm.vhd
Test Modules/tb_a15_a16_osvvm.vhd
Test Modules/tb_a17_osvvm.vhd
Test Modules/tb_a18_osvvm.vhd
Test Modules/tb_a19_osvvm.vhd
Test Modules/tb_a20_osvvm.vhd
Test Modules/tb_a21_osvvm.vhd
Test Modules/tb_a22_osvvm.vhd
Test Modules/tb_a23_osvvm.vhd
Test Modules/tb_line_buffer_osvvm.vhd
Test Modules/tb_context_ram_osvvm.vhd
Test Modules/tb_byte_stuffer_osvvm.vhd
Test Modules/tb_jls_framer_osvvm.vhd
# Non-default OUT_WIDTH sweep around the 64 default (range 48..1024): 48 =
# range floor; 56 = another final-header-beat split; 200 = the 25-byte header
# ends exactly on a beat boundary (25 % BYTES_OUT = 0); 1024 = top of the
# range (pins the BUFFER_BYTES_NOMINAL sizing).
Test Modules/tb_jls_framer_osvvm.vhd [generic OUT_WIDTH 48]
Test Modules/tb_jls_framer_osvvm.vhd [generic OUT_WIDTH 56]
Test Modules/tb_jls_framer_osvvm.vhd [generic OUT_WIDTH 200]
Test Modules/tb_jls_framer_osvvm.vhd [generic OUT_WIDTH 1024]

# Top-level control-plane stress: the 64-bit default OUT_WIDTH, then
# non-power-of-2 MAX dims, then the range floor and ceiling.
TestSuite Top
Test Top/tb_openjls_top_osvvm.vhd
Test Top/tb_openjls_top_osvvm.vhd [generic MAX_W 320] [generic MAX_H 200]
Test Top/tb_openjls_top_osvvm.vhd [generic OUT_WIDTH 48]
Test Top/tb_openjls_top_osvvm.vhd [generic OUT_WIDTH 1024]
