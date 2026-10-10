# ============================================================================
# File: create_vivado_project.tcl
# Description: Generates Standalone Vivado Project for Feature 2 (RV32M Multiplier)
# Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T)
# ============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PROJ_DIR [file join $SCRIPT_DIR "vivado_project"]
set PROJ_NAME "rv32m_multiplier_fpga"

puts "=========================================================="
puts " Creating Standalone Vivado Project for Feature 2 (RV32M) "
puts " Project Path: $PROJ_DIR/$PROJ_NAME.xpr"
puts "=========================================================="

file mkdir $PROJ_DIR
create_project -name $PROJ_NAME -dir $PROJ_DIR -part xc7a100tcsg324-1 -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# Add RTL Design Sources
set RTL_FILES [list \
    [file join $SCRIPT_DIR "modules" "opcode.vh"] \
    [file join $SCRIPT_DIR "modules" "multiplier_dsp.v"] \
    [file join $SCRIPT_DIR "modules" "booth_radix4_multiplier.v"] \
    [file join $SCRIPT_DIR "modules" "multiplier_unit.v"] \
    [file join $SCRIPT_DIR "modules" "decode_stage.v"] \
    [file join $SCRIPT_DIR "modules" "id_ex_reg.v"] \
    [file join $SCRIPT_DIR "modules" "execute_stage.v"] \
    [file join $SCRIPT_DIR "modules" "if_id_reg.v"] \
    [file join $SCRIPT_DIR "modules" "ex_mem_reg.v"] \
    [file join $SCRIPT_DIR "modules" "memory_stage.v"] \
    [file join $SCRIPT_DIR "modules" "mem_wb_reg.v"] \
    [file join $SCRIPT_DIR "modules" "writeback_stage.v"] \
    [file join $SCRIPT_DIR "modules" "hazard_unit.v"] \
    [file join $SCRIPT_DIR "modules" "memory.v"] \
    [file join $SCRIPT_DIR "modules" "pipe.v"] \
    [file join $SCRIPT_DIR "modules" "seven_seg_controller.v"] \
    [file join $SCRIPT_DIR "modules" "pipeline_5stage.v"] \
    [file join $SCRIPT_DIR "modules" "fpga_top_feature2.v"] \
]

add_files -norecurse -fileset sources_1 $RTL_FILES

# Set include directory for opcode.vh
set_property include_dirs [list [file join $SCRIPT_DIR "modules"]] [get_filesets sources_1]

# Add XDC Constraints
set XDC_FILE [file join $SCRIPT_DIR "constraints" "nexys_a7_100t.xdc"]
add_files -norecurse -fileset constrs_1 $XDC_FILE

# Add Memory Files
set MEM_FILES [list \
    [file join $SCRIPT_DIR "mem" "imem.hex"] \
    [file join $SCRIPT_DIR "mem" "dmem.hex"] \
]
add_files -norecurse -fileset sources_1 $MEM_FILES

# Set Top Module
set_property top fpga_top_feature2 [current_fileset]
update_compile_order -fileset sources_1

puts "=========================================================="
puts " Feature 2 Vivado Project Successfully Created!"
puts " Top Module: fpga_top_feature2"
puts "=========================================================="
