# Engine.zig Refactoring Status

## Goal
Split engine.zig (8767 lines) into 8+ modular files using pipeline architecture for testability.

## Progress: 5/9 Modules Complete

### ✅ Completed Modules

1. **types.zig** (~130 lines)
   - Shared types, constants, and data structures
   - StatusCode enum, ExecState struct, Program struct
   - AddressExpression union, memory map constants
   - Re-exports from model.zig and engine_data.zig

2. **registers.zig** (~70 lines)
   - Register access abstraction
   - read_reg/write_reg (handles $zero hardwiring)
   - Floating-point register access (single/double)
   - HI/LO register operations
   - FP condition flag access

3. **memory.zig** (~170 lines)
   - Memory subsystem for data/heap/text segments
   - Big-endian read/write operations (u8/u16/u32/u64)
   - Text address <-> instruction index mapping
   - SMC (self-modifying code) support via write_text_patch_word
   - syscall_sbrk for heap management

4. **input_output.zig** (~170 lines)
   - Input parsing for syscalls
   - read_next_input_int/float/double/char/token
   - String operations: syscall_read_string (MARS fgets behavior)
   - C-string helpers: read_c_string_from_data, append_c_string_from_data

5. **label_resolver.zig** (~145 lines)
   - Label lookup: find_label, find_data_label
   - Address resolution: resolve_label_address
   - Fixup registration: add_fixup
   - Fixup resolution: resolve_fixups (patches label references)
   - Hi/Lo computation helpers for split immediates

## 🚧 Remaining Work

### Module 6: parser.zig (~400 lines estimated)
**Extracts:** parse_program, register_instruction, normalize_line, compute_text_layout
**Dependencies:** label_resolver.zig, pseudo_expander.zig
- Line-oriented source parsing
- Label and data directive handling  
- Instruction registration
- Text layout computation (instruction <-> word mapping)
- Integration with pseudo-op expansion

### Module 7: pseudo_expander.zig (~1700 lines estimated)
**Extracts:** process_pseudo_op, try_expand_pseudo_op, emit helpers
**Dependencies:** label_resolver.zig
- **MASSIVE MODULE** - Contains all pseudo-instruction expansion logic
- Single source of truth for 50+ pseudo-ops (li, la, move, b, beqz, blt, etc.)
- Dual-mode operation: emit (parse-time expansion) and count (layout estimation)
- Immediate helpers: emit_load_immediate_at, extract_high_bits, extract_low_bits
- Address operand parsing: parse_address_operand, parse_address_expression

**Key pseudo-ops:**
- Arithmetic: addi/addiu/subi/subiu (with 32-bit immediate support)
- Logical: andi/ori/xori (with 32-bit immediate support)
- Branches: blt/bgt/ble/bge variants (signed/unsigned, register/immediate)
- Memory: la (load address), ulw/usw (unaligned access), ld/sd (64-bit pairs)
- Multiplication/division: mul/mulo/mulou/div/divu/rem/remu
- Comparison: seq/sne/slt/sle/sgt/sge (signed/unsigned variants)
- Shifts: rol/ror (rotate operations)
- Misc: move, neg/negu, abs, mfc1.d/mtc1.d (FP register pairs)

### Module 8: syscalls.zig (~1000 lines estimated)
**Extracts:** execute_syscall and all service implementations
**Dependencies:** registers.zig, memory.zig, input_output.zig
- 50+ MARS runtime services
- I/O services (1-15): print_int, print_float, print_string, read_int, etc.
- File I/O (13-16): open, read, write, close
- Memory services (9): sbrk (heap allocation)
- Utility services (30-42): time, MIDI, sleep, print_hex, RNG, etc.
- Exit and exception handling (10, 17)

### Module 9: executor.zig (~4000 lines estimated)
**Extracts:** execute_instruction, execute_patched_instruction, opcode handlers
**Dependencies:** registers.zig, memory.zig, syscalls.zig
- **LARGEST MODULE** - Main execution dispatcher
- Giant switch statement for all MIPS opcodes
- Integer arithmetic: add/sub/mult/div (signed/unsigned variations)
- Logical: and/or/xor/nor
- Shifts: sll/srl/sra/sllv/srlv/srav
- Branches: beq/bne/blez/bgtz with delayed branch support
- Jumps: j/jal/jr/jalr with return address handling
- Memory loads/stores: lb/lh/lw/lbu/lhu with alignment checking
- Floating-point: add.s/d, sub.s/d, mul.s/d, div.s/d, sqrt.s/d
- FP compare: c.eq.s/d, c.lt.s/d, c.le.s/d (with condition flags)
- FP branches: bc1t/bc1f
- HI/LO operations: mfhi/mthi/mflo/mtlo
- CP0 instructions: mfc0/mtc0/eret for exception handling
- execute_patched_instruction: SMC path dispatching patched machine words
- Delayed branch state machine
- Trap and exception handling

### Module 10: engine.zig (refactored ~200 lines estimated)
**Keeps:** Public API and pipeline orchestration
**Dependencies:** ALL above modules
- run_program (parse → execute pipeline)
- init_execution/step_execution (step-by-step debugging)
- Snapshot functions for inspection (regs, memory, PC, etc.)
- Input management: update_input_slice, snapshot_input_offset_bytes
- Static storage: parsed_program_storage, exec_state_storage
- Pipeline coordination between all stages

## Pipeline Architecture

```
Input Source Text
       ↓
[source_preprocess] (existing module)
       ↓
[parse_program] → parser.zig
       ├→ register_instruction
       ├→ try_expand_pseudo_op → pseudo_expander.zig
       ├→ compute_text_layout
       └→ resolve_fixups → label_resolver.zig
       ↓
   Program AST
       ↓
[execute_program] → engine.zig orchestrator
       ├→ execute_instruction → executor.zig
       │    ├→ Memory ops → memory.zig
       │    ├→ Register ops → registers.zig
       │    └→ Syscalls → syscalls.zig
       │              └→ I/O → input_output.zig
       └→ execute_patched_instruction → executor.zig (SMC path)
       ↓
   Output Buffer
```

## Benefits of Refactored Architecture

1. **Testability**: Each pipeline stage can be tested independently
2. **Clarity**: Related functionality grouped in focused modules
3. **Maintainability**: Changes isolated to specific modules
4. **Compilation Speed**: Smaller files compile faster
5. **Comprehension**: ~200-1700 line modules vs 8767-line monolith
6. **Safety**: Clear module boundaries prevent unintended coupling

## Implementation Strategy

### Phase 1: Foundation (✅ COMPLETE)
- Extract shared types → types.zig
- Extract register access → registers.zig  
- Extract memory operations → memory.zig
- Extract I/O helpers → input_output.zig
- Extract label resolution → label_resolver.zig

### Phase 2: Parsing (🚧 IN PROGRESS)
- Extract parser → parser.zig
- Extract pseudo-op expansion → pseudo_expander.zig
  * This is the largest single extraction (~1700 lines)
  * process_pseudo_op is single source of truth for all pseudo-ops
  * Both parse-time expansion and word-count estimation

### Phase 3: Execution (⏭️ NEXT)
- Extract syscalls → syscalls.zig
- Extract executor → executor.zig (largest module ~4000 lines)
  * May benefit from further subdivision (integer ops, FP ops, memory ops, branches)

### Phase 4: Integration (⏭️ FINAL)
- Refactor engine.zig to orchestrate pipeline
- Verify all tests pass
- Update imports in dependent modules

## File Size Summary

| Module | Lines | Status | Extracted From |
|--------|-------|--------|----------------|
| types.zig | ~130 | ✅ | Lines 1-100 (constants, types) |
| registers.zig | ~70 | ✅ | Scattered (register helpers) |
| memory.zig | ~170 | ✅ | Scattered (memory helpers) |
| input_output.zig | ~170 | ✅ | Syscall I/O sections |
| label_resolver.zig | ~145 | ✅ | Lines 400-700 (label/fixup logic) |
| parser.zig | ~400 | 🚧 | Lines 250-700 (parse_program, etc.) |
| pseudo_expander.zig | ~1700 | 🚧 | Lines 853-1703 (process_pseudo_op) |
| syscalls.zig | ~1000 | ⏭️ | Lines 3500-4500 (execute_syscall) |
| executor.zig | ~4000 | ⏭️ | Lines 2000-6000 (execute_instruction) |
| engine.zig (refactored) | ~200 | ⏭️ | Public API + orchestration |

**Total:** 685 lines extracted (7.8%) | 8082 lines remaining | Target: 9+ modular files

## Next Steps

1. Complete parser.zig extraction
2. Complete pseudo_expander.zig extraction (largest single task)
3. Extract syscalls.zig
4. Extract executor.zig (consider subdividing this 4000-line behemoth)
5. Refactor engine.zig to wire everything together
6. Run full test suite to verify behavior unchanged
7. Consider further subdivision of executor.zig into:
   - integer_ops.zig (~1000 lines)
   - fp_ops.zig (~800 lines)
   - memory_ops.zig (~600 lines)
   - branch_ops.zig (~600 lines)
   - core_executor.zig (dispatcher ~1000 lines)

## Testing Strategy

After each module extraction:
1. Verify no compilation errors in new module
2. Update engine.zig imports
3. Run subset of integration tests
4. After all modules complete: run full test suite
5. Verify output byte-for-byte identical to original

## Notes

- All modules follow AGENTS.md style guidelines (70 lines/function max, explicit naming, assertions)
- Pipeline architecture enables independent testing of parse/expand/execute stages
- process_pseudo_op's dual-mode design (emit vs count) is critical for layout computation
- SMC (self-modifying code) support complicates executor - needs text patch dispatch
- Delayed branching is stateful - requires careful sequencing in executor
- FP operations use custom fp_math.zig for deterministic results matching MARS
