# Delayed-branch parity probe for compare/abs pseudo-op expansion behavior.
#
# Goal:
# - Lock in MARS semantics that only the first expanded machine word executes
#   when a multiword pseudo-op appears in a delay slot.
# - Cover register and immediate forms where the first word updates either the
#   destination register or `$at`, while later words (which must not run in the
#   slot) would normally finalize boolean/absolute-value results.

.text
.globl main

main:
    # 1) `abs` expands to `sra $at, rs, 31; xor rd, $at, rs; subu rd, rd, $at`.
    # In delay slot: only first word runs, so `rd` stays unchanged and `$at`
    # receives the sign mask.
    li    $t0, -123
    li    $t1, 777
    li    $at, 42
    beq   $zero, $zero, abs_done
    abs   $t1, $t0
abs_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 2) `seq` register form first word is `subu rd, rs, rt`.
    li    $t0, 5
    li    $t1, 5
    li    $t2, 77
    beq   $zero, $zero, seq_reg_done
    seq   $t2, $t0, $t1
seq_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 3) `sne` register form first word is `subu rd, rs, rt`.
    li    $t0, 9
    li    $t1, 5
    li    $t2, 77
    beq   $zero, $zero, sne_reg_done
    sne   $t2, $t0, $t1
sne_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 4) `sge` register form first word is `slt rd, rs, rt`.
    li    $t0, 2
    li    $t1, 5
    li    $t2, 77
    beq   $zero, $zero, sge_reg_done
    sge   $t2, $t0, $t1
sge_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 5) `sle` register form first word is `slt rd, rt, rs`.
    li    $t0, 2
    li    $t1, 5
    li    $t2, 77
    beq   $zero, $zero, sle_reg_done
    sle   $t2, $t0, $t1
sle_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 6) `sgeu` register form first word is `sltu rd, rs, rt`.
    li    $t0, 1
    li    $t1, -1
    li    $t2, 77
    beq   $zero, $zero, sgeu_reg_done
    sgeu  $t2, $t0, $t1
sgeu_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 7) `sleu` register form first word is `sltu rd, rt, rs`.
    li    $t0, 1
    li    $t1, -1
    li    $t2, 77
    beq   $zero, $zero, sleu_reg_done
    sleu  $t2, $t0, $t1
sleu_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop

    # 8) `seq` immediate-16 form first word is `addi $at, $zero, imm`.
    li    $t0, 5
    li    $t2, 77
    li    $at, 111
    beq   $zero, $zero, seq_imm16_done
    seq   $t2, $t0, 5
seq_imm16_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 9) `sne` immediate-16 form first word is `addi $at, $zero, imm`.
    li    $t0, 9
    li    $t2, 77
    li    $at, 111
    beq   $zero, $zero, sne_imm16_done
    sne   $t2, $t0, 5
sne_imm16_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 10) `sgt` immediate-16 form first word is `addi $at, $zero, imm`.
    li    $t0, 9
    li    $t2, 77
    li    $at, 111
    beq   $zero, $zero, sgt_imm16_done
    sgt   $t2, $t0, 5
sgt_imm16_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 11) `seq` immediate-32 form first word is `lui $at, high(imm)`.
    li    $t0, 100000
    li    $t2, 77
    li    $at, 111
    beq   $zero, $zero, seq_imm32_done
    seq   $t2, $t0, 100000
seq_imm32_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    li    $v0, 10
    syscall

print_int_line:
    li    $v0, 1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    jr    $ra
    nop
