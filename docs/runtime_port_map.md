# Runtime Port Map

This map tracks file-by-file parity work between MARS Java sources and the Zig runtime.

## Current seed modules

- MARS source: `MARS/mars/Globals.java`
  - Zig module: `src/mars_runtime/globals.zig`
  - Ported now: version/capacity constants and invariants.

- MARS source: `MARS/mars/mips/instructions/BasicInstruction.java` and `MARS/mars/mips/instructions/InstructionSet.java`
  - Zig module: `src/mars_runtime/instruction_word.zig`
  - Ported now: instruction-word masks for syscall code fields and jump immediates.

- WASM runtime entry
  - Zig module: `src/wasm_runtime.zig`
  - Shared state: `src/mars_runtime/runtime_state.zig`

## Case-driven parity plan

Use `tests/runtime_cases/manifest.json` and `tools/runtime_main.mjs` as the loop:

1. Pick one case id.
2. Implement missing runtime behavior in Zig.
3. Run:

```bash
node tools/runtime_main.mjs --engine compare --case <case_id>
```

4. Repeat until output parity is exact.

## Immediate next files to port

- `MARS/mars/mips/hardware/RegisterFile.java`
- `MARS/mars/mips/hardware/Memory.java`
- `MARS/mars/assembler/Tokenizer.java`
- `MARS/mars/assembler/Assembler.java`
- `MARS/mars/simulator/Simulator.java`
- `MARS/mars/mips/instructions/InstructionSet.java`
