# Delayed-branch parity probe for additional pseudo-op families.
#
# Focus: `la`, `rol/ror`, register-pair transfer pseudos, and selected
# arithmetic pseudo immediates whose first expansion word should be the only one
# executed in a delay slot.

.text
.globl main

main:
    # 1) `la rd, label` first word is `lui $at, high(label)`.
    li    $t0, 99
    li    $at, 7
    beq   $zero, $zero, la_label_done
    la    $t0, anchor
la_label_done:
    move  $a0, $t0
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 2) `la rd, 100000` first word is `lui $at, high(imm)`.
    li    $t0, 99
    li    $at, 7
    beq   $zero, $zero, la_imm_done
    la    $t0, 100000
la_imm_done:
    move  $a0, $t0
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 3) `rol` register form first word is `subu $at, $zero, rs`.
    li    $t0, 0x12345678
    li    $t1, 4
    li    $t2, 99
    li    $at, 7
    beq   $zero, $zero, rol_reg_done
    rol   $t2, $t0, $t1
rol_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 4) `rol` immediate form first word is `srl $at, rt, (32-imm)`.
    li    $t0, 0x12345678
    li    $t2, 99
    li    $at, 7
    beq   $zero, $zero, rol_imm_done
    rol   $t2, $t0, 4
rol_imm_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 5) `ror` register form first word is `subu $at, $zero, rs`.
    li    $t0, 0x12345678
    li    $t1, 4
    li    $t2, 99
    li    $at, 7
    beq   $zero, $zero, ror_reg_done
    ror   $t2, $t0, $t1
ror_reg_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 6) `ror` immediate form first word is `sll $at, rt, (32-imm)`.
    li    $t0, 0x12345678
    li    $t2, 99
    li    $at, 7
    beq   $zero, $zero, ror_imm_done
    ror   $t2, $t0, 4
ror_imm_done:
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 7) `mfc1.d` first word moves low register only.
    li    $t4, 0x11223344
    li    $t5, 0x55667788
    mtc1  $t4, $f2
    mtc1  $t5, $f3
    li    $t0, 99
    li    $t1, 88
    beq   $zero, $zero, mfc1d_done
    mfc1.d $t0, $f2
mfc1d_done:
    move  $a0, $t0
    jal   print_int_line
    nop
    move  $a0, $t1
    jal   print_int_line
    nop

    # 8) `mtc1.d` first word moves low register only.
    li    $t0, 0x99AABBCC
    li    $t1, 0xDDEEFF00
    mtc1  $zero, $f4
    mtc1  $zero, $f5
    beq   $zero, $zero, mtc1d_done
    mtc1.d $t0, $f4
mtc1d_done:
    mfc1  $t2, $f4
    mfc1  $t3, $f5
    move  $a0, $t2
    jal   print_int_line
    nop
    move  $a0, $t3
    jal   print_int_line
    nop

    # 9) `mul` imm16 first word is `addi $at, $zero, imm`.
    li    $t0, 6
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, mul_imm16_done
    mul   $t1, $t0, 5
mul_imm16_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 10) `mul` imm32 first word is `lui $at, high(imm)`.
    li    $t0, 6
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, mul_imm32_done
    mul   $t1, $t0, 100000
mul_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 11) `div` imm16 first word is `addi $at, $zero, imm`.
    li    $t0, 20
    li    $t1, 99
    li    $at, 7
    li    $t6, 123
    li    $t7, 456
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, div_imm16_done
    div   $t1, $t0, 5
div_imm16_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop
    move  $a0, $s0
    jal   print_int_line
    nop
    move  $a0, $s1
    jal   print_int_line
    nop

    # 12) `rem` imm16 first word is `addi $at, $zero, imm`.
    li    $t0, 20
    li    $t1, 99
    li    $at, 7
    li    $t6, 123
    li    $t7, 456
    mthi  $t6
    mtlo  $t7
    beq   $zero, $zero, rem_imm16_done
    rem   $t1, $t0, 5
rem_imm16_done:
    mfhi  $s0
    mflo  $s1
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
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

anchor:
    nop
