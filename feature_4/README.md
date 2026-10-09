# Feature 4: IEEE754 Single-Precision FPU (RV32F)

## Objectives & Scope
Integration of an IEEE 754-2008 single-precision (32-bit) Floating Point Unit (FPU) supporting standard floating-point arithmetic instructions:
- `FADD.S`: Floating-Point Addition
- `FSUB.S`: Floating-Point Subtraction
- `FMUL.S`: Floating-Point Multiplication
- `FDIV.S`: Floating-Point Division

## Microarchitecture
- Dedicated 32-entry $\times$ 32-bit Floating-Point Register File (`f0` – `f31`)
- Multi-cycle execution pipelines with stall signaling into the hazard unit
- Standard IEEE 754 sign, 8-bit biased exponent, and 23-bit mantissa formatting
- Rounding modes (Round to Nearest Even `RNE`, Round toward Zero `RTZ`, etc.)
- Exception flag status generation (Divide-by-zero, Invalid, Overflow, Underflow, Inexact)
