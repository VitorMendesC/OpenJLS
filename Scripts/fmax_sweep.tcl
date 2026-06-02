#-----------------------------------------------------------------------------
# fmax_sweep.tcl - Characterize max frequency vs image size for the OpenJLS IP.
#
# Drives the existing project_OpenJLS_tests project in BATCH mode. For each
# image size (MAX_IMAGE_WIDTH = MAX_IMAGE_HEIGHT) and each implementation
# strategy, it runs synth + impl under a single AGGRESSIVE clock constraint and
# records fmax = 1000 / (period - WNS). P&R stops optimizing once WNS >= 0, so
# the probe period must be tighter than the real fmax for the number to be
# meaningful (see Docs/timing_considerations.md).
#
# Output: $OUTDIR/fmax_sweep.csv  (size,strategy,period_ns,wns_ns,fmax_mhz,lut,ff,bram,met,status)
#         $OUTDIR/rpt_<size>_<strategy>_{timing,util}.log  (per-point provenance)
#
# Run (inside vivado_box):
#   vivado -mode batch -source Scripts/fmax_sweep.tcl
# or via the wrapper:
#   distrobox enter vivado_box -- /home/Vitor/EDA/vivado-launch \
#       /home/Vitor/EDA/Logs -mode batch -source \
#       /home/Vitor/Repos/OpenJLS/Scripts/fmax_sweep.tcl
#
# NON-DESTRUCTIVE: backs up and restores the clock XDC, clears the generic
# override, and restores the default strategy on exit.
#-----------------------------------------------------------------------------

# ---- Configuration (edit here) ---------------------------------------------
set PROJ  "/home/Vitor/Repos/OpenJLS-vivado-private/project_OpenJLS_tests/project_OpenJLS_tests.xpr"
set XDC   "/home/Vitor/Repos/OpenJLS-vivado-private/project_OpenJLS_tests/project_OpenJLS_tests.srcs/constrs_1/new/timing_constraints.xdc"
set OUTDIR "/home/Vitor/EDA/Logs"
set CLKPORT iClk
set OVERCONSTRAIN_NS 3.000 ;# aggressive probe period; keep tighter than real fmax
set JOBS 12

set SIZES      {4096 8192 12288 16384 32768}
# Line 1 is the pinned "Vivado Implementation Defaults" baseline (set below).
# These are the performance lines. Congestion_SpreadLogic_high directly targets
# this design's routing/congestion-bound wall (deliberately spreads logic to
# de-congest). Swap/extend freely (Performance_NetDelay_high,
# Performance_ExplorePostRoutePhysOpt, ...).
set PERF_STRATEGIES {Performance_Explore Congestion_SpreadLogic_high}

# ---- Helpers ----------------------------------------------------------------
proc grab {pattern text default} {
  if {[regexp $pattern $text -> m]} { return $m }
  return $default
}

# ---- Open project, capture original state -----------------------------------
open_project $PROJ
set FS [current_fileset]
puts "INFO: top = [get_property top $FS]"

# Pin the baseline to the real Vivado default BY NAME. Do NOT read it from the
# project: a prior manual session may have left impl_1 on another strategy
# (e.g. Performance_Explore), which would silently replace the "standard" line.
set STD_STRATEGY "Vivado Implementation Defaults"
puts "INFO: standard/baseline strategy = $STD_STRATEGY"
set STRATEGIES [concat [list $STD_STRATEGY] $PERF_STRATEGIES]

# Back up the clock XDC, then over-constrain it.
set fp [open $XDC r]; set XDC_ORIG [read $fp]; close $fp
set fp [open $XDC w]
puts $fp "create_clock -period $OVERCONSTRAIN_NS -name $CLKPORT \[get_ports $CLKPORT\]"
close $fp
puts "INFO: clock over-constrained to ${OVERCONSTRAIN_NS} ns for the sweep"

# CSV header
set CSV "$OUTDIR/fmax_sweep.csv"
set ch [open $CSV w]
puts $ch "size,strategy,period_ns,wns_ns,fmax_mhz,lut,ff,bram,met,status"
close $ch

# ---- Sweep (wrapped so we always restore project state) ---------------------
set rc [catch {
  foreach size $SIZES {
    puts "==== SIZE $size ============================================"
    set_property generic "MAX_IMAGE_WIDTH=$size MAX_IMAGE_HEIGHT=$size" $FS
    reset_run synth_1
    launch_runs synth_1 -jobs $JOBS
    catch {wait_on_run synth_1} ;# wait_on_run THROWS on a failed run; swallow it and inspect PROGRESS below

    if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
      set ch [open $CSV a]
      foreach strat $STRATEGIES {
        puts $ch "$size,$strat,$OVERCONSTRAIN_NS,NA,NA,NA,NA,NA,0,SYNTH_FAIL"
      }
      close $ch
      puts "WARN: synth failed for size $size; skipping"
      continue
    }

    foreach strat $STRATEGIES {
      puts "---- strategy $strat ----"
      set_property strategy $strat [get_runs impl_1]
      reset_run impl_1
      launch_runs impl_1 -jobs $JOBS
      catch {wait_on_run impl_1} ;# don't let one failed impl abort the whole campaign

      if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
        set ch [open $CSV a]
        puts $ch "$size,$strat,$OVERCONSTRAIN_NS,NA,NA,NA,NA,NA,0,IMPL_FAIL"
        close $ch
        puts "WARN: impl failed for size $size / $strat"
        continue
      }

      open_run impl_1
      set wpath [lindex [get_timing_paths -delay_type max -max_paths 1 -nworst 1] 0]
      set wns   [get_property SLACK $wpath]
      set fmax  [expr {1000.0 / ($OVERCONSTRAIN_NS - $wns)}]
      set met   [expr {$wns >= 0 ? 1 : 0}]

      set tag "${size}_${strat}"
      report_timing_summary -file "$OUTDIR/rpt_${tag}_timing.log" -quiet
      set u [report_utilization -return_string]
      report_utilization -file "$OUTDIR/rpt_${tag}_util.log" -quiet
      set lut  [grab {CLB LUTs\s*\|\s*(\d+)}        $u NA]
      set ff   [grab {CLB Registers\s*\|\s*(\d+)}   $u NA]
      set bram [grab {Block RAM Tile\s*\|\s*([\d.]+)} $u NA]

      set ch [open $CSV a]
      puts $ch "$size,$strat,$OVERCONSTRAIN_NS,$wns,[format %.2f $fmax],$lut,$ff,$bram,$met,OK"
      close $ch
      puts "RESULT size=$size strat=$strat wns=$wns fmax=[format %.1f $fmax] MHz met=$met"
      if {$met} {
        puts "WARN: WNS>=0 at ${OVERCONSTRAIN_NS} ns for $size/$strat -> probe too loose; fmax is a FLOOR. Tighten OVERCONSTRAIN_NS and rerun this point."
      }
      close_design
    }
  }
} err]

# ---- Restore project state (always) -----------------------------------------
puts "INFO: restoring project state"
catch {close_design}
set fp [open $XDC w]; puts -nonewline $fp $XDC_ORIG; close $fp
catch {set_property generic "" $FS} ;# reset_property doesn't support <generic>; clear it with empty string
catch {set_property strategy $STD_STRATEGY [get_runs impl_1]}

if {$rc} {
  puts "ERROR: sweep aborted: $err"
} else {
  puts "DONE: results in $CSV"
}
close_project
