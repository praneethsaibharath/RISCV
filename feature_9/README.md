# Feature 9: RISC-V Bit Manipulation Extension (Zba / Zbb / Zbs)

## Objectives & Scope
Integration of standard RISC-V Bit Manipulation instructions into the Execution (EX) stage ALU to accelerate cryptography, hashing, parsing, and arithmetic.

## Supported Instruction Subsets

### 1. Count & Extract Operations (Zbb)
- `CLZ`: Count Leading Zeros
- `CTZ`: Count Trailing Zeros
- `CPOP`: Count Set Bits (Population Count)
- `MIN`, `MAX`, `MINU`, `MAXU`: Minimum/Maximum signed and unsigned

### 2. Logical with Negate (Zbb)
- `ANDN`: AND with inverted operand ($rs1 \ \& \ \sim rs2$)
- `ORN`: OR with inverted operand ($rs1 \ \| \ \sim rs2$)
- `XNOR`: Exclusive NOR ($rs1 \ \oplus \ \sim rs2$)

### 3. Bitwise Rotations (Zbb)
- `ROR`, `RORI`: Rotate Right (register and immediate)
- `ROL`: Rotate Left

### 4. Single-Bit Operations (Zbs)
- `BSET`, `BSETI`: Bit Set
- `BCLR`, `BCLRI`: Bit Clear
- `BINV`, `BINVI`: Bit Invert
- `BEXT`, `BEXTI`: Bit Extract

### 5. Address Generation (Zba)
- `SH1ADD`, `SH2ADD`, `SH3ADD`: Shift by 1/2/3 and add (for array indexing)
