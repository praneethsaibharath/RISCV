@echo off
rem ============================================================================
rem Launcher script to open RV32M Hardware Multiplier (Feature 2) in Vivado GUI
rem ============================================================================
echo ==========================================================================
echo   Launching AMD Vivado for Feature 2: Hardware Multiplier (Group 13)...
echo ==========================================================================

cd /d "%~dp0"

if exist "vivado_project\rv32m_multiplier.xpr" (
    echo [*] Opening existing Vivado project: vivado_project\rv32m_multiplier.xpr
    start vivado "vivado_project\rv32m_multiplier.xpr"
) else (
    echo [*] Generating Vivado project from create_vivado_project.tcl...
    call vivado -mode batch -source create_vivado_project.tcl
    start vivado "vivado_project\rv32m_multiplier.xpr"
)
