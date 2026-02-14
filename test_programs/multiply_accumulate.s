# Multiply/accumulate family and leading-bit count coverage.

.text
.globl main

main:
    li    $t0, 3
    li    $t1, 4

    mul   $t2, $t0, $t1
    mfhi  $s0
    mflo  $s1

    li    $v0, 1
    move  $a0, $s0
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $s1
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $t2
    syscall
    jal   print_newline

    li    $t3, 2
    li    $t4, 5

    madd  $t3, $t4
    mflo  $s2
    li    $v0, 1
    move  $a0, $s2
    syscall
    jal   print_newline

    msub  $t3, $t4
    mflo  $s3
    li    $v0, 1
    move  $a0, $s3
    syscall
    jal   print_newline

    mthi  $zero
    mtlo  $zero
    li    $t5, -1
    li    $t6, 2
    maddu $t5, $t6
    mfhi  $s4
    mflo  $s5

    li    $v0, 34
    move  $a0, $s4
    syscall
    jal   print_newline

    li    $v0, 34
    move  $a0, $s5
    syscall
    jal   print_newline

    msubu $t5, $t6
    mfhi  $s6
    mflo  $s7

    li    $v0, 34
    move  $a0, $s6
    syscall
    jal   print_newline

    li    $v0, 34
    move  $a0, $s7
    syscall
    jal   print_newline

    li    $t7, -1
    li    $t8, 1

    clo   $t9, $t7
    clz   $k0, $t7
    clo   $k1, $t8
    clz   $gp, $t8

    li    $v0, 1
    move  $a0, $t9
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $k0
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $k1
    syscall
    jal   print_newline

    li    $v0, 1
    move  $a0, $gp
    syscall
    jal   print_newline

    li    $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
