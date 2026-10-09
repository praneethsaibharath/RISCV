# Feature 6: Dynamic Branch Prediction

## Objectives & Scope
Integration of dynamic branch prediction logic to mitigate the 2-cycle control hazard penalty in the 5-stage pipeline.

## Architectural Components
- **Branch Target Buffer (BTB)**: Cache mapping branch instruction PCs to their target addresses.
- **Branch History Table (BHT)**: Array of 2-bit saturating counters:
  - `00`: Strongly Not Taken
  - `01`: Weakly Not Taken
  - `10`: Weakly Taken
  - `11`: Strongly Taken
- **Speculative Fetch**: Fetch stage queries BTB & BHT on every clock cycle.
- **Misprediction Recovery**:
  - Validated in the Execute (EX) stage.
  - On misprediction: 2-cycle flush triggered, PC redirected, BHT counter updated.
  - On correct prediction: Zero branch bubble penalty incurred.
