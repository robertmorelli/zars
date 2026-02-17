# Delayed-branch parity probe for multiword `mulu` in the delay slot.
#
# Only the first expanded word (`multu`) should execute in the slot, so `mflo`
# writeback into destination register must not occur.

.text
.globl main

main:
    li    $t2, 6
    li    $t3, 7
    li    $t4, 123

    beq   $zero, $zero, target
    mulu  $t4, $t2, $t3

target:
    li    $v0, 1
    move  $a0, $t4
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    li    $v0, 10
    syscall
