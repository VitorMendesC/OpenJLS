#-----------------------------------------------------------------------------
# synth_funcsim.tcl - Synthesize openjls_top and export a VHDL funcsim netlist
# for gate-level simulation under NVC (driven by build_run.sh).
#
# Non-project batch mode. The generics MUST mirror tb_openjls_top_osvvm's
# defaults (BITNESS is an architecture constant there): the netlist bakes its
# configuration at synthesis, and the TB's POST_SYNTH component declares the
# matching fixed port widths.
#
# Run standalone:
#   vivado -mode batch -source synth_funcsim.tcl
#-----------------------------------------------------------------------------

set HERE [file dirname [file normalize [info script]]]
set ROOT [file normalize [file join $HERE .. ..]]
# Outputs go to the cwd: Vivado mishandles space-containing paths (this
# script's directory has one) in shell-outs during synthesis, dropping a
# stray prefix-truncated file. build_run.sh runs this from a space-free
# scratch dir and collects the artifacts into Output/.
set OUT [pwd]

# Same device as the fmax characterization project.
set PART xczu7eg-fbvb900-1-e

set OL_SRC [file join $ROOT ThirdParty open-logic src base vhdl]
foreach f {
  olo_base_pkg_array.vhd
  olo_base_pkg_math.vhd
  olo_base_pkg_string.vhd
  olo_base_pkg_logic.vhd
  olo_base_pkg_attribute.vhd
  olo_base_ram_sp.vhd
  olo_base_ram_sdp.vhd
  olo_base_ram_tdp.vhd
  olo_base_fifo_sync.vhd
} {
  read_vhdl -vhdl2008 -library openlogic_base [file join $OL_SRC $f]
}

set SRC [file join $ROOT Sources]
foreach f {
  Common.vhd
  A1_gradient_comp.vhd
  A3_mode_selection.vhd
  A4_quantization_gradients.vhd
  A4_1_quant_gradient_merging.vhd
  A4_2_Q_mapping.vhd
  A5_edge_detecting_predictor.vhd
  A6_prediction_correction.vhd
  A7_prediction_error.vhd
  A9_modulo_reduction.vhd
  A10_compute_k.vhd
  A11_error_mapping.vhd
  A11_1_golomb_encoder.vhd
  A11_2_bit_packer.vhd
  A12_variables_update.vhd
  A13_update_bias.vhd
  A14_run_length_determination.vhd
  A15_A16_encode_run.vhd
  A17_run_interruption_index.vhd
  A18_run_interruption_prediction_error.vhd
  A19_run_interruption_error.vhd
  A20_compute_temp.vhd
  A21_compute_map.vhd
  A22_errval_mapping.vhd
  A23_run_interruption_update.vhd
  line_buffer.vhd
  context_ram.vhd
  byte_stuffer.vhd
  jls_framer.vhd
  openjls_top.vhd
} {
  read_vhdl -vhdl2008 [file join $SRC $f]
}

# out_of_context: no IO buffer insertion, so the netlist ports stay
# bit-for-bit those of the RTL entity.
synth_design -top openjls_top -part $PART -mode out_of_context \
  -generic BITNESS=8 \
  -generic MAX_IMAGE_WIDTH=4096 \
  -generic MAX_IMAGE_HEIGHT=4096 \
  -generic OUT_WIDTH=64

write_vhdl -mode funcsim -force [file join $OUT openjls_top_funcsim.vhd]
report_utilization -file [file join $OUT synth_util.rpt]
puts "DONE: netlist at [file join $OUT openjls_top_funcsim.vhd]"
