# Coprocessor 0 transfer and eret behavior coverage.

.text
.globl main

main:
    li    $t0, 0x00000002
    mtc0  $t0, $12

    la    $t1, epc_target
    mtc0  $t1, $14

    eret

    # Should not execute when eret sets PC to EPC.
    li    $v0, 1
    li    $a0, 999
    syscall
    li    $v0, 10
    syscall

epc_target:
    mfc0  $t2, $12

    li    $v0, 1
    move  $a0, $t2
    syscall

    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 10
    syscall
