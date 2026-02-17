.data
mydata: .word 123

.text
.globl main

main:
    la $s0, mydata
    lw $t0, 0($s0)
    
    move $a0, $t0
    li $v0, 1
    syscall
    
    li $v0, 10
    syscall
