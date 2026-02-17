# MARS formatting syscalls: 34 (hex), 35 (binary), 36 (unsigned).

.text
.globl main

main:
    li   $t0, -1

    move $a0, $t0
    li   $v0, 34
    syscall
    jal  print_newline

    move $a0, $t0
    li   $v0, 35
    syscall
    jal  print_newline

    move $a0, $t0
    li   $v0, 36
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
