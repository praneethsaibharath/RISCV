# Feature 5: L1 Instruction Cache (I-Cache)

## Objectives & Scope
Integration of a high-speed L1 Instruction Cache between the Fetch (IF) stage and main memory.

## Architecture Specifications
- **Organization**: Direct-mapped or 2-way set-associative cache
- **Capacity**: 1 KB – 4 KB (parameterizable cache size)
- **Line Size**: 16 bytes (4 words per cache block) / 32 bytes
- **Hit Latency**: Single-cycle hit response to instruction fetch
- **Miss Handling**:
  - Memory stall controller freezing the Fetch/Decode pipeline
  - Block refill burst transfer from memory
  - Hit/Miss status monitoring for performance analysis
