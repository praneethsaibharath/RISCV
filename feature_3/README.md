# Feature 3: L1 Instruction Cache (Direct-Mapped)

## Objectives & Scope
Integration of a high-speed, direct-mapped L1 Instruction Cache between the Fetch (IF) stage and background main memory hierarchy to reduce instruction fetch latency.

## Architecture Specifications
- **Organization**: Direct-Mapped Cache
- **Capacity**: 1 KB – 4 KB (parameterizable words per line, number of cache lines)
- **Line Size**: 16 bytes (4 words per block) / 32 bytes (8 words per block)
- **Hit Latency**: Single-cycle hit response on clock edge
- **Tag & Valid Array**: Hardware tag comparison and valid bit tracking
- **Miss Handling**:
  - Cache miss detection asserts `icache_stall` to freeze the Fetch (IF) and Decode (ID) pipeline stages
  - Multi-word burst refill FSM from background instruction memory
  - Cache refill completed flag resumes core pipeline execution
