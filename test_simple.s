.text
.globl main
main:
    add $t0, $t1, $t2
    sub $t3, $t4, $t5
    li $t6, 40
    li $v0, 10
    syscall
