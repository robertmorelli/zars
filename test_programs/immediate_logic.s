# Immediate and logical instruction coverage.
# This program intentionally mixes signed and unsigned views so output can
# validate both value interpretation and bit-pattern behavior.

.text
.globl main

main:
    # addi: signed immediate addition with overflow checking.
    li   $t0, -5
    addi $t1, $t0, 2

    # andi/ori/xori: immediate must be zero-extended.
    li   $t2, -1
    andi $t3, $t2, 0xff00
    ori  $t4, $zero, 0x1234
    xori $t5, $t4, 0x00ff

    # slti/sltiu: compare with sign-extended immediate.
    slti  $t6, $t0, -4
    sltiu $t7, $t0, -4

    # lui: upper half set, lower half zeroed.
    lui  $s0, 0x1234

    li   $v0, 1
    move $a0, $t1
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

    li   $v0, 1
    move $a0, $t5
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $t6
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $t7
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $s0
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
