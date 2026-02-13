# Delayed-branch probe.
# Expected:
# - default (no db): prints 1
# - with db option: prints 11

.text
.globl main

main:
    li    $t0, 0
    li    $t1, 1

    beq   $t1, $t1, branch_taken
    addiu $t0, $t0, 10

branch_taken:
    addiu $t0, $t0, 1

    li    $v0, 1
    move  $a0, $t0
    syscall

    li    $v0, 11
    li    $a0, 10
    syscall

    li    $v0, 10
    syscall
