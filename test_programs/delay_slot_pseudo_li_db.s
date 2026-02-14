# Delayed-branch parity probe for multiword `li` in the delay slot.
#
# With delayed branching enabled, only the first expanded word (`lui`) of the
# pseudo-instruction should execute in the slot, so destination register stays
# at its prior value.

.text
.globl main

main:
    li    $t0, 7
    beq   $zero, $zero, target
    li    $t0, 0x12345678

target:
    li    $v0, 1
    move  $a0, $t0
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    li    $v0, 10
    syscall
