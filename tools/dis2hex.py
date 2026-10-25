#!/usr/bin/env python3
# ==============================================================================
# File: tools/dis2hex.py
# Description: Converts RISC-V disassembly (.dis) into Verilog imem.hex
# Supports both pure-Python riscv_as format and GNU objdump format.
# Padds unused memory locations up to 1024 words with NOPs (00000013).
# ==============================================================================

import os
import sys
import re
import argparse

def convert_dis_to_hex(dis_path, hex_path, total_words=1024, add_comments=True):
    if not os.path.exists(dis_path):
        print(f"[-] Error: Disassembly file '{dis_path}' not found.")
        return False

    # Initialize memory array with RISC-V NOP (addi x0, x0, 0 = 0x00000013)
    memory = ["00000013"] * total_words
    max_idx = -1
    count = 0

    # Pattern matches both:
    # 1. "0x00000000:  3fc000b7    lui  x1, 0x3FC00" (riscv_as format)
    # 2. "       0:	3fc000b7          	lui  ra,0x3fc00" (GNU objdump format)
    pattern = re.compile(r'^\s*(?:0x)?([0-9a-fA-F]+):\s+([0-9a-fA-F]{8})')

    with open(dis_path, "r") as f:
        for line in f:
            m = pattern.search(line)
            if m:
                addr_hex = m.group(1)
                inst_hex = m.group(2).lower()
                addr = int(addr_hex, 16)
                idx = addr // 4
                if 0 <= idx < total_words:
                    memory[idx] = inst_hex
                    count += 1
                    if idx > max_idx:
                        max_idx = idx

    # Ensure parent output directory exists
    out_dir = os.path.dirname(os.path.abspath(hex_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    with open(hex_path, "w") as f:
        for i in range(total_words):
            addr = i * 4
            if add_comments:
                f.write(f"{memory[i]} // 32'h{addr:08x}\n")
            else:
                f.write(f"{memory[i]}\n")

    print(f"[+] Loaded {count} instructions from '{dis_path}' into '{hex_path}'")
    print(f"    - Total size: {total_words} words ({total_words * 4} bytes)")
    print(f"    - Program range: 0x00000000 - 0x{(max_idx * 4):08x}")
    return True

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert RISC-V .dis disassembly to imem.hex")
    parser.add_argument("dis_file", nargs="?", default="code.dis", help="Path to input .dis file (default: code.dis)")
    parser.add_argument("hex_file", nargs="?", default="imem.hex", help="Path to output imem.hex file (default: imem.hex)")
    parser.add_argument("--size", type=int, default=1024, help="Total words to output (default: 1024)")
    parser.add_argument("--no-comments", action="store_true", help="Omit // address comments")
    args = parser.parse_args()

    success = convert_dis_to_hex(args.dis_file, args.hex_file, total_words=args.size, add_comments=not args.no_comments)
    if not success:
        sys.exit(1)
