# Address-expression parity fixture.
# Covers immediate, label, label+offset, and optional base-register forms for
# `la` plus load/store addressing.

.data
arr: .word 10, 20, 30, 40

.text
main:
    # Load forms: label, label+offset, label(base), label+offset(base), and
    # absolute numeric address.
    lw   $t0, arr
    lw   $t1, arr+4
    lw   $t2, arr($zero)
    lw   $t3, arr+8($zero)
    lw   $t4, 0x10010000
    li   $t8, 4
    lw   $t5, arr($t8)

    li   $v0, 1
    move $a0, $t0
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $t1
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $t3
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $t4
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $t5
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    # Store forms: label+offset, label+offset(base), and absolute numeric.
    li   $s0, 77
    sw   $s0, arr+12
    li   $s0, 88
    sw   $s0, arr+4($zero)
    li   $s0, 99
    sw   $s0, arr($zero)
    li   $s0, 66
    sw   $s0, 0x10010008
    li   $s0, 55
    sw   $s0, arr($t8)

    lw   $s1, arr
    lw   $s2, arr+4
    lw   $s3, arr+8
    lw   $s4, arr+12

    li   $v0, 1
    move $a0, $s1
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s2
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s3
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s4
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    # `la` forms with labels and base registers.
    la   $s1, arr
    la   $s2, arr+8
    la   $s3, ($s1)
    la   $s4, 0($s1)
    la   $s5, 4($s1)
    la   $s6, arr+12($zero)
    la   $s7, arr($t8)

    subu $s2, $s2, $s1
    subu $s3, $s3, $s1
    subu $s4, $s4, $s1
    subu $s5, $s5, $s1
    subu $s6, $s6, $s1
    subu $s7, $s7, $s1

    li   $v0, 1
    move $a0, $s2
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s3
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s4
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s5
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s6
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 1
    move $a0, $s7
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    # `la` immediate forms with and without explicit base register.
    la   $t0, 65535($zero)
    la   $t1, -1($zero)
    la   $t2, 65536($zero)
    la   $t3, -32769($zero)

    li   $v0, 34
    move $a0, $t0
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t1
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t3
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    la   $t0, 65535
    la   $t1, -1
    la   $t2, 65536
    la   $t3, -32769

    li   $v0, 34
    move $a0, $t0
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t1
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t2
    syscall
    li   $v0, 11
    li   $a0, 32
    syscall
    li   $v0, 34
    move $a0, $t3
    syscall
    li   $v0, 11
    li   $a0, 10
    syscall

    li   $v0, 10
    syscall
