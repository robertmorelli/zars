.text
.globl main
main:
    li $t0, 5
    move $t1, $t0
    move $a0, $t1
    li $v0, 1
    syscall
    li $v0, 10
    syscall
