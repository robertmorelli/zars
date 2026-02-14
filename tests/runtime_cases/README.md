# Runtime Parity Harness

This directory defines parity cases used to match the Zig runtime against MARS behavior.

## Layout

- `tests/runtime_cases/manifest.json`
  - Source of truth for case definitions.
  - Each case points to a MIPS program, MARS flags, optional stdin, and a golden stdout file.
  - Optional `expected_run_status_code` overrides default success status `0` and is used for
    runtime-error parity cases where stdout text is intentionally not compared.
  - Optional `expected_diagnostic_path` stores exact command-mode MARS diagnostics for non-zero
    status cases.
  - Optional `expected_mars_error_kind` (`runtime` or `parse`) constrains command-mode MARS
    diagnostics for non-zero-status cases.

- `tests/runtime_cases/expected/*.stdout`
  - Golden outputs generated from MARS.
- `tests/runtime_cases/expected/*.diagnostic`
  - Exact command-mode diagnostics for negative cases.

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

Compare mode also validates integer/floating register snapshots and data/heap memory words against
MARS command-mode state dumps for successful cases.

### Run Deep Pseudo-Op Layout Sweep

```bash
node tools/pseudo_layout_probe.mjs
```

This generates hundreds of one-op probes from `MARS/PseudoOps.txt` and checks
that text-label byte deltas match MARS exactly. The probe disables register/memory
state parity checks and focuses on text-layout differentials only.

### Run SMC Decode Focus Cases

```bash
node tools/runtime_main.mjs --engine compare --case smc_patch_integer_hilo
node tools/runtime_main.mjs --engine compare --case smc_patch_regimm_branches
node tools/runtime_main.mjs --engine compare --case smc_patch_partial_memory
node tools/runtime_main.mjs --engine compare --case smc_patch_trap_cp0
node tools/runtime_main.mjs --engine compare --case smc_patch_cop1_transfer_branch
node tools/runtime_main.mjs --engine compare --case smc_patch_cop1_arith_convert
node tools/runtime_main.mjs --engine compare --case smc_patch_special2_madd
node tools/runtime_main.mjs --engine compare --case smc_patch_invalid_primary_opcode
node tools/runtime_main.mjs --engine compare --case smc_patch_invalid_cop1_rs
node tools/runtime_main.mjs --engine compare --case smc_patch_invalid_special_funct
node tools/runtime_main.mjs --engine compare --case smc_patch_invalid_special2_funct
```

### Run Source Gap-Closure Cases

```bash
node tools/runtime_main.mjs --engine compare --case fp_missing_ops
node tools/runtime_main.mjs --engine compare --case mulou_coverage
node tools/runtime_main.mjs --engine compare --case break_runtime_error
node tools/runtime_main.mjs --engine compare --case pseudo_div_rem_forms
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_li_db
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_mulu_db
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_compare_abs_db
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_arith_logic_db
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_misc_db
node tools/runtime_main.mjs --engine compare --case delay_slot_pseudo_div_reg_db
node tools/runtime_main.mjs --engine compare --case parse_unknown_mnemonic
```

## Porting workflow

1. Pick one case id from `manifest.json`.
2. Implement the next runtime behavior in Zig.
3. Run compare mode for that case:

```bash
node tools/runtime_main.mjs --engine compare --case <case_id>
```

4. Continue case-by-case until all pass.
