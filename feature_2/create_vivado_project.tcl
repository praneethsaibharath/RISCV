# ==============================================================================
# File: create_vivado_project.tcl
# Description: Automated Vivado Project Generator for Feature 2 (Hardware Multiplier)
# Target: Xilinx Artix-7 XC7A100T (xc7a100tcsg324-1)
# ==============================================================================

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR   [file normalize "$SCRIPT_DIR/.."]

set PROJECT_NAME "rv32m_multiplier"
set PROJECT_DIR  "$SCRIPT_DIR/vivado_project"
set PART_NUMBER  "xc7a100tcsg324-1"

puts "=========================================================================="
puts "  CREATING VIVADO PROJECT: $PROJECT_NAME (Feature 2)"
puts "  Target Part: $PART_NUMBER"
puts "  Project Dir: $PROJECT_DIR"
puts "=========================================================================="

# Create Project
create_project -force $PROJECT_NAME $PROJECT_DIR -part $PART_NUMBER

# Add Feature 2 Multiplier RTL Sources
add_files [list \
    "$SCRIPT_DIR/multiplier_dsp.v" \
    "$SCRIPT_DIR/booth_radix4_multiplier.v" \
    "$SCRIPT_DIR/multiplier_unit.v" \
]

# Add Core 5-Stage Pipeline RTL Sources
set MODULES_DIR "$ROOT_DIR/feature_1/modules"
add_files [list \
    "$MODULES_DIR/opcode.vh" \
    "$MODULES_DIR/if_id_reg.v" \
    "$MODULES_DIR/decode_stage.v" \
    "$MODULES_DIR/id_ex_reg.v" \
    "$MODULES_DIR/execute_stage.v" \
    "$MODULES_DIR/ex_mem_reg.v" \
    "$MODULES_DIR/memory_stage.v" \
    "$MODULES_DIR/mem_wb_reg.v" \
    "$MODULES_DIR/writeback_stage.v" \
    "$MODULES_DIR/hazard_unit.v" \
    "$MODULES_DIR/pipeline_5stage.v" \
    "$MODULES_DIR/memory.v" \
    "$MODULES_DIR/seven_seg_controller.v" \
    "$MODULES_DIR/fpga_top_feature1.v" \
]

# Set Verilog Include Directory
set_property include_dirs [list "$MODULES_DIR"] [current_fileset]

# Add XDC Constraints
set CONSTR_FILE "$ROOT_DIR/feature_1/constraints/nexys_a7_100t.xdc"
if {[file exists $CONSTR_FILE]} {
    add_files -fileset constrs_1 -norecurse $CONSTR_FILE
}

# Add Simulation Testbenches
add_files -fileset sim_1 [list \
    "$SCRIPT_DIR/tb_multiplier.v" \
    "$SCRIPT_DIR/tb_feature2_pipeline.v" \
]

# Set Top Modules
set_property top fpga_top_feature1 [current_fileset]
set_property top tb_multiplier [get_filesets sim_1]

# Enable VCD / Trace dumping
set_property -name {xsim.simulate.runtime} -value {10000ns} -objects [get_filesets sim_1]

puts "=========================================================================="
puts "  SUCCESS: Vivado project $PROJECT_NAME generated successfully!"
puts "  Open in GUI with: feature_2/open_vivado.bat"
puts "=========================================================================="
