# Pseudo-op parity coverage for div/divu/rem/remu three-operand forms.
#
# This focuses on MARS expansion behavior:
# - register third operand traps on zero divisor (handled separately in Zig tests)
# - immediate third operand uses raw div/divu expansion and keeps HI/LO unchanged
#   when the immediate is zero.

.text
.globl main

main:
    li    $s0, 20
    li    $s1, 3

    div   $t0, $s0, $s1
    rem   $t1, $s0, $s1
    divu  $t2, $s0, $s1
    remu  $t3, $s0, $s1

    div   $t4, $s0, 5
    rem   $t5, $s0, 5
    divu  $t6, $s0, 7
    remu  $t7, $s0, 7

    # Immediate-zero forms should not trap and should copy prior HI/LO.
    li    $t8, 77
    mtlo  $t8
    li    $t9, 88
    mthi  $t9

    div   $s2, $s0, 0
    rem   $s3, $s0, 0
    divu  $s4, $s0, 0
    remu  $s5, $s0, 0

    move  $a0, $t0
    jal   print_int_line
    move  $a0, $t1
    jal   print_int_line
    move  $a0, $t2
    jal   print_int_line
    move  $a0, $t3
    jal   print_int_line

    move  $a0, $t4
    jal   print_int_line
    move  $a0, $t5
    jal   print_int_line
    move  $a0, $t6
    jal   print_int_line
    move  $a0, $t7
    jal   print_int_line

    move  $a0, $s2
    jal   print_int_line
    move  $a0, $s3
    jal   print_int_line
    move  $a0, $s4
    jal   print_int_line
    move  $a0, $s5
    jal   print_int_line

    li    $v0, 10
    syscall

print_int_line:
    li    $v0, 1
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    jr    $ra
