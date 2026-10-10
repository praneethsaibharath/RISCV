#!/usr/bin/env python3
# ============================================================================
# File: run_pipeline_trace.py
# Description: Interactive Pipeline Simulation & Cycle-by-Cycle Terminal Visualizer
# Project: 5-Stage RV32I Processor Core (Feature 1)
#
# Features:
# 1. Shows cycle-by-cycle pipeline progression across IF, ID, EX, MEM, WB stages.
# 2. Explains what instruction is in each stage (address + mnemonic).
# 3. Highlights in real-time when:
#    - A Data Hazard is detected (Load-Use Stall) -> FPGA LED[0] ON
#    - Data Forwarding is active (EX/MEM or MEM/WB bypass) -> FPGA LED[1] ON
#    - A Branch / Speculative Flush occurs -> FPGA LED[2] ON
# 4. Notes the current Fetch Address on the FPGA 8-digit 7-segment display.
# 5. Displays the static Instruction Memory listing and the dynamic execution order.
# 6. Supports:
#    - Standard benchmarks: addition, fibonacci, sort, negative, xor
#    - Custom C files (.c), Assembly files (.s), or Hex files (.hex)
#    - Direct inline assembly strings: --asm "addi x1, x0, 10; addi x2, x0, 2; add x3, x1, x2; ret"
# ============================================================================

import os
import sys
import subprocess
import re
import argparse
import shutil

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
if os.path.basename(CURRENT_DIR) == "feature_1":
    ROOT_DIR = os.path.dirname(CURRENT_DIR)
    FEATURE1_DIR = CURRENT_DIR
else:
    ROOT_DIR = CURRENT_DIR
    FEATURE1_DIR = os.path.join(ROOT_DIR, "feature_1")

SIM_DIR = os.path.join(FEATURE1_DIR, "simulation")
MEM_DIR = os.path.join(FEATURE1_DIR, "mem")
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
    """Decodes a 32-bit RV32I machine word into assembly mnemonic."""
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

    # Sign-extended immediates
    imm_i = (word >> 20) - ((word >> 31) << 12)
    imm_s = ((word >> 7) & 0x1F) | (((word >> 25) & 0x7F) << 5)
    if imm_s >= 0x800:
        imm_s -= 0x1000
    imm_b = (((word >> 8) & 0xF) << 1) | (((word >> 25) & 0x3F) << 5) | (((word >> 7) & 0x1) << 11) | (((word >> 31) & 0x1) << 12)
    if imm_b >= 0x1000:
        imm_b -= 0x2000
    imm_u = word & 0xFFFFF000
    imm_j = (((word >> 21) & 0x3FF) << 1) | (((word >> 20) & 0x1) << 11) | (((word >> 12) & 0xFF) << 12) | (((word >> 31) & 0x1) << 20)
    if imm_j >= 0x100000:
        imm_j -= 0x200000

    r_d = REG_NAMES[rd]
    r_1 = REG_NAMES[rs1]
    r_2 = REG_NAMES[rs2]

    if opcode == 0x13:  # OP-IMM
        names = ['addi', 'slli', 'slti', 'sltiu', 'xori', 'srli/srai', 'ori', 'andi']
        if funct3 == 0:
            if rs1 == 0:
                return f"li {r_d}, {imm_i}"
            return f"addi {r_d}, {r_1}, {imm_i}"
        return f"{names[funct3]} {r_d}, {r_1}, {imm_i}"
    elif opcode == 0x33:  # OP
        if funct3 == 0:
            return f"sub {r_d}, {r_1}, {r_2}" if funct7 == 0x20 else f"add {r_d}, {r_1}, {r_2}"
        names = ['add/sub', 'sll', 'slt', 'sltu', 'xor', 'srl/sra', 'or', 'and']
        return f"{names[funct3]} {r_d}, {r_1}, {r_2}"
    elif opcode == 0x03:  # LOAD
        names = ['lb', 'lh', 'lw', 'res', 'lbu', 'lhu']
        return f"{names[funct3]} {r_d}, {imm_i}({r_1})"
    elif opcode == 0x23:  # STORE
        names = ['sb', 'sh', 'sw']
        return f"{names[funct3]} {r_2}, {imm_s}({r_1})"
    elif opcode == 0x63:  # BRANCH
        names = ['beq', 'bne', 'res', 'res', 'blt', 'bge', 'bltu', 'bgeu']
        return f"{names[funct3]} {r_1}, {r_2}, {imm_b:+d}"
    elif opcode == 0x6F:  # JAL
        return f"j {imm_j:+d}" if rd == 0 else f"jal {r_d}, {imm_j:+d}"
    elif opcode == 0x67:  # JALR
        return f"jalr {r_d}, {r_1}, {imm_i}"
    elif opcode == 0x37:  # LUI
        return f"lui {r_d}, 0x{imm_u >> 12:x}"
    elif opcode == 0x17:  # AUIPC
        return f"auipc {r_d}, 0x{imm_u >> 12:x}"

    return f"0x{word:08x}"

def load_imem_map(imem_hex_path):
    """Loads imem.hex into a dictionary {address: (word, mnemonic)}."""
    imem = {}
    if not os.path.exists(imem_hex_path):
        return imem

    addr = 0
    with open(imem_hex_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            token = line.split()[0].split("//")[0]
            try:
                word = int(token, 16)
                if word != 0 or addr < 0x80:
                    imem[addr] = (word, disassemble_word(word))
                addr += 4
            except ValueError:
                continue
    return imem

def compile_custom_asm(asm_code, out_imem, out_dmem):
    """Compiles an assembly string into imem.hex and dmem.hex."""
    tmp_s = os.path.join(C_TESTS_DIR, "_tmp_custom.s")
    tmp_elf = os.path.join(C_TESTS_DIR, "_tmp_custom.elf")
    tmp_bin = os.path.join(C_TESTS_DIR, "_tmp_custom.bin")

    # Header with main and ret
    full_asm = f"""
.section .text
.globl main
main:
{asm_code}
    ret
"""
    with open(tmp_s, "w", encoding="utf-8") as f:
        f.write(full_asm)

    # Compile with GCC
    subprocess.check_call([CC, "-march=rv32i", "-mabi=ilp32", "-nostdlib", "-c", tmp_s, "-o", tmp_elf])
    subprocess.check_call([OBJCOPY, "-O", "binary", tmp_elf, tmp_bin])

    # Convert binary to hex
    j = 0
    with open(out_imem, "w", encoding="utf-8") as f:
        with open(tmp_bin, "rb") as bf:
            while True:
                chunk = bf.read(4)
                if not chunk:
                    break
                import struct
                word = struct.unpack("<I", chunk.ljust(4, b"\x00"))[0]
                f.write(f"{word:08x} // 32'h{j:08x}\n")
                j += 4
        while j < 4096:
            f.write(f"00000000 // 32'h{j:08x}\n")
            j += 4

    # Empty DMEM
    with open(out_dmem, "w", encoding="utf-8") as f:
        for k in range(0, 4096, 4):
            f.write(f"00000000 // 32'h{k:08x}\n")

def compile_c_or_asm_file(file_path, out_imem, out_dmem):
    """Compiles a C (.c) or Assembly (.s) file into hex."""
    tmp_elf = os.path.join(C_TESTS_DIR, "_tmp_custom.elf")
    tmp_bin = os.path.join(C_TESTS_DIR, "_tmp_custom.bin")

    is_c = file_path.endswith(".c")
    cflags = ["-march=rv32i", "-mabi=ilp32", "-O0"]
    if not is_c:
        cflags += ["-nostdlib"]

    subprocess.check_call([CC, "-c", file_path, "-o", tmp_elf] + cflags)
    subprocess.check_call([OBJCOPY, "-O", "binary", tmp_elf, tmp_bin])

    j = 0
    with open(out_imem, "w", encoding="utf-8") as f:
        with open(tmp_bin, "rb") as bf:
            while True:
                chunk = bf.read(4)
                if not chunk:
                    break
                import struct
                word = struct.unpack("<I", chunk.ljust(4, b"\x00"))[0]
                f.write(f"{word:08x} // 32'h{j:08x}\n")
                j += 4
        while j < 4096:
            f.write(f"00000000 // 32'h{j:08x}\n")
            j += 4

    with open(out_dmem, "w", encoding="utf-8") as f:
        for k in range(0, 4096, 4):
            f.write(f"00000000 // 32'h{k:08x}\n")

def run_simulation(target_name, imem_map):
    """Runs xsim and parses simulation trace output."""
    cmd = "xsim sim_pipeline_snap -runall"
    proc = subprocess.run(cmd, cwd=SIM_DIR, capture_output=True, text=True, shell=True)
    out = proc.stdout

    trace_records = []
    trace_re = re.compile(
        r"\[TRACE\]\s+CC=(\d+)\s+\|\s+IF_PC=([0-9a-fA-F]+)\s+\|\s+IF_INST=([0-9a-fA-F]+)\s+\|\s+ID_PC=([0-9a-fA-F]+)\s+\|\s+EX_PC=([0-9a-fA-F]+)\s+\|\s+MEM_PC=([0-9a-fA-F]+)\s+\|\s+WB_PC=([0-9a-fA-F]+)\s+\|\s+FWD_A=(\d+)\s+\|\s+FWD_B=(\d+)\s+\|\s+STALL=(\d+)\s+\|\s+FLUSH=(\d+)\s+\|\s+WB_WE=(\d+)\s+\|\s+WB_RD=(\d+)\s+\|\s+WB_DATA=([0-9a-fA-F]+)"
    )

    for line in out.splitlines():
        m = trace_re.search(line)
        if m:
            trace_records.append({
                "cc": int(m.group(1)),
                "if_pc": int(m.group(2), 16),
                "if_inst": int(m.group(3), 16),
                "id_pc": int(m.group(4), 16),
                "ex_pc": int(m.group(5), 16),
                "mem_pc": int(m.group(6), 16),
                "wb_pc": int(m.group(7), 16),
                "fwd_a": int(m.group(8)),
                "fwd_b": int(m.group(9)),
                "stall": int(m.group(10)),
                "flush": int(m.group(11)),
                "wb_we": int(m.group(12)),
                "wb_rd": int(m.group(13)),
                "wb_data": int(m.group(14), 16),
            })

    # Extract final return value
    m_val = re.search(r"FINAL RETURN VALUE a0 \(x10\) =\s*(-?\d+)", out)
    ret_val = int(m_val.group(1)) if m_val else None

    return trace_records, ret_val, out

def print_banner(target_name):
    print("=" * 135)
    print(f"       RV32I 5-STAGE PIPELINE CYCLE-BY-CYCLE SIMULATION & TRACE VISUALIZER ({target_name.upper()})")
    print("       Features: Hazard Detection, Data Forwarding, Branch Flushes, FPGA 8-Digit Display Mapping")
    print("=" * 135)

def print_imem_listing(imem_map):
    print("\n[1] STATIC INSTRUCTION MEMORY LISTING (HEX & MNEMONICS):")
    print("-" * 80)
    print(f" {'Address':<12} | {'Machine Word':<14} | {'Disassembled Instruction Mnemonic':<45}")
    print("-" * 80)
    for addr in sorted(imem_map.keys()):
        word, mnem = imem_map[addr]
        if word != 0 or addr < 0x40:
            print(f" 0x{addr:08x}   | 0x{word:08x}     | {mnem:<45}")
    print("-" * 80)

def print_trace_table(records, imem_map):
    print("\n[2] CYCLE-BY-CYCLE PIPELINE EXECUTION TRACE TABLE:")
    print("=" * 135)
    header = f"{'CC':<4} | {'FETCH (IF)':<24} | {'DECODE (ID)':<24} | {'EXECUTE (EX)':<24} | {'MEMORY (MEM)':<18} | {'WRITEBACK (WB)':<18} | {'HAZARDS / FORWARDING / NOTES'}"
    print(header)
    print("=" * 135)

    retired_instructions = []

    for r in records:
        cc = r["cc"]

        # Stage IF
        if_pc = r["if_pc"]
        if_inst = r["if_inst"]
        if_mnem = imem_map.get(if_pc, (if_inst, disassemble_word(if_inst)))[1]
        if_str = f"0x{if_pc:04x}: {if_mnem[:15]}"

        # Stage ID
        id_pc = r["id_pc"]
        id_mnem = imem_map.get(id_pc, (0, "bubble"))[1] if id_pc != 0 else "bubble (nop)"
        id_str = f"0x{id_pc:04x}: {id_mnem[:15]}" if id_pc != 0 else "[BUBBLE/NOP]"

        # Stage EX
        ex_pc = r["ex_pc"]
        ex_mnem = imem_map.get(ex_pc, (0, "bubble"))[1] if ex_pc != 0 else "bubble (nop)"
        ex_str = f"0x{ex_pc:04x}: {ex_mnem[:15]}" if ex_pc != 0 else "[BUBBLE/NOP]"

        # Stage MEM
        mem_pc = r["mem_pc"]
        mem_str = f"0x{mem_pc:04x}" if mem_pc != 0 and mem_pc != 0xfffffffc else "-"

        # Stage WB
        wb_we = r["wb_we"]
        wb_rd = r["wb_rd"]
        wb_data = r["wb_data"]
        wb_pc = r["wb_pc"]

        if wb_we and wb_rd != 0:
            wb_str = f"{REG_NAMES[wb_rd]} <= {wb_data}"
            wb_mnem = imem_map.get(wb_pc, (0, "retire"))[1]
            retired_instructions.append((cc, wb_pc, wb_mnem, REG_NAMES[wb_rd], wb_data))
        else:
            wb_str = "-"

        # Notes / Hazards / Forwarding
        notes = []
        if r["stall"]:
            notes.append(">>> [DATA HAZARD STALL] (LED[0] ON! Freeze IF/ID, bubble to EX)")
        if r["fwd_a"] != 0 or r["fwd_b"] != 0:
            fwd_a_desc = "EX/MEM" if r["fwd_a"] == 1 else ("MEM/WB" if r["fwd_a"] == 2 else "")
            fwd_b_desc = "EX/MEM" if r["fwd_b"] == 1 else ("MEM/WB" if r["fwd_b"] == 2 else "")
            fwd_info = []
            if fwd_a_desc: fwd_info.append(f"A:{fwd_a_desc}")
            if fwd_b_desc: fwd_info.append(f"B:{fwd_b_desc}")
            notes.append(f"[*] [DATA FORWARDING] (LED[1] ON! {', '.join(fwd_info)})")
        if r["flush"]:
            notes.append("[!] [BRANCH/CONTROL FLUSH] (LED[2] ON! Annulling IF/ID)")
        if wb_we and wb_rd != 0:
            notes.append(f"[+] [RETIRE] {REG_NAMES[wb_rd]} = {wb_data} (LED[3] ON)")

        notes_str = "; ".join(notes) if notes else "Normal Execution"

        print(f"{cc:<4} | {if_str:<24} | {id_str:<24} | {ex_str:<24} | {mem_str:<18} | {wb_str:<18} | {notes_str}")

    print("=" * 135)
    return retired_instructions

def print_execution_order(retired_instructions):
    print("\n[3] DYNAMIC INSTRUCTION EXECUTION ORDER (COMMITTED / RETIRED):")
    print("-" * 95)
    print(f" {'#':<4} | {'Cycle':<6} | {'PC':<12} | {'Instruction Mnemonic':<32} | {'Register Commit Result':<30}")
    print("-" * 95)
    for idx, (cc, pc, mnem, rd, val) in enumerate(retired_instructions, 1):
        signed_val = val if val < 0x80000000 else val - 0x100000000
        print(f" {idx:<4} | CC={cc:<3} | 0x{pc:08x}   | {mnem:<32} | {rd} <= {signed_val} (0x{val:08x})")
    print("-" * 95)

def print_fpga_mapping_summary(records, ret_val):
    total_cycles = len(records)
    stalls = sum(1 for r in records if r["stall"])
    forwards = sum(1 for r in records if r["fwd_a"] != 0 or r["fwd_b"] != 0)
    flushes = sum(1 for r in records if r["flush"])
    retired = sum(1 for r in records if r["wb_we"] and r["wb_rd"] != 0)
    ipc = retired / total_cycles if total_cycles > 0 else 0

    print("\n[4] FPGA HARDWARE & VERIFICATION SUMMARY:")
    print("=" * 80)
    print(f" * 8-Digit Seven-Segment Display : Shows Fetch Address (pc_if) in real-time")
    print(f" * LED[0] (DATA HAZARD STALL)    : Triggered {stalls} times (Load-Use interlocks)")
    print(f" * LED[1] (DATA FORWARDING)      : Triggered {forwards} times (Distance-1 & 2 bypasses)")
    print(f" * LED[2] (BRANCH FLUSH)         : Triggered {flushes} times (Control hazard flushes)")
    print(f" * LED[3] (WRITEBACK RETIREMENT) : Triggered {retired} times (Instructions retired)")
    print(f" * Total Elapsed Clock Cycles    : {total_cycles}")
    print(f" * Instructions Retired          : {retired}")
    print(f" * Throughput (IPC)              : {ipc:.2f} instructions / cycle")
    if ret_val is not None:
        print(f" * FINAL RETURN VALUE a0 (x10)   : {ret_val} (0x{ret_val & 0xFFFFFFFF:08x})")
    print("=" * 80 + "\n")

def main():
    parser = argparse.ArgumentParser(description="5-Stage RV32I Processor Pipeline Trace Visualizer")
    parser.add_argument("target", nargs="?", default="addition",
                        help="Target test (addition, fibonacci, sort, negative, xor, or custom file .c / .s / .hex)")
    parser.add_argument("--asm", type=str, default=None,
                        help="Direct assembly string (e.g. 'addi x1, x0, 10; addi x2, x0, 2; add x3, x1, x2; ret')")

    args = parser.parse_args()
    target = args.target

    print_banner(target)

    imem_hex = os.path.join(MEM_DIR, "imem.hex")
    dmem_hex = os.path.join(MEM_DIR, "dmem.hex")
    os.makedirs(MEM_DIR, exist_ok=True)

    # 1. Prepare Hex / Program
    if args.asm:
        print(f"[*] Compiling custom inline assembly: \"{args.asm}\"...")
        compile_custom_asm(args.asm, imem_hex, dmem_hex)
    elif target.endswith(".c") or target.endswith(".s"):
        print(f"[*] Compiling custom source file: {target}...")
        compile_c_or_asm_file(target, imem_hex, dmem_hex)
    elif target.endswith(".hex"):
        print(f"[*] Using custom hex file: {target}...")
        shutil.copy2(target, imem_hex)
    else:
        # Standard benchmark program
        build_script = os.path.join(C_TESTS_DIR, "build_hex.py")
        print(f"[*] Building benchmark program: {target} via {build_script}...")
        subprocess.check_call([sys.executable, build_script, target], cwd=SIM_DIR)

    # 2. Load Instruction Memory Map
    imem_map = load_imem_map(imem_hex)
    print_imem_listing(imem_map)

    # 3. Run Simulation
    print("\n[*] Running cycle-by-cycle simulation via Vivado xsim...")
    records, ret_val, raw_out = run_simulation(target, imem_map)

    if not records:
        print("[-] Error: No trace records collected from xsim. Raw output:\n", raw_out)
        sys.exit(1)

    # 4. Print Cycle Trace Table
    retired = print_trace_table(records, imem_map)

    # 5. Print Dynamic Execution Order
    print_execution_order(retired)

    # 6. Print FPGA & Performance Summary
    print_fpga_mapping_summary(records, ret_val)

if __name__ == "__main__":
    main()
