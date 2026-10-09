# Feature 4: IEEE754 Single-Precision Floating Point Unit (FPU)

## Objectives & Scope
Implementation of an IEEE 754-2008 compliant single-precision (32-bit) Floating Point Unit integrated into the pipelined processor core (RV32F extension).

## Instruction Support
- **Arithmetic**: `FADD.S`, `FSUB.S`, `FMUL.S`, `FDIV.S`, `FSQRT.S`
- **Conversion**: `FCVT.W.S` (Float to signed integer), `FCVT.S.W` (Signed integer to float)
- **Comparison**: `FEQ.S`, `FLT.S`, `FLE.S`
- **Sign Injection**: `FSGNJ.S`, `FSGNJN.S`, `FSGNJX.S`
- **Memory**: `FLW` (Float load), `FSW` (Float store)

## Microarchitecture
- Dedicated 32-entry $\times$ 32-bit Floating-Point Register File (`f0`–`f31`)
- Multi-cycle execution pipeline with stall handshaking into the hazard unit
- Exception flags generation (Invalid Operation, Divide by Zero, Overflow, Underflow, Inexact)
- Rounding mode controller (Round to Nearest Even `RNE`, Round toward Zero `RTZ`, etc.)
