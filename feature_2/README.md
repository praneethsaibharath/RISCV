# Feature 2: Hardware Multiplier (RV32M Extension) with DSP Acceleration

**Project:** Pipelined RV32IMF RISC-V Core with L1 Cache Hierarchy, Branch Prediction, and Math Accelerators  
**Course:** CS2202L (Group 13)  
**Deliverable Milestone (Week 12–18 Oct):** Hardware Multiplier with DSP Slices & Booth RTL  
**Deliverables:** `multiplier_dsp.v`, `booth_radix4_multiplier.v`, `multiplier_unit.v`, `tb_multiplier.v`, and `tb_feature2_pipeline.v`  

---

## 1. Architectural Overview

Feature 2 implements the complete **RISC-V RV32M Standard Multiplication Extension**, enabling single-cycle 32-bit hardware multiplication directly within the Execution (EX) stage of the 5-stage pipeline.

```
       +----+        +----+        +-------------------------+        +-----+        +----+
-----> | IF | -----> | ID | -----> | EX Stage: ALU / MULT    | -----> | MEM | -----> | WB | -----> (RegFile)
       +----+        +----+        +-------------------------+        +-----+        +----+
                                                ^
                                                |
                           +--------------------+--------------------+
                           |  FEATURE 2: HARDWARE MULTIPLIER UNIT   |
                           |  - DSP48E1 Accelerated Engine           |
                           |  - Radix-4 Modified Booth Engine        |
                           |  - Supported: MUL, MULH, MULHSU, MULHU  |
                           +-----------------------------------------+
```

### Supported Instructions:

| Instruction | Type | `opcode` | `funct3` | `funct7` | Operands | Result Returned | Output Bits |
|---|---|---|---|---|---|---|---|
| **`MUL`** | R-Type | `0110011` | `000` (`0x0`) | `0000001` | Signed $\times$ Signed | Low 32 bits | `product[31:0]` |
| **`MULH`** | R-Type | `0110011` | `001` (`0x1`) | `0000001` | Signed $\times$ Signed | High 32 bits | `product[63:32]` |
| **`MULHSU`** | R-Type | `0110011` | `010` (`0x2`) | `0000001` | Signed $\times$ Unsigned | High 32 bits | `product[63:32]` |
| **`MULHU`** | R-Type | `0110011` | `011` (`0x3`) | `0000001` | Unsigned $\times$ Unsigned | High 32 bits | `product[63:32]` |

---

## 2. DSP Acceleration Architecture (Artix-7 XC7A100T)

The primary multiplier implementation (`multiplier_dsp.v`) targets the dedicated **DSP48E1 slices** of the Xilinx Artix-7 FPGA:

### Mathematical Formulation:
To support all 4 signedness combinations without duplicating multiplier hardware, each 32-bit operand is dynamically extended to **33 bits**:
- **Signed Operand:** Sign-extended using its sign bit: $A_{ext} = \{A[31], A[31:0]\}$
- **Unsigned Operand:** Zero-extended: $A_{ext} = \{1'b0, A[31:0]\}$

By multiplying two 33-bit signed numbers:
$$P_{raw} = \$signed(A_{ext}) \times \$signed(B_{ext}) \quad (66\text{ bits})$$
- `MUL` result: $P_{raw}[31:0]$ (exact 32-bit lower product for both signed and unsigned values)
- `MULH`, `MULHSU`, `MULHU` result: $P_{raw}[63:32]$ (exact 32-bit upper product matching the respective sign rules)

### FPGA Resource Budget:
- Synthesized using the `(* use_dsp = "yes" *)` attribute.
- Utilizes **<= 4 DSP48E1 slices**, adhering to the project specification budget.
- Executes within **1 single clock cycle** at 100 MHz on the Artix-7 board without multi-cycle pipeline stalls.

---

## 3. Algorithmic Radix-4 Modified Booth Multiplier (`booth_radix4_multiplier.v`)

In addition to DSP inference, a pure algorithmic **Radix-4 Modified Booth Multiplier** is implemented:
1. **Booth Recoding**: Groups multiplier bits into 3-bit sliding windows $(y_{2i+1}, y_{2i}, y_{2i-1})$ with $y_{-1} = 0$.
2. **Partial Product Halving**: Reduces the number of partial products from 34 down to 17.
3. **Multiples Generated**: Generates factors $\{-2X, -X, 0, +X, +2X\}$ using bit shifts and two's complement arithmetic.
4. **Parameter Selection**: The top module `multiplier_unit.v` features a parameter `USE_DSP`:
   - `USE_DSP = 1` (Default): Direct Artix-7 DSP48 hard-macro mapping.
   - `USE_DSP = 0`: Pure logic Radix-4 Booth reduction array.

---

## 4. Pipeline Integration & Forwarding

### EX Stage Multiplexing:
The multiplier receives operands directly from the **Hazard Forwarding Multiplexers** (`forward_a` and `forward_b`):
- Any operand dependency from the preceding instruction (`EX/MEM` stage) is forwarded directly into `op_a` or `op_b`.
- Any operand dependency from 2 cycles prior (`MEM/WB` stage) is forwarded directly into `op_a` or `op_b`.

### Zero-Stall Result Bypassing:
Because the hardware multiplier executes in a single cycle in the EX stage:
- The result `mul_result` passes immediately to `ex_mem_reg`.
- Dependent instructions immediately following a `mul` receive the product via standard `EX/MEM -> EX` forwarding without incurring any pipeline bubble or stall cycle ($1.0\text{ IPC}$ maintained).

---

## 5. Verification & Test Suite

### 1. Unit Testbench (`tb_multiplier.v`)
- Tests 122 directed and randomized vectors.
- Verifies boundary conditions: $0$, $1$, $-1$, $\text{INT\_MIN}$ (`0x80000000`), $\text{INT\_MAX}$ (`0x7FFFFFFF`), $\text{UINT\_MAX}$ (`0xFFFFFFFF`).
- Cross-compares the DSP engine against the Radix-4 Booth engine and a software golden reference model.
- **Result:** **100% (122 / 122) Passed with 0 Errors**.

Run command:
```powershell
xvlog -sv feature_2/multiplier_dsp.v feature_2/booth_radix4_multiplier.v feature_2/multiplier_unit.v feature_2/tb_multiplier.v
xelab -debug typical tb_multiplier -s sim_tb_mult
xsim sim_tb_mult -R
```

### 2. Full 5-Stage Pipeline Testbench (`tb_feature2_pipeline.v`)
- Executes assembly sequence with back-to-back multiplications, negative numbers, upper-half multiplications, and ALU forwarding.
- Verifies retirement to register file:
  - `mul x3, x1, x2` $\implies 25 \times 16 = 400$
  - `addi x4, x3, 50` $\implies 400 + 50 = 450$ (Forwarding from multiplier verified!)
  - `mul x6, x1, x5` $\implies 25 \times (-4) = -100$ (Signed math verified!)
  - `mulh x7, x1, x2` $\implies 0$ (Upper 32 bits verified!)
- **Result:** **100% Assertions Passed**.

Run command:
```powershell
$files = (Get-ChildItem feature_1/modules/*.v).FullName
xvlog -sv $files feature_2/tb_feature2_pipeline.v
xelab -debug typical tb_feature2_pipeline -s sim_f2_pipe
xsim sim_f2_pipe -R
```

### 3. Interactive Terminal Simulation & Trace Visualizer
A compiled C multiplication benchmark is available:
```powershell
python run_pipeline_trace.py multiplication
```
Or with custom inline assembly:
```powershell
python run_pipeline_trace.py --asm "li x1, 50; li x2, -4; mul x3, x1, x2; mv a0, x3; ret"
```

---

## 6. Opening in AMD Vivado GUI

To open or synthesize the Feature 2 project in AMD Vivado:
1. Double-click or run [`feature_2/open_vivado.bat`](open_vivado.bat).
2. Or batch-generate the project:
   ```powershell
   cd feature_2
   vivado -mode batch -source create_vivado_project.tcl
   ```
3. Direct Project File: [`feature_2/vivado_project/rv32m_multiplier.xpr`](vivado_project/rv32m_multiplier.xpr).
