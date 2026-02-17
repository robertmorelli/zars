# Coprocessor 1 condition flag coverage.
# Uses bc1t/bc1f with explicit condition flag indices.

.data
f_one:   .float 1.0
f_two:   .float 2.0
f_three: .float 3.0
d_three: .double 3.0
d_four:  .double 4.0

.text
.globl main

main:
    l.s  $f0, f_one
    l.s  $f1, f_two
    l.s  $f2, f_three
    l.d  $f4, d_three
    l.d  $f6, d_four

    li   $s0, 0

    c.lt.s $f0, $f1
    bc1t   flag0_true
    nop
flag0_true:
    addiu $s0, $s0, 1

    c.eq.s 1, $f0, $f0
    bc1f   1, skip_flag1
    addiu  $s0, $s0, 2
skip_flag1:

    c.le.s 2, $f2, $f1
    bc1f   2, flag2_false
    nop
flag2_false:
    addiu $s0, $s0, 4

    c.le.d 3, $f4, $f6
    bc1t   3, flag3_true
    nop
flag3_true:
    addiu $s0, $s0, 8

    c.lt.d 4, $f6, $f4
    bc1f   4, flag4_false
    nop
flag4_false:
    addiu $s0, $s0, 16

    li   $v0, 1
    move $a0, $s0
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
