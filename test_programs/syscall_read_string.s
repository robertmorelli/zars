# Syscall 8 read-string behavior (fgets-like).
# With a generous max length, MARS appends newline then null terminator.

.data
buf: .space 32

.text
.globl main

main:
    li   $v0, 8
    la   $a0, buf
    li   $a1, 16
    syscall

    li   $v0, 4
    la   $a0, buf
    syscall

    li   $v0, 10
    syscall
