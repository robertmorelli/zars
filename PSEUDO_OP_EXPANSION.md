# Pseudo-Op Expansion Task

## Goal
Convert zars from interpreting pseudo-ops to **expanding them to basic MIPS instructions** during parsing. This achieves instruction-level parity with MARS.

## Current State
- `src/mars_runtime/engine.zig:709` - `estimate_instruction_word_count()` estimates how many machine words each pseudo-op expands to
- This matches MARS's PseudoOps.txt exactly
- But zars interprets pseudo-ops directly instead of expanding them

## What Needs to Change

### Phase 1: Add Instruction Emission
Modify `engine.zig` to add a function that emits basic instructions:
```zig
fn emit_basic_instruction(parsed: *Program, op: []const u8, r1: u8, r2: u8, r3: u8, imm: i32) bool {
    // Add a LineInstruction for a basic MIPS instruction
    // Handle: lui, ori, add, addu, slt, beq, jr, etc.
}
```

### Phase 2: Convert Estimation to Emission
For each case in `estimate_instruction_word_count()`, change from returning a count to emitting the actual instructions.

**Example - Current (line 714-719):**
```zig
if (std.mem.eql(u8, op, "li")) {
    if (instruction.operand_count != 2) return 1;
    const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return 1;
    if (imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16)) return 1;
    if (imm >= 0 and imm <= std.math.maxInt(u16)) return 1;
    return 2;  // <-- This becomes emission
}
```

**Example - New:**
```zig
if (std.mem.eql(u8, op, "li")) {
    if (instruction.operand_count != 2) return false;
    const rd = operand_parse.parse_register(instruction_operand(instruction, 0)) orelse return false;
    const imm = operand_parse.parse_immediate(instruction_operand(instruction, 1)) orelse return false;

    if (imm >= std.math.minInt(i16) and imm <= std.math.maxInt(i16)) {
        // Single instruction: ori rd, $zero, imm
        return emit_basic_instruction(parsed, "ori", rd, 0, 0, imm);
    }
    if (imm >= 0 and imm <= std.math.maxInt(u16)) {
        // Single instruction: ori rd, $zero, imm (unsigned)
        return emit_basic_instruction(parsed, "ori", rd, 0, 0, imm & 0xFFFF);
    }
    // Two instructions: lui $at, HIGH; ori rd, $at, LOW
    const high = (imm >> 16) & 0xFFFF;
    const low = imm & 0xFFFF;
    return emit_basic_instruction(parsed, "lui", 1, 0, 0, high) and
           emit_basic_instruction(parsed, "ori", rd, 1, 0, low);
}
```

## Reference Documentation
- **MARS Pseudo-Ops:** `/Users/robertmorelli/Documents/personal-repos/zars/MARS/PseudoOps.txt` (572 lines)
  - Format: `source_pattern [TAB] template1 [TAB] template2 ...`
  - Example: `li $t1,100000	lui $1, VHL2	ori RG1, $1, VL2U`
  - VHL/VL means high/low 16 bits of immediate value
  - RG1 means register from operand 1

- **Current Estimation Logic:** `src/mars_runtime/engine.zig:709-890`
  - Already handles all the cases correctly
  - Just need to emit instead of return counts

## Execution Changes
Currently `execute_instruction()` handles pseudo-ops:
- Need to remove pseudo-op cases (li, move, la, etc.)
- Keep only basic machine instructions (add, ori, lui, addu, etc.)
- This will simplify execution code significantly

## Testing
After changes:
1. Run: `node tools/runtime_main.mjs --engine compare`
2. Should pass all 90 tests (final state matches)
3. Run: `node tools/turbo_diff.mjs test_programs/integer_arithmetic.s`
4. Should show perfect step-level match with MARS

## Key Files
- `src/mars_runtime/engine.zig` - Main work here
- `src/mars_runtime/model.zig` - LineInstruction structure (may need tweaks)
- `MARS/PseudoOps.txt` - Reference for expansion rules
- `tools/turbo_diff.mjs` - Verify step-level parity

## Design Principle
**We always strive to match MARS. Always.** See GOAL.md for full context.
