# Feature 6: L1 Data Cache (Direct-Mapped)

## Objectives & Scope
Integration of a high-speed, direct-mapped L1 Data Cache between the Memory (MEM) stage and background data memory to minimize memory access latencies.

## Architecture Specifications
- **Organization**: Direct-Mapped Cache
- **Capacity**: 1 KB – 4 KB (parameterizable words per line, number of cache lines)
- **Line Size**: 16 bytes (4 words per block) / 32 bytes (8 words per block)
- **Write Policy**: Write-through with write-buffer or Write-back with dirty bits
- **Byte Alignment Support**: Byte, half-word, and word write masking (`SB`, `SH`, `SW`)
- **Miss Handling**:
  - Memory stage interlock: asserts `dcache_stall` to freeze earlier pipeline stages
  - Burst line refill from background main memory on read miss
  - Cache hit detection and single-cycle read/write access
