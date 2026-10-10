@echo off
rem ============================================================================
rem Launcher script to open RV32I 5-Stage Core project in Vivado GUI
rem ============================================================================
echo ==========================================================================
echo   Launching AMD Vivado for RV32I 5-Stage Core (Group 13)...
echo ==========================================================================

if exist "vivado_project\rv32i_5stage_core.xpr" (
    echo [*] Opening existing Vivado project: vivado_project\rv32i_5stage_core.xpr
    start vivado "vivado_project\rv32i_5stage_core.xpr"
) else (
    echo [*] Generating Vivado project from create_vivado_project.tcl...
    call vivado -mode batch -source create_vivado_project.tcl
    start vivado "vivado_project\rv32i_5stage_core.xpr"
)
