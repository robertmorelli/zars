# Branch family + link behavior coverage.
# This intentionally accumulates a bitmask-like sum so each taken branch/call
# contributes a unique power-of-two-ish chunk to the final value.

.text
.globl main

main:
    li   $s0, 0
    li   $t0, -1
    li   $t1, 0
    li   $t2, 1

    bne  $t0, $t1, label_bne
    li   $a0, 900
label_bne:
    addiu $s0, $s0, 1

    bgez $t0, after_bgez
    addiu $s0, $s0, 2
after_bgez:

    bltz $t0, label_bltz
    li   $a0, 901
label_bltz:
    addiu $s0, $s0, 4

    blez $t1, label_blez
    li   $a0, 902
label_blez:
    addiu $s0, $s0, 8

    bgtz $t2, label_bgtz
    li   $a0, 903
label_bgtz:
    addiu $s0, $s0, 16

    # Branch-and-link forms should update $ra as in MARS processReturnAddress().
    bgezal $t2, call_bgezal
    addiu  $s0, $s0, 512

    bltzal $t0, call_bltzal
    addiu  $s0, $s0, 1024

    # jalr with explicit link register.
    la    $s3, jalr_target
    jalr  $s4, $s3
    addiu $s0, $s0, 64

    li   $v0, 1
    move $a0, $s0
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

call_bgezal:
    addiu $s0, $s0, 128
    jr    $ra

call_bltzal:
    addiu $s0, $s0, 256
    jr    $ra

jalr_target:
    addiu $s0, $s0, 32
    jr    $s4

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
