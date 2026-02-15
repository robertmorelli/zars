# Pseudo-Op Expansion Issues

## Critical Issues

### 1. Instruction Count Discrepancy
- **Status**: BLOCKING
- **Symptom**: turbo_diff shows MARS=71 instructions vs zars=47 for `integer_arithmetic.s`
- **Expected**: Should match (71 instructions)
- **Root Cause**: Unknown - li pseudo-op expansion may not be triggering for all cases
- **Impact**: Step-level parity not achieved despite final state matching

### 2. li Expansion Not Triggering
- **Status**: Blocking instruction count fix
- **Evidence**:
  - Code checks small immediates (e.g., `li $t0, 40`) should expand to `ori $t0, $zero, 40`
  - But instruction count gap suggests this isn't happening
- **Possible Causes**:
  - `try_expand_pseudo_op()` returning false when it shouldn't
  - Operand parsing failing for simple cases
  - Operand count detection broken
  - Return value not being handled correctly
- **Next Debug Steps**:
  - Add logging to `try_expand_pseudo_op()` to see if it's called
  - Check if immediates are parsing correctly
  - Verify operand_count for li instructions

### 3. 32-bit li Expansion Not Implemented
- **Status**: Deferred (causes gaps in instruction count)
- **Case**: `li $rd, 0xHHHHLLLL` where immediate doesn't fit in 16 bits
- **Current Code**: Returns early without expansion
- **Required**: Should expand to:
  ```
  lui $at, HIGH
  ori $rd, $at, LOW
  ```
- **Blocker**: Need to emit lui and ori with proper number formatting

### 4. Missing Pseudo-Op Expansions
- **Status**: Incomplete
- **Already Done**:
  - `li` (partial - only small immediates)
  - `move` (basic implementation)
- **Missing**:
  - All arithmetic immediates (addi, andi, ori, xori, etc.)
  - Load address (la)
  - Branches (blt, ble, bgt, bge, beq, bne)
  - All others from PseudoOps.txt (572 lines)
- **Reference**: `/Users/robertmorelli/Documents/personal-repos/zars/MARS/PseudoOps.txt`

## Debugging Checklist

- [ ] Run turbo_diff on test_li.s to see actual vs expected instructions
- [ ] Add debug output to try_expand_pseudo_op() to verify it's called
- [ ] Check if small li instructions are being expanded or interpreted as-is
- [ ] Verify operand_count detection for pseudoops
- [ ] Confirm emit_instruction() is being called and adding to program
- [ ] Check instruction sequence in final program for test_li.s

## Test Cases

### Immediate test_li.s
```asm
.text
.globl main
main:
    li $t0, 40          # Should expand to: ori $t0, $zero, 40 (1 instruction)
    li $t1, 2           # Should expand to: ori $t1, $zero, 2 (1 instruction)
    li $v0, 1           # Should expand to: ori $v0, $zero, 1 (1 instruction)
    syscall             # (1 instruction)
    li $v0, 10          # Should expand to: ori $v0, $zero, 10 (1 instruction)
    syscall             # (1 instruction)
```
Expected: 6 instructions
Current: Likely not expanding properly

## Known Working State

- All 90 runtime tests pass (final state parity)
- Register/memory state matches MARS at program end
- Parser doesn't crash on pseudo-ops
- emit_instruction() function exists and compiles

## Known Broken State

- Instruction counts don't match MARS
- turbo_diff shows divergence in instruction count despite step-by-step parity
- Small li instructions not expanding (hypothesis)
- 32-bit li completely missing
- Most pseudo-ops not implemented

