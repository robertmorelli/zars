# Variable shift instruction coverage.
# Uses one negative source value so arithmetic and logical right shifts diverge.

.text
.globl main

main:
    li   $t0, -16
    li   $t1, 2

    sllv $t2, $t0, $t1
    srlv $t3, $t0, $t1
    srav $t4, $t0, $t1

    li   $v0, 1
    move $a0, $t2
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $t3
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $t4
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
