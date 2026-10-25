# ============================================================================
# File: program_fpga.tcl
# Description: Connects to Nexys A7-100T via Vivado Hardware Manager and programs bitstream
# ============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set BIT_FILE [file join $SCRIPT_DIR "vivado_project" "rv32mf_fpu_fpga.runs" "impl_1" "fpga_top_feature4.bit"]

if {![file exists $BIT_FILE]} {
    set BIT_FILE [file join $SCRIPT_DIR "fpga_top_feature4.bit"]
}

if {![file exists $BIT_FILE]} {
    puts "ERROR: Bitstream file not found at $BIT_FILE"
    exit 1
}

puts "=========================================================="
puts " Connecting to Hardware Server and Programming Nexys A7-100T"
puts " Bitstream: $BIT_FILE"
puts "=========================================================="

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices xc7a100t_0] 0]
if {$device eq ""} {
    puts "ERROR: xc7a100t_0 device not found on JTAG chain!"
    exit 1
}

current_hw_device $device
refresh_hw_device -update_hw_probes false $device

set_property PROBES.FILE {} $device
set_property FULL_PROBES.FILE {} $device
set_property PROGRAM.FILE $BIT_FILE $device

puts ">>> Programming device $device ..."
program_hw_devices $device
refresh_hw_device $device

puts "=========================================================="
puts " Nexys A7-100T programmed successfully!"
puts "=========================================================="

close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
