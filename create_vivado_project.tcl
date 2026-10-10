# ============================================================================
# Vivado TCL Project Generation Script
# Project: RV32I 5-Stage Core with 8-Digit Display & Hazard/Forwarding LEDs
# Target Device: Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T Board)
# ============================================================================

set proj_name "rv32i_5stage_core"
set proj_dir  "./vivado_project"
set part_num  "xc7a100tcsg324-1"

puts "=========================================================================="
puts "  CREATING VIVADO PROJECT: $proj_name for $part_num"
puts "=========================================================================="

# 1. Create project
create_project $proj_name $proj_dir -part $part_num -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# 2. Add RTL Design Sources
set rtl_files [list \
    [file normalize "feature_1/modules/opcode.vh"] \
    [file normalize "feature_1/modules/if_id_reg.v"] \
    [file normalize "feature_1/modules/id_ex_reg.v"] \
    [file normalize "feature_1/modules/ex_mem_reg.v"] \
    [file normalize "feature_1/modules/mem_wb_reg.v"] \
    [file normalize "feature_1/modules/hazard_unit.v"] \
    [file normalize "feature_1/modules/decode_stage.v"] \
    [file normalize "feature_1/modules/execute_stage.v"] \
    [file normalize "feature_1/modules/memory_stage.v"] \
    [file normalize "feature_1/modules/writeback_stage.v"] \
    [file normalize "feature_1/modules/pipe.v"] \
    [file normalize "feature_1/modules/memory.v"] \
    [file normalize "feature_1/modules/pipeline_5stage.v"] \
    [file normalize "feature_1/modules/seven_seg_controller.v"] \
    [file normalize "feature_1/modules/fpga_top_feature1.v"] \
]

add_files -norecurse -fileset sources_1 $rtl_files
set_property file_type "Verilog Header" [get_files [file normalize "feature_1/modules/opcode.vh"]]

# Set include directories
set_property include_dirs [list [file normalize "feature_1/modules"]] [current_fileset]

# Set Top Module for Synthesis / Implementation
set_property top fpga_top_feature1 [current_fileset]
update_compile_order -fileset sources_1

# 3. Add Constraints (.xdc)
set xdc_file [file normalize "feature_1/constraints/nexys_a7_100t.xdc"]
if {[file exists $xdc_file]} {
    add_files -norecurse -fileset constrs_1 $xdc_file
    set_property target_constrs_file $xdc_file [current_fileset -constrset]
    puts "\[+\] Added constraints file: $xdc_file"
}

# 4. Add Simulation Sources & Testbenches
set sim_files [list \
    [file normalize "feature_1/tb_pipeline_base.v"] \
    [file normalize "feature_1/tb_hazard.v"] \
    [file normalize "feature_1/mem/imem.hex"] \
    [file normalize "feature_1/mem/dmem.hex"] \
]

add_files -norecurse -fileset sim_1 $sim_files
set_property top tb_pipeline_base [get_filesets sim_1]
set_property top_lib work [get_filesets sim_1]
set_property include_dirs [list [file normalize "feature_1/modules"]] [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {15000ns} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "=========================================================================="
puts "  PROJECT CREATED SUCCESSFULLY!"
puts "  Project Location: [file normalize "$proj_dir/$proj_name.xpr"]"
puts "  Synthesis Top   : fpga_top_feature1"
puts "  Simulation Top  : tb_pipeline_base"
puts "=========================================================================="
