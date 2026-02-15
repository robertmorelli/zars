.text
.globl main
main:
    li $t0, 0x12345678
    move $a0, $t0
    li $v0, 1
    syscall
    li $v0, 10
    syscall
