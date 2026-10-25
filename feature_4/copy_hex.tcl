# ============================================================================
# File: copy_hex.tcl
# Description: Pre-synthesis hook to ensure memory hex files are copied
#              into the synthesis execution directory (synth_1)
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set mem_dir [file join $script_dir "mem"]

if {![file exists [file join $mem_dir "imem.hex"]]} {
    set mem_dir "C:/RISCV/feature_4/mem"
}

puts "\[copy_hex.tcl\] Using mem_dir: $mem_dir"
puts "\[copy_hex.tcl\] Target directory (pwd): [pwd]"

if {[file exists [file join $mem_dir "imem.hex"]]} {
    file copy -force [file join $mem_dir "imem.hex"] [file join [pwd] "imem.hex"]
    puts "\[copy_hex.tcl\] Successfully copied imem.hex to [pwd]"
} else {
    puts "\[copy_hex.tcl\] CRITICAL ERROR: $mem_dir/imem.hex not found!"
}

if {[file exists [file join $mem_dir "dmem.hex"]]} {
    file copy -force [file join $mem_dir "dmem.hex"] [file join [pwd] "dmem.hex"]
    puts "\[copy_hex.tcl\] Successfully copied dmem.hex to [pwd]"
} else {
    puts "\[copy_hex.tcl\] CRITICAL ERROR: $mem_dir/dmem.hex not found!"
}
