set SCRIPT_DIR [file normalize [file dirname [info script]]]
set PROJ_FILE [file join $SCRIPT_DIR "vivado_project" "rv32mf_fpu_fpga.xpr"]

puts "=========================================================="
puts " Opening Vivado Project: $PROJ_FILE"
puts "=========================================================="
open_project $PROJ_FILE

# Set pre-synthesis and pre-opt hooks to copy imem.hex and dmem.hex
set PRE_TCL [file join $SCRIPT_DIR "copy_hex.tcl"]
set_property STEPS.SYNTH_DESIGN.TCL.PRE $PRE_TCL [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.PRE $PRE_TCL [get_runs impl_1]

# Reset previous runs
reset_run synth_1
reset_run impl_1

# Pre-copy memory files directly into synth_1 and impl_1 directories
set SYNTH_DIR [file join $SCRIPT_DIR "vivado_project" "rv32mf_fpu_fpga.runs" "synth_1"]
set IMPL_DIR  [file join $SCRIPT_DIR "vivado_project" "rv32mf_fpu_fpga.runs" "impl_1"]
file mkdir $SYNTH_DIR
file mkdir $IMPL_DIR
file copy -force [file join $SCRIPT_DIR "mem" "imem.hex"] [file join $SYNTH_DIR "imem.hex"]
file copy -force [file join $SCRIPT_DIR "mem" "dmem.hex"] [file join $SYNTH_DIR "dmem.hex"]
file copy -force [file join $SCRIPT_DIR "mem" "imem.hex"] [file join $IMPL_DIR "imem.hex"]
file copy -force [file join $SCRIPT_DIR "mem" "dmem.hex"] [file join $IMPL_DIR "dmem.hex"]

puts ">>> Launching synthesis and implementation to bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 8

puts ">>> Waiting for synth_1 to complete..."
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "=========================================================="
puts " Synthesis complete: $synth_status"
puts "=========================================================="

if { [string first "ERROR" $synth_status] != -1 || [string first "failed" $synth_status] != -1 } {
    puts "ERROR: Synthesis failed!"
    exit 1
}

puts ">>> Waiting for impl_1 to complete..."
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "=========================================================="
puts " Bitstream generation complete: $impl_status"
puts "=========================================================="

if { [string first "ERROR" $impl_status] != -1 || [string first "failed" $impl_status] != -1 } {
    puts "ERROR: Implementation/Bitstream build failed!"
    exit 1
}

close_project
exit 0
