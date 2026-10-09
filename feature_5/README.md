# Feature 5: Hardware Divider (RV32M)

## Objectives & Scope
Integration of a multi-cycle hardware divider into the Execute (EX) stage to support integer division and remainder instructions from the standard RISC-V "M" extension.

## Supported Instructions
- `DIV`: Signed integer division ($rs1 / rs2$)
- `DIVU`: Unsigned integer division ($rs1 / rs2$)
- `REM`: Signed remainder ($rs1 \pmod{rs2}$)
- `REMU`: Unsigned remainder ($rs1 \pmod{rs2}$)

## Microarchitecture & Integration
- Multi-cycle non-restoring / Radix-2 state machine (32 clock cycle latency)
- Dynamic stall controller asserting `divider_stall` to freeze the pipeline during computation
- Corner cases handled:
  - Division by zero ($rs2 == 0$): sets quotient to $-1$ or $2^{32}-1$, remainder to dividend
  - Signed overflow ($\text{INT\_MIN} / -1$): sets quotient to $\text{INT\_MIN}$, remainder to $0$
