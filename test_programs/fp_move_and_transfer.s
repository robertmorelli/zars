# Floating-point move and transfer coverage.
# Exercises movf/movt integer and FP variants, movn/movz, plus mfc1/mtc1.

.data
f_one: .float 1.0
f_two: .float 2.0

.text
.globl main

main:
    l.s   $f0, f_one
    l.s   $f1, f_two

    c.eq.s $f0, $f1

    li    $t1, 22
    movf  $t2, $t1
    movt  $t3, $t1

    li    $v0, 1
    move  $a0, $t2
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t3
    syscall
    jal   print_newline

    c.lt.s 1, $f0, $f1
    movt  $t4, $t1, 1
    movf  $t5, $t1, 1

    li    $v0, 1
    move  $a0, $t4
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t5
    syscall
    jal   print_newline

    li    $t6, 33
    li    $t7, 1
    li    $t8, 0
    movn  $t9, $t6, $t7
    movz  $s0, $t6, $t8

    li    $v0, 1
    move  $a0, $t9
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $s0
    syscall
    jal   print_newline

    li    $a1, 12345
    mtc1  $a1, $f6
    mfc1  $a2, $f6

    li    $v0, 1
    move  $a0, $a2
    syscall
    jal   print_newline

    movf.s $f7, $f6
    mfc1   $a3, $f7

    li    $v0, 1
    move  $a0, $a3
    syscall
    jal   print_newline

    li    $v1, 0x11223344
    li    $gp, 0x55667788
    mtc1  $v1, $f10
    mtc1  $gp, $f11
    mov.d $f12, $f10

    c.eq.s 2, $f0, $f0
    movt.d $f14, $f12, 2
    movf.d $f16, $f12, 2

    li    $sp, 1
    movn.d $f18, $f14, $sp
    li    $fp, 0
    movz.d $f20, $f14, $fp

    mfc1  $s1, $f20
    mfc1  $s2, $f21

    li    $v0, 34
    move  $a0, $s1
    syscall
    jal   print_newline

    li    $v0, 34
    move  $a0, $s2
    syscall
    jal   print_newline

    li    $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
