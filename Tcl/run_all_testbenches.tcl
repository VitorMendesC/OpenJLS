# Batch-run all VHDL testbenches in Testbenches/ using Vivado XSim.
#
# Usage:
#   vivado -mode batch -source Tcl/run_all_testbenches.tcl -tclargs \
#     -runtime all
#
# Notes:
# - Vivado requires a part for project creation, even for simulation-only runs.
# - Default part is xc7z020clg400-1 (override with -part).
# - Testbenches call std.env.finish; default runtime is "all".

set part "xc7z020clg400-1"
set runtime "all"
set project_dir ""

for {set i 0} {$i < [llength $argv]} {incr i} {
  set arg [lindex $argv $i]
  switch -- $arg {
    -part {
      incr i
      set part [lindex $argv $i]
    }
    -runtime {
      incr i
      set runtime [lindex $argv $i]
    }
    -project_dir {
      incr i
      set project_dir [lindex $argv $i]
    }
    default {
      puts "Unknown arg: $arg"
      puts "Usage: -part <fpga_part> -runtime all -project_dir <dir>"
      exit 1
    }
  }
}

if {$part eq ""} {
  set part "xc7z020clg400-1"
}

# Normalize runtime; accept "10 us", "10us", or "all".
set runtime [string trim $runtime]
if {![string equal -nocase $runtime "all"]} {
  if {[llength $runtime] > 1} {
    set runtime [join $runtime ""]
  } else {
    regsub -all {\s+} $runtime "" runtime
  }
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file normalize [file join $script_dir ".."]]
set src_dir    [file join $repo_dir "Sources"]
set tb_dir     [file join $repo_dir "Testbenches"]

if {$project_dir eq ""} {
  set project_dir [file join $repo_dir "project_testbenches"]
}

file mkdir $project_dir
create_project -force tb_batch $project_dir -part $part
set_property target_language VHDL [current_project]

# Third-party libs (openlogic_base)
source [file join $repo_dir "Tcl" "create_libraries_vivado.tcl"]

set src_files [concat \
  [glob -nocomplain -directory $src_dir *.vhd] \
  [glob -nocomplain -directory $src_dir *.vhdl]]
set tb_files [concat \
  [glob -nocomplain -directory $tb_dir *.vhd] \
  [glob -nocomplain -directory $tb_dir *.vhdl]]

add_files -fileset sources_1 $src_files
add_files -fileset sim_1 $tb_files

set_property FILE_TYPE {VHDL 2008} [get_files $src_files]
set_property FILE_TYPE {VHDL 2008} [get_files $tb_files]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Running testbenches (runtime: $runtime)"
set pass_list {}
set fail_list {}
foreach tb_file $tb_files {
  set tb [file rootname [file tail $tb_file]]
  puts "\n== $tb =="
  set_property top $tb [get_filesets sim_1]
  reset_simulation -quiet
  set_property xsim.simulate.runtime $runtime [get_filesets sim_1]
  set sim_ok 1
  if {[catch {launch_simulation -mode behavioral} sim_err]} {
    puts "Simulation error: $sim_err"
    set sim_ok 0
  }

  catch {close_sim}

  set sim_dir [file join $project_dir "tb_batch.sim" "sim_1" "behav" "xsim"]
  set sim_log [file join $sim_dir "simulate.log"]
  set alt_log [file join $sim_dir "xsim.log"]
  set tb_result "FAIL"
  set log_files {}
  if {[file exists $sim_log]} {
    lappend log_files $sim_log
  }
  if {[file exists $alt_log]} {
    lappend log_files $alt_log
  }
  foreach log_path $log_files {
    set fh [open $log_path r]
    set log [read $fh]
    close $fh
    set matches [regexp -nocase -all -inline {RESULT:\s*(PASS|FAIL)} $log]
    if {[llength $matches] >= 2} {
      set tb_result [string toupper [lindex $matches end]]
      break
    }
  }

  if {!$sim_ok} {
    set tb_result "FAIL"
  }

  if {$tb_result eq "PASS"} {
    lappend pass_list $tb
    puts "PASS: $tb"
  } else {
    lappend fail_list $tb
    puts "FAIL: $tb"
  }
}

puts "\nSummary"
puts "Passed: [llength $pass_list]"
foreach tb $pass_list {
  puts "  PASS $tb"
}
puts "Failed: [llength $fail_list]"
foreach tb $fail_list {
  puts "  FAIL $tb"
}

if {[llength $fail_list] > 0} {
  puts "\nSome testbenches failed."
  exit 1
}

puts "\nAll testbenches passed."
exit 0
