# Delayed-branch parity probe for register-divisor div/rem pseudo-op forms.
#
# In a delay slot, only the first expanded word (`bne rt, $zero, ...`) executes,
# so destination and HI/LO must remain unchanged and zero-divisor does not trap.

.text
.globl main

main:
    # div non-zero divisor in delay slot.
    li    $t0, 20
    li    $t1, 5
    li    $t2, 99
    li    $t6, 11
    li    $t7, 22
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, div_reg_nz_done
    div   $t2, $t0, $t1
div_reg_nz_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
    jal   print_int_line
    nop

    # div zero divisor in delay slot.
    li    $t0, 20
    li    $t1, 0
    li    $t2, 99
    li    $t6, 33
    li    $t7, 44
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, div_reg_z_done
    div   $t2, $t0, $t1
div_reg_z_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
    jal   print_int_line
    nop

    # divu non-zero divisor in delay slot.
    li    $t0, 20
    li    $t1, 5
    li    $t2, 99
    li    $t6, 55
    li    $t7, 66
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, divu_reg_nz_done
    divu  $t2, $t0, $t1
divu_reg_nz_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
    jal   print_int_line
    nop

    # rem non-zero divisor in delay slot.
    li    $t0, 20
    li    $t1, 6
    li    $t2, 99
    li    $t6, 77
    li    $t7, 88
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, rem_reg_nz_done
    rem   $t2, $t0, $t1
rem_reg_nz_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
    jal   print_int_line
    nop

    # remu non-zero divisor in delay slot.
    li    $t0, 20
    li    $t1, 6
    li    $t2, 99
    li    $t6, 101
    li    $t7, 202
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, remu_reg_nz_done
    remu  $t2, $t0, $t1
remu_reg_nz_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
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
