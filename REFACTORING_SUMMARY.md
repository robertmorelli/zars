# Engine Refactoring Summary

## Code Smells Identified and Fixed

### 1. String Literal Duplication ✅ FIXED
**Problem**: Directive names like `.align`, `.asciiz`, `.ascii`, `.word`, `.half`, `.float`, `.double`, etc. were scattered throughout the parser with hardcoded string literals appearing 10+ times each.

**Solution**: Created centralized `directives` struct with named constants:
```zig
const directives = struct {
    pub const text = ".text";
    pub const ktext = ".ktext";
    pub const data = ".data";
    pub const kdata = ".kdata";
    pub const globl = ".globl";
    pub const extern_dir = ".extern";
    pub const set_dir = ".set";
    pub const align_dir = ".align";
    pub const asciiz = ".asciiz";
    pub const ascii = ".ascii";
    pub const space = ".space";
    pub const byte = ".byte";
    pub const half = ".half";
    pub const word = ".word";
    pub const float_dir = ".float";
    pub const double_dir = ".double";
};
```

**Impact**: Eliminated all directive string literal duplication. Single source of truth for directive names prevents accidental typos and makes future changes centralized.

### 2. Parse Program Section ✅ DOCUMENTED
Located in: parse_program() function starting at line ~347
- Line parsing and tokenization
- Label and directive registration
- Text/data section switching
- 150+ lines of parser logic

### 3. Pseudo-Op Expansion ✅ DOCUMENTED  
Located in: process_pseudo_op() function
- Single source of truth for pseudo-op patterns
- Eliminates three-way duplication between:
  - Parse-time expansion (try_expand_pseudo_op)
  - Count estimation (estimate_instruction_word_count)
  - Runtime execution (execute_instruction)
- Handles 40+ pseudo-instruction patterns

### 4. Instruction Execution (CODE SMELL) ⚠️ DOCUMENTED
Located in: execute_instruction() function (lines 1975-4929)
- **Complexity**: 2,954 lines
- **Pattern**: Massive if-chain dispatch (100+ `if (std.mem.eql(u8, op, "..."))` checks)
- **Instruction families**: Integer arithmetic, memory access, branching, floating-point, system calls

**Why not split further**: The function has deep coupling with execution state and would require significant refactoring of dependencies. Documented with clear markers for future developers.

## Refactoring Opportunities

### High Priority (Complexity Reduction)
1. **extract_instruction_dispatcher()**: Break execute_instruction into focused handlers:
   - `execute_integer_arithmetic_ops()` 
   - `execute_memory_ops()`
   - `execute_branch_ops()`
   - `execute_fp_ops()`
   - `execute_syscall_handler()`

2. **Reduce immediate-fitting checks**: Create helpers:
   ```zig
   pub fn immediate_fits_signed_16(imm: i32) bool
   pub fn immediate_fits_unsigned_16(imm: i32) bool
   ```

### Medium Priority (Module Extraction)
1. **runtime_helpers.zig**: Register/memory/FP operations
2. **pseudo_ops.zig**: Pseudo-op expansion logic
3. **parser.zig**: Source parsing and label registration
4. **executor.zig**: Instruction dispatch (when split)

### Design Pattern: Single Source of Truth
- ✅ Directives (constants now used everywhere)
- ✅ Pseudo-op expansion (process_pseudo_op)
- ⚠️ Instruction execution (needs dispatch splitting)

## File Statistics
- **Total lines**: 8,808
- **Total functions**: 100
- **Largest function**: execute_instruction() at 2,954 lines
- **Second largest**: execute_patched_instruction() at 1,121 lines

## Testing Status
- ✅ All tests passing
- ✅ Build successful
- ✅ No regressions from refactoring

## Next Steps
1. Split execute_instruction into family-specific handlers
2. Extract runtime_helpers module
3. Consider instruction pattern matching refactor (dispatcher table approach)
4. Add performance profiling to identify hot paths for optimization
