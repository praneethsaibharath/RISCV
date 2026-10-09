# Feature 7: L1 Data Cache (D-Cache)

## Objectives & Scope
Integration of an L1 Data Cache between the Memory (MEM) stage and background main memory hierarchy.

## Architectural Specifications
- **Organization**: Direct-mapped or 2-way set-associative cache
- **Write Policy**: Write-through with write-buffer or Write-back with dirty bits
- **Byte Alignment Support**: Byte, half-word, and word write enables (`SB`, `SH`, `SW`)
- **Pipeline Interconnect**:
  - Interlocks Memory stage on cache miss via `dcache_stall`
  - Coherence / serialization with I-Cache during memory refills
