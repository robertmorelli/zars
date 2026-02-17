# Syscall 12 read-char behavior.
# Prints both the char itself and its integer code.

.text
.globl main

main:
    li   $v0, 12
    syscall
    move $s0, $v0

    li   $v0, 11
    move $a0, $s0
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 1
    move $a0, $s0
    syscall

    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
