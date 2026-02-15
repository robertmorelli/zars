.text
.globl main
main:
    li $t0, 40
    li $t1, 2
    li $v0, 1
    syscall
    li $v0, 10
    syscall
