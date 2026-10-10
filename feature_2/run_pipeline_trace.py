#!/usr/bin/env python3
# ============================================================================
# File: run_pipeline_trace.py (Feature 2: RV32M Multiplier Visualizer)
# Description: Cycle-by-cycle pipeline trace & FPGA Nexys A7 mapping tool
# ============================================================================

import os
import sys
import subprocess
import re
import argparse
import shutil

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(CURRENT_DIR)

SIM_DIR = os.path.join(CURRENT_DIR, "simulation")
MEM_DIR = os.path.join(CURRENT_DIR, "mem")
C_TESTS_DIR = os.path.join(ROOT_DIR, "c_tests")

CC      = "riscv-none-elf-gcc"
OBJCOPY = "riscv-none-elf-objcopy"
OBJDUMP = "riscv-none-elf-objdump"

REG_NAMES = [
    'zero', 'ra', 'sp', 'gp', 'tp', 't0', 't1', 't2',
    's0', 's1', 'a0', 'a1', 'a2', 'a3', 'a4', 'a5',
    'a6', 'a7', 's2', 's3', 's4', 's5', 's6', 's7',
    's8', 's9', 's10', 's11', 't3', 't4', 't5', 't6'
]

def disassemble_word(word):
    """Decodes a 32-bit RV32I / RV32M machine word into assembly mnemonic."""
    if word == 0x00000013:
        return "nop"
    if word == 0x00008067:
        return "ret"
    if word == 0x00000000:
        return "bubble (nop)"

    opcode = word & 0x7F
    rd = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1 = (word >> 15) & 0x1F
    rs2 = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F

    imm_i = (word >> 20) - ((word >> 31) << 12)
    imm_s = ((word >> 7) & 0x1F) | (((word >> 25) & 0x7F) << 5)
    if imm_s >= 0x800:
        imm_s -= 0x1000

    if opcode == 0x33: # R-Type (ARITHR or RV32M)
        if funct7 == 0x01: # RV32M Extension
            m_ops = {0: "mul", 1: "mulh", 2: "mulhsu", 3: "mulhu"}
            name = m_ops.get(funct3, f"m_ext_f3_{funct3}")
            return f"{name} {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {REG_NAMES[rs2]}"
        r_ops = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl", 6: "or", 7: "and"}
        if funct7 == 0x20 and funct3 == 0:
            return f"sub {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {REG_NAMES[rs2]}"
        if funct7 == 0x20 and funct3 == 5:
            return f"sra {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {REG_NAMES[rs2]}"
        return f"{r_ops.get(funct3, 'unknown')} {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {REG_NAMES[rs2]}"
    elif opcode == 0x13: # I-Type (ARITHI)
        i_ops = {0: "addi", 1: "slli", 2: "slti", 3: "sltiu", 4: "xori", 5: "srli", 6: "ori", 7: "andi"}
        name = i_ops.get(funct3, "unknown")
        if name == "addi" and rs1 == 0:
            return f"li {REG_NAMES[rd]}, {imm_i}"
        return f"{name} {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {imm_i}"
    elif opcode == 0x03: # LOAD
        ld_ops = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
        return f"{ld_ops.get(funct3, 'lw')} {REG_NAMES[rd]}, {imm_i}({REG_NAMES[rs1]})"
    elif opcode == 0x23: # STORE
        st_ops = {0: "sb", 1: "sh", 2: "sw"}
        return f"{st_ops.get(funct3, 'sw')} {REG_NAMES[rs2]}, {imm_s}({REG_NAMES[rs1]})"
    elif opcode == 0x63: # BRANCH
        b_ops = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
        return f"{b_ops.get(funct3, 'branch')} {REG_NAMES[rs1]}, {REG_NAMES[rs2]}"
    elif opcode == 0x37: # LUI
        return f"lui {REG_NAMES[rd]}, 0x{(word >> 12) & 0xFFFFF:x}"
    elif opcode == 0x17: # AUIPC
        return f"auipc {REG_NAMES[rd]}, 0x{(word >> 12) & 0xFFFFF:x}"
    elif opcode == 0x6F: # JAL
        return f"jal {REG_NAMES[rd]}"
    elif opcode == 0x67: # JALR
        return f"jalr {REG_NAMES[rd]}, {REG_NAMES[rs1]}, {imm_i}"

    return f"unknown (0x{word:08x})"

def load_imem_map(imem_path):
    imem_map = {}
    if not os.path.exists(imem_path):
        return imem_map

    pc = 0
    with open(imem_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            word_str = line.split()[0].split("//")[0].strip()
            if len(word_str) == 8:
                try:
                    word = int(word_str, 16)
                    imem_map[pc] = (word, disassemble_word(word))
                    pc += 4
                except ValueError:
                    pass
    return imem_map

def print_imem_listing(imem_map):
    print("\n[1] FEATURE 2 INSTRUCTION MEMORY LISTING & FPGA 7-SEGMENT DISPLAY MAPPING:")
    print("=" * 115)
    print(f" {'Address (7-Seg sw[2]=0)':<25} | {'Hex Code (7-Seg sw[2]=1)':<25} | {'Disassembled Mnemonic':<30} | {'FPGA Hardware Note':<25}")
    print("=" * 115)
    for addr in sorted(imem_map.keys()):
        word, mnem = imem_map[addr]
        if word != 0 or addr < 0x48:
            note = ""
            if "mul" in mnem:
                note = "<-- RV32M MULTIPLIER (DSP48E1)"
            elif "lw" in mnem or "sw" in mnem:
                note = "Memory Access (DMEM)"
            elif "ret" in mnem or "jalr" in mnem or "beq" in mnem or "bne" in mnem:
                note = "Control Flow (Branch/Jump)"
            elif "addi" in mnem or "add" in mnem or "sub" in mnem:
                note = "Arithmetic / Immediate"
            print(f" 0x{addr:08x}                | 0x{word:08x}                | {mnem:<30} | {note:<25}")
    print("=" * 115)

def print_fpga_instructions():
    print("\n[2] HOW TO VIEW THESE MULTIPLICATION INSTRUCTIONS ON THE PHYSICAL NEXYS A7 BOARD:")
    print("=" * 95)
    print(" 1. EXECUTION SPEED & STEP CONTROL (Slide Switches & Pushbuttons):")
    print("    - sw[1] = 1 (Pin L16 ON) : 1 Hz Slow Clock mode. Processor runs 1 cycle per second.")
    print("                               Watch each instruction advance live at human-readable speed!")
    print("    - sw[0] = 1 (Pin J15 ON) : Manual Single-Step mode.")
    print("                               Press Center Pushbutton (btnc, Pin N17) to advance exactly 1 cycle.")
    print("    - cpu_resetn (Pin C12)   : Press red CPU Reset button to restart program execution from PC=0x00.")
    print("")
    print(" 2. 8-DIGIT SEVEN-SEGMENT DISPLAY (Directly above the switches/LEDs):")
    print("    - sw[2] = 0 (Pin M13 OFF): Shows Program Counter Fetch Address (pc_if[31:0]).")
    print("                               Cycle 10 shows '00000028' (Memory address of 'mul a5, a4, a5').")
    print("    - sw[2] = 1 (Pin M13 ON) : Shows 32-bit Machine Instruction Code (imem_rdata[31:0]).")
    print("                               Cycle 10 shows '02F707B3' (Hex machine code of 'mul a5, a4, a5').")
    print("")
    print(" 3. MULTIPLIER HARDWARE SELECTION (Slide Switch sw[3]):")
    print("    - sw[3] = 0 (Pin R15 OFF): Xilinx Artix-7 DSP48E1 Slices (LED[5] ON - Single-cycle DSP).")
    print("    - sw[3] = 1 (Pin R15 ON) : Radix-4 Modified Booth Multiplier RTL (LED[5] OFF).")
    print("")
    print(" 4. LED HARDWARE INDICATORS:")
    print("    - LED[0] (Pin H17)       : DATA HAZARD STALL (Turns ON during load-use stall before mul).")
    print("    - LED[1] (Pin K15)       : DATA FORWARDING ACTIVE (Turns ON when operand forwards into multiplier).")
    print("    - LED[2] (Pin J13)       : BRANCH / FLUSH.")
    print("    - LED[3] (Pin N14)       : WRITEBACK COMMIT (Turns ON whenever result writes to register).")
    print("    - LED[4] (Pin R18)       : MULTIPLIER ACTIVE LED (Lights up when 'mul' executes in EX stage).")
    print("    - LED[5] (Pin V17)       : DSP MODE LED (ON when using DSP48E1; OFF when using Booth RTL).")
    print("    - LED[15:8] (Pins V11..H6): Low 8 bits of committed result wb_data[7:0].")
    print("                               Multiplication product 25 x 16 = 400 (0x00000190) -> LED[15:8] = 0x90 (10010000b).")
    print("                               LED[15] is ON, LED[12] is ON, all others OFF.")
    print("=" * 95 + "\n")

def main():
    parser = argparse.ArgumentParser(description="Feature 2: RV32M Multiplier Visualizer & FPGA Mapping")
    parser.add_argument("target", nargs="?", default="multiplication",
                        help="Target test (multiplication, addition, fibonacci, sort, negative, xor, etc.)")
    parser.add_argument("--bitstream", action="store_true",
                        help="Automatically regenerate FPGA bitstream in Vivado after compiling hex")
    args = parser.parse_args()
    target = args.target

    # Build target if build_hex.py is available
    build_script = os.path.join(C_TESTS_DIR, "build_hex.py")
    if os.path.exists(build_script):
        print(f"[*] Building benchmark program '{target}' via build_hex.py...")
        try:
            subprocess.check_call([sys.executable, build_script, target])
        except Exception as e:
            print(f"[-] Build failed: {e}")

    imem_hex = os.path.join(MEM_DIR, "imem.hex")
    if not os.path.exists(imem_hex):
        print("[-] Error: imem.hex not found in feature_2/mem/")
        return
    imem_map = load_imem_map(imem_hex)
    print("=" * 115)
    print(f"       FEATURE 2: RV32M HARDWARE MULTIPLIER (DSP48E1 & RADIX-4 BOOTH) - FPGA VISUALIZER ({target.upper()})")
    print("=" * 115)
    print_imem_listing(imem_map)
    print_fpga_instructions()

    if args.bitstream:
        print("\n[*] Regenerating FPGA bitstream via Vivado (takes ~1-2 mins)...")
        b_tcl = os.path.join(CURRENT_DIR, "build_bitstream.tcl")
        subprocess.check_call(f"vivado -mode batch -source {b_tcl}", shell=True, cwd=ROOT_DIR)
        print("\n[+] FPGA bitstream successfully generated:")
        print(f"    -> {os.path.join(CURRENT_DIR, 'vivado_project', 'rv32m_multiplier_fpga.runs', 'impl_1', 'fpga_top_feature2.bit')}")
        print("    Program your Nexys A7 FPGA in Vivado Hardware Manager with this bitfile to view live execution!")

if __name__ == "__main__":
    main()
