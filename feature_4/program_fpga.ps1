# ============================================================================
# Script: program_fpga.ps1
# Description: Powershell helper to program the Nexys A7 FPGA
# ============================================================================

$VIVADO = "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat"
$SCRIPT = Join-Path $PSScriptRoot "program_fpga.tcl"

Write-Host ">>> Programming Digilent Nexys A7-100T with Feature 4 RV32IMF Bitstream..." -ForegroundColor Cyan
& $VIVADO -mode batch -source $SCRIPT -nojournal -nolog
