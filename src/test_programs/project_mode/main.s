# Multi-file project entry point.
# Run with command option: p

.text
.globl main

main:
    li   $a0, 21
    jal  helper_double

    move $a0, $v0
    li   $v0, 1
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
