# This script creates the libraries needed by the RTL in Vivado.

# Get the third party directory
set script_dir [file dirname [file normalize [info script]]]
set third_party_dir [file normalize [file join $script_dir ".." ThirdParty]]

# Get the Open Logic base directory
set olo_dir  [file join $third_party_dir open-logic src base vhdl]

# Grab the files and build the libraries
set olo_files [glob -nocomplain -directory $olo_dir *.vhd]
add_files -fileset sources_1 $olo_files
set_property library openlogic_base [get_files $olo_files]
# Set VHDL-2008 for all the files (packages + RTL)
set_property FILE_TYPE {VHDL 2008} [get_files $olo_files]