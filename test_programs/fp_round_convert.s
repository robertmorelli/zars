# Floating-point conversion and rounding instruction coverage.
# Includes floor/ceil/round/trunc and cvt family variants.

.data
f_neg_half: .float -2.5
f_pos:      .float 3.9
f_zero:     .float 0.0
d_half:     .double 2.5
d_neg_half: .double -2.5

.text
.globl main

main:
    l.s   $f0, f_neg_half
    floor.w.s $f1, $f0
    ceil.w.s  $f2, $f0
    round.w.s $f3, $f0
    trunc.w.s $f4, $f0

    mfc1  $t0, $f1
    mfc1  $t1, $f2
    mfc1  $t2, $f3
    mfc1  $t3, $f4

    li    $v0, 1
    move  $a0, $t0
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t1
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t2
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t3
    syscall
    jal   print_newline

    l.d   $f6, d_half
    round.w.d $f8, $f6
    mfc1  $t4, $f8
    li    $v0, 1
    move  $a0, $t4
    syscall
    jal   print_newline

    l.d   $f10, d_neg_half
    trunc.w.d $f12, $f10
    mfc1  $t5, $f12
    li    $v0, 1
    move  $a0, $t5
    syscall
    jal   print_newline

    li    $t6, -7
    mtc1  $t6, $f14
    cvt.s.w $f15, $f14
    mov.s $f12, $f15
    li    $v0, 2
    syscall
    jal   print_newline

    cvt.d.w $f16, $f14
    mov.d $f12, $f16
    li    $v0, 3
    syscall
    jal   print_newline

    l.s   $f18, f_pos
    cvt.w.s $f19, $f18
    mfc1  $t7, $f19
    li    $v0, 1
    move  $a0, $t7
    syscall
    jal   print_newline

    l.d   $f20, d_half
    cvt.w.d $f21, $f20
    mfc1  $t8, $f21
    li    $v0, 1
    move  $a0, $t8
    syscall
    jal   print_newline

    l.s   $f22, f_pos
    cvt.d.s $f24, $f22
    mov.d $f12, $f24
    li    $v0, 3
    syscall
    jal   print_newline

    l.d   $f26, d_half
    cvt.s.d $f28, $f26
    mov.s $f12, $f28
    li    $v0, 2
    syscall
    jal   print_newline

    li    $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
