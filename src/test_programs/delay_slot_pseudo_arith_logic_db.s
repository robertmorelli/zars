# Delayed-branch parity probe for arithmetic/logical pseudo-op families.
#
# The fixture checks that when these pseudo-ops are in a delay slot, only the
# first expanded machine word executes, matching MARS behavior.

.text
.globl main

main:
    # 1) add imm16: first word is `addi rd, rs, imm` (rd updates in slot).
    li    $t0, 10
    li    $t1, 99
    beq   $zero, $zero, add_imm16_done
    add   $t1, $t0, 5
add_imm16_done:
    move  $a0, $t1
    jal   print_int_line
    nop

    # 2) add imm32: first word is `lui $at, high(imm)` (rd unchanged).
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, add_imm32_done
    add   $t1, $t0, 100000
add_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 3) addu immediate form always starts with `lui $at, high(imm)`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, addu_imm_done
    addu  $t1, $t0, 5
addu_imm_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 4) sub imm16: first word is `addi $at, $zero, imm`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, sub_imm16_done
    sub   $t1, $t0, 5
sub_imm16_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 5) subu immediate form always starts with `lui $at, high(imm)`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, subu_imm_done
    subu  $t1, $t0, 5
subu_imm_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 6) addi imm32: first word is `lui $at, high(imm)`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, addi_imm32_done
    addi  $t1, $t0, 100000
addi_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 7) addiu imm32: first word is `lui $at, high(imm)`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, addiu_imm32_done
    addiu $t1, $t0, 100000
addiu_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 8) subi imm16: first word is `addi $at, $zero, imm`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, subi_imm16_done
    subi  $t1, $t0, 5
subi_imm16_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 9) subiu immediate form always starts with `lui $at, high(imm)`.
    li    $t0, 10
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, subiu_imm_done
    subiu $t1, $t0, 5
subiu_imm_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 10) and imm16 (3-op): first word is `andi rd, rs, imm`.
    li    $t0, 0x1234
    li    $t1, 99
    beq   $zero, $zero, and_imm16_done
    and   $t1, $t0, 255
and_imm16_done:
    move  $a0, $t1
    jal   print_int_line
    nop

    # 11) andi imm32 (3-op): first word is `lui $at, high(imm)`.
    li    $t0, 0x1234
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, andi_imm32_done
    andi  $t1, $t0, 100000
andi_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 12) andi immediate (2-op) imm32: first word is `lui $at, high(imm)`.
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, andi2_imm32_done
    andi  $t1, 100000
andi2_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 13) ori imm32 (3-op): first word is `lui $at, high(imm)`.
    li    $t0, 0x1234
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, ori_imm32_done
    ori   $t1, $t0, 100000
ori_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 14) ori immediate (2-op) imm32: first word is `lui $at, high(imm)`.
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, ori2_imm32_done
    ori   $t1, 100000
ori2_imm32_done:
    move  $a0, $t1
    jal   print_int_line
    nop
    move  $a0, $at
    jal   print_int_line
    nop

    # 15) xori imm32 (3-op): first word is `lui $at, high(imm)`.
    li    $t0, 0x1234
    li    $t1, 99
    li    $at, 7
    beq   $zero, $zero, xori_imm32_done
    xori  $t1, $t0, 100000
xori_imm32_done:
    move  $a0, $t1
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
