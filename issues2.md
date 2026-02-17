# Issues Found During Architectural Refactoring

## Pre-existing Test Failure

### smc_advanced: Text Layout Off by 1 Word

**Status**: PRE-EXISTING (present before refactoring)
**Test**: `smc_advanced` (test_programs/smc.s with input "20\n")

Register mismatches all consistent with text addresses being 4 bytes (1 word) too low:
- t5 (la j_or_syscall): expected 0x00400074, got 0x00400070
- t8 (la body): expected 0x00400050, got 0x0040004c
- a0, t0, t4: downstream mismatches from shifted addresses

**Root Cause**: One instruction before the `body` label is being estimated at 1 word fewer than MARS expects. Likely candidate is `sub $t3, $t3, 1` (line 48 of smc.s) — a `sub` with an immediate operand, which `estimate_add_sub_immediate_word_count("sub", 1)` returns 2 for, but MARS may expand differently. Another candidate is `subiu $t3, $v0, 1` (line 27).

---

## Jank Discovered During Refactoring

### 1. `neg` Uses Wrapping Negate Instead of Trapping `sub`

**File**: engine.zig:4337
**Code**: `write_reg(state, rd, -%read_reg(state, rs));`

MARS defines `neg $rd, $rs` as `sub $rd, $zero, $rs` which traps on overflow (e.g. neg of -2147483648). The current implementation uses Zig's wrapping negate (`-%`) which silently wraps. `negu` (line 4361) correctly uses wrapping since it maps to `subu`, but `neg` should trap.

---

### 2. `ld`/`sd` Duplicated in Old Estimation Code (Dead Code)

**File**: engine.zig (old code, now cleaned up)

In the old `estimate_instruction_word_count`, `ld`/`sd` appeared in both the `ulw`/`usw`/`ld`/`sd` block (using `estimate_ulw_like_word_count`) and the standard memory ops block (using `estimate_memory_operand_word_count`). Since the `ulw` block came first, the memory ops entry for `ld`/`sd` was dead code. The refactored code removes this duplication — `ld`/`sd` now appear only in the `ulw`/`usw` block where they belong.

---

### 3. Count-Only Pseudo-Ops Still Execute Directly (570+ Lines)

**File**: engine.zig:1600-4400+ (execute_instruction)
**Status**: Known/intentional debt from partial refactoring

The `process_pseudo_op` function now serves as the single source of truth for expansion logic and word count estimation. However, only 5 pseudo-ops are fully expanded at parse time (li, move, b, beqz, bnez). The remaining ~25 recognized pseudo-ops (la, blt, sub-with-immediate, etc.) still have their execution logic in `execute_instruction()`. The `is_count_only_pseudo_op` list documents exactly which ops still need migration.

---

### 4. `abs` Delay Slot: Hardcoded Register 1

**File**: engine.zig:4348
**Code**: `write_reg(state, 1, read_reg(state, rs) >> 31);`

The `abs` pseudo-op's delay-slot path hardcodes register 1 ($at) instead of using a named constant. This is part of the broader issue #4 from issues.md (23+ hardcoded $at references), but this specific instance is particularly subtle since it only triggers in delay-slot mode.

---

### 5. `beq`/`bne` With Immediate Second Operand: Estimated but Cannot Execute

**File**: engine.zig:845-851 (estimation), execute_instruction (execution)

The estimation code handles `beq $rs, imm, label` and `bne $rs, imm, label` forms (where the second operand is an immediate instead of a register), returning 2-3 words. However, execute_instruction expects operand 1 to be a register — there's no execution path for the immediate form. If MARS accepts this syntax, it would estimate correctly for address layout but fail at runtime.

---

### 6. `and`/`or`/`xor` With Immediate: No Estimation

**File**: engine.zig (missing)

The estimation code handles `andi`/`ori`/`xori` with large immediates (expanding to lui+ori+op, 3 words). However, MARS also accepts `and $rd, $rs, imm` / `or $rd, $rs, imm` / `xor $rd, $rs, imm` which silently convert to their i-type forms. These are NOT in the estimation code — they fall through to default 1 word. If MARS expands them to >1 word for large immediates, the word count would be wrong.

---

### 7. `blt`/`bge`/etc With Immediate: Estimated but Execute Falls Through

**File**: engine.zig:820-843 (estimation)

The estimation handles branch comparison pseudo-ops with immediate second operands (e.g. `blt $t0, 100, label`), returning 2-4 words depending on immediate size. However, the execution path in execute_instruction only handles the register-register form. If the immediate form is ever used, it would have correct text layout but fail at runtime.

---

## Summary

| # | Issue | Severity | Type |
|---|-------|----------|------|
| Pre | smc_advanced off-by-1-word | HIGH | Pre-existing bug |
| 1 | neg wrapping vs trapping | MEDIUM | Semantic bug |
| 2 | ld/sd wrong estimation group | LOW | Refactoring artifact |
| 3 | 570+ lines of direct pseudo-op execution | LOW | Tech debt (known) |
| 4 | abs delay-slot hardcoded $at | LOW | Magic number |
| 5 | beq/bne immediate form: estimate only | MEDIUM | Missing execution |
| 6 | and/or/xor immediate: no estimation | LOW | Missing estimation |
| 7 | blt/bge immediate form: estimate only | MEDIUM | Missing execution |
