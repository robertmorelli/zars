# HI/LO unsigned path coverage.
# Verifies multu/divu plus explicit HI/LO control using mthi/mtlo.

.text
.globl main

main:
    # Explicit HI/LO seed and readback.
    li   $t0, 0x12345678
    li   $t1, 0x9abcdef0
    mthi $t0
    mtlo $t1
    mfhi $s0
    mflo $s1

    li   $v0, 34
    move $a0, $s0
    syscall
    jal  print_newline

    li   $v0, 34
    move $a0, $s1
    syscall
    jal  print_newline

    # Unsigned multiply: 0xffffffff * 2 => HI=1 LO=0xfffffffe.
    li    $t2, -1
    li    $t3, 2
    multu $t2, $t3
    mfhi  $s2
    mflo  $s3

    li   $v0, 34
    move $a0, $s2
    syscall
    jal  print_newline

    li   $v0, 34
    move $a0, $s3
    syscall
    jal  print_newline

    # Unsigned divide: 0xffffffff / 2 => LO=2147483647 HI=1.
    divu  $t2, $t3
    mfhi  $s4
    mflo  $s5

    li   $v0, 36
    move $a0, $s5
    syscall
    jal  print_newline

    li   $v0, 1
    move $a0, $s4
    syscall
    jal  print_newline

    li   $v0, 10
    syscall

print_newline:
    li   $v0, 11
    li   $a0, 10
    syscall
    jr   $ra
