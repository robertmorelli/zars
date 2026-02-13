# MARS Coverage Test Programs

This folder contains focused MIPS assembly programs for validating MARS-compatible behavior.

## How To Run

From repo root:

```bash
java -jar MARS/Mars.jar nc test_programs/<file>.s
```

Use additional options for feature-specific tests (`smc`, `db`, `p`, `pa`, etc.).

## Programs

- `test_programs/smc.s`
  - Advanced self-modifying control flow (15-state fizzbuzz machine).
  - Requires: `smc`

- `test_programs/integer_arithmetic.s`
  - Integer ALU operations, `mult/div`, `mflo/mfhi`, `slt/sltu`.

- `test_programs/bitwise_shift.s`
  - `and/or/xor/nor`, `sll/srl/sra`, formatted hex output.

- `test_programs/memory_access.s`
  - `.byte/.half/.word/.space`, `lb/lbu/lh/lhu/lw`, `sb/sh/sw`.

- `test_programs/control_flow.s`
  - Loops, `beq`, `j`, `jal`, `jr`.

- `test_programs/pseudo_ops.s`
  - Pseudo-instructions (`li`, `move`, `neg`, `not`, `blt`) expansion behavior.

- `test_programs/macro_and_include.s`
  - `.macro`, `.include`, `.eqv`.
  - Uses: `test_programs/include/common_macros.inc`

- `test_programs/syscall_formatting.s`
  - MARS formatting syscalls 34 (hex), 35 (binary), 36 (unsigned).

- `test_programs/syscall_file_io.s`
  - File I/O syscalls 13/14/15/16.
  - Creates/reads `mars_io_test.txt` in the working directory.

- `test_programs/syscall_random_seed.s`
  - Random syscalls 40/41/42/43/44 with fixed seed.

- `test_programs/floating_point.s`
  - Coprocessor 1 arithmetic (`add.s`, `mul.s`, `sub.d`) and compare (`bc1t`).

- `test_programs/program_args.s`
  - Command-mode program arguments (`pa`) and argv walking.
  - Example: `java -jar MARS/Mars.jar nc test_programs/program_args.s pa alpha beta`

- `test_programs/delayed_branch_probe.s`
  - Delayed branch semantics probe.
  - Default expected output: `1`
  - With `db` expected output: `11`

- `test_programs/smc_patch_syscall_code.s`
  - Self-modifies text by patching a non-zero-code-field `syscall` instruction.
  - Requires: `smc`

- `test_programs/syscall_clear_screen.s`
  - MARS extension syscall 60 smoke test.

- `test_programs/exception_address_error.s`
  - Negative test: unaligned `lw` should raise runtime exception.

- `test_programs/project_mode/main.s` + `test_programs/project_mode/helper.s`
  - Multi-file project assembly and linking.
  - Run with `p`: `java -jar MARS/Mars.jar nc p test_programs/project_mode/main.s`
