# Macro expansion, .include, and .eqv test.

.include "include/common_macros.inc"

.eqv MAGIC_VALUE 73

.data
msg: .asciiz "macro-include-ok"

.text
.globl main

main:
    print_string(msg)
    print_newline

    li   $t0, MAGIC_VALUE
    print_int_reg($t0)
    print_newline

    li   $t1, 5
    li   $t2, 8
    li   $t3, 13
    add_three($t4, $t1, $t2, $t3)
    print_int_reg($t4)
    print_newline

    li   $v0, 10
    syscall
