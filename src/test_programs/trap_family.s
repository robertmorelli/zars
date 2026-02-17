# Trap instruction family coverage.
# Runs non-trapping variants only so compare mode can match stdout exactly.

.text
.globl main

main:
    li   $t0, 1
    li   $t1, 2

    teq   $t0, $t1
    tne   $t0, $t0
    tge   $t0, $t1
    tgeu  $t0, $t1
    tlt   $t1, $t0
    tltu  $t1, $t0

    teqi  $t0, 2
    tnei  $t0, 1
    tgei  $t0, 2
    tgeiu $t0, -1
    tlti  $t0, 0
    tltiu $t0, 0

    li   $v0, 1
    li   $a0, 123
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
