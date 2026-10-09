# Block Diagram Report

**Project Title:** Design and FPGA Implementation of a Pipelined RV32IMF Processor Core with L1 Cache Hierarchy, Branch Prediction, and Hardware Math Accelerators  
**Group Number:** Group 13  
**Target Device:** Xilinx Artix-7 XC7A100T-1CSG324C (Digilent Nexys A7-100T FPGA)  
**Authors / Team Members:**
- Sigilipelli Praneeth Sai Bharath (`praneethsaibharath`)
- Bandaru Rohith Datta (`Rohith-Datta`)
- Siddharth Misro (`sidmisro`)
- Pisini Ramana (`thisispisiniramana`)
- Chimbili Sahithi (`chimbilisahithi`)

---

## 1. Top-Level Hardware Block Diagram

```text
===================================================================================================================================================================
                                                  TOP-LEVEL HARDWARE BLOCK DIAGRAM: RV32IMF 5-STAGE PIPELINED CORE
===================================================================================================================================================================

       +--------------------------------------------------------------------------------------------------------------------------------------------------+
       |                                                 Feature 7: Static 32-Entry Branch Target Buffer (BTB)                                            |
       +--------------------------------------------------------------------------------------------------------------------------------------------------+
                                        | pc[31:0]                                                                       ^ actual_target[31:0]
                                        v                                                                                | actual_taken / update_pc
                                  [btb_hit, btb_target[31:0]]                                                            |
                                        |                                                                                |
                                        +---------------------------------------+                                        |
                                                                                |                                        |
     +--------------------------------------------------------------------+     |                                        |
     |                                                                    |     |                                        |
     |   +-------------------+                                            v     v                                        |
     +-->| 0                 |                                         +-------------+                                   |
         |   PC Multiplexer  |----->[ pc_next[31:0] ]----------------->|   PC Reg    |                                   |
     +-->| 1 (branch_target) |                                         |   [31:0]    |--+                                |
     |   +-------------------+                                         +-------------+  |                                |
     |             ^                                                          ^         | pc[31:0]                       |
     |             | branch_taken                                             | clk,rst |                                |
     |             |                                                    (~pc_stall)     +--------------------+           |
     |             |                                                                    |                    |           |
     |             |                                                                    v                    v           |
     |             |                                                             +--------------+     +--------------+   |
     |             |                                                             |  Adder (+4)  |     |  Feature 3:  |   |
     |             |                                                             +--------------+     |  L1 I-Cache  |   |
     |             |                                                                    |             | (Direct-Map) |   |
     |             |                                                        pc_plus_4   |             +--------------+   |
     |             |                                                          [31:0]    |                    |           |
     |             |                                                                    |         instr[31:0]|           |
     |             |                                                                    |         icache_stall           |
     |             |                                                                    v                    v           |
=====|=============|==================================================================[ IF/ID PIPELINE REGISTER ]======|===
     |             |                                                                    |                    |           |
     |             |                                                          pc_plus_4 |        instr[31:0] |           |
     |             |                                                                    v                    v           |
     |             |                                                                          +----------------------+   |
     |             |                                                                          |     Control Unit     |   |
     |             |                                                                          +----------------------+   |
     |             |                                                                                     | Control Lines |
     |             |                                                                                     v (EX, MEM, WB) |
     |             |                                           +------------------------------------+    |               |
     |             |                                           |     Register File (x0 - x31)       |    |               |
     |             |                                           |        Dual Read / 1 Write         |    |               |
     |             |                                           +------------------------------------+    |               |
     |             |                                              | rs1_data[31:0]    | rs2_data[31:0]   |               |
     |             |                                              v                   v                  |               |
     |             |       +------------------------------------+ |                   |                  |               |
     |             |       |    HAZARD DETECTION UNIT           | |                   |                  |               |
     |             |       | - Load-Use Stall Logic             | |                   |                  |               |
     |             |       | - Divider / FPU Multi-Cycle Stall  | |                   |                  |               |
     |             |       | - I-Cache & D-Cache Stall Interlock| |                   |                  |               |
     |             |       +------------------------------------+ |                   |                  |               |
     |             |          | pc_stall, if_id_stall             |                   |                  |               |
     |             |          | id_ex_flush, if_id_flush          |                   |                  |               |
     |             |          v                                   v                   v                  v               |
=====|=============|============================================[ ID/EX PIPELINE REGISTER ]==============================|===
     |             |                                              | rs1_data          | rs2_data         | Control       |
     |             |                                              v                   v                  v               |
     |             |        ForwardA [1:0]                     +--------+          +--------+                            |
     |             |        +--------------------------------->| Mux A  |          | Mux B  |<---------------------------+ ForwardB [1:0]
     |             |        |                                  +--------+          +--------+                            |
     |             |        |                                       | op1_fwd           | op2_fwd                        |
     |             |        |                                       +--------+   +------+--------+                       |
     |             |        |                                                |   |               |                       |
     |             |        |                                                v   v               v                       |
     |             |        |                                         +-------------+    +---------------+               |
     |             |        |   +------------------------------------>| Base ALU    |    |  ALUSrcB Mux  |               |
     |             |        |   |                                     | (RV32I)     |    +---------------+               |
     |             |        |   |                                     +-------------+            | alu_in_b              |
     |             |        |   |                                            |                   v                       |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |    | Feature 2: HW Multiplier    |        |
     |             |        |   |                                            |    | (Radix-4 Booth / DSP48E2)   |        |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |                   | mul_out[31:0]         |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |    | Feature 5: HW Divider       |        |
     |             |        |   |                                            |    | (Radix-2 Non-Restoring)     |        |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |                   | div_out, div_busy     |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |    | Feature 4: IEEE 754 FPU     |        |
     |             |        |   |                                            |    | (Single-Precision 32-bit)   |        |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |                   | fpu_out, fpu_busy     |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |    | Feature 9: Bit-Manip (Zbb)  |        |
     |             |        |   |                                            |    | (CLZ, CTZ, CPOP, MIN, MAX)  |        |
     |             |        |   |                                            |    +-----------------------------+        |
     |             |        |   |                                            |                   | zbb_out[31:0]         |
     |             |        |   |                                            v                   v                       |
     |             |        |   |                                        +----------------------------------+                |
     |             |        |   |                                        |     Execution Output Multiplexer |                |
     |             |        |   |                                        +----------------------------------+                |
     |             |        |   |                                                          | ex_result[31:0]                 |
     |             |        |   |     +----------------------------+                       |                                 |
     |             |        |   |     | Branch & Jump Unit (EX)    |                       |                                 |
     |             |        |   |     | - Target Adder: pc + imm   |                       |                                 |
     |             |        |   |     | - Condition Comparator     |                       |                                 |
     |             |        |   |     +----------------------------+                       |                                 |
     |             |        |   |       | branch_target[31:0]                              |                                 |
     |             |        |   |       | branch_taken                                     |                                 |
     |             +--------|---|-------|--------------------------------------------------+                                 |
     +----------------------+   |       |                                                  |                                 |
                                |       v                                                  v                                 |
================================|=====[ EX/MEM PIPELINE REGISTER ]===========================================================|===
                                |       |                                                  |                                 |
                                |       | EX/MEM Forward Bus [31:0]                        v ex_result (dmem_addr)           |
                                +-------+---------------------------------------->+------------------+                       |
                                                                                 | Feature 6:       |                       |
                                                                                 | L1 D-Cache       |                       |
                                                                                 | (Direct-Mapped)  |                       |
                                                                                 +------------------+                       |
                                                                                          | dmem_rdata[31:0]                 |
                                                                                          | dcache_stall                     |
                                                                                          v                                  |
===============================================================================[ MEM/WB PIPELINE REGISTER ]==================|===
                                                                                          |                                  |
                                                                                          | MEM/WB Forward Bus [31:0]        |
                                                                                          +----------------------------------+
                                                                                          |
                                      +---------------------------------------------+     |
                                      | Feature 8: Performance Counters (Passive)   |     |
                                      | CSRs: cycle, instret, stalls, misses        |     |
                                      +---------------------------------------------+     |
                                                             | csr_rdata[31:0]            |
                                                             v                            v
                                                     +--------------------------------------------+
                                                     |        Writeback Multiplexer (4-to-1)      |
                                                     +--------------------------------------------+
                                                                            | wb_data [31:0]
                                                                            v
                                             +------------------------------------------------------------+
                                             | Routed back to Register File Port rd & WB-to-ID Bypass Bus |
                                             +------------------------------------------------------------+
===================================================================================================================================================================
```

### Architectural Signal and Bus Width Definitions

| Signal Name | Source Module | Destination | Width | Function / Description |
|---|---|---|:---:|---|
| `pc` | PC Register | L1 I-Cache, Adder, BTB | 32 bits | Current program counter address |
| `pc_plus_4` | Adder (+4) | IF/ID Register, PC Mux | 32 bits | Sequential next instruction address |
| `instr` | L1 I-Cache | IF/ID Register | 32 bits | Fetched instruction machine word |
| `btb_target` | Static 32-entry BTB | PC Multiplexer | 32 bits | Predicted branch target address on BTB hit |
| `btb_hit` | Static 32-entry BTB | Fetch Control | 1 bit | Active high when PC matches an entry in the BTB |
| `rs1_data`, `rs2_data`| Register File | ID/EX Register | 32 bits | Source register operand values from dual read ports |
| `imm` | Imm Generator | ID/EX Register | 32 bits | Sign-extended 32-bit immediate for I/S/B/U/J types |
| `pc_stall` | Hazard Unit | PC Register Enable | 1 bit | Active high freeze signal for PC register on stalls |
| `if_id_stall` | Hazard Unit | IF/ID Register Enable | 1 bit | Active high hold signal for IF/ID register on stalls |
| `id_ex_flush` | Hazard Unit | ID/EX Sync Clear | 1 bit | Injects synchronous bubble (NOP) into ID/EX on hazard |
| `if_id_flush` | Hazard Unit | IF/ID Sync Clear | 1 bit | Injects synchronous bubble into IF/ID on branch taken |
| `forward_a`, `forward_b` | Forwarding Unit | Mux A, Mux B | 2 bits | Selects operand bypass (`00`=RF, `01`=EX/MEM, `10`=MEM/WB) |
| `mul_out` | Feature 2 Multiplier | EX Result Mux | 32 bits | Lower or upper 32 bits of 64-bit product (`MUL`/`MULH`) |
| `div_out` | Feature 5 Divider | EX Result Mux | 32 bits | Quotient or remainder of 32-bit integer division |
| `div_busy` | Feature 5 Divider | Hazard Unit | 1 bit | Multi-cycle stall request signal (asserted for 32 cycles) |
| `fpu_out` | Feature 4 FPU | EX Result Mux | 32 bits | IEEE 754 single-precision float calculation result |
| `fpu_busy` | Feature 4 FPU | Hazard Unit | 1 bit | Multi-cycle FPU stall request signal |
| `zbb_out` | Feature 9 Zbb Unit | EX Result Mux | 32 bits | Result of bit manipulation operations (`CLZ`, `CPOP`, etc.) |
| `branch_taken` | Branch Unit | PC Mux, Hazard Unit | 1 bit | Evaluated branch condition in EX stage |
| `branch_target`| Branch Unit | PC Mux | 32 bits | Target address calculated in EX stage (`pc_ex + imm`) |
| `ex_result` | EX Result Mux | EX/MEM Reg, D-Cache | 32 bits | Memory byte address or ALU result |
| `dmem_rdata` | Feature 6 D-Cache | MEM/WB Register | 32 bits | Data word read from L1 Data Cache |
| `dcache_stall` | Feature 6 D-Cache | Hazard Unit | 1 bit | Stall request during D-Cache miss burst refill |
| `icache_stall` | Feature 3 I-Cache | Hazard Unit | 1 bit | Stall request during I-Cache miss burst refill |
| `csr_rdata` | Feature 8 Counters | WB Multiplexer | 32 bits | Passive performance counter values (`cycle`, `instret`) |
| `wb_data` | WB Multiplexer | Register File Write | 32 bits | Final retirement result written to `rd` in RegFile |
| `clk`, `reset_n` | Clock Management | All Modules | 1 bit | 100 MHz oscillator and active-low synchronous reset |

---

## 2. Timing Diagram (24 Clock Cycles with Hazards)

The following timing diagram traces a benchmark sequence containing:
1. **EX-to-EX and MEM-to-EX operand forwarding**
2. **Single-cycle hardware multiplier execution (`MUL`)**
3. **Load-use data hazard with 1-cycle pipeline freeze and bubble insertion**
4. **Multi-cycle hardware division (`DIV`) holding pipeline stall via `div_busy`**
5. **Branch taken control hazard with 2-cycle flush of speculative instructions**

### Real Instruction Benchmark Sequence

| Label | Address | Instruction | Type | Operands / Hazard Characteristics |
|---|---|---|---|---|
| **I1** | `0x00` | `addi x1, x0, 10` | I-Type | Initializer: writes `x1 = 10` |
| **I2** | `0x04` | `addi x2, x0, 2`  | I-Type | Initializer: writes `x2 = 2` |
| **I3** | `0x08` | `mul  x3, x1, x2` | R-Type | **Feature 2 Multiplier**: Dual forwarding (`x1` from EX/MEM, `x2` from MEM/WB) |
| **I4** | `0x0C` | `lw   x4, 0(x3)`  | I-Type | Memory Load: Address `x3` forwarded from EX/MEM stage |
| **I5** | `0x10` | `add  x5, x4, x1` | R-Type | **Load-Use Hazard on `x4`**: 1-cycle stall in ID; bubble inserted into EX |
| **I6** | `0x14` | `div  x6, x5, x2` | R-Type | **Feature 5 Divider**: Multi-cycle stall in EX stage (`div_busy` asserted) |
| **I7** | `0x18` | `sub  x7, x6, x1` | R-Type | Consumes `x6` from Divider via EX/MEM forwarding |
| **I8** | `0x1C` | `beq  x7, x0, target` | B-Type | **Branch Taken in EX**: Evaluates condition; triggers 2-cycle flush |
| **I9** | `0x20` | `addi x8, x0, 99` | I-Type | *Speculatively fetched in ID* $\rightarrow$ **FLUSHED to BUBBLE** |
| **I10**| `0x24` | `addi x9, x0, 99` | I-Type | *Speculatively fetched in IF* $\rightarrow$ **FLUSHED to BUBBLE** |
| **I11**| `0x38` | `target: addi x10, x7, 5` | I-Type | **Branch Target**: Fetched after PC redirection; completes to Writeback |
| **I12**| `0x3C` | `sw   x10, 4(x3)` | S-Type | Memory Store: Writes computed result into memory |

---

### Cycle-by-Cycle Pipeline Reservation Table (Cycles 1 to 24)

```text
Cycle | IF Stage      | ID Stage      | EX Stage      | MEM Stage     | WB Stage      | Hazard / Control Signals
======+===============+===============+===============+===============+===============+==============================================
 CC01 | I1 (addi x1)  | —             | —             | —             | —             | Normal fetch
 CC02 | I2 (addi x2)  | I1 (addi x1)  | —             | —             | —             | Normal fetch
 CC03 | I3 (mul x3)   | I2 (addi x2)  | I1 (addi x1)  | —             | —             | I1 executes in EX
 CC04 | I4 (lw x4)    | I3 (mul x3)   | I2 (addi x2)  | I1 (addi x1)  | —             | FwdA=01 (x1 to I2)
 CC05 | I5 (add x5)   | I4 (lw x4)    | I3 (mul x3)*  | I2 (addi x2)  | I1 (addi x1)  | F2 MUL in EX: FwdA=10 (x1), FwdB=01 (x2)
 CC06 | I6 (div x6)   | I5 (add x5)   | I4 (lw x4)    | I3 (mul x3)   | I2 (addi x2)  | I4 in EX; Hazard Unit detects Load-Use on x4!
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC07 | I6 [FROZEN]   | I5 [FROZEN]   | BUBBLE [NOP]  | I4 (lw x4)    | I3 (mul x3)   | LOAD-USE STALL 1: pc_stall=1, if_id_stall=1
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC08 | I7 (sub x7)   | I6 (div x6)   | I5 (add x5)   | BUBBLE [NOP]  | I4 (lw x4)    | Stall released; FwdA=10 (x4 from WB to I5)
 CC09 | I8 (beq)      | I7 (sub x7)   | I6 (div x6)#  | I5 (add x5)   | BUBBLE [NOP]  | F5 DIV starts in EX; div_busy=1 asserted
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC10 | I8 [FROZEN]   | I7 [FROZEN]   | I6 (div cyc2)#| BUBBLE [NOP]  | I5 (add x5)   | MULTI-CYCLE DIV STALL (Cycle 1): pc_stall=1
 CC11 | I8 [FROZEN]   | I7 [FROZEN]   | I6 (div cyc3)#| BUBBLE [NOP]  | BUBBLE [NOP]  | MULTI-CYCLE DIV STALL (Cycle 2): pc_stall=1
 CC12 | I8 [FROZEN]   | I7 [FROZEN]   | I6 (div cyc4)#| BUBBLE [NOP]  | BUBBLE [NOP]  | MULTI-CYCLE DIV STALL (Cycle 3): div_busy=0
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC13 | I9 (spec)     | I8 (beq)      | I7 (sub x7)   | I6 (div x6)   | BUBBLE [NOP]  | Div complete! FwdA=01 (x6 from MEM to I7)
 CC14 | I10 (spec)    | I9 (spec)     | I8 (beq)*     | I7 (sub x7)   | I6 (div x6)   | Branch Condition TRUE in EX! branch_taken=1
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC15 | I11 (target)  | BUBBLE [FLUSH]| BUBBLE [FLUSH]| I8 (beq)      | I7 (sub x7)   | 2-CYCLE FLUSH: I9 & I10 annulled; PC redirected
 CC16 | I12 (sw)      | I11 (target)  | BUBBLE [FLUSH]| BUBBLE [FLUSH]| I8 (beq)      | Pipeline resumes from target; I11 in ID
------+---------------+---------------+---------------+---------------+---------------+----------------------------------------------
 CC17 | —             | I12 (sw)      | I11 (target)  | BUBBLE [FLUSH]| BUBBLE [FLUSH]| I11 executes in EX
 CC18 | —             | —             | I12 (sw)      | I11 (target)  | BUBBLE [FLUSH]| I12 calculates address; I11 in MEM
 CC19 | —             | —             | —             | I12 (sw)      | I11 (target)  | I12 writes to D-Cache; I11 retires in WB
 CC20 | —             | —             | —             | —             | I12 (sw)      | I12 completes memory stage; retires
 CC21 | —             | —             | —             | —             | —             | Program termination / post-drain
 CC22 | —             | —             | —             | —             | —             | Passive CSR counters hold final profile
 CC23 | —             | —             | —             | —             | —             | Cycle counter = 23, retired instructions = 8
 CC24 | —             | —             | —             | —             | —             | Pipeline fully drained
=============================================================================================================================
Legend:
 *  : Single-cycle operand forwarding active.
 #  : Multi-cycle arithmetic unit active (holding pipeline stall).
[FLUSH]: Instruction cleared by control hazard unit (converted to bubble NOP).
```

---

## 3. Module Summary Table

| Module | Purpose | File | Implementation Type |
|---|---|---|---|
| `pipeline_5stage` | Top-level structural core integrating IF, ID, EX, MEM, WB | `feature_1/modules/pipeline_5stage.v` | Hardware (Verilog HDL) |
| `if_id_reg` | Pipeline register with synchronous stall freeze and branch flush | `feature_1/modules/if_id_reg.v` | Hardware (Verilog HDL) |
| `decode_stage` | Instruction decoder, sign extender, 32-entry dual-port RegFile | `feature_1/modules/decode_stage.v` | Hardware (Verilog HDL) |
| `id_ex_reg` | Pipeline register holding operands and control lines for EX | `feature_1/modules/id_ex_reg.v` | Hardware (Verilog HDL) |
| `execute_stage` | Base 32-bit ALU, branch comparator, and EX output multiplexer | `feature_1/modules/execute_stage.v` | Hardware (Verilog HDL) |
| `hazard_unit` | Detects load-use hazards, branch taken, and multi-cycle stalls | `feature_1/modules/hazard_unit.v` | Hardware (Verilog HDL) |
| `forwarding_unit` | Selects EX/MEM and MEM/WB bypass multiplexer paths (Mux A/B) | `feature_1/modules/hazard_unit.v` | Hardware (Verilog HDL) |
| `ex_mem_reg` | Pipeline register passing memory address, write data, control | `feature_1/modules/ex_mem_reg.v` | Hardware (Verilog HDL) |
| `memory_stage` | Memory interface with byte/halfword alignment masking | `feature_1/modules/memory_stage.v` | Hardware (Verilog HDL) |
| `mem_wb_reg` | Pipeline register passing final load data and ALU result to WB | `feature_1/modules/mem_wb_reg.v` | Hardware (Verilog HDL) |
| `writeback_stage` | Writeback multiplexer selecting memory, ALU, link PC, or CSR | `feature_1/modules/writeback_stage.v` | Hardware (Verilog HDL) |
| `multiplier_unit` | **Feature 2**: Radix-4 Booth / DSP multiplier (`MUL`/`MULH`) | `feature_2/multiplier_unit.v` | Hardware (Verilog HDL) |
| `icache_controller`| **Feature 3**: Direct-mapped 2 KB L1 Instruction Cache & FSM | `feature_3/icache_controller.v` | Hardware (Verilog HDL) |
| `fpu_single_core` | **Feature 4**: IEEE 754 single-precision FPU (`FADD`, `FMUL`) | `feature_4/fpu_single_core.v` | Hardware (Verilog HDL) |
| `divider_unit` | **Feature 5**: Radix-2 non-restoring divider with stall handshaking | `feature_5/divider_unit.v` | Hardware (Verilog HDL) |
| `dcache_controller`| **Feature 6**: Direct-mapped 2 KB L1 Data Cache & write buffer | `feature_6/dcache_controller.v` | Hardware (Verilog HDL) |
| `btb_branch_pred` | **Feature 7**: Static 32-entry Branch Target Buffer (BTB) | `feature_7/btb_branch_pred.v` | Hardware (Verilog HDL) |
| `csr_perf_counters`| **Feature 8**: Passive performance CSR monitoring registers | `feature_8/csr_perf_counters.v` | Hardware (Verilog HDL) |
| `bitmanip_unit` | **Feature 9**: Zbb bit manipulation ALU (`CLZ`, `CPOP`, `MIN`, `MAX`)| `feature_9/bitmanip_unit.v` | Hardware (Verilog HDL) |

---

## 4. Hardware Resource Estimates

Target FPGA Architecture: **Xilinx Artix-7 XC7A100T-1CSG324C** (Digilent Nexys A7 Board)

| Hardware Resource | Maximum Available on XC7A100T | Estimated Core Usage | % Utilization | Engineering Justification |
|---|:---:|:---:|:---:|---|
| **LUTs (Look-Up Tables)** | **63,400** | **9,450** | **14.9 %** | Base 5-stage core (2,100), FPU arithmetic (3,800), Divider (950), Bit-manip (800), Caches (1,800) |
| **FF (Flip-Flops)** | **126,800** | **6,820** | **5.4 %** | Pipeline registers (1,200), FPU registers (1,024), Cache tags/data (2,500), CSR counters (640) |
| **BRAM (36Kb Blocks)** | **135 blocks** (4,860 Kb) | **8 blocks** | **5.9 %** | 4 BRAMs for L1 I-Cache data array, 4 BRAMs for L1 D-Cache data array |
| **DSP48E1 Slices** | **240 slices** | **4 slices** | **1.7 %** | Dedicated to high-speed single-cycle 32-bit integer multiplication (`MUL`/`MULH`) and FPU mantissa |

---

## 5. Verification Plans

- **Automated C Benchmark Suite**: Validate full-system processor execution across arithmetic, iterative loops, memory arrays, and logic operations using standalone bare-metal C programs (`addition.c`, `fibonacci.c`, `sort.c`, `negative.c`, `xor.c`) running on Vivado Simulator (`xsim`).
- **Targeted Unit Math Testbenches**: Exhaustively verify the Hardware Multiplier (Feature 2) and Divider (Feature 5) across signed/unsigned boundary conditions, division by zero ($rs2 = 0$), and overflow ($\text{INT\_MIN} / -1$).
- **Cache Hit/Miss Assertion Framework**: Verify L1 I-Cache and D-Cache refill state machines using memory access patterns that provoke sequential hits, cold misses, capacity evictions, and byte-enable store masking.
- **Hardware-in-the-Loop FPGA Validation**: Synthesize the core with a UART diagnostic interface and 7-segment display on the Nexys A7 FPGA to verify real-time performance counters and retired instruction metrics at 100 MHz.

---

## 6. Project Gantt Chart & Milestone Schedule

**Team Members (Group 13):**
- **Student 1 (S1):** Sigilipelli Praneeth Sai Bharath
- **Student 2 (S2):** Bandaru Rohith Datta
- **Student 3 (S3):** Siddharth Misro
- **Student 4 (S4):** Pisini Ramana
- **Student 5 (S5):** Sahithi Chimbili

**Key Deadlines:**
- **Milestone 1 Core Completion:** October 25, 2026
- **Minimum System Commitment:** November 1, 2026
- **Final Demonstration:** November 8, 2026

| # | Concrete Testable Activity | Owner | Duration | Oct 01–10 | Oct 11–18 | Oct 19–25 | Oct 26–Nov 01 | Nov 02–08 |
|:---:|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| 1 | Baseline 5-stage pipeline registers & datapath integration | S1 | Oct 01–07 | [DONE] | | | | |
| 2 | Hazard Detection Unit & forwarding multiplexers implementation | S2 | Oct 04–08 | [DONE] | | | | |
| 3 | Full-system testbench & C compiler automation toolchain | S1 | Oct 06–09 | [DONE] | | | | |
| 4 | Timing analysis, stall verification & reservation charts | S4 | Oct 07–09 | [DONE] | | | | |
| 5 | Radix-4 Booth Multiplier RTL implementation & testbench | S2 | Oct 10–15 | | [ACTIVE]| | | |
| 6 | Direct-mapped L1 Instruction Cache & refill FSM design | S3 | Oct 11–17 | | [ACTIVE]| | | |
| 7 | Multiplier EX stage integration & `MUL`/`MULH` C validation | S1 | Oct 16–20 | | | [PLANNED]| | |
| 8 | Multi-cycle Radix-2 Hardware Divider & stall controller | S4 | Oct 14–21 | | | [PLANNED]| | |
| 9 | Direct-mapped L1 Data Cache & write-through controller | S3 | Oct 18–24 | | | [PLANNED]| | |
| 10| **Milestone 1 Review: Pipeline + Caches + Math Modules** | **ALL** | **Oct 25** | | | **[MS 1]** | | |
| 11| Static 32-entry Branch Target Buffer (BTB) RTL & fetch hook | S5 | Oct 22–28 | | | | [PLANNED]| |
| 12| IEEE 754 single-precision FPU (`FADD`, `FMUL`) core design | S2 | Oct 24–30 | | | | [PLANNED]| |
| 13| Passive CSR Performance Counters implementation | S4 | Oct 26–31 | | | | [PLANNED]| |
| 14| Zbb Bit-Manipulation ALU instructions integration | S5 | Oct 28–Nov 01| | | | [PLANNED]| |
| 15| **Minimum System Commitment: All 9 Features Integrated**| **ALL** | **Nov 01** | | | | **[COMMIT]**| |
| 16| Vivado synthesis & timing closure at 100 MHz on Artix-7 | S1 | Nov 01–04 | | | | | [PLANNED]|
| 17| FPGA bitstream generation, UART & 7-segment display hookup | S3 | Nov 03–06 | | | | | [PLANNED]|
| 18| Final system benchmark verification & project demonstration | ALL | Nov 06–08 | | | | | [FINAL]  |

---

## 7. Risks and Challenges

1. **Multi-Cycle Stall Interlocking**: Coordinating concurrent stall requests from the divider, FPU, and cache misses without causing deadlock in the hazard unit.
2. **FPGA Timing Closure on DSP Paths**: Critical path timing violations through cascading 32-bit multiply-accumulate and FPU mantissa normalization stages at 100 MHz.
3. **Cache Coherency During Refills**: Ensuring instruction fetch and data memory accesses serialize correctly without stale data when reading recently modified lines.
4. **IEEE 754 Corner Case Compliance**: Accurately handling edge cases including NaN propagation, subnormal numbers, signed zeros, and rounding modes.
5. **Branch Penalty Overheads**: Preventing excessive speculative fetch flushes on unpredictable control flows by tuning the BTB indexing and tag match logic.

---

## 8. Response to TA Feedback

| TA Feedback Item | Specific Technical Response & Implementation Plan |
|---|---|
| **1. Limited hardware contribution in base 3-stage core** | The project has expanded the hardware scope to a complete 5-stage pipelined processor featuring **9 fully integrated hardware modules**, including dedicated Radix-4 Booth multiplication, multi-cycle division, an IEEE 754 FPU, separate L1 instruction/data caches, a 32-entry BTB, and passive performance counters. |
| **2. Hazard resolution without software delays** | All data hazards (distance-1 and distance-2 RAW) are resolved entirely in hardware using dual 3:1 operand forwarding multiplexers, and load-use hazards trigger automatic single-cycle hardware interlocks without requiring compiler NOP insertion. |
| **3. Demonstration of realistic workloads** | The processor execution is verified using compiled bare-metal C benchmark programs (`addition.c`, `fibonacci.c`, `sort.c`, `negative.c`, `xor.c`) with cycle-accurate terminal profiling rather than synthetic stimulus vectors. |
| **4. Realistic timing diagram showing hazards** | A full 24-cycle timing diagram has been included that explicitly details multi-cycle divider execution, single-cycle DSP multiplication, load-use stall freezes, and 2-cycle branch flushes. |
