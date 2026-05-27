# This script creates the libraries needed by the RTL in Vivado.

# Get the third party directory
set script_dir [file dirname [file normalize [info script]]]
set third_party_dir [file normalize [file join $script_dir ".." ThirdParty]]

# Get the Open Logic base directory
set olo_dir  [file join $third_party_dir open-logic src base vhdl]

# Grab the files and build the libraries
# Ensure package compile order (dependencies):
#   array -> math -> logic/string, attributes independent
set olo_pkg_array     [file join $olo_dir "olo_base_pkg_array.vhd"]
set olo_pkg_math      [file join $olo_dir "olo_base_pkg_math.vhd"]
set olo_pkg_logic     [file join $olo_dir "olo_base_pkg_logic.vhd"]
set olo_pkg_string    [file join $olo_dir "olo_base_pkg_string.vhd"]
set olo_pkg_attribute [file join $olo_dir "olo_base_pkg_attribute.vhd"]

set olo_pkg_files [list \
  $olo_pkg_array \
  $olo_pkg_math \
  $olo_pkg_logic \
  $olo_pkg_string \
  $olo_pkg_attribute \
]

set olo_other_files [list \
  [file join $olo_dir "olo_base_ram_sp.vhd"] \
  [file join $olo_dir "olo_base_ram_sdp.vhd"] \
  [file join $olo_dir "olo_base_ram_tdp.vhd"] \
  [file join $olo_dir "olo_base_fifo_sync.vhd"] \
  [file join $olo_dir "olo_base_fifo_packet.vhd"] \
]

set olo_files [concat $olo_pkg_files $olo_other_files]

add_files -fileset sources_1 $olo_files
set_property library openlogic_base [get_files $olo_files]
# Set VHDL-2008 for all the files (packages + RTL)
set_property FILE_TYPE {VHDL 2008} [get_files $olo_files]
