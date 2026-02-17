.text
.globl main

main:
    add $t1, $t0, 100000
    li $v0, 10
    syscall
