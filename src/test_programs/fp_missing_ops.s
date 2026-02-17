# Floating-point parity coverage for mnemonics that were implemented but not
# previously hit by source-level test programs.
#
# The program prints integer or hex projections of FP results so MARS-vs-wasm
# comparisons stay exact and deterministic across platforms.

.data
.align 3
fp_slot: .space 24

f_neg_two: .float -2.0
f_one: .float 1.0
f_two: .float 2.0
f_six: .float 6.0
f_eight: .float 8.0
f_nine: .float 9.0

d_neg_three: .double -3.0
d_one_five: .double 1.5
d_two_five: .double 2.5
d_four: .double 4.0
d_seven: .double 7.0
d_two: .double 2.0
d_sixfive: .double 6.5
d_sixfour: .double 6.4

.text
.globl main

main:
    # Single-precision path: abs.s, neg.s, sub.s, div.s, sqrt.s.
    l.s   $f0, f_neg_two
    abs.s $f1, $f0
    cvt.w.s $f2, $f1
    mfc1  $a0, $f2
    jal   print_int_line

    l.s   $f3, f_six
    l.s   $f4, f_one
    sub.s $f5, $f3, $f4
    cvt.w.s $f6, $f5
    mfc1  $a0, $f6
    jal   print_int_line

    l.s   $f7, f_eight
    l.s   $f8, f_two
    div.s $f9, $f7, $f8
    cvt.w.s $f10, $f9
    mfc1  $a0, $f10
    jal   print_int_line

    l.s   $f11, f_nine
    sqrt.s $f12, $f11
    cvt.w.s $f13, $f12
    mfc1  $a0, $f13
    jal   print_int_line

    neg.s $f14, $f12
    abs.s $f15, $f14
    cvt.w.s $f16, $f15
    mfc1  $a0, $f16
    jal   print_int_line

    # Double-precision path: abs.d, add.d, mul.d, div.d, sqrt.d.
    l.d   $f20, d_neg_three
    abs.d $f22, $f20
    cvt.w.d $f24, $f22
    mfc1  $a0, $f24
    jal   print_int_line

    neg.d $f30, $f22
    abs.d $f30, $f30
    cvt.w.d $f28, $f30
    mfc1  $a0, $f28
    jal   print_int_line

    l.d   $f20, d_one_five
    l.d   $f22, d_two_five
    add.d $f24, $f20, $f22
    cvt.w.d $f26, $f24
    mfc1  $a0, $f26
    jal   print_int_line

    mul.d $f24, $f20, $f22
    cvt.w.d $f26, $f24
    mfc1  $a0, $f26
    jal   print_int_line

    l.d   $f20, d_seven
    l.d   $f22, d_two
    div.d $f24, $f20, $f22
    floor.w.d $f26, $f24
    mfc1  $a0, $f26
    jal   print_int_line

    ceil.w.d $f28, $f24
    mfc1  $a0, $f28
    jal   print_int_line

    l.d   $f20, d_four
    sqrt.d $f24, $f20
    cvt.w.d $f26, $f24
    mfc1  $a0, $f26
    jal   print_int_line

    # c.eq.d with a false condition, then bc1t should not branch.
    l.d   $f20, d_sixfive
    l.d   $f22, d_sixfour
    c.eq.d $f20, $f22
    li    $t0, 0
    bc1t  c_eq_d_true
    nop
    j     c_eq_d_done
    nop
c_eq_d_true:
    li    $t0, 1
c_eq_d_done:
    move  $a0, $t0
    jal   print_int_line

    # movt.s/movz.s/movn.s report raw bits through syscall 34.
    c.eq.s $f12, $f12
    mtc1  $zero, $f17
    movt.s $f17, $f12
    mfc1  $a0, $f17
    jal   print_hex_line

    li    $t1, 0
    movz.s $f18, $f9, $t1
    mfc1  $a0, $f18
    jal   print_hex_line

    li    $t1, 1
    movn.s $f19, $f11, $t1
    mfc1  $a0, $f19
    jal   print_hex_line

    # Explicit COP1 memory opcodes: swc1/ldc1/sdc1 (with a lwc1 check too).
    la    $s0, fp_slot
    swc1  $f9, 0($s0)
    lwc1  $f2, 0($s0)
    cvt.w.s $f3, $f2
    mfc1  $a0, $f3
    jal   print_int_line

    sdc1  $f24, 8($s0)
    ldc1  $f4, 8($s0)
    cvt.w.d $f6, $f4
    mfc1  $a0, $f6
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

print_hex_line:
    li    $v0, 34
    syscall
    li    $v0, 11
    li    $a0, 10
    syscall
    jr    $ra
