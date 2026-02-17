# Architectural Issues - ZARS Zig MIPS Runtime

## Critical Issues

### 1. Instruction Logic Duplicated in Three Places

**Severity**: CRITICAL
**Status**: BLOCKING (documented in pseudoops_issues.md)

The `li` (load immediate) and `move` pseudo-ops are defined in three separate locations that must stay perfectly in sync:

1. **Expansion Phase** - `src/mars_runtime/engine.zig:690-743` in `try_expand_pseudo_op()`
   - Converts pseudo-ops to basic instructions
   - Emits machine words via `emit_instruction()`

2. **Estimation Phase** - `src/mars_runtime/engine.zig:841-847` in `estimate_instruction_word_count()`
   - Counts how many machine words each pseudo-op expands to
   - Must predict what expansion will do

3. **Execution Phase** - `src/mars_runtime/engine.zig:1345-1366` in `execute_instruction()`
   - Directly interprets pseudo-op instructions at runtime
   - Falls back when expansion didn't happen

**The Problem**:
- All three must stay in perfect sync regarding operand validation, immediate range checks, and expansion logic
- A change to `li` handling requires updates in all 3 locations
- The expansion estimates must match actual execution behavior
- **Current mismatch** at line 703-710: validates `imm >= std.math.minInt(i16) and imm < 0` differently than line 844-845

**Impact**:
- Already documented issue: "li Expansion Not Triggering"
- Documented issue: "Instruction Count Discrepancy" (MARS=71 vs zars=47 instructions)
- Test file: test_li.s, test_li_32bit.s failing

**Root Cause**: No single source of truth for how instructions expand. Each layer reimplements the logic.

---

### 2. Pseudo-Op Expansion vs Execution Architecture Conflict

**Severity**: CRITICAL
**Status**: BLOCKING

The codebase has conflicting design approaches:

**Current State (Fragmented)**:
1. **Expansion phase** `try_expand_pseudo_op()` (line 686-743) emits basic instructions
2. **Execution phase** `execute_instruction()` (line 1334+) still directly interprets pseudo-ops as fallback

**Intended Design** (per GOAL.md):
- Parse → Expand all pseudo-ops → Execute only basic instructions
- Each step corresponds to one machine instruction
- Pseudo-ops expand to same sequence as MARS

**Why This Rots**:
- Pseudo-op handling is split across two functions
- No clear ownership: is something expanded or executed raw?
- New pseudo-ops require updates in both places
- Expansion is incomplete (only li and move, per pseudoops_issues.md)

**Impact**:
- pseudoops_issues.md states expansion is "partial" and "not triggering"
- Line 1345+ still has direct li, move, la, addi, etc. execution
- Word count estimation function tries to compensate for incomplete expansion

---

### 3. Documentation vs Code Mismatches

**Severity**: CRITICAL
**Status**: ACTIVE

**GOAL.md claims**:
> "Pseudo-ops must expand to the exact same machine instruction sequence as MARS"
> "Each step in zars should correspond to one machine instruction"

**But pseudoops_issues.md documents**:
- "Instruction Count Discrepancy: MARS=71 vs zars=47"
- "li Expansion Not Triggering"
- "32-bit li completely missing"

**PSEUDO_OP_EXPANSION.md describes a refactoring plan** (single source of truth) but code still has the fragmented three-location design.

**Affected Files**:
- `/Users/robertmorelli/Documents/personal-repos/zars/GOAL.md` (claims expansion complete)
- `/Users/robertmorelli/Documents/personal-repos/zars/PSEUDO_OP_EXPANSION.md` (describes ideal design)
- `/Users/robertmorelli/Documents/personal-repos/zars/pseudoops_issues.md` (documents real problems)

**Why This Rots**: Developers reading GOAL.md will assume pseudo-ops work correctly per MARS, but they don't.

---

## High Severity Issues

### 4. Magic Number: Register $at Hardcoded 23+ Times

**Severity**: HIGH
**Status**: ONGOING

The $at (assembler temporary) register is hardcoded as `1` throughout the codebase:

**Locations in engine.zig**:
- Lines 727, 730: In `emit_instruction()` calls for pseudo-op expansion
- Lines 1390, 1395, 1400, 1425, 1433: In `execute_instruction()` for la (load address)
- Lines 1803, 1822, 1841, 1847, 1871, 1887, 1893, 1916, 1936, 1953, 1979, 2001, 2033+: In pseudo-op execution blocks

**Total: 23+ hardcoded occurrences of `1` for $at**

**Missing Single Source of Truth**:
- No constant defined like `const AT_REGISTER = 1` in model.zig
- Other registers ($sp = 29, $gp = 28) also hardcoded inline

**Why This Rots**: If assembler temporary register assignment ever changes (for compatibility, debugging, or custom configs), 20+ locations need manual updates.

**Related Issue**: Register name constants should be defined in model.zig

---

### 5. Word Count Estimation: 62-Branch Complex Logic

**Severity**: HIGH
**Status**: FRAGILE

The `estimate_instruction_word_count()` function (line 836-1062 in engine.zig) contains 62 different conditional branches trying to predict machine instruction expansion.

**Structure**:
- Lines 841-847: `li` expansion rules
- Lines 854-877: Branch comparisons (`blt`, `bltu`, `bge`, `bgeu`, `bgt`, `bgtu`, `ble`, `bleu`)
- Lines 879-885: `beq`, `bne`
- Lines 887-892: `addi`, `addiu`
- Lines 894-899: `subi`, `subiu`
- Lines 901-907: `and`, `or`, `xor`, `andi`, `ori`, `xori`
- ... plus ~20 more pseudo-ops

**The Problem**:
1. This entire function approximates what MARS does but is separate from:
   - Actual expansion in `try_expand_pseudo_op()`
   - Actual execution in `execute_instruction()`
2. All three must stay in sync but have no common source of truth
3. It's essentially duplicating pseudo-op logic a second time just for estimation

**Why It Rots**: When pseudo-op expansion is modified, this estimation function must also be updated, or instruction counts diverge from actual execution. This is already happening: MARS=71 vs zars=47.

**Maintenance Cost**: Any new pseudo-op requires updates to all 3 locations (expand, estimate, execute).

---

### 6. Incomplete Pseudo-Op Coverage

**Severity**: HIGH
**Status**: BLOCKING

Only 2 pseudo-ops are partially implemented in `try_expand_pseudo_op()`:
- `li` (lines 690-731) - Partial, not triggering correctly
- `move` (lines 734-740) - Basic implementation

**But MARS supports 572 pseudo-ops** (from MARS/PseudoOps.txt), including:
- `la` (load address) - Started in execute_instruction but not expanded
- `addi` with 32-bit immediates
- `blt`, `bge`, `bgt`, `ble` (branch comparisons)
- `abs`, `mul`, `div`, `rem` (arithmetic)
- `ulw`, `usw` (unaligned loads/stores)
- ~560+ more

**Why This Rots**:
- As more pseudo-ops are added to `try_expand_pseudo_op()`, both `estimate_instruction_word_count()` AND `execute_instruction()` must be updated in parallel
- The three-location duplication makes adding new pseudo-ops 3x the work
- Dead code exists: 570 pseudo-ops are missing but documented

**Impact**:
- Feature incomplete (most MARS pseudo-ops don't work)
- Architecture will scale poorly

---

### 7. Memory Layout Constants Fragmented Across Two Files

**Severity**: HIGH
**Status**: INCOMPLETE

Memory addresses are partially centralized but split between files:

**In model.zig** (lines 9-11):
```zig
pub const text_base_addr: u32 = 0x00400000;
pub const data_base_addr: u32 = 0x10010000;
pub const heap_base_addr: u32 = 0x10040000;
```

**Hardcoded in engine.zig** (lines 50-54, missing from model.zig):
```zig
regs[28] = @bitCast(@as(u32, 0x10008000)); // $gp - NOT in model.zig
regs[29] = @bitCast(@as(u32, 0x7fffeffc)); // $sp - MISSING from model.zig
```

**Why This Rots**:
- The $gp and $sp initial values are magic numbers with no constant name
- If MARS changes memory layout, developers must find and update these hardcoded values in engine.zig
- No single source of truth for register initialization

**Missing Constants in model.zig**:
- `GP_INITIAL_VALUE = 0x10008000`
- `SP_INITIAL_VALUE = 0x7fffeffc`

---

## Medium Severity Issues

### 8. Immediate Range Checking: Duplicated Validation Logic

**Severity**: MEDIUM
**Status**: INCONSISTENT

Helper functions exist (`immediate_fits_signed_16()`, `immediate_fits_unsigned_16()` at lines 1200-1205) but the logic is also duplicated inline in multiple locations:

**Helper functions** (line 1200-1205):
```zig
fn immediate_fits_signed_16(imm: i32) bool {
    return imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16);
}

fn immediate_fits_unsigned_16(imm: i32) bool {
    return imm >= 0 and imm <= std.math.maxInt(u16);
}
```

**But inline duplicates exist**:
- Line 703: `if (imm >= std.math.minInt(i16) and imm < 0)` - DIFFERENT LOGIC
- Line 708: `if (imm >= 0 and imm <= std.math.maxInt(u16))`
- Line 844-845: Same logic in `estimate_instruction_word_count()`

**The Bug**: Line 703 uses `imm < 0` (only negative) instead of `<= maxInt(i16)` (full range), which could cause expansion to miss some valid cases.

**Why This Rots**:
- Validation logic appears in 3+ places
- Different conditions for same check (< 0 vs <= maxInt)
- If range rules change (for new instruction types), all copies must update

**Calls**: These functions are called 62+ times but duplicates exist inline.

---

### 9. Missing Register Name Constants

**Severity**: MEDIUM
**Status**: MISSING

No register name constants defined. Register operations use numeric indices:

**Current State**:
- `regs[28]` and `regs[29]` for initialization (numeric indices)
- `write_reg(state, 1, ...)` for $at (hardcoded 1)
- `regs[0]` for $zero (implied)

**Missing Constants in model.zig** (should define all 32):
```zig
pub const ZERO = 0;
pub const AT = 1;
pub const V0 = 2;
pub const V1 = 3;
// ... through ...
pub const RA = 31;

// Special registers
pub const SP = 29;
pub const GP = 28;
pub const FP = 30;  // also called $frame pointer
```

**Why This Rots**:
- Code is harder to read (what does register 1 do?)
- Magic numbers make bugs harder to spot
- Register usage is implicit, not explicit
- Differences from MARS conventions harder to spot

**Affected Files**: Throughout `engine.zig` (100+ register accesses)

---

### 10. Inconsistent Naming Conventions

**Severity**: MEDIUM
**Status**: MIXED

Mixed naming patterns throughout codebase:

**Inconsistencies**:
- Some pseudo-ops use full names (`li`, `move`, `la`, `add`, `addi`)
- Some use numeric forms (`op_li`, no numbering scheme)
- Register references: numeric indices vs. implied names
- Memory locations: hardcoded vs. named constants (partial)

**Example**: The function `try_expand_pseudo_op()` vs. `execute_instruction()` - inconsistent naming for similar concepts.

**Why This Rots**:
- New contributors don't know naming pattern to follow
- Makes searching for related code harder
- Documentation inconsistent with code

---

## Summary Table

| # | Issue | Type | Severity | File(s) | Occurrences | Status |
|---|-------|------|----------|---------|-------------|--------|
| 1 | li/move logic in 3 places | Duplication | CRITICAL | engine.zig | 3 | Blocking |
| 2 | Expansion vs Execution conflict | Architecture | CRITICAL | engine.zig | 2 functions | Blocking |
| 3 | Doc/code mismatch on pseudo-ops | Documentation | CRITICAL | 3 .md files | Multiple | Active |
| 4 | $at register hardcoded | Magic Number | HIGH | engine.zig | 23+ | Ongoing |
| 5 | Word count estimation logic | Fragmentation | HIGH | engine.zig | 1 function | Fragile |
| 6 | Incomplete pseudo-op coverage | Dead Code | HIGH | engine.zig | 570/572 missing | Blocking |
| 7 | Memory addresses split | Fragmentation | HIGH | 2 files | 2 values | Incomplete |
| 8 | Immediate range checks duplicated | Pattern | MEDIUM | engine.zig | 62 calls + 3 inline | Inconsistent |
| 9 | Missing register constants | Convention | MEDIUM | model.zig | 0 (should have 32) | Missing |
| 10 | Inconsistent naming | Convention | MEDIUM | engine.zig | Throughout | Mixed |

---

## Recommended Refactoring Order

### Phase 1: Extract Constants (Lowest Risk)
1. **Extract $at register constant** to model.zig
   - Add: `pub const AT_REGISTER = 1;`
   - Update: 23+ hardcoded `1` references in engine.zig

2. **Extract memory initialization values** to model.zig
   - Add: `pub const GP_INITIAL_VALUE = 0x10008000;`
   - Add: `pub const SP_INITIAL_VALUE = 0x7fffeffc;`
   - Update: Lines 50-54 in engine.zig

3. **Add register name constants** to model.zig
   - Add: ZERO, AT, V0, V1, ... RA (all 32 registers)
   - Add: Named aliases (SP=29, GP=28, FP=30, RA=31)
   - Update: Register accesses for clarity

### Phase 2: Unify Instruction Definitions (Medium Risk)
4. **Create single instruction definition source**
   - Move pseudo-op definitions to a table (data-driven)
   - Define: operand types, expansion rules, word counts
   - Replace: The 3-location duplication (expand, estimate, execute)

5. **Fix immediate range checks**
   - Remove inline duplicates
   - Use helper functions consistently
   - Fix the `imm < 0` bug on line 703

### Phase 3: Unify Pseudo-Op Handling (Higher Risk)
6. **Complete expansion phase first**
   - Implement all MARS pseudo-ops in `try_expand_pseudo_op()`
   - Remove direct pseudo-op handling from `execute_instruction()`
   - Update `estimate_instruction_word_count()` to match expansion

7. **Simplify execution**
   - Remove 570+ lines of pseudo-op execution code
   - Execute only basic instructions
   - Update tests to verify expansion correctness

### Phase 4: Documentation (Low Risk)
8. **Update GOAL.md and pseudoops_issues.md**
   - Document actual design state
   - Mark completed vs. incomplete pseudo-ops
   - Update instruction count targets

---

## Files to Update

- `src/mars_runtime/model.zig` - Add constants (0 → ~35)
- `src/mars_runtime/engine.zig` - Remove duplication, refactor (1000s of lines)
- `GOAL.md` - Update claims about pseudo-op completeness
- `pseudoops_issues.md` - Update status once fixed
- `PSEUDO_OP_EXPANSION.md` - Verify against new design

