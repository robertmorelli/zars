.text
.globl main
main:
    li $v0, 20
    subiu $t3, $v0, 1
    li $v0, 10
    syscall
