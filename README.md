# Pipelined RV32IM RISC-V Core with Advanced Arithmetic, Cache Hierarchy, and System Extensions

**Group Number:** 13  
**Repository:** https://github.com/praneethsaibharath/RISCV

---

## Project Overview
This repository contains the complete design, implementation, verification, and full-system integration of a high-performance **5-Stage Pipelined RV32IM RISC-V Processor Core** with extended arithmetic, cache memory hierarchy, dynamic branch prediction, and system coprocessors.

All 9 features are designed to integrate seamlessly into a unified pipeline architecture:

```text
       +-------------------------------------------------------------+
       |               Feature 6: Dynamic Branch Predictor           |
       +-------------------------------------------------------------+
                                      | (Predicted PC / Flush Recovery)
                                      v
+--------------+    +--------------+    +-----------------------+    +--------------+    +--------------+
|  Fetch (IF)  | -> | Decode (ID)  | -> |     Execute (EX)      | -> | Memory (MEM) | -> |Writeback (WB)|
+--------------+    +--------------+    +-----------------------+    +--------------+    +--------------+
       |                                            |                       |                   |
       v                                            |                       v                   v
+--------------+                                    |                +--------------+    +--------------+
|  Feature 5:  |                                    |                |  Feature 7:  |    |  Reg File /  |
|  L1 I-Cache  |                                    |                |  L1 D-Cache  |    |  Writeback   |
+--------------+                                    |                +--------------+    +--------------+
                                                    |
             +--------------------------------------+--------------------------------------+
             |                      |                      |                      |        |
             v                      v                      v                      v        v
      +--------------+       +--------------+       +--------------+       +------------+ +-------------+
      |  Feature 2:  |       |  Feature 3:  |       |  Feature 4:  |       | Feature 9: | | Feature 8:  |
      |   Hardware   |       |   Hardware   |       |   IEEE 754   |       |    Bit     | | Performance |
      |  Multiplier  |       |   Divider    |       |     FPU      |       |Manipulation| |  Counters   |
      +--------------+       +--------------+       +--------------+       +------------+ +-------------+
```

---

## Complete 9-Feature Architecture Roadmap

| Feature | Directory | Module / Extension | Integration Stage | Description & Deliverables |
|---|---|---|---|---|
| **Feature 1** | [`feature_1/`](feature_1/) | **5-Stage Pipeline Upgrade** | All Stages (IF–WB) | 5-stage core, Hazard Detection & Forwarding Unit, C test suite, cycle-by-cycle timing analyses |
| **Feature 2** | [`feature_2/`](feature_2/) | **Hardware Multiplier** | Execute (EX) | Radix-4 Booth / DSP multiplier supporting `MUL`, `MULH`, `MULHSU`, `MULHU` |
| **Feature 3** | [`feature_3/`](feature_3/) | **Hardware Divider** | Execute (EX) | Multi-cycle Radix-2 non-restoring divider (`DIV`, `DIVU`, `REM`, `REMU`) with stall controller |
| **Feature 4** | [`feature_4/`](feature_4/) | **IEEE754 FPU** | Execute (EX) & RegFile | Single-precision (32-bit) Floating Point Unit (`FADD`, `FSUB`, `FMUL`, `FDIV`, `FCVT`, `FLW`, `FSW`) |
| **Feature 5** | [`feature_5/`](feature_5/) | **L1 Instruction Cache** | Fetch (IF) | Direct-mapped / 2-way set-associative I-Cache with hit/miss controller and burst refill |
| **Feature 6** | [`feature_6/`](feature_6/) | **Branch Prediction** | Fetch & Execute | 32-entry Branch Target Buffer (BTB) + 2-bit saturating counter BHT to reduce branch penalty |
| **Feature 7** | [`feature_7/`](feature_7/) | **L1 Data Cache** | Memory (MEM) | D-Cache with write-through/write-back policy and byte-enable alignment |
| **Feature 8** | [`feature_8/`](feature_8/) | **Performance Counters** | System / CSRs | Hardware performance monitor for cycles, retired instructions, branch mispredicts, and cache misses |
| **Feature 9** | [`feature_9/`](feature_9/) | **Bit Manipulation** | Execute (EX) ALU | RV32B extension (Zba, Zbb, Zbs: `CLZ`, `CTZ`, `CPOP`, `ROL`, `ROR`, `ANDN`, `XNOR`, etc.) |

---

## Verification & Simulation Flow

Testbenches and automation scripts are configured for **Vivado Simulator (`xvlog`, `xelab`, `xsim`)**:

```bash
# 1. Automated multi-test runner from root
python run_c_tests.py all

# 2. Run individual C tests on the 5-stage core
python run_c_tests.py addition
python run_c_tests.py fibonacci
python run_c_tests.py sort

# 3. Vivado simulation via Makefile
cd feature_1/simulation
make all
```
