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

- `test_programs/pseudo_ops_more.s`
  - Additional pseudo-op coverage: `b`, `beqz`, `bnez`, `s.s`, `s.d`, `negu`, `subi`, `subiu`.

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

- `test_programs/delay_slot_pseudo_li_db.s`
  - Delayed-branch slot probe for multiword `li` pseudo-op expansion behavior.
  - Requires: `db`

- `test_programs/delay_slot_pseudo_mulu_db.s`
  - Delayed-branch slot probe for multiword `mulu` pseudo-op expansion behavior.
  - Requires: `db`

- `test_programs/delay_slot_pseudo_compare_abs_db.s`
  - Delayed-branch slot probe for compare-family and `abs` pseudo-op first-word execution semantics.
  - Requires: `db`

- `test_programs/delay_slot_pseudo_arith_logic_db.s`
  - Delayed-branch slot probe for arithmetic/logical pseudo-op immediate expansion first-word semantics.
  - Requires: `db`

- `test_programs/delay_slot_pseudo_misc_db.s`
  - Delayed-branch slot probe for `la`, `rol/ror`, `mfc1.d`/`mtc1.d`, and selected `mul/div/rem` pseudo forms.
  - Requires: `db`

- `test_programs/delay_slot_pseudo_div_reg_db.s`
  - Delayed-branch slot probe for register-divisor `div/divu/rem/remu` pseudo-op first-word semantics.
  - Requires: `db`

- `test_programs/smc_patch_syscall_code.s`
  - Self-modifies text by patching a non-zero-code-field `syscall` instruction.
  - Requires: `smc`

- `test_programs/syscall_clear_screen.s`
  - MARS extension syscall 60 smoke test.

- `test_programs/smc_patch_basic_decode.s`
  - Self-modifying decode probe for patched `addi`/`ori`/`beq` machine words.
  - Requires: `smc`

- `test_programs/smc_patch_logic_shift.s`
  - Self-modifying decode probe for patched R-type logic/shift instructions.
  - Requires: `smc`

- `test_programs/smc_patch_load_store.s`
  - Self-modifying decode probe for patched `addi`/`andi`/`lw`/`sw` instruction words.
  - Requires: `smc`

- `test_programs/smc_patch_branch_jal.s`
  - Self-modifying decode probe for patched `beq`/`bne` plus `jal`/`jr` call flow.
  - Requires: `smc`

- `test_programs/smc_patch_integer_hilo.s`
  - Self-modifying decode probe for patched integer core ops, HI/LO moves, and SPECIAL2 decode.
  - Requires: `smc`

- `test_programs/smc_patch_regimm_branches.s`
  - Self-modifying decode probe for patched REGIMM branch family plus `blez`/`bgtz`.
  - Requires: `smc`

- `test_programs/smc_patch_partial_memory.s`
  - Self-modifying decode probe for patched byte/halfword and partial-word memory opcodes.
  - Requires: `smc`

- `test_programs/smc_patch_trap_cp0.s`
  - Self-modifying decode probe for patched `movn`/`movz`, trap-family opcodes, and CP0 `eret`.
  - Requires: `smc`

- `test_programs/smc_patch_cop1_transfer_branch.s`
  - Self-modifying decode probe for patched COP1 transfer/memory ops plus `bc1t`/`bc1f`.
  - Requires: `smc`

- `test_programs/smc_patch_cop1_arith_convert.s`
  - Self-modifying decode probe for patched COP1 arithmetic, conversion, and compare opcodes.
  - Requires: `smc`

- `test_programs/smc_patch_special2_madd.s`
  - Self-modifying decode probe for patched SPECIAL2 accumulation opcodes.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_regimm_rt.s`
  - Self-modifying decode negative probe for unsupported REGIMM `rt` selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop0_rs.s`
  - Self-modifying decode negative probe for unsupported COP0 `rs` selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop1_branch_likely.s`
  - Self-modifying decode negative probe for unsupported COP1 branch-likely forms.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop1_fmt_s_funct.s`
  - Self-modifying decode negative probe for unsupported COP1 `fmt.s` funct selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop1_fmt_d_funct.s`
  - Self-modifying decode negative probe for unsupported COP1 `fmt.d` funct selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop1_fmt_w_funct.s`
  - Self-modifying decode negative probe for unsupported COP1 `fmt.w` funct selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_cop1_rs.s`
  - Self-modifying decode negative probe for unsupported COP1 `rs` selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_primary_opcode.s`
  - Self-modifying decode negative probe for unsupported primary opcode selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_special_funct.s`
  - Self-modifying decode negative probe for unsupported SPECIAL funct selector.
  - Requires: `smc`

- `test_programs/smc_patch_invalid_special2_funct.s`
  - Self-modifying decode negative probe for unsupported SPECIAL2 funct selector.
  - Requires: `smc`

- `test_programs/parse_unknown_mnemonic.s`
  - Source parse negative probe for unknown mnemonic handling.

- `test_programs/syscall_exit2.s`
  - Command-mode `Exit2` syscall (17) behavior.

- `test_programs/syscall_time.s`
  - Time syscall (30) register update behavior.

- `test_programs/syscall_midi_sleep.s`
  - Command-mode smoke coverage for MIDI and sleep syscalls (31/32/33).

- `test_programs/syscall_dialog_50.s` ... `test_programs/syscall_dialog_59.s`
  - Headless command-mode behavior probes for dialog/message syscalls 50 through 59.

- `test_programs/directive_compat_kernel_segments.s`
  - Directive compatibility for `.globl` and `.extern`.

- `test_programs/exception_address_error.s`
  - Negative test: unaligned `lw` should raise runtime exception.

- `test_programs/immediate_logic.s`
  - Immediate ALU and logical operations: `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `lui`.

- `test_programs/shift_variable.s`
  - Variable shifts: `sllv`, `srlv`, `srav`.

- `test_programs/hi_lo_unsigned.s`
  - Unsigned HI/LO operations: `multu`, `divu`, plus `mthi`/`mtlo`.

- `test_programs/branch_and_link_family.s`
  - Branch family (`bne`, `bgez`, `bgtz`, `blez`, `bltz`) and link forms (`bgezal`, `bltzal`, `jalr`).

- `test_programs/jalr_forms.s`
  - `jalr` one-operand and two-operand forms.

- `test_programs/syscall_read_string.s`
  - Input syscall 8 (`ReadString`) semantics.

- `test_programs/syscall_read_char.s`
  - Input syscall 12 (`ReadChar`) semantics.

- `test_programs/syscall_read_float_double.s`
  - Input syscalls 6/7 and output syscalls 2/3 for floating-point parsing/printing.

- `test_programs/syscall_sbrk_heap.s`
  - Heap allocation syscall 9 (`sbrk`) alignment and heap memory reads/writes.

- `test_programs/directive_ascii_align.s`
  - Data directive semantics for `.ascii` and `.align`.

- `test_programs/delayed_branch_nested.s`
  - Nested delayed-branch behavior probe (delay slot contains a successful branch).

- `test_programs/memory_partial_words.s`
  - Partial-word and atomic-family memory instructions: `ll`, `sc`, `lwl`, `lwr`, `swl`, `swr`.

- `test_programs/fp_condition_flags.s`
  - Coprocessor 1 condition flags with `bc1t`/`bc1f` and explicit flag-index forms.

- `test_programs/fp_round_convert.s`
  - Floating-point conversion and rounding families: `floor.w.*`, `ceil.w.*`, `round.w.*`, `trunc.w.*`, `cvt.*`.

- `test_programs/fp_move_and_transfer.s`
  - Conditional FP moves (`movf.*`, `movt.*`, `movn.*`, `movz.*`) and transfers (`mfc1`, `mtc1`).

- `test_programs/fp_missing_ops.s`
  - Additional FP parity coverage for uncovered source mnemonics: `abs.d`, `add.d`, `mul.d`, `div.d`,
    `sqrt.d`, `div.s`, `sqrt.s`, `sub.s`, `floor.w.d`, `ceil.w.d`, `c.eq.d`, plus `swc1`/`sdc1`/`ldc1`.

- `test_programs/cp0_eret.s`
  - Coprocessor 0 transfer instructions (`mfc0`, `mtc0`) and `eret` behavior.

- `test_programs/trap_family.s`
  - Trap instruction family: `te*`, `tg*`, `tl*` forms including immediate variants.

- `test_programs/multiply_accumulate.s`
  - Multiply/accumulate family (`mul`, `madd`, `maddu`, `msub`, `msubu`) and `clo`/`clz`.

- `test_programs/mulou_coverage.s`
  - `mulou` pseudo-op parity coverage for register and immediate forms.

- `test_programs/break_runtime_error.s`
  - `break` mnemonic source coverage in an unreachable slot for compare-mode stability.

- `test_programs/project_mode/main.s` + `test_programs/project_mode/helper.s`
  - Multi-file project assembly and linking.
  - Run with `p`: `java -jar MARS/Mars.jar nc p test_programs/project_mode/main.s`

- `test_programs/pseudo_branches_math.s`
  - Additional pseudo-op coverage for branch/compare/arithmetic aliases.

- `test_programs/pseudo_div_rem_forms.s`
  - Pseudo-op execution coverage for `div`/`divu`/`rem`/`remu` 3-operand forms,
    including immediate-zero HI/LO carry behavior.

- `test_programs/pseudo_unaligned_and_pair.s`
  - Additional pseudo-op coverage for unaligned memory and register-pair transfer aliases.

- `test_programs/address_expression_forms.s`
  - Address-expression coverage for `la/lw/sw` forms: immediates, labels, `label+offset`,
    and optional base-register combinations.

- `test_programs/pseudo_layout_counts.s`
  - Pseudo-op layout probe that validates label-address byte deltas across selected
    multi-instruction pseudo expansions.

- `test_programs/pseudo_layout_counts_more.s`
  - Additional pseudo-op layout probe covering compare/set, branch aliases, pair-transfer
    aliases, and immediate-form multiply pseudo expansions.

- `test_programs/pseudo_layout_counts_expanded.s`
  - Expanded pseudo-op layout probe for immediate-width-sensitive arithmetic/branch aliases
    plus unaligned memory pseudo families.
