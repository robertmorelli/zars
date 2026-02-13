# Runtime Parity Harness

This directory defines parity cases used to match the Zig runtime against MARS behavior.

## Layout

- `tests/runtime_cases/manifest.json`
  - Source of truth for case definitions.
  - Each case points to a MIPS program, MARS flags, optional stdin, and a golden stdout file.

- `tests/runtime_cases/expected/*.stdout`
  - Golden outputs generated from MARS.

## Runner

Use `tools/runtime_main.mjs` as the single entry point.

### Refresh goldens from MARS

```bash
node tools/runtime_main.mjs --refresh-golden --engine mars
```

### Build WASM runtime artifact

```bash
node tools/runtime_main.mjs --build-wasm --engine wasm --case integer_arithmetic
```

### Compare WASM runtime output to goldens

```bash
node tools/runtime_main.mjs --engine compare
```

## Porting workflow

1. Pick one case id from `manifest.json`.
2. Implement the next runtime behavior in Zig.
3. Run compare mode for that case:

```bash
node tools/runtime_main.mjs --engine compare --case <case_id>
```

4. Continue case-by-case until all pass.
