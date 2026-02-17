.text
.globl main

main:
    li $t0, 42
    move $t1, $t0
    
    li $v0, 1
    move $a0, $t1
    syscall
    
    li $v0, 10
    syscall
