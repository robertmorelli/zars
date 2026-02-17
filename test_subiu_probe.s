# Test to see how MARS expands subiu
.text
.globl main
main:
    subiu $t0, $t1, 1
    subiu $t2, $t3, 100
    subiu $t4, $t5, 32767
    # Exit
    li $v0, 10
    syscall
