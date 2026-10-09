# Feature 8: Hardware Performance Counters

## Objectives & Scope
Integration of standard RISC-V hardware performance monitoring registers (HPM / CSR counters) to profile pipeline execution, cache efficiency, and hazard penalties.

## Counters Implemented (64-bit / 32-bit registers)
- `cycle`: Total elapsed clock cycles
- `instret`: Number of instructions retired in the writeback stage
- `stall_cycles`: Total pipeline stall cycles caused by load-use dependencies, divider, or cache misses
- `branch_count`: Total branch instructions executed
- `branch_mispredict`: Number of branch mispredictions detected
- `icache_miss`: L1 Instruction Cache miss events
- `dcache_miss`: L1 Data Cache miss events

## Software & Diagnostic Access
- Readable via `RDCYCLE`, `RDTIME`, `RDINSTRET` (CSR `0xC00`, `0xC01`, `0xC02`) or memory-mapped diagnostic ports for real-time profiling.
